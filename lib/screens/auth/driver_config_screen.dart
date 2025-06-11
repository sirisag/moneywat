// lib/screens/auth/driver_config_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart'; // For SharedPreferences
// If you plan to use a crypto package, add it to pubspec.yaml and import here:

import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:moneywat/models/account_balance_models.dart'; // For DriverAdvanceAccount
import 'package:moneywat/services/hashing_service.dart'; // Import HashingService

class DriverConfigScreen extends StatefulWidget {
  final String primaryId; // Driver's Primary ID (5 digits)

  const DriverConfigScreen({super.key, required this.primaryId});

  @override
  State<DriverConfigScreen> createState() => _DriverConfigScreenState();
}

class _DriverConfigScreenState extends State<DriverConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _driverSecondaryIdController =
      TextEditingController(); // Added for driver's secondary ID
  final _confirmPinController = TextEditingController();
  final _treasurerPrimaryIdController = TextEditingController();
  final _treasurerSecondaryIdController = TextEditingController();

  final _dbHelper = DatabaseHelper();
  final _hashingService = HashingService(); // Instantiate HashingService
  bool _isPinVisible = false;
  bool _isConfirmPinVisible = false;
  bool _isLoading = false;

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    final driverSecondaryId =
        _driverSecondaryIdController.text; // Get from input

    final pin = _pinController.text;
    final hashedPin = await _hashingService.hashPin(pin); // Use HashingService
    final treasurerPrimaryId = _treasurerPrimaryIdController.text;
    final treasurerSecondaryId = _treasurerSecondaryIdController.text;

    // DisplayName will be set/updated when the initial data file is imported.
    // For now, we can use a placeholder or the primaryId.
    final driver = User(
      primaryId: widget.primaryId,
      secondaryId: driverSecondaryId,
      displayName: "คนขับรถ ${widget.primaryId}", // Placeholder display name
      role: UserRole.driver,
      hashedPin: hashedPin,
      // Store associated treasurer IDs directly in the User model if it supports it,
      // or manage this association separately if needed.
      // For simplicity, assuming User model can hold these or they are stored in SharedPreferences.
    );

    try {
      await _dbHelper.insertUser(driver);

      // Create initial DriverAdvanceAccount
      final driverAdvance = DriverAdvanceAccount(
        driverPrimaryId: widget.primaryId,
        balance: 0, // Initial advance is 0, to be updated by treasurer
        lastUpdated: DateTime.now(),
      );
      await _dbHelper.insertOrUpdateDriverAdvance(driverAdvance);

      // Update SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_setup_complete', true);
      await prefs.setString('user_primary_id', widget.primaryId);
      // DisplayName will be updated from the imported file later.
      await prefs.setString(
        'user_secondary_id',
        driverSecondaryId,
      ); // Save driver's own secondary ID
      // await prefs.setString('user_display_name',
      //     "คนขับรถ ${widget.primaryId}"); // DisplayName is set by treasurer and imported
      await prefs.setString('user_role', UserRole.driver.name);
      await prefs.setString(
        'associated_treasurer_primary_id',
        treasurerPrimaryId,
      );
      await prefs.setString(
        'associated_treasurer_secondary_id',
        treasurerSecondaryId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ตั้งค่าบัญชีคนขับรถสำเร็จ')),
        );
        Navigator.pop(context, true); // Indicate successful setup
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: ${error.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _driverSecondaryIdController.dispose(); // Dispose new controller
    _confirmPinController.dispose();
    _treasurerPrimaryIdController.dispose();
    _treasurerSecondaryIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่าบัญชีคนขับรถ')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _driverSecondaryIdController,
                decoration: const InputDecoration(
                  labelText: 'Secondary ID ของคุณ',
                  hintText: 'กรอกเลข 5 หลัก (ที่ได้รับจากไวยาวัจกรณ์)',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณากรอก Secondary ID ของคุณ';
                  }
                  if (value.length != 5) {
                    return 'Secondary ID ของคุณต้องมี 5 หลัก';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pinController,
                decoration: InputDecoration(
                  labelText: 'รหัส PIN เข้าแอป',
                  hintText: 'กำหนดรหัส PIN (อย่างน้อย 4 หลัก)',
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
                keyboardType:
                    TextInputType.number, // Already number, ensure it's correct
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6), // Max PIN length
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณากรอกรหัส PIN';
                  }
                  if (value.length < 4) {
                    return 'PIN ต้องมีอย่างน้อย 4 หลัก';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPinController,
                decoration: InputDecoration(
                  labelText: 'ยืนยันรหัส PIN',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isConfirmPinVisible
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _isConfirmPinVisible = !_isConfirmPinVisible;
                      });
                    },
                  ),
                ),
                obscureText: !_isConfirmPinVisible,
                keyboardType:
                    TextInputType.number, // Already number, ensure it's correct
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณายืนยันรหัส PIN';
                  }
                  if (value != _pinController.text) {
                    return 'รหัส PIN ไม่ตรงกัน';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'ข้อมูลไวยาวัจกรณ์ (สำหรับเชื่อมต่อข้อมูล):',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _treasurerPrimaryIdController,
                decoration: const InputDecoration(
                  labelText: 'Primary ID ของไวยาวัจกรณ์',
                  hintText: 'กรอกเลข 4 หลัก',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณากรอก Primary ID ของไวยาวัจกรณ์';
                  }
                  if (value.length != 4) {
                    return 'Primary ID ไวยาวัจกรณ์ต้องมี 4 หลัก';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _treasurerSecondaryIdController,
                decoration: const InputDecoration(
                  labelText: 'Secondary ID ของไวยาวัจกรณ์',
                  hintText: 'กรอกเลข 4 หลัก',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณากรอก Secondary ID ของไวยาวัจกรณ์';
                  }
                  if (value.length != 4) {
                    return 'Secondary ID ไวยาวัจกรณ์ต้องมี 4 หลัก';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitForm,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('บันทึกการตั้งค่า'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
