// lib/screens/auth/universal_login_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moneywat/models/user_model.dart'; // For UserRole enum
import 'package:moneywat/services/database_helper.dart';
import 'package:moneywat/services/hashing_service.dart'; // Import HashingService

// Import role-specific configuration screens
import 'package:moneywat/screens/auth/treasurer_config_screen.dart';
import 'package:moneywat/screens/auth/driver_config_screen.dart';
import 'package:moneywat/screens/auth/monk_config_screen.dart';

// Import placeholder dashboard screens (We will create these simple screens next)
import 'package:moneywat/screens/dashboard/treasurer_dashboard_screen.dart';
import 'package:moneywat/screens/dashboard/driver_dashboard_screen.dart';
import 'package:moneywat/screens/dashboard/monk_dashboard_screen.dart';

class UniversalLoginSetupScreen extends StatefulWidget {
  const UniversalLoginSetupScreen({super.key});

  @override
  State<UniversalLoginSetupScreen> createState() =>
      _UniversalLoginSetupScreenState();
}

class _UniversalLoginSetupScreenState extends State<UniversalLoginSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _inputController = TextEditingController();
  final _dbHelper = DatabaseHelper();
  final _hashingService = HashingService(); // Instantiate HashingService
  late SharedPreferences _prefs;

  bool _isSetupComplete = false;
  String? _loggedInUserDisplayName;
  String? _loggedInUserPrimaryId;
  String?
  _loggedInUserSecondaryId; // To store the logged-in user's secondary ID
  UserRole? _loggedInUserRole;
  bool _isLoading = true; // To show loading indicator while checking prefs
  bool _isPinVisible = false; // To toggle PIN visibility

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    if (!mounted) return; // Check if the widget is still in the tree
    setState(() {
      _isSetupComplete = _prefs.getBool('is_setup_complete') ?? false;
      if (_isSetupComplete) {
        _loggedInUserDisplayName = _prefs.getString('user_display_name');
        _loggedInUserPrimaryId = _prefs.getString('user_primary_id');
        _loggedInUserSecondaryId = _prefs.getString(
          'user_secondary_id',
        ); // Load secondary ID
        String? roleString = _prefs.getString('user_role');

        if (roleString != null && roleString.isNotEmpty) {
          try {
            _loggedInUserRole = UserRole.values.byName(roleString);
          } catch (e) {
            // Handle error if roleString is a valid string but not a valid UserRole name
            print(
              "Error parsing UserRole '$roleString' from SharedPreferences: $e",
            );
            _loggedInUserRole = null;
            _isSetupComplete = false;
            _loggedInUserSecondaryId = null;
            _prefs.setBool('is_setup_complete', false);
          }
        } else {
          // Handle error if roleString is null or empty
          print(
            "UserRole string is null or empty in SharedPreferences. Resetting setup.",
          );
          _loggedInUserRole = null; // Or a default/unknown role
          _isSetupComplete = false;
          _loggedInUserSecondaryId = null;
          _prefs.setBool('is_setup_complete', false);
        }
      }
      _isLoading = false;
    });
  }

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final inputText = _inputController.text;

    if (_isSetupComplete) {
      // Login mode
      _loginUser(inputText);
    } else {
      // Setup mode: inputText is the Primary ID
      _initiateSetup(inputText);
    }
  }

  Future<void> _loginUser(String pin) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // For treasurer, we also need secondaryId to be available for operations like encryption key generation
    if (_loggedInUserPrimaryId == null ||
        _loggedInUserRole == null ||
        (_loggedInUserRole == UserRole.treasurer &&
            _loggedInUserSecondaryId == null)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ข้อมูลผู้ใช้ไม่สมบูรณ์, กรุณาตั้งค่าใหม่'),
          ),
        );
        await _prefs.setBool('is_setup_complete', false);
        if (!mounted) return; // Added mounted check
        setState(() {
          _isSetupComplete = false;
          _loggedInUserSecondaryId = null;
          _isLoading = false;
        });
      }
      return;
    }

    User? user = await _dbHelper.getUser(_loggedInUserPrimaryId!);
    if (!mounted) return;

    if (user != null && user.hashedPin != null) {
      // Verify the entered PIN against the stored hashed PIN
      bool pinMatch = await _hashingService.verifyPin(pin, user.hashedPin!);
      if (!mounted) return; // Added mounted check

      if (pinMatch) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'เข้าสู่ระบบสำเร็จ! ยินดีต้อนรับคุณ $_loggedInUserDisplayName',
            ),
          ),
        );
        _navigateToDashboard(_loggedInUserRole!);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('รหัส PIN ไม่ถูกต้อง')));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่พบข้อมูลผู้ใช้หรือ PIN, กรุณาตั้งค่าใหม่'),
        ),
      );
      await _prefs.setBool('is_setup_complete', false);
      setState(() {
        _isSetupComplete = false;
        _loggedInUserSecondaryId = null;
      });
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _navigateToDashboard(UserRole role) {
    Widget dashboardScreen;
    switch (role) {
      case UserRole.treasurer:
        dashboardScreen = const TreasurerDashboardScreen();
        break;
      case UserRole.driver:
        dashboardScreen = const DriverDashboardScreen();
        break;
      case UserRole.monk:
        dashboardScreen = const MonkDashboardScreen();
        break;
      // default case is not strictly necessary if UserRole is always valid
      // but good for robustness if _loggedInUserRole could somehow be invalid.
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บทบาทผู้ใช้ไม่รู้จัก ไม่สามารถเปิด Dashboard'),
          ),
        );
        return;
    }
    // Clear the input field before navigating
    _inputController.clear();
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (context) => dashboardScreen));
  }

  void _initiateSetup(String primaryId) {
    UserRole? potentialRole;
    String roleName = "";

    if (primaryId.length == 4) {
      potentialRole = UserRole.treasurer;
      roleName = "ไวยาวัจกรณ์";
    } else if (primaryId.length == 5) {
      potentialRole = UserRole.driver;
      roleName = "คนขับรถ";
    } else if (primaryId.length == 6) {
      // Further validation for monk ID range (000000-999999)
      final idNum = int.tryParse(primaryId);
      if (idNum != null && idNum >= 0 && idNum <= 999999) {
        potentialRole = UserRole.monk;
        roleName = "พระ";
      }
    }

    if (potentialRole != null) {
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('ยืนยันการลงทะเบียน'),
            content: Text(
              'คุณต้องการลงทะเบียนด้วย ID: $primaryId ในฐานะ "$roleName" ใช่หรือไม่?',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('ยกเลิก'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
              ),
              TextButton(
                child: const Text('ยืนยัน'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _navigateToRoleConfigScreen(potentialRole!, primaryId);
                },
              ),
            ],
          );
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'รูปแบบ ID ไม่ถูกต้อง (ไวยาวัจกรณ์: 4 หลัก, คนขับรถ: 5 หลัก, พระ: 6 หลักตัวเลข)',
          ),
        ),
      );
    }
  }

  void _navigateToRoleConfigScreen(UserRole role, String primaryId) {
    Widget configScreen;
    switch (role) {
      case UserRole.treasurer:
        configScreen = TreasurerConfigScreen(primaryId: primaryId);
        break;
      case UserRole.driver:
        configScreen = DriverConfigScreen(primaryId: primaryId);
        break;
      case UserRole.monk:
        configScreen = MonkConfigScreen(primaryId: primaryId);
        break;
      // default case not needed here as potentialRole is validated before calling
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => configScreen)).then((
      setupSuccess,
    ) {
      // After returning from config screen, reload preferences
      // to reflect setup completion.
      if (setupSuccess == true && mounted) {
        _inputController.clear();
        _loadPreferences(); // This will set _isSetupComplete and other user details
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && !_isSetupComplete) {
      // Show loading only on initial load or during processing
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSetupComplete ? 'เข้าสู่ระบบ' : 'ยินดีต้อนรับ - ตั้งค่าเริ่มต้น',
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_isSetupComplete) ...[
                  if (_loggedInUserDisplayName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        'ยินดีต้อนรับกลับ, คุณ $_loggedInUserDisplayName',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_loggedInUserPrimaryId != null)
                    Text(
                      '(ID: $_loggedInUserPrimaryId - ${_loggedInUserRole?.name})',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _inputController,
                    decoration: InputDecoration(
                      labelText: 'รหัส PIN เข้าแอป',
                      prefixIcon: Icon(Icons.lock_outline),
                      // Add suffix icon to toggle visibility
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPinVisible
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPinVisible = !_isPinVisible;
                          });
                        },
                      ),
                    ),
                    obscureText: !_isPinVisible,
                    keyboardType: TextInputType.number, // เปลี่ยนเป็นแป้นตัวเลข
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6), // Max PIN length
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'กรุณากรอกรหัส PIN';
                      }
                      if (value.length < 4) {
                        // Assuming min PIN length is 4
                        return 'รหัส PIN ต้องมีอย่างน้อย 4 หลัก';
                      }
                      return null;
                    },
                  ),
                ] else ...[
                  Text(
                    'แอปพลิเคชันจัดการเงินวัด',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'กรุณากรอก ID หลักของคุณเพื่อเริ่มการตั้งค่า หรือหากเคยตั้งค่าแล้ว ระบบจะแสดงหน้าจอเข้าสู่ระบบ',
                    style: TextStyle(fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _inputController,
                    decoration: const InputDecoration(
                      labelText: 'Primary ID (4, 5, หรือ 6 หลัก)',
                      hintText: 'เช่น 1234 หรือ 12345 หรือ 123456',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    keyboardType:
                        TextInputType.text, // สำหรับ Primary ID ตอน setup
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(
                        6,
                      ), // Max length for any ID
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'กรุณากรอก Primary ID';
                      }
                      if (value.length < 4 || value.length > 6) {
                        return 'Primary ID ต้องมี 4, 5, หรือ 6 หลัก';
                      }
                      if (value.length == 6) {
                        final idNum = int.tryParse(value);
                        if (idNum == null || idNum < 0 || idNum > 999999) {
                          return 'ID พระไม่ถูกต้อง (ต้องเป็นตัวเลข 000000-999999)';
                        }
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  child:
                      _isLoading &&
                          _isSetupComplete // Show loading on button only if already setup and processing login
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : Text(_isSetupComplete ? 'เข้าสู่ระบบ' : 'ดำเนินการต่อ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
