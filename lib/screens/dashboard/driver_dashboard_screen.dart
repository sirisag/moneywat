// lib/screens/dashboard/driver_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Import for kDebugMode
import 'package:flutter/services.dart'; // Import for FilteringTextInputFormatter
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moneywat/screens/auth/universal_login_setup_screen.dart'; // For logout
// Import screen for importing initial data (to be created)
import 'package:moneywat/screens/driver/import_initial_data_screen.dart';
// Import screens for recording transactions (to be created)
import 'package:moneywat/screens/driver/record_monk_transaction_screen.dart';
import 'package:moneywat/screens/driver/record_trip_expense_screen.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:moneywat/models/account_balance_models.dart';
import 'package:intl/intl.dart'; // For number formatting
import 'package:moneywat/screens/driver/monk_transaction_history_screen.dart'; // Import history screen
import 'package:moneywat/screens/driver/driver_transaction_history_screen.dart'; // Import driver's own history screen
import 'package:moneywat/models/user_model.dart'; // For User model
import 'package:moneywat/models/transaction_model.dart'; // For Transaction model
import 'package:moneywat/services/file_export_service.dart'; // For FileExportService
import 'package:moneywat/screens/driver/manage_monks_by_driver_screen.dart'; // Changed to ManageMonksByDriverScreen
import 'package:share_plus/share_plus.dart'; // For sharing files
import 'package:moneywat/utils/constants.dart'; // For AppConstants
import 'package:file_picker/file_picker.dart'; // Import FilePicker
import 'dart:io'; // Import for File class
import 'dart:convert'; // Import for jsonDecode

class MonkForExportDialog {
  final User monk;
  final DateTime? lastActivity;
  final int balanceWithDriver;

  MonkForExportDialog({
    required this.monk,
    this.lastActivity,
    required this.balanceWithDriver,
  });
}

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FileExportService _fileExportService = FileExportService();
  bool _initialDataImported = false;
  DriverAdvanceAccount? _driverAdvanceAccount;
  bool _isLoadingBalance = true;
  bool _isProcessingFile = false; // For import/export loading state
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );
  String? _currentDriverId; // To store current driver's ID
  String? _currentDriverDisplayName;

  @override
  void initState() {
    super.initState();
    _checkInitialDataStatus();
  }

  Future<void> _checkInitialDataStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _initialDataImported =
          prefs.getBool(AppConstants.driverInitialDataImported) ?? false;
      _currentDriverId = prefs.getString(AppConstants.userPrimaryId);
      _currentDriverDisplayName = prefs.getString(AppConstants.userDisplayName);
    });
    if (_initialDataImported) {
      _loadDriverAdvanceBalance();
    } else {
      if (mounted) {
        setState(() => _isLoadingBalance = false);
      }
    }
  }

  Future<void> _loadDriverAdvanceBalance() async {
    if (!mounted) return;
    setState(() => _isLoadingBalance = true);
    // _currentDriverId should be loaded in _checkInitialDataStatus
    if (_currentDriverId != null) {
      final account = await _dbHelper.getDriverAdvance(_currentDriverId!);
      if (mounted) {
        setState(() {
          _driverAdvanceAccount = account;
          _isLoadingBalance = false;
        });
      }
    } else {
      if (mounted) {
        setState(() => _isLoadingBalance = false);
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clears all data, effectively logging out
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const UniversalLoginSetupScreen(),
        ),
        (Route<dynamic> route) => false,
      );
    }
  }

  void _navigateToImportInitialData() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ImportInitialDataScreen()),
    );
    if (result == true && mounted) {
      _checkInitialDataStatus(); // This will also call _loadDriverAdvanceBalance if successful
    }
  }

  void _navigateToRecordMonkTransaction() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RecordMonkTransactionScreen(),
      ),
    );
    if (result == true && mounted) {
      _loadDriverAdvanceBalance(); // Reload balance after transaction
    }
  }

  void _navigateToRecordTripExpense() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RecordTripExpenseScreen()),
    );
    if (result == true && mounted) {
      _loadDriverAdvanceBalance(); // Reload balance after transaction
    }
  }

  void _navigateToMonkTransactionHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MonkTransactionHistoryScreen(),
      ),
    );
  }

  void _navigateToDriverTransactionHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DriverTransactionHistoryScreen(),
      ),
    );
  }

  void _navigateToManageMonksByDriver() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ManageMonksByDriverScreen(),
      ), // Changed to ManageMonksByDriverScreen
    );
    if (result == true && mounted) {
      // Optionally, reload any data if needed, though adding a monk might not directly affect driver's dashboard balance.
      // _loadDriverAdvanceBalance();
    }
  }

  Future<void> _showExportDataDialog() async {
    if (_currentDriverId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบข้อมูลคนขับรถปัจจุบัน')),
      );
      return;
    }

    if (!mounted) return; // Early exit if not mounted

    // Fetch monks this driver has funds for
    final List<MonkFundAtDriver> monkFunds = await _dbHelper
        .getMonkFundsByDriver(_currentDriverId!);
    if (!mounted) return; // Exit if unmounted after await

    List<MonkForExportDialog> monksForDialog = [];
    final db = await _dbHelper.database; // Fetch database instance once
    if (!mounted) return; // Exit if unmounted after await

    for (var fund in monkFunds) {
      if (fund.balance != 0) {
        // Only show monks with non-zero balance with this driver
        final monkUser = await _dbHelper.getUser(fund.monkPrimaryId);
        if (!mounted) return; // Exit if unmounted after await

        if (monkUser != null) {
          // Fetch last activity for this monk (could be optimized if many monks)
          final List<Map<String, dynamic>> monkMapList = await db.rawQuery(
            'SELECT (SELECT MAX(t.timestamp) FROM transactions t WHERE t.recordedByPrimaryId = ? OR t.sourceAccountId = ? OR t.destinationAccountId = ? OR t.processedByPrimaryId = ?) as last_activity_timestamp',
            [
              monkUser.primaryId,
              monkUser.primaryId,
              monkUser.primaryId,
              monkUser.primaryId,
            ],
          );
          DateTime? lastActivity;
          if (!mounted) return; // Exit if unmounted after await

          if (monkMapList.isNotEmpty &&
              monkMapList.first['last_activity_timestamp'] != null) {
            lastActivity = DateTime.tryParse(
              monkMapList.first['last_activity_timestamp'] as String,
            );
          }
          monksForDialog.add(
            MonkForExportDialog(
              monk: monkUser,
              lastActivity: lastActivity,
              balanceWithDriver: fund.balance,
            ),
          );
        }
      }
    }
    monksForDialog.sort((a, b) {
      if (a.lastActivity == null && b.lastActivity == null) {
        return a.monk.displayName.compareTo(b.monk.displayName);
      }
      if (a.lastActivity == null) return 1;
      if (b.lastActivity == null) return -1;
      return b.lastActivity!.compareTo(a.lastActivity!);
    });

    List<User> selectedMonksToExport = [];
    final TextEditingController advanceReturnController = TextEditingController(
      text: '0',
    );
    final formKey = GlobalKey<FormState>();
    int totalMonkFundsToForward = 0; // Declare here to be accessible later

    if (!mounted) return;
    // ignore: use_build_context_synchronously
    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('ส่งออกข้อมูลให้ไวยาวัจกรณ์'),
              content: SizedBox(
                width: double.maxFinite,
                child: Form(
                  key: formKey,
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      const Text(
                        'เลือกพระที่จะส่งข้อมูลปัจจัย:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (monksForDialog.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text("ไม่มีข้อมูลปัจจัยพระที่ต้องส่ง"),
                        ),
                      ...monksForDialog.map((monkDetail) {
                        return CheckboxListTile(
                          title: Text(monkDetail.monk.displayName),
                          value: selectedMonksToExport.any(
                            (m) => m.primaryId == monkDetail.monk.primaryId,
                          ),
                          onChanged: (bool? value) {
                            setDialogState(() {
                              if (value == true) {
                                selectedMonksToExport.add(monkDetail.monk);
                              } else {
                                selectedMonksToExport.removeWhere(
                                  (m) =>
                                      m.primaryId == monkDetail.monk.primaryId,
                                );
                              }
                            });
                          },
                        );
                      }),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: advanceReturnController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'เงินสำรองเดินทางคืนวัด (บาท)',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'กรุณากรอกจำนวนเงิน (0 ถ้าไม่คืน)';
                          }
                          if (int.tryParse(value) == null ||
                              int.parse(value) < 0) {
                            return 'จำนวนเงินไม่ถูกต้อง';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('ยกเลิก'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                TextButton(
                  child: const Text('ตกลงและส่งออก'),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(
                        dialogContext,
                      ).pop(); // Close the selection dialog

                      if (!mounted) {
                        return; // Check before further async operations
                      }
                      // Calculate total monk funds to be sent AFTER dialog is closed
                      final int advanceToReturn = int.parse(
                        advanceReturnController.text,
                      );
                      // if (mounted) { // This mounted check is redundant due to the one above
                      totalMonkFundsToForward = 0; // Reset before recalculating
                      for (var monkUser in selectedMonksToExport) {
                        final fund = await _dbHelper.getMonkFundAtDriver(
                          monkUser.primaryId,
                          _currentDriverId!,
                        );
                        if (!mounted) return; // Check inside loop after await
                        totalMonkFundsToForward += (fund?.balance ?? 0);
                        // Note: This calculation happens *after* the first dialog closes.
                      }

                      if (!mounted) return; // Check before showing next dialog
                      // Show confirmation dialog with summary
                      bool? confirmExport = await showDialog<bool>(
                        context: context, // Use the main screen's context
                        // Ensure 'context' is valid; 'mounted' check above helps
                        barrierDismissible: false,
                        builder: (BuildContext summaryDialogContext) {
                          return AlertDialog(
                            title: const Text('ยืนยันการส่งข้อมูลและเงิน'),
                            content: SingleChildScrollView(
                              child: ListBody(
                                children: <Widget>[
                                  Text(
                                    'คุณกำลังจะส่งข้อมูลของพระ ${selectedMonksToExport.length} รูป',
                                  ),
                                  Text(
                                    // Use the calculated total here
                                    'ยอดเงินปัจจัยพระที่ต้องส่งมอบ: ${_currencyFormat.format(totalMonkFundsToForward)}',
                                  ),
                                  Text(
                                    'เงินสำรองเดินทางคืนวัด: ${_currencyFormat.format(advanceToReturn)}',
                                  ),
                                  const Divider(),
                                  Text(
                                    'รวมเงินสดที่ต้องเตรียมส่งให้ไวยาวัจกรณ์: ${_currencyFormat.format(totalMonkFundsToForward + advanceToReturn)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.of(
                                  summaryDialogContext,
                                ).pop(false),
                                child: const Text('ยกเลิก'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(
                                  summaryDialogContext,
                                ).pop(true),
                                child: const Text('ยืนยันและส่งออก'),
                              ),
                            ],
                          );
                        },
                      );
                      if (!mounted) return; // Check after dialog
                      if (confirmExport == true && mounted) {
                        // Double check mounted before long op
                        await _proceedWithDriverDataExport(
                          selectedMonksToExport,
                          advanceToReturn,
                        );
                      }
                      // }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _proceedWithDriverDataExport(
    List<User> monksToExport,
    int advanceReturned,
  ) async {
    if (_currentDriverId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถระบุคนขับรถปัจจุบันได้')),
      );
      return;
    }
    setState(() => _isProcessingFile = true);

    String? finalFilePath; // Variable to hold the path if everything succeeds
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return; // Check mounted after async

      final driverDisplayName =
          prefs.getString(AppConstants.userDisplayName) ?? "คนขับรถ";
      final driverSecondaryId = prefs.getString(AppConstants.userSecondaryId);
      final treasurerPrimaryId = prefs.getString(
        AppConstants.associatedTreasurerPrimaryId,
      );
      final treasurerSecondaryId = prefs.getString(
        AppConstants.associatedTreasurerSecondaryId,
      );

      if (driverSecondaryId == null ||
          treasurerPrimaryId == null ||
          treasurerSecondaryId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "ข้อมูล ID ที่จำเป็นสำหรับการส่งออกไม่ครบถ้วน (รหัสคนขับ, รหัสไวยาวัจกรณ์)",
              ),
            ),
          );
        }
        throw Exception("ข้อมูล ID ที่จำเป็นสำหรับการส่งออกไม่ครบถ้วน");
      }

      // --- Prepare data for export and DB update (Read operations before DB transaction) ---
      List<Transaction> pendingMonkTransactions = [];
      // This list will hold the FORWARD_MONK_FUND_TO_TREASURER transactions
      // that will be created and included in the export file.
      List<Transaction> monkFundForwardTransactionsToExport = [];
      // Fetch pending monk transactions *before* the transaction
      for (var monkUser in monksToExport) {
        // monksToExport is List<User> from dialog
        final transactions = await _dbHelper.getTransactionsForMonkAndDriver(
          monkUser.primaryId,
          _currentDriverId!,
          status: TransactionStatus.pendingExport,
        );
        pendingMonkTransactions.addAll(transactions);
      }
      // For selected monks, create FORWARD_MONK_FUND_TO_TREASURER transactions
      // These will be added to the export file and inserted into the driver's DB.
      // The MonkFundAtDriver balance will be set to 0 *after* the treasurer reconciles.
      // Fetch monk funds *before* the transaction to calculate amounts.
      for (var monkUser in monksToExport) {
        final MonkFundAtDriver? monkFund = await _dbHelper.getMonkFundAtDriver(
          // This read is outside the transaction, which is fine for preparing data.
          monkUser.primaryId,
          _currentDriverId!,
        );
        if (monkFund != null && monkFund.balance != 0) {
          // Create a transaction to represent the forwarding of this balance
          final forwardTx = Transaction.create(
            type: TransactionType.FORWARD_MONK_FUND_TO_TREASURER,
            amount: monkFund.balance, // The current balance to be forwarded
            note: 'ส่งยอดปัจจัยของ ${monkUser.displayName} ให้ไวยาวัจกรณ์',
            recordedByPrimaryId: _currentDriverId!,
            sourceAccountId: monkUser.primaryId, // Monk's fund with driver
            destinationAccountId:
                treasurerPrimaryId, // Destination is the treasurer
            status: TransactionStatus.exportedToTreasurer, // New status
          );
          monkFundForwardTransactionsToExport.add(forwardTx);
        }
      }

      // Fetch pending trip expenses *before* the transaction
      final List<Transaction> pendingTripExpenses = await _dbHelper
          .getTransactionsByTypeAndStatus(
            _currentDriverId!,
            TransactionType.TRIP_EXPENSE_BY_DRIVER,
            TransactionStatus.pendingExport,
          );

      final List<User> allMonksInDb = await _dbHelper.getUsersByRole(
        // Fetch all monks *before* the transaction for the updatedMonkList
        UserRole.monk,
      );
      final List<User> newMonksPotentiallyCreatedByDriver = allMonksInDb.where((
        monk,
      ) {
        // Filter for monks likely created by this driver (based on ID range)
        final monkIdNum = int.tryParse(monk.primaryId);
        return monkIdNum != null &&
            monkIdNum >= AppConstants.monkPrimaryIdDriverMin &&
            monkIdNum <= AppConstants.monkPrimaryIdDriverMax;
        // Note: Treasurer import logic handles if monk already exists.
      }).toList();
      // Map monks to the format needed for the export file
      final List<Map<String, dynamic>> allMonksMapped = allMonksInDb.map((
        monk,
      ) {
        return monk.toMap(forFileExport: true);
      }).toList();

      // Fetch reconciled transaction updates *inside* the transaction
      List<Map<String, dynamic>> reconciledTransactionUpdates = [];
      // Fetch driver advance balance *inside* the transaction
      int updatedDriverAdvanceBalance = 0;

      final db = await _dbHelper.database;
      if (!mounted) return; // Check mounted after async
      await db.transaction((txn) async {
        // --- Fetch data needed for export file *inside* the transaction ---
        final List<Transaction> reconciledDriverTransactions = await _dbHelper
            .getTransactionsByStatusAndProcessor(
              TransactionStatus.reconciledByTreasurer,
              treasurerPrimaryId, // Processor is the treasurer
              txn: txn, // Use the transaction object
            );
        // Filter for transactions recorded by the specific driver being updated
        reconciledTransactionUpdates = reconciledDriverTransactions
            .where(
              (tx) => tx.recordedByPrimaryId == _currentDriverId,
            ) // Use current driver ID
            .map((tx) => {'uuid': tx.uuid, 'status': tx.status?.name})
            .toList();
        if (kDebugMode) {
          print(
            "[FES] Fetched ${reconciledTransactionUpdates.length} reconciled transaction updates for driver.",
          );
        }

        final DriverAdvanceAccount? driverAdvanceAccount = await _dbHelper
            .getDriverAdvance(
              _currentDriverId!,
              txn: txn,
            ); // Use the transaction object
        updatedDriverAdvanceBalance = driverAdvanceAccount?.balance ?? 0;
        if (kDebugMode) {
          print(
            "[FES] Fetched driver advance balance: $updatedDriverAdvanceBalance",
          );
        }

        // --- DB UPDATES ---
        // Update status of original monk transactions
        for (var txToUpdate in pendingMonkTransactions) {
          await _dbHelper.updateTransactionStatus(
            txToUpdate.uuid,
            TransactionStatus.exportedToTreasurer,
            txn: txn,
          );
        }
        // Update status of trip expenses
        for (var txToUpdate in pendingTripExpenses) {
          await _dbHelper.updateTransactionStatus(
            txToUpdate.uuid,
            TransactionStatus.exportedToTreasurer,
            txn: txn,
          );
        }

        // Insert the new FORWARD_MONK_FUND_TO_TREASURER transactions into driver's DB
        for (var forwardTx in monkFundForwardTransactionsToExport) {
          // Check if a similar pending forward transaction exists for this monk
          // and set its status to 'cancelled' or 'superseded' before inserting the new one.
          // This prevents multiple active forward transactions for the same monk.
          final existingForwardTxs = await txn.query(
            DatabaseHelper.tableTransactions,
            where:
                'sourceAccountId = ? AND recordedByPrimaryId = ? AND type = ? AND status = ?',
            whereArgs: [
              forwardTx.sourceAccountId, // monk's primaryId
              _currentDriverId,
              TransactionType.FORWARD_MONK_FUND_TO_TREASURER.name,
              TransactionStatus
                  .exportedToTreasurer
                  .name, // or pendingTreasurerConfirmation
            ],
          );

          for (var oldTxMap in existingForwardTxs) {
            final oldTx = Transaction.fromMap(oldTxMap);
            await _dbHelper.updateTransactionStatus(
              oldTx.uuid,
              TransactionStatus.cancelled, // Or a new 'superseded' status
              txn: txn,
            );
            if (kDebugMode) {
              print(
                "Cancelled old FORWARD_MONK_FUND_TO_TREASURER tx: ${oldTx.uuid} for monk ${forwardTx.sourceAccountId}",
              );
            }
          }
          await _dbHelper.insertTransaction(forwardTx, txn: txn);
        }

        // DO NOT set MonkFundAtDriver.balance to 0 here.
        // This will be done when the driver imports the update file from the treasurer
        // confirming that the FORWARD_MONK_FUND_TO_TREASURER transaction was reconciled.

        if (advanceReturned > 0) {
          DriverAdvanceAccount? currentAdvanceInTx = await _dbHelper
              .getDriverAdvance(_currentDriverId!, txn: txn);
          if (currentAdvanceInTx != null) {
            currentAdvanceInTx.balance -= advanceReturned;
            currentAdvanceInTx.lastUpdated = DateTime.now();
            await _dbHelper.insertOrUpdateDriverAdvance(
              currentAdvanceInTx,
              txn: txn,
            );
          } else {
            print(
              "DriverAdvanceAccount not found for driver $_currentDriverId during advance return. Balance not updated in transaction.",
            );
          }
        }

        // --- FILE EXPORT (after successful DB updates within transaction) ---
        finalFilePath = await _fileExportService.exportDriverDataToTreasurer(
          driverPrimaryId: _currentDriverId!,
          driverSecondaryId: driverSecondaryId, // Already checked for null
          driverDisplayName: driverDisplayName,
          // Send both original pending transactions AND the new forward transactions
          monkTransactions: [
            ...pendingMonkTransactions,
            ...monkFundForwardTransactionsToExport,
          ],
          tripExpenses: pendingTripExpenses,
          newMonks: newMonksPotentiallyCreatedByDriver,
          advanceReturnedAmount: advanceReturned,
          treasurerPrimaryId: treasurerPrimaryId, // Already checked for null
          treasurerSecondaryId:
              treasurerSecondaryId, // Already checked for null
        );

        if (finalFilePath == null) {
          throw Exception("การสร้างไฟล์ส่งออกล้มเหลว (FES returned null)");
        }
      }); // End transaction

      // --- AFTER SUCCESSFUL TRANSACTION AND FILE CREATION ---
      if (finalFilePath != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ส่งออกข้อมูลสำเร็จ!')));
        Share.shareXFiles([
          XFile(finalFilePath!),
        ], text: 'ไฟล์ข้อมูลจากคนขับรถ $driverDisplayName');
        _loadDriverAdvanceBalance(); // Refresh balance
      } else if (mounted) {
        // This path should ideally not be hit if finalFilePath is null due to exception in transaction
        // ScopedMessenger.of(context).showSnackBar(const SnackBar(content: Text('การส่งออกข้อมูลล้มเหลว หรือไฟล์ไม่ได้ถูกสร้าง')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการส่งออก: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingFile = false);
    }
  }

  Future<void> _importTreasurerUpdateFile() async {
    setState(() => _isProcessingFile = true);
    if (!mounted) return; // Check after setState before async operations
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any, // Or specify custom extension
      );
      if (!mounted) return;

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final file = File(filePath);
        final encryptedContent = await file.readAsString();
        if (!mounted) return; // Check after file read

        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return; // Check after getting prefs

        final String? treasurerPrimaryId = prefs.getString(
          AppConstants.associatedTreasurerPrimaryId,
        );
        final String? treasurerSecondaryId = prefs.getString(
          AppConstants.associatedTreasurerSecondaryId,
        );
        final String? driverPrimaryId = prefs.getString(
          AppConstants.userPrimaryId,
        );

        if (treasurerPrimaryId == null ||
            treasurerSecondaryId == null ||
            driverPrimaryId == null) {
          throw Exception('ไม่พบข้อมูล ID ที่จำเป็นสำหรับการถอดรหัส');
        }

        final decryptedJsonString = _fileExportService.decryptData(
          encryptedContent,
          treasurerPrimaryId, // Treasurer's ID is used for key
          treasurerSecondaryId,
        );

        if (decryptedJsonString == null) {
          throw Exception(
            'ไม่สามารถถอดรหัสไฟล์ได้ อาจเป็นเพราะไฟล์ไม่ถูกต้องหรือ ID ไวยาวัจกรณ์ไม่ตรงกัน',
          );
        }

        final Map<String, dynamic> data = jsonDecode(decryptedJsonString);

        // Validate file type and target driver
        if (data['metadata']?['fileType'] !=
                AppConstants.fileTypeTreasurerUpdateForDriver ||
            data['metadata']?['driverPrimaryId'] != driverPrimaryId) {
          throw Exception('ไฟล์อัปเดตไม่ถูกต้องสำหรับคนขับรถคนนี้');
        }

        final db = await _dbHelper.database;
        if (!mounted) return;
        await db.transaction((txn) async {
          // --- Process Data ---
          // 1. Update reconciled transaction statuses
          final reconciledUpdates =
              data['reconciledTransactionUpdates'] as List<dynamic>?;
          if (reconciledUpdates != null) {
            for (var updateData in reconciledUpdates) {
              final updateMap = updateData as Map<String, dynamic>;
              final uuid = updateMap['uuid'] as String?;
              final statusString = updateMap['status'] as String?;
              if (uuid != null && statusString != null) {
                try {
                  final status = TransactionStatus.values.byName(statusString);
                  await _dbHelper.updateTransactionStatus(
                    uuid,
                    status,
                    txn: txn,
                  );

                  // If a FORWARD_MONK_FUND_TO_TREASURER transaction is reconciled,
                  // set the MonkFundAtDriver.balance to 0 for that monk.
                  if (status == TransactionStatus.reconciledByTreasurer) {
                    final reconciledTx = await _dbHelper.getTransaction(
                      uuid,
                      txn: txn,
                    );
                    if (reconciledTx != null &&
                        reconciledTx.type ==
                            TransactionType.FORWARD_MONK_FUND_TO_TREASURER &&
                        reconciledTx.sourceAccountId != null) {
                      // sourceAccountId is monk's ID

                      MonkFundAtDriver? monkFund = await _dbHelper
                          .getMonkFundAtDriver(
                            reconciledTx.sourceAccountId!,
                            driverPrimaryId,
                            txn: txn,
                          );

                      if (monkFund != null) {
                        monkFund.balance = 0; // Clear the balance
                        monkFund.lastUpdated = DateTime.now();
                        await _dbHelper.insertOrUpdateMonkFundAtDriver(
                          monkFund,
                          txn: txn,
                        );
                        if (kDebugMode) {
                          print(
                            "MonkFundAtDriver for ${reconciledTx.sourceAccountId} cleared after FORWARD_MONK_FUND_TO_TREASURER reconciliation.",
                          );
                        }
                      }
                    }
                  }
                } catch (e) {
                  // Consider logging this error more formally if needed
                  print("Error parsing status $statusString for tx $uuid: $e");
                }
              }
            }
          }

          // 2. Process new driver advance given
          final newAdvanceData =
              data['newDriverAdvanceGiven'] as Map<String, dynamic>?;
          if (newAdvanceData != null && newAdvanceData['amount'] != null) {
            final int advanceAmount = newAdvanceData['amount'] as int;
            if (advanceAmount > 0) {
              DriverAdvanceAccount? currentAdvance = await _dbHelper
                  .getDriverAdvance(driverPrimaryId, txn: txn);
              currentAdvance ??= DriverAdvanceAccount(
                driverPrimaryId: driverPrimaryId,
                balance: 0,
                lastUpdated: DateTime.now(),
              );
              currentAdvance.balance += advanceAmount;
              currentAdvance.lastUpdated = DateTime.now();
              await _dbHelper.insertOrUpdateDriverAdvance(
                currentAdvance,
                txn: txn,
              );

              // Create a transaction for receiving advance
              final receiveAdvanceTx = Transaction.create(
                type: TransactionType.RECEIVE_DRIVER_ADVANCE,
                amount: advanceAmount,
                note:
                    newAdvanceData['note'] as String? ??
                    'รับเงินสำรองเดินทางจากไวยาวัจกรณ์ (นำเข้าไฟล์)',
                recordedByPrimaryId: driverPrimaryId,
                sourceAccountId: treasurerPrimaryId,
                destinationAccountId: driverPrimaryId,
                status: TransactionStatus.completed,
              );
              await _dbHelper.insertTransaction(receiveAdvanceTx, txn: txn);
            }
          }

          // 3. Process monk funds transferred to driver
          final monkFundsTransferred =
              data['monkFundsTransferredToDriver'] as List<dynamic>?;
          if (monkFundsTransferred != null) {
            for (var fundData in monkFundsTransferred) {
              final fundMap = fundData as Map<String, dynamic>;
              final monkId = fundMap['monkPrimaryId'] as String?;
              final amount = fundMap['amount'] as int?;
              if (monkId != null && amount != null && amount > 0) {
                MonkFundAtDriver? monkFund = await _dbHelper
                    .getMonkFundAtDriver(monkId, driverPrimaryId, txn: txn);
                monkFund ??= MonkFundAtDriver(
                  monkPrimaryId: monkId,
                  driverPrimaryId: driverPrimaryId,
                  balance: 0,
                  lastUpdated: DateTime.now(),
                );
                monkFund.balance += amount;
                monkFund.lastUpdated = DateTime.now();
                await _dbHelper.insertOrUpdateMonkFundAtDriver(
                  monkFund,
                  txn: txn,
                );

                // Create a transaction for receiving monk fund
                final receiveMonkFundTx = Transaction.create(
                  type: TransactionType.RECEIVE_MONK_FUND_FROM_TREASURER,
                  amount: amount,
                  note: 'รับเงินปัจจัยพระ $monkId จากไวยาวัจกรณ์ (นำเข้าไฟล์)',
                  recordedByPrimaryId: driverPrimaryId,
                  sourceAccountId: treasurerPrimaryId,
                  destinationAccountId: monkId, // Fund is for the monk
                  status: TransactionStatus.completed,
                );
                await _dbHelper.insertTransaction(receiveMonkFundTx, txn: txn);
              }
            }
          }

          // 4. Update monk list (including status)
          final updatedMonkList = data['updatedMonkList'] as List<dynamic>?;
          if (updatedMonkList != null) {
            for (var monkData in updatedMonkList) {
              final monk = User.fromMap(
                monkData as Map<String, dynamic>,
              ); // Ensure User.fromMap handles all fields correctly
              await _dbHelper.insertUser(
                monk,
                txn: txn,
              ); // Assumes insertUser handles updates if user exists
            }
          }
        }); // End transaction

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('นำเข้าข้อมูลอัปเดตสำเร็จ!')),
          );
          _loadDriverAdvanceBalance();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ยกเลิกการเลือกไฟล์')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessingFile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentDriverDisplayName ?? 'หน้าหลักคนขับรถ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
            tooltip: 'ออกจากระบบ',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'ยอดเงินสำรองเดินทางคงเหลือ',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _isLoadingBalance
                        ? const CircularProgressIndicator()
                        : Text(
                            _currencyFormat.format(
                              _driverAdvanceAccount?.balance ?? 0,
                            ),
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color:
                                      (_driverAdvanceAccount?.balance ?? 0) < 0
                                      ? Colors.red
                                      : Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (!_initialDataImported)
              Expanded(
                child: Center(
                  child: Card(
                    color: Colors.amber[100],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.amber,
                            size: 40,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'กรุณานำเข้าไฟล์ข้อมูลเริ่มต้นที่คุณได้รับจากไวยาวัจกรณ์เพื่อเริ่มใช้งานฟังก์ชันต่างๆ',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.file_download),
                            label: const Text('นำเข้าไฟล์ข้อมูลเริ่มต้น'),
                            onPressed: _isProcessingFile
                                ? null
                                : _navigateToImportInitialData,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_initialDataImported) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.volunteer_activism),
                label: const Text('บันทึกรายการรับ/จ่ายปัจจัยให้พระ'),
                onPressed: _isProcessingFile
                    ? null
                    : _navigateToRecordMonkTransaction,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.receipt_long),
                label: const Text('บันทึกค่าใช้จ่ายเดินทาง'),
                onPressed: _isProcessingFile
                    ? null
                    : _navigateToRecordTripExpense,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.history),
                label: const Text('ดูประวัติธุรกรรมของพระ'),
                onPressed: _isProcessingFile
                    ? null
                    : _navigateToMonkTransactionHistory,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: Theme.of(context).primaryColor),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.list_alt_rounded),
                label: const Text('ดูประวัติธุรกรรมของฉัน'),
                onPressed: _isProcessingFile
                    ? null
                    : _navigateToDriverTransactionHistory,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: Theme.of(context).primaryColor),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('จัดการบัญชีพระ'), // Changed button text
                onPressed: _isProcessingFile
                    ? null
                    : _navigateToManageMonksByDriver, // Changed navigation target
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: Theme.of(context).primaryColor),
                ),
              ),
            ],
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
      bottomNavigationBar: _initialDataImported ? _buildActionButtons() : null,
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          Expanded(
            child: ElevatedButton.icon(
              icon: _isProcessingFile
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.file_download),
              label: const Text('นำเข้าข้อมูล'),
              onPressed: _isProcessingFile ? null : _importTreasurerUpdateFile,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              icon: _isProcessingFile
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.file_upload),
              label: const Text('ส่งออกข้อมูล'),
              onPressed: _isProcessingFile ? null : _showExportDataDialog,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
