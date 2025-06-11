// lib/screens/auth/treasurer_config_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
// If you plan to use a crypto package, add it to pubspec.yaml and import here:
import 'dart:math'; // For generating random Secondary ID

import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:moneywat/models/account_balance_models.dart';
import 'package:moneywat/services/hashing_service.dart'; // Import HashingService

class TreasurerConfigScreen extends StatefulWidget {
  final String primaryId;

  const TreasurerConfigScreen({super.key, required this.primaryId});

  @override
  State<TreasurerConfigScreen> createState() => _TreasurerConfigScreenState();
}

class _TreasurerConfigScreenState extends State<TreasurerConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  // Removed final for _primaryIdController to allow it to be passed if needed, or used as is.
  // For this temporary change, we'll assume widget.primaryId is always the one to use.
  final _displayNameController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _dbHelper = DatabaseHelper();
  final _hashingService = HashingService(); // Instantiate HashingService
  bool _isPinVisible = false;
  bool _isConfirmPinVisible = false;
  bool _isLoading = false;

  // Secondary ID will be generated and displayed, not input by user
  String? _generatedSecondaryId;

  @override
  void initState() {
    super.initState();
    _generateAndSetSecondaryId();
  }

  void _generateAndSetSecondaryId() {
    // Treasurer Secondary ID is 4 digits (1000-9999)
    final random = Random();
    _generatedSecondaryId = (random.nextInt(9000) + 1000).toString();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    final displayName = _displayNameController.text;
    final pin = _pinController.text;
    final secondaryId = _generatedSecondaryId;
    final hashedPin = await _hashingService.hashPin(pin); // Use HashingService

    if (secondaryId == null) {
      // Should not happen if _generateAndSetSecondaryId was called
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('เกิดข้อผิดพลาด: ไม่สามารถสร้าง Secondary ID ได้'),
        ),
      );
      setState(() => _isLoading = false);
      return;
    }
    final treasurer = User(
      primaryId: widget.primaryId,
      secondaryId: secondaryId,
      displayName: displayName,
      role: UserRole.treasurer,
      hashedPin: hashedPin,
    );

    try {
      await _dbHelper.insertUser(treasurer);

      // Create initial TempleFundAccount
      final templeFund = TempleFundAccount(
        treasurerPrimaryId: widget.primaryId,
        balance: 0,
        lastUpdated: DateTime.now(),
      );
      await _dbHelper.insertOrUpdateTempleFund(templeFund);

      // Update SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_setup_complete', true);
      await prefs.setString('user_primary_id', widget.primaryId);
      await prefs.setString('user_display_name', displayName);
      await prefs.setString(
        'user_secondary_id',
        secondaryId,
      ); // Save treasurer's secondary ID
      await prefs.setString('user_role', UserRole.treasurer.name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ตั้งค่าบัญชีไวยาวัจกรณ์สำเร็จ')),
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
    _displayNameController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่าบัญชีไวยาวัจกรณ์')),
      body: SingleChildScrollView(
        // Wrap with SingleChildScrollView
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Padding(
            // Add Padding back inside SingleChildScrollView if needed for overall padding
            padding: const EdgeInsets.symmetric(
              horizontal: 0,
            ), // Adjust as needed, or remove if padding:all(24.0) on SingleChildScrollView is enough
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Primary ID (PIN): ${widget.primaryId}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Secondary ID (ระบบสร้างให้): ${_generatedSecondaryId ?? "กำลังสร้าง..."}\n(กรุณาจดจำ ID นี้ไว้สำหรับใช้งาน)',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.blueGrey,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อแสดงผล',
                    hintText: 'เช่น ไวยาวัจกรณ์สมชาย',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'กรุณากรอกชื่อแสดงผล';
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
                    LengthLimitingTextInputFormatter(6),
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
      ),
    );
  }
}
