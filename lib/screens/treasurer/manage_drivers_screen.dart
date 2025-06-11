// lib/screens/treasurer/manage_drivers_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for FilteringTextInputFormatter
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/services/database_helper.dart';
// Import a screen for adding/editing a driver
import 'package:moneywat/screens/treasurer/add_edit_driver_screen.dart';
// For file operations
import 'package:file_picker/file_picker.dart'; // For FilePicker
import 'package:moneywat/services/file_export_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart'; // Import share_plus
import 'package:moneywat/models/transaction_model.dart'; // For Transaction.create
import 'package:moneywat/models/account_balance_models.dart'; // For AccountBalance models
import 'package:moneywat/screens/treasurer/driver_financial_history_screen.dart'; // Import history screen
import 'package:intl/intl.dart'; // For currency formatting

class ManageDriversScreen extends StatefulWidget {
  const ManageDriversScreen({super.key});

  @override
  State<ManageDriversScreen> createState() => _ManageDriversScreenState();
}

// Helper class to return multiple values from the dialog
class InitialExportData {
  final int driverAdvance;
  final Map<String, int> monkDeposits;

  InitialExportData({required this.driverAdvance, required this.monkDeposits});
}

class DriverWithDetails {
  final User driver;
  final DriverAdvanceAccount? advanceAccount;
  final DateTime? lastActivityTimestamp;

  DriverWithDetails({
    required this.driver,
    this.advanceAccount,
    this.lastActivityTimestamp,
  });
}

class _ManageDriversScreenState extends State<ManageDriversScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FileExportService _fileExportService = FileExportService();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );
  List<DriverWithDetails> _driversWithDetails = [];
  bool _isLoading = true;
  String? _currentTreasurerId;
  bool _isImporting = false;
  // bool _isExporting = false; // _isLoading can cover general export busy state

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _currentTreasurerId = prefs.getString('user_primary_id');

    if (_currentTreasurerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบข้อมูลไวยาวัจกรณ์ปัจจุบัน')),
        );
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final List<Map<String, dynamic>> driverMaps = await _dbHelper
          .getUsersByRoleWithLastActivity(UserRole.driver);

      List<DriverWithDetails> tempDriversWithDetails = [];
      for (var driverMap in driverMaps) {
        final driverUser = User.fromMap(driverMap);
        final advance = await _dbHelper.getDriverAdvance(driverUser.primaryId);
        final lastActivityString =
            driverMap['last_activity_timestamp'] as String?;
        final lastActivity = lastActivityString != null
            ? DateTime.tryParse(lastActivityString)
            : null;
        tempDriversWithDetails.add(
          DriverWithDetails(
            driver: driverUser,
            advanceAccount: advance,
            lastActivityTimestamp: lastActivity,
          ),
        );
      }

      // Sort drivers: most recent activity first, then by display name
      tempDriversWithDetails.sort((a, b) {
        if (a.lastActivityTimestamp == null &&
            b.lastActivityTimestamp == null) {
          return a.driver.displayName.compareTo(b.driver.displayName);
        }
        if (a.lastActivityTimestamp == null) return 1;
        if (b.lastActivityTimestamp == null) return -1;
        int dateComparison = b.lastActivityTimestamp!.compareTo(
          a.lastActivityTimestamp!,
        );
        return dateComparison == 0
            ? a.driver.displayName.compareTo(b.driver.displayName)
            : dateComparison;
      });

      if (mounted) {
        setState(() {
          _driversWithDetails = tempDriversWithDetails;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถโหลดข้อมูลคนขับรถได้: $e')),
        );
      }
    }
  }

  void _navigateToAddEditDriverScreen({User? driver}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditDriverScreen(driver: driver),
      ),
    );
    if (result == true && mounted) {
      _loadInitialData();
    }
  }

  Future<InitialExportData?> _showInitialExportSetupDialog(User driver) async {
    final TextEditingController advanceController = TextEditingController(
      text: '0',
    );
    final Map<String, TextEditingController> monkDepositControllers = {};
    final List<User> allMonks = await _dbHelper
        .getActiveMonks(); // Fetch only active monks

    for (var monk in allMonks) {
      monkDepositControllers[monk.primaryId] = TextEditingController(text: '0');
    }

    final formKey = GlobalKey<FormState>();

    return await showDialog<InitialExportData>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('ตั้งค่าข้อมูลเริ่มต้นสำหรับ ${driver.displayName}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: formKey,
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  TextFormField(
                    controller: advanceController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'เงินสำรองเดินทางให้คนขับ (บาท)',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'กรุณากรอกจำนวนเงิน';
                      }
                      if (int.tryParse(value) == null || int.parse(value) < 0) {
                        return 'กรุณากรอกจำนวนเงินที่ถูกต้อง (0 หรือมากกว่า)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "เงินที่พระฝากให้คนขับดูแล (ผ่านไวยาวัจกรณ์):",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (allMonks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text("ยังไม่มีข้อมูลพระในระบบ"),
                    ),
                  ...allMonks.map((monk) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: TextFormField(
                        controller: monkDepositControllers[monk.primaryId],
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: 'ฝากให้ ${monk.displayName} (บาท)',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'กรอกจำนวนเงิน (0 ถ้าไม่มี)';
                          }
                          if (int.tryParse(value) == null ||
                              int.parse(value) < 0) {
                            return 'จำนวนเงินไม่ถูกต้อง';
                          }
                          return null;
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () => Navigator.of(dialogContext).pop(null),
            ),
            TextButton(
              child: const Text('ต่อไป'), // Changed button text
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final driverAdvance = int.parse(advanceController.text);
                  final Map<String, int> monkDeposits = {};
                  monkDepositControllers.forEach((monkId, controller) {
                    monkDeposits[monkId] = int.parse(controller.text);
                  });
                  Navigator.of(dialogContext).pop(
                    InitialExportData(
                      driverAdvance: driverAdvance,
                      monkDeposits: monkDeposits,
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showShareSuccessDialog(String driverName) async {
    // Use the class's `context`
    return showDialog<void>(
      context: context, // This 'context' is the State's context
      barrierDismissible: false, // User must acknowledge
      builder: (BuildContext dialogContext) {
        // This is the dialog's own context
        return AlertDialog(
          title: const Text('การแชร์ไฟล์'),
          content: Text('ส่งไฟล์ให้คนขับรถ $driverName สำเร็จแล้ว'),
          actions: <Widget>[
            TextButton(
              child: const Text('ตกลง'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _proceedWithExport(
    User driver,
    int initialAdvanceAmount,
    Map<String, int> initialMonkDeposits,
  ) async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? treasurerPrimaryId = prefs.getString('user_primary_id');
      final String? treasurerSecondaryId = prefs.getString('user_secondary_id');

      if (treasurerPrimaryId == null || treasurerSecondaryId == null) {
        throw Exception(
          'ไม่พบข้อมูล ID ของไวยาวัจกรณ์ปัจจุบันใน SharedPreferences',
        );
      }

      // *** BEGIN: Record transactions on Treasurer's side BEFORE exporting file ***
      final db = await _dbHelper.database;
      await db.transaction((txn) async {
        // 1. Record GIVE_DRIVER_ADVANCE transaction
        if (initialAdvanceAmount > 0) {
          final advanceTx = Transaction.create(
            type: TransactionType.GIVE_DRIVER_ADVANCE,
            amount: initialAdvanceAmount,
            note: 'ให้เงินสำรองเดินทางเริ่มต้นแก่ ${driver.displayName}',
            recordedByPrimaryId: treasurerPrimaryId,
            sourceAccountId: treasurerPrimaryId, // Temple fund
            destinationAccountId: driver.primaryId,
            status: TransactionStatus.completed, // Or reconciledByTreasurer
          );
          await _dbHelper.insertTransaction(advanceTx, txn: txn);
          await _dbHelper.updateTempleFundBalance(
            treasurerPrimaryId,
            -initialAdvanceAmount,
            txn: txn,
          );

          DriverAdvanceAccount? dAccount = await _dbHelper.getDriverAdvance(
            driver.primaryId,
            txn: txn,
          );
          dAccount ??= DriverAdvanceAccount(
            driverPrimaryId: driver.primaryId,
            balance: 0,
            lastUpdated: DateTime.now(),
          );
          dAccount.balance += initialAdvanceAmount;
          dAccount.lastUpdated = DateTime.now();
          await _dbHelper.insertOrUpdateDriverAdvance(dAccount, txn: txn);
        }

        // 2. Record TRANSFER_MONK_FUND_TO_DRIVER for each monk's initial deposit
        for (var entry in initialMonkDeposits.entries) {
          final monkId = entry.key;
          final amountToTransfer = entry.value;
          if (amountToTransfer > 0) {
            // This transaction signifies the treasurer giving the monk's money to the driver to manage.
            // It reduces the monk's balance with the treasurer.
            final transferTx = Transaction.create(
              type: TransactionType.TRANSFER_MONK_FUND_TO_DRIVER,
              amount: amountToTransfer,
              note:
                  'โอนปัจจัยเริ่มต้นของพระ (ID: $monkId) ให้ ${driver.displayName} ดูแล',
              recordedByPrimaryId: treasurerPrimaryId,
              sourceAccountId: monkId, // Monk's fund at treasurer is the source
              destinationAccountId:
                  driver.primaryId, // Driver receives it to manage for the monk
              status: TransactionStatus.completed, // Or exportedToDriver
            );
            await _dbHelper.insertTransaction(transferTx, txn: txn);

            MonkFundAtTreasurer? mFund = await _dbHelper.getMonkFundAtTreasurer(
              monkId,
              treasurerPrimaryId,
              txn: txn,
            );
            if (mFund != null) {
              mFund.balance -= amountToTransfer;
              mFund.lastUpdated = DateTime.now();
              await _dbHelper.insertOrUpdateMonkFundAtTreasurer(
                mFund,
                txn: txn,
              );
            } else {
              // This case might occur if a monk has no prior fund record with the treasurer.
              // Create a new fund record with a negative balance, representing the amount "loaned" or "advanced"
              // to the driver on behalf of the monk.
              final newMonkFund = MonkFundAtTreasurer(
                monkPrimaryId: monkId,
                treasurerPrimaryId: treasurerPrimaryId,
                balance: -amountToTransfer, // Start with a negative balance
                lastUpdated: DateTime.now(),
              );
              await _dbHelper.insertOrUpdateMonkFundAtTreasurer(
                newMonkFund,
                txn: txn,
              );
              print(
                "Warning: MonkFundAtTreasurer not found for monk $monkId during initial export. Created new record with negative balance.",
              );
            }
          }
        }
      });
      // *** END: Record transactions on Treasurer's side ***

      // Fetch all monks, regardless of status, to include in the initial export
      final List<User> allMonks = await _dbHelper.getUsersByRole(UserRole.monk);

      final String? filePath = await _fileExportService.exportInitialDriverData(
        driver: driver,
        allMonks: allMonks,
        initialAdvanceAmount: initialAdvanceAmount,
        initialMonkDepositsToDriver: initialMonkDeposits,
        treasurerPrimaryId: treasurerPrimaryId,
        treasurerSecondaryId: treasurerSecondaryId,
      );

      if (filePath != null && mounted) {
        _loadInitialData(); // Refresh the driver list to show updated advance
        showDialog(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('ส่งออกข้อมูลสำเร็จ!'),
            content: SingleChildScrollView(
              child: Text(
                'ไฟล์ข้อมูลเริ่มต้นสำหรับ ${driver.displayName} ถูกสร้างแล้ว\n\n'
                'ข้อมูลที่ต้องแจ้งให้คนขับรถ:\n'
                '- Primary ID คนขับรถ: ${driver.primaryId}\n'
                '- Secondary ID คนขับรถ: ${driver.secondaryId}\n'
                '- Primary ID ไวยาวัจกรณ์: $treasurerPrimaryId\n'
                '- Secondary ID ไวยาวัจกรณ์: $treasurerSecondaryId\n\n'
                'คุณต้องการแชร์ไฟล์นี้เลยหรือไม่?',
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('แชร์ไฟล์'),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  final params = ShareParams(
                    files: [XFile(filePath)],
                    text:
                        'ไฟล์ข้อมูลเริ่มต้นสำหรับคนขับรถ ${driver.displayName}',
                  );
                  await SharePlus.instance.share(params);
                  // Show success dialog AFTER sharing
                  // ignore: use_build_context_synchronously
                  if (mounted) {
                    await _showShareSuccessDialog(driver.displayName);
                  }
                },
              ),
              TextButton(
                child: const Text('ตกลง'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('การส่งออกข้อมูลล้มเหลว')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool?> _showFinalInitialExportConfirmationDialog(
    User driver,
    int driverAdvance,
    Map<String, int> monkDeposits,
    List<User> allMonks, // Pass allMonks to get display names
  ) async {
    List<Widget> monkDepositDetails = [];
    bool hasMonkDeposits = false;
    monkDeposits.forEach((monkId, amount) {
      if (amount > 0) {
        hasMonkDeposits = true;
        final monkName = allMonks
            .firstWhere((m) => m.primaryId == monkId)
            .displayName;
        monkDepositDetails.add(
          Text('- พระ $monkName: ${_currencyFormat.format(amount)}'),
        );
      }
    });

    if (!hasMonkDeposits) {
      monkDepositDetails.add(const Text('- ไม่มีรายการเงินฝากของพระ'));
    }

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            'ยืนยันการส่งออกข้อมูลเริ่มต้นสำหรับ ${driver.displayName}',
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'เงินสำรองเดินทางให้คนขับ: ${_currencyFormat.format(driverAdvance)}',
                ),
                const SizedBox(height: 8),
                const Text(
                  'เงินที่พระฝากให้คนขับดูแล (ผ่านไวยาวัจกรณ์):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...monkDepositDetails,
                const SizedBox(height: 16),
                const Text('คุณต้องการดำเนินการส่งออกข้อมูลนี้ใช่หรือไม่?'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: const Text('ยืนยันการส่งออก'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _showExportUpdateDialog(User driver) async {
    final TextEditingController newAdvanceController = TextEditingController(
      text: '0',
    );
    final Map<String, TextEditingController> monkTransferControllers = {};
    final List<User> monksUnderTreasurer = [];

    final prefs = await SharedPreferences.getInstance();
    final String? currentTreasurerId = prefs.getString('user_primary_id');
    if (currentTreasurerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบ ID ไวยาวัจกรณ์ปัจจุบัน')),
        );
      }
      return null;
    }

    final allMonks = await _dbHelper.getActiveMonks(); // Fetch active monks
    for (var monk in allMonks) {
      final fund = await _dbHelper.getMonkFundAtTreasurer(
        monk.primaryId,
        currentTreasurerId,
      );
      if (fund != null && fund.balance > 0) {
        monksUnderTreasurer.add(monk);
        monkTransferControllers[monk.primaryId] = TextEditingController(
          text: '0',
        );
      }
    }

    final formKey = GlobalKey<FormState>();

    Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('เตรียมส่งไฟล์อัปเดตให้ ${driver.displayName}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: formKey,
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  TextFormField(
                    controller: newAdvanceController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'เงินสำรองที่จะให้เพิ่ม (บาท)',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'กรุณากรอกจำนวน (0 ถ้าไม่เพิ่ม)';
                      }
                      if (int.tryParse(value) == null || int.parse(value) < 0) {
                        return 'จำนวนเงินไม่ถูกต้อง';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "โอนเงินปัจจัยพระให้คนขับรถดูแล:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (monksUnderTreasurer.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text("ไม่มีพระที่มียอดเงินฝากกับคุณ"),
                    ),
                  ...monksUnderTreasurer.map((monk) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: TextFormField(
                        controller: monkTransferControllers[monk.primaryId],
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: 'โอนให้ ${monk.displayName} (บาท)',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'กรอกจำนวน (0 ถ้าไม่โอน)';
                          }
                          final amountToTransfer = int.tryParse(value);
                          if (amountToTransfer == null ||
                              amountToTransfer < 0) {
                            return 'จำนวนเงินไม่ถูกต้อง';
                          }
                          // Check against monk's balance with treasurer
                          // This requires fetching the balance again or passing it to the dialog.
                          // For simplicity, this check is done before calling _proceedWithUpdateExport
                          return null;
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () => Navigator.of(dialogContext).pop(null),
            ),
            TextButton(
              child: const Text('ตกลงและส่งออก'),
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final int advance = int.parse(newAdvanceController.text);
                  final Map<String, int> transfers = {};
                  monkTransferControllers.forEach((monkId, controller) {
                    transfers[monkId] = int.parse(controller.text);
                  });
                  Navigator.of(
                    dialogContext,
                  ).pop({'newAdvance': advance, 'monkTransfers': transfers});
                }
              },
            ),
          ],
        );
      },
    );
    return result; // This will be the Map or null
  }

  Future<bool?> _showConfirmDataForUpdateDialog(
    User driver,
    int newAdvanceAmount,
    Map<String, int> monkTransfers,
  ) async {
    int totalMonkFundsToGiveDriver = 0;
    monkTransfers.forEach((monkId, amount) {
      totalMonkFundsToGiveDriver += amount;
    });
    final int totalCashToPrepare =
        newAdvanceAmount + totalMonkFundsToGiveDriver;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('ยืนยันข้อมูลก่อนส่งให้ ${driver.displayName}'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'เงินสำรองเดินทางที่จะให้คนขับเพิ่ม: ${_currencyFormat.format(newAdvanceAmount)}',
                ),
                Text(
                  'เงินปัจจัยพระที่จะโอนให้คนขับดูแล: ${_currencyFormat.format(totalMonkFundsToGiveDriver)}',
                ),
                const Divider(),
                Text(
                  'รวมเงินสดที่ต้องเตรียมให้คนขับรถ: ${_currencyFormat.format(totalCashToPrepare)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  '(ข้อมูลสถานะธุรกรรมที่กระทบยอดแล้ว และรายชื่อพระทั้งหมดจะถูกส่งไปด้วย)',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: const Text('ยืนยันและส่งออก'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
  }

  Future<void> _proceedWithUpdateExport(
    User driver,
    int newAdvanceAmount,
    Map<String, int> monkTransfers,
    String currentTreasurerId,
  ) async {
    setState(() => _isLoading = true);
    String? exportedFilePath; // To store the path from the transaction

    try {
      final prefs = await SharedPreferences.getInstance(); // Fetch prefs once
      final String? treasurerPrimaryId = prefs.getString('user_primary_id');
      final String? treasurerSecondaryId = prefs.getString('user_secondary_id');

      if (treasurerPrimaryId == null || treasurerSecondaryId == null) {
        throw Exception('ไม่พบ ID ไวยาวัจกรณ์ปัจจุบัน');
      }
      if (treasurerPrimaryId != currentTreasurerId) {
        throw Exception('ID ไวยาวัจกรณ์ไม่ตรงกันระหว่างการดำเนินการ');
      }

      // --- BEGIN PRE-VALIDATION ---
      List<String> insufficientFundMonks = [];
      for (var entry in monkTransfers.entries) {
        if (entry.value > 0) {
          final monkId = entry.key;
          final amountToTransfer = entry.value;
          MonkFundAtTreasurer? mFund = await _dbHelper.getMonkFundAtTreasurer(
            monkId,
            treasurerPrimaryId,
          ); // No txn here
          if (mFund == null || mFund.balance < amountToTransfer) {
            User? monkUser = await _dbHelper.getUser(monkId);
            insufficientFundMonks.add(monkUser?.displayName ?? monkId);
          }
        }
      }

      if (insufficientFundMonks.isNotEmpty) {
        // ignore: use_build_context_synchronously
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('ยอดเงินไม่เพียงพอ'),
            content: Text(
              'ไม่สามารถโอนเงินให้พระต่อไปนี้ได้เนื่องจากยอดเงินในบัญชี (กับไวยาวัจกรณ์) ไม่เพียงพอ:\n- ${insufficientFundMonks.join("\n- ")}\n\nกรุณาตรวจสอบยอดเงินของพระ หรือปรับปรุงจำนวนเงินที่จะโอน',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('ตกลง'),
              ),
            ],
          ),
        );
        setState(() => _isLoading = false);
        return; // Abort operation
      }
      // --- END PRE-VALIDATION ---

      final db = await _dbHelper.database;
      await db.transaction((txn) async {
        if (newAdvanceAmount > 0) {
          final giveAdvanceTx = Transaction.create(
            type: TransactionType.GIVE_DRIVER_ADVANCE,
            amount: newAdvanceAmount,
            note: 'ให้เงินสำรองเดินทางเพิ่มเติมแก่ ${driver.displayName}',
            recordedByPrimaryId: treasurerPrimaryId,
            sourceAccountId: treasurerPrimaryId,
            destinationAccountId: driver.primaryId,
            status: TransactionStatus.reconciledByTreasurer, // Or completed
          );
          await _dbHelper.insertTransaction(giveAdvanceTx, txn: txn);
          await _dbHelper.updateTempleFundBalance(
            treasurerPrimaryId,
            -newAdvanceAmount,
            txn: txn,
          );

          DriverAdvanceAccount? dAccount = await _dbHelper.getDriverAdvance(
            driver.primaryId,
            txn: txn,
          );
          dAccount ??= DriverAdvanceAccount(
            driverPrimaryId: driver.primaryId,
            balance: 0,
            lastUpdated: DateTime.now(),
          );
          dAccount.balance += newAdvanceAmount;
          dAccount.lastUpdated = DateTime.now();
          await _dbHelper.insertOrUpdateDriverAdvance(dAccount, txn: txn);
        }

        List<Map<String, dynamic>> monkFundsToTransferDataForFile = [];
        for (var entry in monkTransfers.entries) {
          if (entry.value > 0) {
            final monkId = entry.key;
            final amountToTransfer = entry.value;

            MonkFundAtTreasurer? mFund = await _dbHelper.getMonkFundAtTreasurer(
              monkId,
              treasurerPrimaryId,
              txn: txn,
            );
            // This check is now a safeguard, primary validation is outside.
            if (mFund == null || mFund.balance < amountToTransfer) {
              throw Exception(
                'ยอดเงินของพระ $monkId ไม่เพียงพอ (ตรวจสอบซ้ำภายใน transaction)',
              );
            }

            final transferTx = Transaction.create(
              type: TransactionType.TRANSFER_MONK_FUND_TO_DRIVER,
              amount: amountToTransfer,
              note: 'โอนปัจจัยของพระ $monkId ให้ ${driver.displayName} ดูแล',
              recordedByPrimaryId: treasurerPrimaryId,
              sourceAccountId: monkId,
              destinationAccountId: driver.primaryId,
              status: TransactionStatus.exportedToDriver, // Or completed
            );
            await _dbHelper.insertTransaction(transferTx, txn: txn);

            mFund.balance -= amountToTransfer;
            mFund.lastUpdated = DateTime.now();
            await _dbHelper.insertOrUpdateMonkFundAtTreasurer(mFund, txn: txn);

            monkFundsToTransferDataForFile.add({
              'monkPrimaryId': monkId,
              'amount': amountToTransfer,
            });
          }
        }

        // Export file after all DB operations in transaction are successful
        exportedFilePath = await _fileExportService
            .exportTreasurerUpdateToDriver(
              driverToUpdate: driver,
              newAdvanceGiven: newAdvanceAmount,
              monkFundsToTransfer: monkFundsToTransferDataForFile,
              treasurerPrimaryId: treasurerPrimaryId,
              treasurerSecondaryId: treasurerSecondaryId,
            );

        if (exportedFilePath == null) {
          throw Exception("การสร้างไฟล์อัปเดตล้มเหลว (FES returned null)");
        }
      }); // End transaction

      // --- AFTER SUCCESSFUL TRANSACTION AND FILE CREATION ---
      if (exportedFilePath != null && mounted) {
        final params = ShareParams(
          files: [XFile(exportedFilePath!)],
          text: 'ไฟล์อัปเดตสำหรับคนขับรถ ${driver.displayName}',
        );
        await SharePlus.instance.share(params);
        // Check mounted again before showing another dialog
        // ignore: use_build_context_synchronously
        if (mounted) {
          await _showShareSuccessDialog(driver.displayName);
        }
      }
      _loadInitialData(); // Refresh driver list and advances
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _importDataFromDriver() async {
    if (!mounted) return;
    setState(() => _isImporting = true);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any, // Allow any, or filter for .วัดencrypted
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;

        final prefs = await SharedPreferences.getInstance();
        final String? treasurerPrimaryId = prefs.getString('user_primary_id');
        final String? treasurerSecondaryId = prefs.getString(
          'user_secondary_id',
        );

        if (treasurerPrimaryId == null || treasurerSecondaryId == null) {
          throw Exception('ไม่พบข้อมูล ID ของไวยาวัจกรณ์ปัจจุบัน');
        }

        final Map<String, dynamic>? importResult = await _fileExportService
            .importDriverDataFromFile(
              filePath: filePath,
              currentTreasurerPrimaryId: treasurerPrimaryId,
              currentTreasurerSecondaryId: treasurerSecondaryId,
            );

        if (mounted) {
          if (importResult != null && importResult['success'] == true) {
            final String driverName =
                importResult['driverDisplayName'] ?? 'คนขับรถ';
            final int monkFunds = importResult['totalMonkFundsReceived'] ?? 0;
            final int tripExpenses = importResult['totalTripExpenses'] ?? 0;
            final int advanceReturned =
                importResult['advanceReturnedAmount'] ?? 0;
            final String driverPrimaryId =
                // Use driverPrimaryId from importResult metadata
                importResult['driverPrimaryId'] ?? 'N/A';

            final List<Transaction> transactionsToCommit =
                importResult['transactionsToCommit'] as List<Transaction>? ??
                [];
            final List<User> newMonksToCommit =
                importResult['newMonksToCommit'] as List<User>? ?? [];

            // Calculate total cash treasurer should receive from driver
            // This is the sum of net monk funds driver collected and the advance driver is returning.
            final int netCashToReceiveFromDriver = monkFunds + advanceReturned;

            // Show summary dialog
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext dialogContext) {
                return AlertDialog(
                  title: Text(
                    'สรุปข้อมูลนำเข้าจากคนขับ: ${driverName} (ID: $driverPrimaryId)',
                  ),
                  content: SingleChildScrollView(
                    child: ListBody(
                      children: <Widget>[
                        Text(
                          // Display the net amount of monk funds received
                          'ยอดปัจจัยพระที่คนขับนำมาส่ง: ${_currencyFormat.format(monkFunds)}',
                        ),
                        Text(
                          'ค่าใช้จ่ายเดินทางที่คนขับบันทึก: ${_currencyFormat.format(tripExpenses)} (ข้อมูลนี้ใช้เพื่อกระทบยอดเงินสำรองของคนขับ)',
                        ),
                        Text(
                          'เงินสำรองเดินทางที่คนขับคืน: ${_currencyFormat.format(advanceReturned)}',
                        ),
                        const Divider(),
                        Text(
                          'รวมเงินสดที่ควรได้รับจากคนขับรถ: ${_currencyFormat.format(netCashToReceiveFromDriver)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'กรุณาตรวจสอบจำนวนเงินสดที่ได้รับจากคนขับรถให้ตรงกับยอดรวมข้างต้น',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ],
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      child: const Text('ปฏิเสธ (ยอดเงินไม่ตรง)'),
                      onPressed: () {
                        Navigator.of(
                          dialogContext,
                        ).pop(false); // Indicate rejection
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'การนำเข้าถูกยกเลิก ยอดเงินไม่ถูกต้อง คนขับรถต้องส่งข้อมูลมาใหม่',
                            ),
                          ),
                        );
                      },
                    ),
                    ElevatedButton(
                      child: const Text('ยืนยันยอดเงินถูกต้อง'),
                      onPressed: () async {
                        Navigator.of(
                          dialogContext,
                        ).pop(true); // Indicate confirmation
                        // Proceed to commit transactions and users
                        if (mounted) {
                          setState(
                            () => _isImporting = true,
                          ); // Show loading for commit
                        }
                        try {
                          final db = await _dbHelper.database;
                          await db.transaction((txn) async {
                            Set<String> existingTxnUuids = {};
                            for (final txToCommit in transactionsToCommit) {
                              final existingTx = await _dbHelper.getTransaction(
                                txToCommit.uuid,
                                txn: txn,
                              );
                              if (existingTx != null &&
                                  existingTx.status ==
                                      TransactionStatus.reconciledByTreasurer) {
                                print(
                                  "Skipping already reconciled transaction: ${txToCommit.uuid}",
                                );
                                continue; // Skip this transaction
                              }
                              if (existingTx != null &&
                                  existingTx.status !=
                                      TransactionStatus.reconciledByTreasurer) {
                                // If exists and not reconciled, it might be an update or resend.
                                // For now, we'll replace. Consider more sophisticated logic if needed.
                                await _dbHelper.updateTransactionFields(
                                  txToCommit,
                                  txn: txn,
                                ); // You'll need to create this method
                              } else if (existingTx == null) {
                                await _dbHelper.insertTransaction(
                                  txToCommit,
                                  txn: txn,
                                );
                              }
                            }
                            // Correctly loop through newMonksToCommit to insert new users
                            for (final newMonk in newMonksToCommit) {
                              await _dbHelper.insertUser(newMonk, txn: txn);
                            }
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'นำเข้าข้อมูลสำเร็จ! กรุณาไปที่หน้า "กระทบยอดธุรกรรม" เพื่อยืนยันรายการ',
                                ),
                              ),
                            );
                            _loadInitialData(); // Refresh driver list and advances
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'เกิดข้อผิดพลาดขณะบันทึกข้อมูล: $e',
                                ),
                              ),
                            );
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isImporting = false);
                          }
                        }
                      },
                    ),
                  ],
                );
              },
            );
            // The actual commit and success message are now handled inside the dialog's "ยืนยันยอดเงินถูกต้อง" button
          } else {
            // This part handles errors from _fileExportService.importDriverDataFromFile itself
            // (e.g., file decryption error, wrong file type)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'นำเข้าข้อมูลล้มเหลว: ${importResult?['error'] ?? 'ไม่ทราบสาเหตุ'}',
                ),
              ),
            );
          }
        }
      } else {
        // User canceled the picker
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ยกเลิกการเลือกไฟล์')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการนำเข้า: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _showGeneralExportDriverSelectionDialog() async {
    if (_driversWithDetails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีคนขับรถในระบบให้เลือกส่งออกข้อมูล')),
      );
      return;
    }

    User? selectedDriver = await showDialog<User>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('เลือกคนขับรถเพื่อส่งออกข้อมูล'),
          content: SizedBox(
            width: double.minPositive,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _driversWithDetails.length,
              itemBuilder: (BuildContext context, int index) {
                final driverDetail = _driversWithDetails[index];
                return ListTile(
                  title: Text(driverDetail.driver.displayName),
                  onTap: () {
                    Navigator.of(dialogContext).pop(driverDetail.driver);
                  },
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () {
                Navigator.of(dialogContext).pop(null);
              },
            ),
          ],
        );
      },
    );

    if (selectedDriver != null && mounted) {
      _showExportTypeDialog(selectedDriver);
    }
  }

  Future<void> _showExportTypeDialog(
    User driver, {
    bool isInitialOnly = false,
  }) async {
    String? exportType = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('เลือกประเภทการส่งออกสำหรับ ${driver.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (isInitialOnly) // Show only initial export option
                ListTile(
                  leading: const Icon(Icons.fiber_new_outlined),
                  title: const Text(
                    'ส่งข้อมูลเริ่มต้น (สำหรับตั้งค่าครั้งแรก)',
                  ),
                  onTap: () {
                    Navigator.of(dialogContext).pop('initial');
                  },
                ),
              if (!isInitialOnly) // Show only update export option
                ListTile(
                  leading: const Icon(Icons.sync_alt_outlined),
                  title: const Text('ส่งไฟล์อัปเดต (ข้อมูลใหม่/เงินสำรอง)'),
                  onTap: () {
                    Navigator.of(dialogContext).pop('update');
                  },
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () {
                Navigator.of(dialogContext).pop(null);
              },
            ),
          ],
        );
      },
    );

    if (exportType != null && mounted) {
      if (exportType == 'initial') {
        // Fetch all monks once here to pass down
        final List<User> allMonks = await _dbHelper
            .getActiveMonks(); // Fetch active monks
        // ignore: use_build_context_synchronously
        InitialExportData? exportData = await _showInitialExportSetupDialog(
          driver,
        );

        if (exportData != null && mounted) {
          bool? confirmedFinalExport =
              await _showFinalInitialExportConfirmationDialog(
                driver,
                exportData.driverAdvance,
                exportData.monkDeposits,
                allMonks, // Pass allMonks here
              );
          // This 'if (exportData != null && mounted)' was redundant and misplaced.
          // The check for confirmedFinalExport should be inside the previous if.
          if (confirmedFinalExport == true) {
            // Check confirmedFinalExport directly
            _proceedWithExport(
              driver,
              exportData.driverAdvance,
              exportData.monkDeposits,
            );
          }
        }
      } else if (exportType == 'update' && mounted) {
        final String? currentTreasurerId =
            _currentTreasurerId; // Capture current value
        if (currentTreasurerId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่พบ ID ไวยาวัจกรณ์ปัจจุบัน')),
          );
          return;
        }
        Map<String, dynamic>? updateInput = await _showExportUpdateDialog(
          driver,
        );
        if (updateInput != null && mounted) {
          final int newAdvance = updateInput['newAdvance'] as int;
          final Map<String, int> monkTransfers =
              updateInput['monkTransfers'] as Map<String, int>;
          bool? confirmed = await _showConfirmDataForUpdateDialog(
            driver,
            newAdvance,
            monkTransfers,
          );
          if (confirmed == true && mounted) {
            await _proceedWithUpdateExport(
              driver,
              newAdvance,
              monkTransfers,
              currentTreasurerId,
            );
          }
        }
      }
    }
  }

  void _navigateToDriverHistory(
    User driver,
    DriverAdvanceAccount? advanceAccount,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverFinancialHistoryScreen(
          driver: driver,
          driverAdvanceAccount: advanceAccount,
        ),
      ),
    );
    // No need to reload data here unless the history screen can modify data
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการบัญชีคนขับรถ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () => _navigateToAddEditDriverScreen(),
            tooltip: 'เพิ่มคนขับรถใหม่',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _driversWithDetails.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'ยังไม่มีข้อมูลคนขับรถ',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มคนขับรถใหม่'),
                    onPressed: () => _navigateToAddEditDriverScreen(),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _driversWithDetails.length,
              itemBuilder: (context, index) {
                final driverDetail = _driversWithDetails[index];
                final driver = driverDetail.driver;
                final advanceAccount = driverDetail.advanceAccount;
                final balanceText = advanceAccount != null
                    ? _currencyFormat.format(advanceAccount.balance)
                    : 'N/A';
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      driver.displayName.isNotEmpty
                          ? driver.displayName[0].toUpperCase()
                          : 'D',
                    ),
                  ),
                  title: Text(driver.displayName),
                  subtitle: Text(
                    'Primary ID: ${driver.primaryId}\n'
                    'Secondary ID: ${driver.secondaryId}\n'
                    'เงินสำรอง: $balanceText',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'export_initial_data') {
                        _showExportTypeDialog(driver, isInitialOnly: true);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'export_initial_data',
                            child: ListTile(
                              leading: Icon(Icons.upload_file),
                              title: Text('ส่งออกข้อมูลเริ่มต้น'),
                            ),
                          ),
                        ],
                  ),
                  onTap: () {
                    _navigateToDriverHistory(driver, advanceAccount);
                  },
                );
              },
            ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              Expanded(
                child: ElevatedButton.icon(
                  icon: _isImporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.file_download_outlined),
                  label: const Text('รับเข้าไฟล์'),
                  onPressed: _isImporting || _isLoading
                      ? null
                      : _importDataFromDriver,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  icon:
                      _isLoading &&
                          !_isImporting // This is the first 'icon' argument
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.sync_alt_outlined,
                        ), // This was the second 'icon', now part of ternary
                  label: const Text('ส่งไฟล์อัปเดต'), // Changed label
                  onPressed: _isLoading || _isImporting
                      ? null
                      : _showGeneralExportDriverSelectionDialog,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
