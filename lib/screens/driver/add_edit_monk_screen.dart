// lib/screens/driver/add_edit_monk_screen.dart
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/services/database_helper.dart';
// For DatabaseException
import 'package:shared_preferences/shared_preferences.dart';

class AddEditMonkByDriverScreen extends StatefulWidget {
  final User? monk; // Null if adding a new monk

  const AddEditMonkByDriverScreen({super.key, this.monk});

  @override
  State<AddEditMonkByDriverScreen> createState() =>
      _AddEditMonkByDriverScreenState();
}

class _AddEditMonkByDriverScreenState extends State<AddEditMonkByDriverScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = false;

  String? _associatedTreasurerPrimaryId;
  String? _associatedTreasurerSecondaryId;

  @override
  void initState() {
    super.initState();
    if (widget.monk != null) {
      _displayNameController.text = widget.monk!.displayName;
    }
    _loadAssociatedTreasurerIds();
  }

  Future<void> _loadAssociatedTreasurerIds() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _associatedTreasurerPrimaryId = prefs.getString(
        'associated_treasurer_primary_id',
      );
      _associatedTreasurerSecondaryId = prefs.getString(
        'associated_treasurer_secondary_id',
      );
    });
  }

  String _generateMonkPrimaryId() {
    // Monk Primary ID is 6 digits, range 600000-999999 (for driver creation)
    final random = Random();
    return (random.nextInt(400000) + 600000)
        .toString(); // Generates 600000-999999
  }

  String _generateMonkSecondaryId() {
    // Monk Secondary ID is 6 digits
    final random = Random();
    return (random.nextInt(900000) + 100000)
        .toString(); // Generates 100000-999999
  }

  Future<void> _saveMonk() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isLoading = true);

    final displayName = _displayNameController.text;

    try {
      if (widget.monk == null) {
        // Adding new monk
        final existingMonksWithSameName = await _dbHelper
            .getUsersByDisplayNameAndRole(displayName, UserRole.monk);

        if (existingMonksWithSameName.isNotEmpty && mounted) {
          bool? confirmSave = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: const Text('ชื่อซ้ำในระบบ'),
                content: Text(
                  'มีพระชื่อ/ฉายา "$displayName" อยู่ในระบบแล้ว คุณต้องการบันทึกพระรูปใหม่นี้ต่อไปหรือไม่?',
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('แก้ไขชื่อ'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('บันทึกต่อไป'),
                  ),
                ],
              );
            },
          );
          if (confirmSave == null || !confirmSave) {
            setState(() => _isLoading = false);
            return;
          }
        }

        String primaryId;
        String secondaryId;
        bool primaryIdTaken;
        bool secondaryIdTaken;
        int retries = 10;
        do {
          primaryId = _generateMonkPrimaryId();
          secondaryId = _generateMonkSecondaryId();
          primaryIdTaken = (await _dbHelper.getUser(primaryId)) != null;
          secondaryIdTaken = await _dbHelper.isSecondaryIdTaken(secondaryId);
          retries--;
        } while ((primaryIdTaken || secondaryIdTaken) && retries > 0);

        if (primaryIdTaken || secondaryIdTaken) {
          throw Exception('ไม่สามารถสร้าง ID ที่ไม่ซ้ำกันได้ กรุณาลองอีกครั้ง');
        }

        final newMonk = User(
          primaryId: primaryId,
          secondaryId: secondaryId,
          displayName: displayName,
          role: UserRole.monk,
        );
        await _dbHelper.insertUser(newMonk);
        // Show treasurer IDs for the monk to note down
        if (mounted &&
            _associatedTreasurerPrimaryId != null &&
            _associatedTreasurerSecondaryId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'บันทึกข้อมูลพระ "$displayName" สำเร็จ (ID: $primaryId)\nแจ้งให้พระใช้ ID ไวยาวัจกรณ์: $_associatedTreasurerPrimaryId / $_associatedTreasurerSecondaryId สำหรับตั้งค่าแอป',
              ),
              duration: const Duration(seconds: 7),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'บันทึกข้อมูลพระ "$displayName" สำเร็จ (ID: $primaryId)',
              ),
            ),
          );
        }
      } else {
        // Editing existing monk
        final updatedMonk = widget.monk!.copyWith(displayName: displayName);
        await _dbHelper.updateUser(updatedMonk);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('แก้ไขข้อมูลพระ "$displayName" สำเร็จ')),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.monk == null ? 'เพิ่มพระใหม่ (โดยคนขับรถ)' : 'แก้ไขข้อมูลพระ',
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
                decoration: const InputDecoration(labelText: 'ชื่อ/ฉายาของพระ'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณากรอกชื่อหรือฉายา';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveMonk,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('บันทึก'),
              ),
              if (widget.monk == null &&
                  _associatedTreasurerPrimaryId != null &&
                  _associatedTreasurerSecondaryId != null) ...[
                const SizedBox(height: 20),
                Card(
                  color: Colors.amber.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      'เมื่อสร้างบัญชีพระใหม่ กรุณาแจ้งให้พระทราบ ID ของไวยาวัจกรณ์ที่เกี่ยวข้องเพื่อใช้ในการตั้งค่าแอปของพระ:\nPrimary ID: $_associatedTreasurerPrimaryId\nSecondary ID: $_associatedTreasurerSecondaryId',
                      style: TextStyle(color: Colors.amber.shade900),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
