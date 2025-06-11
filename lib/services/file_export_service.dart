// lib/services/file_export_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/models/transaction_model.dart'; // For Transaction model
import 'package:moneywat/models/account_balance_models.dart'; // For AccountBalance models
import 'package:moneywat/services/database_helper.dart';
import 'package:moneywat/services/encryption_service.dart';
import 'package:moneywat/utils/constants.dart'; // Import constants
import 'package:path_provider/path_provider.dart';
//import 'package:permission_handler/permission_handler.dart';
//import 'package:shared_preferences/shared_preferences.dart';

class FileExportService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final EncryptionService _encryptionService = EncryptionService();

  Future<String?> exportInitialDriverData({
    required User driver,
    required List<User> allMonks,
    required int initialAdvanceAmount, // เงินสำรองเดินทางเริ่มต้น
    required Map<String, int>
    initialMonkDepositsToDriver, // Map<monkPrimaryId, amount>
    required String treasurerPrimaryId,
    required String treasurerSecondaryId,
  }) async {
    try {
      // 1. Prepare data structure
      final timestamp = DateTime.now().toIso8601String();
      final dataToExport = {
        'metadata': {
          'fileType': AppConstants.fileTypeInitialDriverData,
          'version': '1.0.0', // App/data version
          'createdAt': timestamp,
          'treasurerPrimaryId': treasurerPrimaryId, // Sender
          // 'treasurerSecondaryId': treasurerSecondaryId, // Not strictly needed in file, but good for verification
          'driverPrimaryId': driver.primaryId, // Receiver
          'driverSecondaryId': driver.secondaryId,
        },
        'driverInfo': {
          'primaryId': driver.primaryId,
          'secondaryId': driver.secondaryId,
          'displayName': driver.displayName, // Name set by treasurer
        },
        'monkList': allMonks.map(
          (monk) {
            final monkMap = monk.toMap(forFileExport: true);
            // Add initialDepositToDriver specifically for this export context
            monkMap['initialDepositToDriver'] =
                initialMonkDepositsToDriver[monk.primaryId] ?? 0;
            return monkMap;
          },
          // monk.toMap(forFileExport: true) already includes primaryId, secondaryId, displayName, role, status
          // We just need to add 'initialDepositToDriver'
        ).toList(),
        'initialDriverAdvance': {
          'amount': initialAdvanceAmount,
          'note': 'เงินสำรองเดินทางเริ่มต้นจากไวยาวัจกรณ์',
        },
        // Add any other necessary initial data
      };

      // 2. Convert to JSON string
      final jsonDataString = jsonEncode(dataToExport);

      // 3. Encrypt the JSON data
      final encryptedDataString = _encryptionService.encryptData(
        jsonDataString,
        treasurerPrimaryId,
        treasurerSecondaryId,
      );

      // 4. Save the encrypted file
      final directory = await getApplicationDocumentsDirectory();
      final filePath =
          '${directory.path}/Data_for_driver_${driver.displayName.replaceAll(' ', '_')}_${driver.primaryId}_${DateTime.now().millisecondsSinceEpoch}.วัดencrypted'; // Custom extension
      final file = File(filePath);
      await file.writeAsString(encryptedDataString);

      if (kDebugMode) {
        print('ไฟล์ข้อมูลเริ่มต้นสำหรับคนขับรถถูกสร้างที่: $filePath');
      }

      return filePath;
    } catch (e) {
      print('Error exporting initial driver data: $e');
      return null;
    }
  }

  Future<String?> exportDriverDataToTreasurer({
    required String driverPrimaryId,
    required String driverSecondaryId,
    required String driverDisplayName,
    required List<Transaction>
    monkTransactions, // Pass pre-fetched and filtered transactions
    required List<Transaction>
    tripExpenses, // Pass pre-fetched and filtered transactions
    required List<User> newMonks, // Pass pre-fetched new monks
    required int advanceReturnedAmount,
    required String treasurerPrimaryId, // For encryption
    required String treasurerSecondaryId, // For encryption
  }) async {
    try {
      final timestamp = DateTime.now().toIso8601String();
      // 2. Prepare data structure
      final dataToExport = {
        'metadata': {
          'fileType': AppConstants.fileTypeDriverDataToTreasurer,
          'version': '1.0.0',
          'createdAt': timestamp,
          'driverPrimaryId': driverPrimaryId,
          'driverSecondaryId': driverSecondaryId,
        },
        'driverInfo': {
          'primaryId': driverPrimaryId,
          'displayName': driverDisplayName,
        },
        'monkTransactions': monkTransactions.map((tx) => tx.toMap()).toList(),
        'tripExpenses': tripExpenses.map((tx) => tx.toMap()).toList(),
        'newMonksCreatedByDriver': newMonks
            .map((user) => user.toMap(forFileExport: true))
            .toList(),
        'advanceReturnedToTemple': {
          'amount': advanceReturnedAmount,
          'note': 'คืนเงินสำรองเดินทาง', // Default note
        },
      };

      // 3. Convert to JSON string
      final jsonDataString = jsonEncode(dataToExport);

      // 4. Encrypt the JSON data using Treasurer's IDs
      final encryptedDataString = _encryptionService.encryptData(
        jsonDataString,
        treasurerPrimaryId,
        treasurerSecondaryId,
      );

      // 5. Save the encrypted file
      final directory = await getApplicationDocumentsDirectory();
      final filePath =
          '${directory.path}/Export_from_driver_${driverDisplayName.replaceAll(' ', '_')}_${driverPrimaryId}_${DateTime.now().millisecondsSinceEpoch}.วัดencrypted';
      final file = File(filePath);
      await file.writeAsString(encryptedDataString);

      if (kDebugMode) {
        print('ไฟล์ข้อมูลจากคนขับรถถูกสร้างที่: $filePath');
      }

      return filePath;
    } catch (e) {
      print('Error exporting driver data to treasurer: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> importDriverDataFromFile({
    required String filePath,
    required String currentTreasurerPrimaryId,
    required String currentTreasurerSecondaryId,
  }) async {
    int totalMonkFundsReceived = 0;
    int totalTripExpenses = 0;
    int advanceReturnedAmount = 0;
    String driverPrimaryIdFromFile = "";
    Map<String, dynamic> parsedData = {};
    List<Transaction> transactionsToCommit = [];
    List<User> newMonksToCommit = [];

    try {
      // No explicit transaction here, as the commit will happen in the calling screen
      // after treasurer confirms cash.
      final file = File(filePath);
      if (!await file.exists()) {
        print('Import Error: File not found at $filePath');
        throw Exception('File not found at $filePath');
      }
      final encryptedContent = await file.readAsString();

      final decryptedJsonString = _encryptionService.decryptData(
        encryptedContent,
        currentTreasurerPrimaryId, // Use current treasurer's ID for decryption key
        currentTreasurerSecondaryId,
      );

      if (decryptedJsonString == null) {
        throw Exception(
          'ไม่สามารถถอดรหัสไฟล์ได้ อาจเป็นเพราะไฟล์ไม่ถูกต้องหรือ ID ไวยาวัจกรณ์ไม่ตรงกัน',
        );
      }

      parsedData = jsonDecode(decryptedJsonString);

      // --- Validate Metadata ---
      final metadata = parsedData['metadata'] as Map<String, dynamic>?;
      if (metadata == null ||
          metadata['fileType'] != AppConstants.fileTypeDriverDataToTreasurer) {
        throw Exception('ประเภทไฟล์ไม่ถูกต้อง (ไม่ใช่ข้อมูลจากคนขับรถ)');
      }
      driverPrimaryIdFromFile = metadata['driverPrimaryId'] as String;

      // --- Process Monk Transactions ---
      final monkTransactionsData =
          parsedData['monkTransactions'] as List<dynamic>?;
      if (monkTransactionsData != null) {
        Set<String> processedMonkTxUuids = {};
        for (var txData in monkTransactionsData) {
          final txMap = txData as Map<String, dynamic>;
          final originalTransaction = Transaction.fromMap(txMap);

          final newTransactionForTreasurer = Transaction.create(
            type: originalTransaction.type,
            amount: originalTransaction.amount,
            note: originalTransaction.note,
            recordedByPrimaryId: driverPrimaryIdFromFile, // Use ID from file
            processedByPrimaryId:
                currentTreasurerPrimaryId, // Current treasurer processing it
            sourceAccountId: originalTransaction.sourceAccountId,
            destinationAccountId: originalTransaction.destinationAccountId,
            customTimestamp: originalTransaction.timestamp,
            status: TransactionStatus.pendingReconciliationByTreasurer,
          );
          // Ensure UUID from original file is preserved
          final finalTransaction =
              newTransactionForTreasurer.uuid == originalTransaction.uuid
              ? newTransactionForTreasurer
              : newTransactionForTreasurer.copyWith(
                  uuid: originalTransaction.uuid,
                );

          final existingTransaction = await _dbHelper.getTransaction(
            finalTransaction.uuid,
          );
          if (existingTransaction == null ||
              existingTransaction.status !=
                  TransactionStatus.reconciledByTreasurer) {
            transactionsToCommit.add(finalTransaction);

            // Accumulate totalMonkFundsReceived ONLY from FORWARD_MONK_FUND_TO_TREASURER transactions
            if (finalTransaction.type ==
                TransactionType.FORWARD_MONK_FUND_TO_TREASURER) {
              totalMonkFundsReceived += finalTransaction.amount;
            }
            // The original DEPOSIT_FROM_MONK_TO_DRIVER and WITHDRAWAL_FOR_MONK_FROM_DRIVER
            // are still imported for audit/detail but do not contribute to the cash treasurer expects to receive directly.
            // That cash amount is now represented by FORWARD_MONK_FUND_TO_TREASURER.

            // Old logic for summing up individual monk tx for totalMonkFundsReceived:
            // if (!processedMonkTxUuids.contains(finalTransaction.uuid)) { ... }
            // This processedMonkTxUuids logic might still be useful if you want to avoid double-counting
            // other transaction types if they could somehow be duplicated in the list.
            // For FORWARD_MONK_FUND_TO_TREASURER, there should ideally be only one active per monk per export.
            if (!processedMonkTxUuids.contains(finalTransaction.uuid)) {
              processedMonkTxUuids.add(finalTransaction.uuid);
            }
          } else {
            // Transaction already exists and is reconciled, skip processing it again.
            print(
              'Transaction ${finalTransaction.uuid} already exists and reconciled. Skipping.',
            );
          }
        }
      }

      // --- Process Trip Expenses ---
      final tripExpensesData = parsedData['tripExpenses'] as List<dynamic>?;
      if (tripExpensesData != null) {
        for (var txData in tripExpensesData) {
          final txMap = txData as Map<String, dynamic>;
          final originalTransaction = Transaction.fromMap(txMap);

          final newExpenseForTreasurer = Transaction.create(
            type: originalTransaction.type,
            amount: originalTransaction.amount,
            note: originalTransaction.note,
            recordedByPrimaryId: driverPrimaryIdFromFile,
            processedByPrimaryId: currentTreasurerPrimaryId,
            sourceAccountId: originalTransaction.sourceAccountId,
            destinationAccountId: originalTransaction.destinationAccountId,
            expenseCategory: originalTransaction.expenseCategory,
            customTimestamp: originalTransaction.timestamp,
            status: TransactionStatus.pendingReconciliationByTreasurer,
          );
          final finalExpense =
              newExpenseForTreasurer.uuid == originalTransaction.uuid
              ? newExpenseForTreasurer
              : newExpenseForTreasurer.copyWith(uuid: originalTransaction.uuid);

          final existingExpenseTransaction = await _dbHelper.getTransaction(
            finalExpense.uuid,
          );
          if (existingExpenseTransaction == null ||
              existingExpenseTransaction.status !=
                  TransactionStatus.reconciledByTreasurer) {
            transactionsToCommit.add(finalExpense);
            totalTripExpenses += originalTransaction.amount;
          } else {
            print(
              'Expense transaction ${finalExpense.uuid} already exists and reconciled. Skipping.',
            );
          }
        }
      }

      // --- Process Advance Returned To Temple ---
      final advanceReturnedData =
          parsedData['advanceReturnedToTemple'] as Map<String, dynamic>?;
      if (advanceReturnedData != null &&
          advanceReturnedData['amount'] != null) {
        advanceReturnedAmount = advanceReturnedData['amount'] as int;
        final returnNote =
            advanceReturnedData['note'] as String? ?? 'คนขับรถคืนเงินสำรอง';

        if (advanceReturnedAmount > 0) {
          // Only create transaction if amount is positive
          final advanceReturnTx = Transaction.create(
            type: TransactionType.RETURN_DRIVER_ADVANCE_TO_TREASURER,
            amount: advanceReturnedAmount,
            note: '$returnNote (รอการกระทบยอด)',
            recordedByPrimaryId: driverPrimaryIdFromFile,
            processedByPrimaryId: currentTreasurerPrimaryId,
            sourceAccountId: driverPrimaryIdFromFile, // Driver is the source
            destinationAccountId: currentTreasurerPrimaryId,
            status: TransactionStatus.pendingReconciliationByTreasurer,
          );
          transactionsToCommit.add(advanceReturnTx);
        }
      }

      // --- Process New Monks Created By Driver ---
      final newMonksData =
          parsedData['newMonksCreatedByDriver'] as List<dynamic>?;
      if (newMonksData != null) {
        for (var monkData in newMonksData) {
          final newMonk = User.fromMap(monkData as Map<String, dynamic>);
          // Check if monk already exists to avoid overwriting treasurer's edits
          final existingMonk = await _dbHelper.getUser(newMonk.primaryId);
          if (existingMonk == null) {
            newMonksToCommit.add(newMonk);
          } else {
            // Optionally, update specific fields if needed, or log that monk already exists.
            // For now, if monk exists, we don't overwrite.
            print(
              "Monk ${newMonk.primaryId} already exists. Skipping insert from driver file.",
            );
          }
        }
      }

      if (kDebugMode) {
        print('เตรียมข้อมูลนำเข้าจากคนขับรถ $driverPrimaryIdFromFile สำเร็จ');
      }
      return {
        'success': true,
        'driverPrimaryId': driverPrimaryIdFromFile,
        'driverDisplayName':
            parsedData['driverInfo']?['displayName'] ?? driverPrimaryIdFromFile,
        'totalMonkFundsReceived': totalMonkFundsReceived,
        'totalTripExpenses': totalTripExpenses,
        'advanceReturnedAmount': advanceReturnedAmount,
        'transactionsToCommit': transactionsToCommit,
        'newMonksToCommit': newMonksToCommit,
      };
    } catch (e) {
      print('Error importing driver data: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<String?> exportTreasurerUpdateToDriver({
    required User driverToUpdate, // Driver who will receive this update
    required int newAdvanceGiven, // New advance amount treasurer is giving
    required List<Map<String, dynamic>>
    monkFundsToTransfer, // List of {'monkPrimaryId': String, 'amount': int}
    required String treasurerPrimaryId,
    required String treasurerSecondaryId,
  }) async {
    try {
      final timestamp = DateTime.now().toIso8601String();

      final List<Transaction> reconciledDriverTransactions = await _dbHelper
          .getTransactionsByStatusAndProcessor(
            TransactionStatus.reconciledByTreasurer,
            treasurerPrimaryId,
          );

      final List<Map<String, dynamic>> reconciledTransactionUpdates =
          reconciledDriverTransactions
              .where((tx) => tx.recordedByPrimaryId == driverToUpdate.primaryId)
              .map((tx) => {'uuid': tx.uuid, 'status': tx.status?.name})
              .toList();

      final DriverAdvanceAccount? driverAdvanceAccount = await _dbHelper
          .getDriverAdvance(driverToUpdate.primaryId);
      final int updatedDriverAdvanceBalance =
          driverAdvanceAccount?.balance ?? 0;

      final List<User> allMonks = await _dbHelper.getAllUsers();

      final dataToExport = {
        'metadata': {
          'fileType': AppConstants.fileTypeTreasurerUpdateForDriver,
          'version': '1.0.0',
          'createdAt': timestamp,
          'treasurerPrimaryId': treasurerPrimaryId,
          'driverPrimaryId': driverToUpdate.primaryId,
        },
        'reconciledTransactionUpdates': reconciledTransactionUpdates,
        'newDriverAdvanceGiven': {
          'amount': newAdvanceGiven,
          'note': newAdvanceGiven > 0
              ? 'เงินสำรองเดินทางเพิ่มเติมจากไวยาวัจกรณ์'
              : '',
        },
        'monkFundsTransferredToDriver': monkFundsToTransfer,
        'updatedDriverAdvanceBalance': updatedDriverAdvanceBalance,
        'updatedMonkList': allMonks
            .map((monk) => monk.toMap(forFileExport: true))
            .toList(),
      };

      final jsonDataString = jsonEncode(dataToExport);

      final encryptedDataString = _encryptionService.encryptData(
        jsonDataString,
        treasurerPrimaryId,
        treasurerSecondaryId,
      );

      final directory = await getApplicationDocumentsDirectory();
      final filePath =
          '${directory.path}/Update_for_driver_${driverToUpdate.displayName.replaceAll(' ', '_')}_${driverToUpdate.primaryId}_${DateTime.now().millisecondsSinceEpoch}.วัดencrypted';
      final file = File(filePath);
      await file.writeAsString(encryptedDataString);

      return filePath;
    } catch (e) {
      print('Error exporting treasurer update to driver: $e');
      return null;
    }
  }

  String? decryptData(
    String encryptedTextWithIv,
    String treasurerPrimaryId,
    String treasurerSecondaryId,
  ) {
    return _encryptionService.decryptData(
      encryptedTextWithIv,
      treasurerPrimaryId,
      treasurerSecondaryId,
    );
  }
}
