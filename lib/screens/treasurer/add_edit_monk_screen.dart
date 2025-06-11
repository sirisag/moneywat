// lib/screens/treasurer/add_edit_monk_screen.dart
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:sqflite/sqflite.dart'; // For DatabaseException

class AddEditMonkScreen extends StatefulWidget {
  final User? monk; // Null if adding a new monk

  const AddEditMonkScreen({super.key, this.monk});

  @override
  State<AddEditMonkScreen> createState() => _AddEditMonkScreenState();
}

class _AddEditMonkScreenState extends State<AddEditMonkScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = false;

  String _generateMonkPrimaryId() {
    // Monk Primary ID is 6 digits, range 100000-599999 (as per definition)
    final random = Random();
    return (random.nextInt(500000) + 100000)
        .toString(); // Generates 100000-599999
  }

  String _generateMonkSecondaryId() {
    // Monk Secondary ID is 6 digits
    final random = Random();
    return (random.nextInt(900000) + 100000)
        .toString(); // Generates 100000-999999
  }

  @override
  void initState() {
    super.initState();
    if (widget.monk != null) {
      _displayNameController.text = widget.monk!.displayName;
    }
  }

  Future<void> _saveMonk() async {
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
            widget.monk == null
                ? 'ยืนยันการเพิ่มพระใหม่'
                : 'ยืนยันการแก้ไขข้อมูลพระ',
          ),
          content: Text(
            'คุณต้องการบันทึกข้อมูลพระชื่อ "$displayName" ใช่หรือไม่?',
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
      if (widget.monk == null) {
        // Adding new monk
        // Check for duplicate display name
        final existingMonksWithSameName = await _dbHelper
            .getUsersByDisplayNameAndRole(displayName, UserRole.monk);

        if (existingMonksWithSameName.isNotEmpty && mounted) {
          bool? confirmSave = await showDialog<bool>(
            context: context,
            barrierDismissible: false, // User must choose an action
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: const Text('ชื่อซ้ำในระบบ'),
                content: Text(
                  'มีพระชื่อ/ฉายา "$displayName" อยู่ในระบบแล้ว คุณต้องการบันทึกพระรูปใหม่นี้ต่อไปหรือไม่?',
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
        int retries = 10; // Increased retries for potentially denser ID space
        do {
          primaryId = _generateMonkPrimaryId();
          secondaryId = _generateMonkSecondaryId();
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

        final newMonk = User(
          primaryId: primaryId,
          secondaryId: secondaryId,
          displayName: displayName,
          role: UserRole.monk,
          // Hashed PIN will be set by the monk during their own setup
        );
        await _dbHelper.insertUser(newMonk);
        // MonkFundAtTreasurer and MonkFundAtDriver accounts are created
        // when transactions involving them are first recorded.
      } else {
        // Editing existing monk (only display name)
        final updatedMonk = widget.monk!.copyWith(displayName: displayName);
        await _dbHelper.updateUser(updatedMonk); // Using updateUser now
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกข้อมูลพระ "$displayName" สำเร็จ')),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      String errorMessage =
          'เกิดข้อผิดพลาดในการบันทึกข้อมูลพระ: ${e.toString()}';
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
        title: Text(widget.monk == null ? 'เพิ่มพระใหม่' : 'แก้ไขข้อมูลพระ'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(labelText: 'ชื่อ/ฉายาของพระ'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณากรอกชื่อหรือฉายา';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveMonk,
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
