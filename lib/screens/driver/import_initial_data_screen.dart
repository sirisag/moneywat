// lib/screens/driver/import_initial_data_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:moneywat/services/encryption_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moneywat/models/account_balance_models.dart';
import 'package:moneywat/models/transaction_model.dart'; // Import Transaction model

class ImportInitialDataScreen extends StatefulWidget {
  const ImportInitialDataScreen({super.key});

  @override
  State<ImportInitialDataScreen> createState() =>
      _ImportInitialDataScreenState();
}

class _ImportInitialDataScreenState extends State<ImportInitialDataScreen> {
  final EncryptionService _encryptionService = EncryptionService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = false;
  String? _filePath;
  String _statusMessage = 'กรุณาเลือกไฟล์ข้อมูลเริ่มต้น (.วัดencrypted)';

  Future<void> _pickAndProcessFile() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'กำลังเลือกไฟล์...';
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any, // Or specify custom extension if possible
      );

      if (result != null && result.files.single.path != null) {
        _filePath = result.files.single.path;
        setState(() {
          _statusMessage =
              'เลือกไฟล์แล้ว: ${_filePath?.split('/').last}\nกำลังประมวลผล...';
        });

        final file = File(_filePath!);
        final encryptedContent = await file.readAsString();

        final prefs = await SharedPreferences.getInstance();
        final String? treasurerPrimaryId = prefs.getString(
          'associated_treasurer_primary_id',
        );
        final String? treasurerSecondaryId = prefs.getString(
          'associated_treasurer_secondary_id',
        );
        final String? driverPrimaryId = prefs.getString('user_primary_id');

        if (treasurerPrimaryId == null ||
            treasurerSecondaryId == null ||
            driverPrimaryId == null) {
          throw Exception('ไม่พบข้อมูล ID ที่จำเป็นสำหรับการถอดรหัส');
        }

        final decryptedJsonString = _encryptionService.decryptData(
          encryptedContent,
          treasurerPrimaryId,
          treasurerSecondaryId,
        );

        if (decryptedJsonString == null) {
          throw Exception(
            'ไม่สามารถถอดรหัสไฟล์ได้ อาจเป็นเพราะไฟล์ไม่ถูกต้องหรือ ID ไวยาวัจกรณ์ไม่ตรงกัน',
          );
        }

        final db = await _dbHelper.database; // Get database instance
        await db.transaction((txn) async {
          // Start transaction
          final Map<String, dynamic> data = jsonDecode(decryptedJsonString);

          // --- Process Data ---
          // Validate file type from metadata
          if (data['metadata']?['fileType'] != 'initial_driver_data' ||
              data['metadata']?['driverPrimaryId'] != driverPrimaryId) {
            throw Exception('ไฟล์ข้อมูลไม่ถูกต้องสำหรับคนขับรถคนนี้');
          }

          // Save Monk List
          final monkList = data['monkList'] as List<dynamic>?;
          if (monkList != null) {
            for (var monkData in monkList) {
              final monk = User.fromMap(monkData as Map<String, dynamic>);
              await _dbHelper.insertUser(monk, txn: txn);

              // Process initial deposit for this monk
              final initialDeposit = monkData['initialDepositToDriver'] as int?;
              if (initialDeposit != null && initialDeposit > 0) {
                final monkFund = MonkFundAtDriver(
                  monkPrimaryId: monk.primaryId,
                  driverPrimaryId: driverPrimaryId,
                  balance: initialDeposit,
                  lastUpdated: DateTime.now(),
                );
                await _dbHelper.insertOrUpdateMonkFundAtDriver(
                  monkFund,
                  txn: txn,
                );

                // Create a transaction record for this initial deposit
                final initialMonkFundTx = Transaction.create(
                  type: TransactionType.INITIAL_MONK_FUND_AT_DRIVER,
                  amount: initialDeposit,
                  note:
                      'ยอดเริ่มต้นของ ${monk.displayName} ที่ฝากกับคนขับรถ (นำเข้าจากไวยาวัจกรณ์)',
                  recordedByPrimaryId:
                      driverPrimaryId, // This transaction is recorded on driver's device
                  sourceAccountId:
                      treasurerPrimaryId, // Conceptually, the fund came via treasurer
                  destinationAccountId: monk.primaryId, // Belongs to the monk
                );
                await _dbHelper.insertTransaction(initialMonkFundTx, txn: txn);
              }
            }
          }

          // Save Initial Driver Advance
          final initialAdvanceData =
              data['initialDriverAdvance'] as Map<String, dynamic>?;
          if (initialAdvanceData?['amount'] != null) {
            final advanceAccount = DriverAdvanceAccount(
              driverPrimaryId: driverPrimaryId,
              balance: initialAdvanceData!['amount'] as int,
              lastUpdated: DateTime.now(),
            );
            await _dbHelper.insertOrUpdateDriverAdvance(
              advanceAccount,
              txn: txn,
            );

            // Create a transaction record for initial driver advance
            final initialAdvanceTx = Transaction.create(
              type: TransactionType.INITIAL_DRIVER_ADVANCE,
              amount: initialAdvanceData['amount'] as int,
              note:
                  initialAdvanceData['note'] as String? ??
                  'รับเงินสำรองเดินทางเริ่มต้น',
              recordedByPrimaryId: driverPrimaryId,
              sourceAccountId:
                  treasurerPrimaryId, // Source is the treasurer providing the advance
              destinationAccountId:
                  driverPrimaryId, // Destination is the driver
            );
            await _dbHelper.insertTransaction(initialAdvanceTx, txn: txn);
          }
        }); // End transaction

        await prefs.setBool('driver_initial_data_imported', true);
        setState(() {
          _statusMessage = 'นำเข้าข้อมูลเริ่มต้นสำเร็จ!';
          _isLoading = false;
        });
        if (mounted) {
          Navigator.pop(context, true); // Return true to indicate success
        }
      } else {
        // User canceled the picker
        setState(() {
          _statusMessage = 'ยกเลิกการเลือกไฟล์';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'เกิดข้อผิดพลาด: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('นำเข้าข้อมูลเริ่มต้น')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 30),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.file_open),
                      label: const Text('เลือกและประมวลผลไฟล์'),
                      onPressed: _pickAndProcessFile,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
