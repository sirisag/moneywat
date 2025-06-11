// lib/screens/auth/monk_config_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
// If you plan to use a crypto package, add it to pubspec.yaml and import here:

import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:moneywat/services/hashing_service.dart'; // Import HashingService

class MonkConfigScreen extends StatefulWidget {
  final String primaryId; // Monk's Primary ID (6 digits)

  const MonkConfigScreen({super.key, required this.primaryId});

  @override
  State<MonkConfigScreen> createState() => _MonkConfigScreenState();
}

class _MonkConfigScreenState extends State<MonkConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  // final _displayNameController = TextEditingController(); // Removed
  final _monkSecondaryIdController =
      TextEditingController(); // Added for monk's secondary ID
  final _pinController = TextEditingController();
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
    final monkSecondaryId = _monkSecondaryIdController.text; // Get from input
    // DisplayName (ชื่อ/ฉายา) will be set/updated when the initial data file is imported.
    final pin = _pinController.text;
    final hashedPin = await _hashingService.hashPin(pin); // Use HashingService
    final treasurerPrimaryId = _treasurerPrimaryIdController.text;
    final treasurerSecondaryId = _treasurerSecondaryIdController.text;

    // For now, we can use a placeholder or the primaryId for display name.
    final monk = User(
      primaryId: widget.primaryId,
      secondaryId: monkSecondaryId,
      displayName:
          "พระ ${widget.primaryId}", // Placeholder, will be updated by file import
      role: UserRole.monk,
      hashedPin: hashedPin,
    );

    try {
      await _dbHelper.insertUser(monk);

      // Update SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_setup_complete', true);
      await prefs.setString('user_primary_id', widget.primaryId);
      // DisplayName will be updated from the imported file later.
      await prefs.setString(
        'user_secondary_id',
        monkSecondaryId,
      ); // Save monk's secondary ID
      // await prefs.setString(
      //     'user_display_name', "พระ ${widget.primaryId}"); // DisplayName is set by treasurer/driver and imported
      await prefs.setString('user_role', UserRole.monk.name);
      await prefs.setString(
        'associated_treasurer_primary_id',
        treasurerPrimaryId,
      );
      await prefs.setString(
        'associated_treasurer_secondary_id',
        treasurerSecondaryId,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ตั้งค่าบัญชีพระสำเร็จ')));
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
    // _displayNameController.dispose(); // Removed
    _monkSecondaryIdController.dispose(); // Dispose new controller
    _pinController.dispose();
    _confirmPinController.dispose();
    _treasurerPrimaryIdController.dispose();
    _treasurerSecondaryIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่าบัญชีพระ')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _monkSecondaryIdController,
                decoration: const InputDecoration(
                  labelText: 'Secondary ID ของคุณ',
                  hintText: 'กรอกเลข 6 หลัก (ที่ได้รับจากไวยาวัจกรณ์/คนขับรถ)',
                ),
                keyboardType: TextInputType.text, // เปลี่ยนเป็น text
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณากรอก Secondary ID ของคุณ';
                  }
                  if (value.length != 6) {
                    return 'Secondary ID ของคุณต้องมี 6 หลัก';
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
                keyboardType: TextInputType.number, // Changed to number
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
                keyboardType: TextInputType.number, // Changed to number
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
                keyboardType: TextInputType.text, // เปลี่ยนเป็น text
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
                keyboardType: TextInputType.text, // เปลี่ยนเป็น text
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
