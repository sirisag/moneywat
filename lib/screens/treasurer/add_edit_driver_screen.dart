// lib/screens/treasurer/add_edit_driver_screen.dart
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:sqflite/sqflite.dart'; // For DatabaseException

class AddEditDriverScreen extends StatefulWidget {
  final User? driver; // Null if adding a new driver

  const AddEditDriverScreen({super.key, this.driver});

  @override
  State<AddEditDriverScreen> createState() => _AddEditDriverScreenState();
}

class _AddEditDriverScreenState extends State<AddEditDriverScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = false;

  String _generateDriverPrimaryId() {
    // Driver Primary ID is 5 digits
    // Ensure this logic doesn't clash with existing IDs if possible,
    // or check for uniqueness before saving.
    final random = Random();
    return (random.nextInt(90000) + 10000).toString(); // Generates 10000-99999
  }

  String _generateDriverSecondaryId() {
    // Driver Secondary ID is 5 digits
    final random = Random();
    return (random.nextInt(90000) + 10000).toString(); // Generates 10000-99999
  }

  @override
  void initState() {
    super.initState();
    if (widget.driver != null) {
      _displayNameController.text = widget.driver!.displayName;
    }
  }

  Future<void> _saveDriver() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isLoading = true);

    final displayName = _displayNameController.text;

    // Show confirmation dialog before proceeding
    bool? confirmSaveDetails = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            widget.driver == null
                ? 'ยืนยันการเพิ่มคนขับรถใหม่'
                : 'ยืนยันการแก้ไขข้อมูลคนขับรถ',
          ),
          content: Text(
            'คุณต้องการบันทึกข้อมูลคนขับรถชื่อ "$displayName" ใช่หรือไม่?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: const Text('ยืนยัน'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmSaveDetails == null || !confirmSaveDetails) {
      setState(() => _isLoading = false);
      return; // User cancelled
    }

    try {
      if (widget.driver == null) {
        // Adding new driver
        // Check for duplicate display name
        final existingDriversWithSameName = await _dbHelper
            .getUsersByDisplayNameAndRole(displayName, UserRole.driver);

        if (existingDriversWithSameName.isNotEmpty && mounted) {
          bool? confirmSave = await showDialog<bool>(
            context: context,
            barrierDismissible: false, // User must choose an action
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: const Text('ชื่อซ้ำในระบบ'),
                content: Text(
                  'มีคนขับรถชื่อ "$displayName" อยู่ในระบบแล้ว คุณต้องการบันทึกคนขับรถคนใหม่นี้ต่อไปหรือไม่?',
                ),
                actions: <Widget>[
                  TextButton(
                    child: const Text('แก้ไขชื่อ'),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                  ),
                  TextButton(
                    child: const Text('บันทึกต่อไป'),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                  ),
                ],
              );
            },
          );
          if (confirmSave == null || !confirmSave) {
            setState(() => _isLoading = false);
            return; // User chose to edit or dismissed
          }
        }

        String primaryId;
        String secondaryId;
        bool primaryIdTaken;
        bool secondaryIdTaken;

        // Attempt to generate unique IDs (simple retry mechanism)
        int retries = 10; // Increased retries for consistency
        do {
          primaryId = _generateDriverPrimaryId();
          secondaryId = _generateDriverSecondaryId();
          primaryIdTaken = (await _dbHelper.getUser(primaryId)) != null;
          secondaryIdTaken = await _dbHelper.isSecondaryIdTaken(secondaryId);
          retries--;
        } while ((primaryIdTaken || secondaryIdTaken) && retries > 0);

        if (primaryIdTaken || secondaryIdTaken) {
          String idErrorMsg =
              'ไม่สามารถสร้าง ID ที่ไม่ซ้ำกันได้ กรุณาลองอีกครั้ง';
          if (primaryIdTaken && secondaryIdTaken) {
            idErrorMsg =
                'ไม่สามารถสร้าง Primary ID และ Secondary ID ที่ไม่ซ้ำกันได้ กรุณาลองอีกครั้ง';
          } else if (primaryIdTaken) {
            idErrorMsg =
                'ไม่สามารถสร้าง Primary ID ที่ไม่ซ้ำกันได้ กรุณาลองอีกครั้ง';
          } else if (secondaryIdTaken) {
            idErrorMsg =
                'ไม่สามารถสร้าง Secondary ID ที่ไม่ซ้ำกันได้ กรุณาลองอีกครั้ง';
          }
          throw Exception(idErrorMsg);
        }

        final newDriver = User(
          primaryId: primaryId,
          secondaryId: secondaryId,
          displayName: displayName,
          role: UserRole.driver,
          // Hashed PIN will be set by the driver during their own setup
        );
        await _dbHelper.insertUser(newDriver);
        // Note: DriverAdvanceAccount is created when the driver sets up their app.
      } else {
        // Editing existing driver (only display name for now)
        final updatedDriver = widget.driver!.copyWith(displayName: displayName);
        await _dbHelper.updateUser(updatedDriver); // Use updateUser for edits
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกข้อมูลคนขับรถ "$displayName" สำเร็จ')),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      String errorMessage =
          'เกิดข้อผิดพลาดในการบันทึกข้อมูลคนขับรถ: ${e.toString()}';
      if (e is DatabaseException && e.isUniqueConstraintError()) {
        if (e.toString().toLowerCase().contains('users.secondaryid')) {
          errorMessage =
              'Secondary ID ที่ระบบสุ่มเกิดซ้ำกับที่มีอยู่ กรุณาลองบันทึกใหม่อีกครั้ง';
        } else if (e.toString().toLowerCase().contains('users.primaryid')) {
          // Should be caught by retry loop, but as a fallback
          errorMessage =
              'Primary ID ที่ระบบสุ่มเกิดซ้ำกับที่มีอยู่ กรุณาลองบันทึกใหม่อีกครั้ง';
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.driver == null ? 'เพิ่มคนขับรถใหม่' : 'แก้ไขข้อมูลคนขับรถ',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อแสดงผลของคนขับรถ',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณากรอกชื่อแสดงผล';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveDriver,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('บันทึก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
