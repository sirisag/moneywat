// lib/screens/driver/record_monk_transaction_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/models/transaction_model.dart';
import 'package:moneywat/models/account_balance_models.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

// Helper class for sorting
class MonkForDriverDialog {
  final User monk;
  final DateTime? lastActivity;
  MonkForDriverDialog({required this.monk, this.lastActivity});
}

class RecordMonkTransactionScreen extends StatefulWidget {
  const RecordMonkTransactionScreen({super.key});

  @override
  State<RecordMonkTransactionScreen> createState() =>
      _RecordMonkTransactionScreenState();
}

class _RecordMonkTransactionScreenState
    extends State<RecordMonkTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Uuid _uuid = const Uuid();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );

  List<MonkForDriverDialog> _sortableMonks = [];
  final List<User> _selectedMonks = []; // Changed to List for multi-select
  TransactionType _selectedTransactionType =
      TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER; // Default
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  bool _isLoading = true;
  String? _currentDriverId;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _currentDriverId = prefs.getString('user_primary_id');

    if (_currentDriverId == null) {
      // Handle error: driver not logged in or ID not found
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบข้อมูลคนขับรถปัจจุบัน')),
        );
        Navigator.pop(context);
      }
      return;
    }

    final List<Map<String, dynamic>> monkMaps = await _dbHelper
        .getUsersByRoleWithLastActivity(UserRole.monk);

    List<MonkForDriverDialog> tempSortableMonks = [];
    for (var monkMap in monkMaps) {
      final monkUser = User.fromMap(monkMap);
      final lastActivityString = monkMap['last_activity_timestamp'] as String?;
      final lastActivity = lastActivityString != null
          ? DateTime.tryParse(lastActivityString)
          : null;
      tempSortableMonks.add(
        MonkForDriverDialog(monk: monkUser, lastActivity: lastActivity),
      );
    }

    tempSortableMonks.sort((a, b) {
      if (a.lastActivity == null && b.lastActivity == null)
        return a.monk.displayName.compareTo(b.monk.displayName);
      if (a.lastActivity == null) return 1;
      if (b.lastActivity == null) return -1;
      return b.lastActivity!.compareTo(a.lastActivity!);
    });

    if (mounted) {
      setState(() {
        _sortableMonks = tempSortableMonks;
        _isLoading = false;
      });
    }
  }

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate() ||
        _selectedMonks.isEmpty ||
        _currentDriverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณากรอกข้อมูลให้ครบถ้วนและเลือกพระอย่างน้อย 1 รูป'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final amount = int.tryParse(_amountController.text) ?? 0;
    final note = _noteController.text;
    final timestamp = DateTime.now();

    // Show confirmation dialog
    bool? confirmSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('ยืนยันการบันทึกรายการ'),
          content: Text(
            'ประเภทรายการ: ${_selectedTransactionType == TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER ? "ฝากเงิน" : "เบิกเงิน"}\n'
            'จำนวนพระที่เลือก: ${_selectedMonks.length} รูป\n'
            'จำนวนเงิน: ${_currencyFormat.format(amount)}\n'
            'หมายเหตุ: "$note"\n'
            'คุณต้องการบันทึกรายการนี้ใช่หรือไม่?',
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

    if (confirmSave == null || !confirmSave) {
      setState(() => _isLoading = false);
      return; // User cancelled
    }

    try {
      final db = await _dbHelper.database;
      await db.transaction((txn) async {
        for (User selectedMonk in _selectedMonks) {
          final transaction = Transaction(
            uuid: _uuid.v4(),
            type: _selectedTransactionType,
            amount: amount, // Apply the same amount to each selected monk
            timestamp: timestamp,
            note: note,
            recordedByPrimaryId: _currentDriverId!,
            sourceAccountId:
                _selectedTransactionType ==
                    TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER
                ? selectedMonk.primaryId
                : _currentDriverId,
            destinationAccountId:
                _selectedTransactionType ==
                    TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER
                ? selectedMonk.primaryId
                : _currentDriverId,
            status: TransactionStatus
                .pendingExport, // Driver transactions usually need export
          );

          await _dbHelper.insertTransaction(transaction, txn: txn);

          // Update MonkFundAtDriver for each selected monk
          MonkFundAtDriver? monkFund = await _dbHelper.getMonkFundAtDriver(
            selectedMonk.primaryId,
            _currentDriverId!,
            txn: txn,
          );

          monkFund ??= MonkFundAtDriver(
            monkPrimaryId: selectedMonk.primaryId,
            driverPrimaryId: _currentDriverId!,
            balance: 0,
            lastUpdated: timestamp,
          );

          if (_selectedTransactionType ==
              TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER) {
            monkFund.balance += amount;
          } else if (_selectedTransactionType ==
              TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER) {
            monkFund.balance -= amount;
            // Note: If withdrawing from driver's advance for multiple monks,
            // the advance deduction logic needs to be handled carefully,
            // possibly by summing up all withdrawals in this batch.
            // For now, this example doesn't directly debit driver's advance here.
            // That would typically be a separate transaction or handled during reconciliation.
          }
          monkFund.lastUpdated = timestamp;
          await _dbHelper.insertOrUpdateMonkFundAtDriver(monkFund, txn: txn);
        }
      }); // End transaction

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('บันทึกรายการสำเร็จ!')));
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('บันทึกรายการรับ/จ่ายปัจจัยพระ')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: <Widget>[
                    const Text(
                      'เลือกพระ (สามารถเลือกได้หลายรูป):',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.3,
                      ), // Limit height
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: _sortableMonks.isEmpty
                          ? const Center(child: Text('ไม่มีข้อมูลพระ'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _sortableMonks.length,
                              itemBuilder: (context, index) {
                                final monk = _sortableMonks[index].monk;
                                return CheckboxListTile(
                                  title: Text(monk.displayName),
                                  value: _selectedMonks.contains(monk),
                                  onChanged: (bool? value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedMonks.add(monk);
                                      } else {
                                        _selectedMonks.remove(monk);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<TransactionType>(
                      decoration: const InputDecoration(
                        labelText: 'ประเภทรายการ',
                        border: OutlineInputBorder(),
                      ),
                      value: _selectedTransactionType,
                      items: const [
                        DropdownMenuItem(
                          value: TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER,
                          child: Text('พระฝากเงิน'),
                        ),
                        DropdownMenuItem(
                          value:
                              TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER,
                          child: Text('เบิกเงินให้พระ'),
                        ),
                      ],
                      onChanged: (TransactionType? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedTransactionType = newValue;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _amountController,
                      decoration: const InputDecoration(
                        labelText: 'จำนวนเงิน (สำหรับแต่ละรูปที่เลือก)',
                        border: OutlineInputBorder(),
                        prefixText: '฿ ',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'กรุณากรอกจำนวนเงิน';
                        }
                        if (int.tryParse(value) == null ||
                            int.parse(value) <= 0) {
                          return 'จำนวนเงินต้องมากกว่า 0';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'หมายเหตุ (ถ้ามี)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submitTransaction,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('บันทึกรายการ'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
