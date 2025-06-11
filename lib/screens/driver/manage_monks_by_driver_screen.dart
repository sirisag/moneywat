// lib/screens/driver/manage_monks_by_driver_screen.dart
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/services/database_helper.dart';
// For DatabaseException
import 'package:shared_preferences/shared_preferences.dart';

class ManageMonksByDriverScreen extends StatefulWidget {
  const ManageMonksByDriverScreen({super.key});

  @override
  State<ManageMonksByDriverScreen> createState() =>
      _ManageMonksByDriverScreenState();
}

class _ManageMonksByDriverScreenState extends State<ManageMonksByDriverScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = false;
  List<User> _allMonksInDriverDb = [];
  User? _editingMonk; // To store monk being edited (for add/edit dialog)
  bool _isAddingNewMonk = false; // To control dialog mode

  String? _associatedTreasurerPrimaryId;
  String? _associatedTreasurerSecondaryId;

  @override
  void initState() {
    super.initState();
    _loadAssociatedTreasurerIds();
    _loadAllMonksFromDriverDb();
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

  Future<void> _loadAllMonksFromDriverDb() async {
    setState(() => _isLoading = true);
    try {
      // Assuming driver's local DB might have monks from initial import or created by driver
      final monks = await _dbHelper.getUsersByRole(UserRole.monk);
      if (mounted) {
        setState(() {
          _allMonksInDriverDb = monks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      // Handle error
    }
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
    final User? monkToSave = _editingMonk; // Use the monk being edited
    final bool isNew = _isAddingNewMonk;

    try {
      if (isNew || monkToSave == null) {
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
        final updatedMonk = monkToSave.copyWith(
          displayName: displayName,
        ); // Only display name can be edited here by driver
        await _dbHelper.updateUser(updatedMonk);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('แก้ไขข้อมูลพระ "${updatedMonk.displayName}" สำเร็จ'),
          ),
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true); // Close dialog and indicate success
        _loadAllMonksFromDriverDb(); // Refresh the list
      }
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

  Future<void> _showAddEditMonkDialog({User? monk}) async {
    _isAddingNewMonk = monk == null;
    _editingMonk = monk;
    _displayNameController.text = monk?.displayName ?? '';

    // ignore: use_build_context_synchronously
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          // Use StatefulBuilder for dialog internal state
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                _isAddingNewMonk
                    ? 'เพิ่มพระใหม่'
                    : 'แก้ไขชื่อพระ "${monk!.displayName}"',
              ),
              content: Form(
                key: _formKey, // Use the same form key
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_isAddingNewMonk)
                      TextFormField(
                        controller: _displayNameController,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อ/ฉายาของพระ',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'กรุณากรอกชื่อหรือฉายา';
                          }
                          return null;
                        },
                      ),
                    if (_isAddingNewMonk &&
                        _associatedTreasurerPrimaryId != null &&
                        _associatedTreasurerSecondaryId != null) ...[
                      const SizedBox(height: 10),
                      Card(
                        color: Colors.amber.shade100,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            'เมื่อสร้างบัญชีพระใหม่ กรุณาแจ้งให้พระทราบ ID ของไวยาวัจกรณ์ที่เกี่ยวข้องเพื่อใช้ในการตั้งค่าแอปของพระ:\nPrimary ID: $_associatedTreasurerPrimaryId\nSecondary ID: $_associatedTreasurerSecondaryId',
                            style: TextStyle(
                              color: Colors.amber.shade900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('ยกเลิก'),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : () => _saveMonk(),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('บันทึก'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == true) {
      // _loadAllMonksFromDriverDb(); // Already called in _saveMonk on success
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('จัดการบัญชีพระ (โดยคนขับรถ)')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allMonksInDriverDb.isEmpty
          ? const Center(child: Text('ยังไม่มีข้อมูลพระในระบบของคนขับรถ'))
          : ListView.builder(
              itemCount: _allMonksInDriverDb.length,
              itemBuilder: (context, index) {
                final monk = _allMonksInDriverDb[index];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).primaryColorLight,
                      child: Text(
                        monk.displayName.isNotEmpty
                            ? monk.displayName[0].toUpperCase()
                            : 'M',
                        style: TextStyle(
                          color: Theme.of(context).primaryColorDark,
                        ),
                      ),
                    ),
                    title: Text(
                      monk.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('ID: ${monk.primaryId}'),
                    isThreeLine:
                        false, // Status removed, so two lines might be enough
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit_name') {
                          _showAddEditMonkDialog(monk: monk);
                        }
                      },
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<String>>[
                            const PopupMenuItem<String>(
                              value: 'edit_name',
                              child: ListTile(
                                leading: Icon(Icons.edit_outlined),
                                title: Text('แก้ไขชื่อ'),
                              ),
                            ),
                          ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditMonkDialog(),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('เพิ่มพระใหม่'),
      ),
    );
  }
}
