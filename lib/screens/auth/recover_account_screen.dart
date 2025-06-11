// lib/screens/auth/recover_account_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:moneywat/services/hashing_service.dart';
import 'package:moneywat/utils/constants.dart';
import 'package:moneywat/screens/dashboard/treasurer_dashboard_screen.dart';
import 'package:moneywat/screens/dashboard/driver_dashboard_screen.dart';
import 'package:moneywat/screens/dashboard/monk_dashboard_screen.dart';

class RecoverAccountScreen extends StatefulWidget {
  const RecoverAccountScreen({super.key});

  @override
  State<RecoverAccountScreen> createState() => _RecoverAccountScreenState();
}

class _RecoverAccountScreenState extends State<RecoverAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _primaryIdController = TextEditingController();
  final _secondaryIdController = TextEditingController();
  final _pinController = TextEditingController();

  final _dbHelper = DatabaseHelper();
  final _hashingService = HashingService();
  bool _isLoading = false;
  bool _isPinVisible = false;

  Future<void> _recoverAccount() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!mounted) return;
    setState(() => _isLoading = true);

    final primaryId = _primaryIdController.text;
    final secondaryId = _secondaryIdController.text;
    final pin = _pinController.text;

    User? user = await _dbHelper.getUser(primaryId);

    if (!mounted) {
      setState(() => _isLoading = false);
      return;
    }

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบบัญชีผู้ใช้สำหรับ Primary ID นี้')),
      );
      setState(() => _isLoading = false);
      return;
    }

    if (user.secondaryId != secondaryId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Secondary ID ไม่ถูกต้อง')));
      setState(() => _isLoading = false);
      return;
    }

    if (user.hashedPin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('บัญชีนี้ยังไม่ได้ตั้งค่า PIN หรือ PINเสียหาย'),
        ),
      );
      setState(() => _isLoading = false);
      return;
    }

    bool pinMatch = await _hashingService.verifyPin(pin, user.hashedPin!);
    if (!mounted) {
      setState(() => _isLoading = false);
      return;
    }

    if (pinMatch) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.isSetupComplete, true);
      await prefs.setString(AppConstants.userPrimaryId, user.primaryId);
      await prefs.setString(AppConstants.userSecondaryId, user.secondaryId);
      await prefs.setString(AppConstants.userDisplayName, user.displayName);
      await prefs.setString(AppConstants.userRole, user.role.name);
      // Note: Associated treasurer IDs are not restored here.
      // If they were previously in SharedPreferences and not cleared, they might still be there.

      if (!mounted) {
        setState(() => _isLoading = false);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'กู้คืนบัญชีสำเร็จ! ยินดีต้อนรับคุณ ${user.displayName}',
          ),
        ),
      );

      Widget dashboardScreen;
      switch (user.role) {
        case UserRole.treasurer:
          dashboardScreen = const TreasurerDashboardScreen();
          break;
        case UserRole.driver:
          dashboardScreen = const DriverDashboardScreen();
          break;
        case UserRole.monk:
          dashboardScreen = const MonkDashboardScreen();
          break;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => dashboardScreen),
        (Route<dynamic> route) => false,
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('รหัส PIN ไม่ถูกต้อง')));
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _primaryIdController.dispose();
    _secondaryIdController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เข้าสู่ระบบบัญชีเดิม')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'กรุณากรอกข้อมูลบัญชีเดิมของคุณเพื่อเข้าสู่ระบบ',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _primaryIdController,
                  decoration: const InputDecoration(
                    labelText: 'Primary ID',
                    hintText: 'เช่น 1234, 12345, หรือ 123456',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'กรุณากรอก Primary ID';
                    }
                    if (value.length < 4 || value.length > 6) {
                      return 'Primary ID ต้องมี 4, 5, หรือ 6 หลัก';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _secondaryIdController,
                  decoration: const InputDecoration(
                    labelText: 'Secondary ID',
                    hintText: 'เช่น 1234, 12345, หรือ 123456',
                    prefixIcon: Icon(Icons.security_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'กรุณากรอก Secondary ID';
                    }
                    if (value.length < 4 || value.length > 6) {
                      return 'Secondary ID ต้องมี 4, 5, หรือ 6 หลัก';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pinController,
                  decoration: InputDecoration(
                    labelText: 'รหัส PIN',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPinVisible ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPinVisible = !_isPinVisible;
                        });
                      },
                    ),
                  ),
                  obscureText: !_isPinVisible,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(AppConstants.maxPinLength),
                  ],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'กรุณากรอกรหัส PIN';
                    }
                    if (value.length < AppConstants.minPinLength) {
                      return 'รหัส PIN ต้องมีอย่างน้อย ${AppConstants.minPinLength} หลัก';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _recoverAccount,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : const Text('เข้าสู่ระบบ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
