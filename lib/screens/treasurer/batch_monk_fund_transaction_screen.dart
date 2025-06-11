// lib/screens/treasurer/batch_monk_fund_transaction_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/models/transaction_model.dart';
import 'package:moneywat/models/account_balance_models.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart'; // For DateFormat and NumberFormat

class MonkWithLastActivity {
  final User monk;
  final DateTime? lastActivity;

  MonkWithLastActivity({required this.monk, this.lastActivity});
}

class BatchMonkFundTransactionScreen extends StatefulWidget {
  const BatchMonkFundTransactionScreen({super.key});

  @override
  State<BatchMonkFundTransactionScreen> createState() =>
      _BatchMonkFundTransactionScreenState();
}

class _BatchMonkFundTransactionScreenState
    extends State<BatchMonkFundTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Uuid _uuid = const Uuid();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );

  List<MonkWithLastActivity> _sortableMonks =
      []; // Using the existing class definition
  final List<User> _selectedMonks = [];
  TransactionType _transactionType =
      TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER; // Default

  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  bool _isLoading = true;
  String? _currentTreasurerId;

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
        Navigator.pop(context);
      }
      return;
    }

    try {
      final List<Map<String, dynamic>> monkMaps = await _dbHelper
          .getUsersByRoleWithLastActivity(UserRole.monk);

      List<MonkWithLastActivity> tempSortableMonks = [];
      for (var monkMap in monkMaps) {
        final monkUser = User.fromMap(monkMap);
        // We don't strictly need the fund balance for sorting here, just last activity.
        // If fund.lastUpdated was the primary source for lastActivity, that logic would be here.
        final lastActivityString =
            monkMap['last_activity_timestamp'] as String?;
        final lastActivity = lastActivityString != null
            ? DateTime.tryParse(lastActivityString)
            : null;
        tempSortableMonks.add(
          MonkWithLastActivity(monk: monkUser, lastActivity: lastActivity),
        );
      }

      // Sort by lastActivity descending (nulls last)
      tempSortableMonks.sort((a, b) {
        if (a.lastActivity == null && b.lastActivity == null) return 0;
        if (a.lastActivity == null) return 1; // nulls go to bottom
        if (b.lastActivity == null) return -1; // nulls go to bottom
        return b.lastActivity!.compareTo(a.lastActivity!); // descending
      });

      if (mounted) {
        setState(() {
          _sortableMonks = tempSortableMonks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถโหลดข้อมูลพระได้: $e')),
        );
      }
    }
  }

  Future<void> _submitBatchTransaction() async {
    if (!_formKey.currentState!.validate() ||
        _selectedMonks.isEmpty ||
        _currentTreasurerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณากรอกข้อมูลให้ครบถ้วนและเลือกพระอย่างน้อย 1 รูป'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final amount = int.tryParse(_amountController.text) ?? 0;
    final note = _noteController.text.isNotEmpty
        ? _noteController.text
        : (_transactionType == TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER
              ? 'พระฝากเงิน (กลุ่ม)'
              : 'พระเบิกเงิน (กลุ่ม)');
    final timestamp = DateTime.now();

    // Show confirmation dialog
    bool? confirmSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            'ยืนยันการ${_transactionType == TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER ? "รับฝาก" : "เบิกจ่าย"}เงิน (กลุ่ม)',
          ),
          content: Text(
            'จำนวนพระที่เลือก: ${_selectedMonks.length} รูป\n'
            'รายการ: ${_transactionType == TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER ? "ฝากเงิน" : "เบิกเงิน"} (สำหรับแต่ละรูป)\n'
            'จำนวนเงินต่อรูป: ${_currencyFormat.format(amount)}\n'
            'หมายเหตุ: "$note"\nคุณต้องการบันทึกรายการทั้งหมดนี้ใช่หรือไม่?',
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

    // --- Check for insufficient funds before proceeding with transaction ---
    final totalAmount = amount * _selectedMonks.length;
    if (_transactionType == TransactionType.MONK_WITHDRAWAL_FROM_TREASURER) {
      final TempleFundAccount? templeFund = await _dbHelper.getTempleFund(
        _currentTreasurerId!,
      );
      final currentTempleBalance = templeFund?.balance ?? 0;

      if (currentTempleBalance < totalAmount) {
        if (!mounted) return;
        bool? confirmProceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('ยอดเงินกองกลางวัดไม่เพียงพอ'),
              content: Text(
                'ยอดเงินกองกลางวัดมี ${_currencyFormat.format(currentTempleBalance)} บาท\n'
                'รายการเบิกกลุ่มนี้รวม ${_currencyFormat.format(totalAmount)} บาท\n'
                'หากดำเนินการต่อ ยอดเงินกองกลางวัดจะติดลบ ${_currencyFormat.format(totalAmount - currentTempleBalance)} บาท\n'
                'คุณต้องการดำเนินการต่อหรือไม่?',
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('ยกเลิก'),
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                TextButton(
                  child: const Text('ยืนยันดำเนินการต่อ'),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            );
          },
        );
        if (confirmProceed == null || !confirmProceed) {
          setState(() => _isLoading = false);
          return; // User cancelled after insufficient funds warning
        }
      }
    }

    // --- Proceed with transaction if funds are sufficient or user confirmed ---

    try {
      final db = await _dbHelper.database;
      await db.transaction((txn) async {
        for (User monk in _selectedMonks) {
          // 1. Create and insert the transaction for this monk
          final transaction = Transaction(
            uuid: _uuid.v4(),
            type: _transactionType,
            amount: amount, // Amount per monk
            timestamp: timestamp,
            note: note,
            recordedByPrimaryId: _currentTreasurerId!,
            sourceAccountId:
                _transactionType ==
                    TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER
                ? monk.primaryId
                : _currentTreasurerId!,
            destinationAccountId:
                _transactionType ==
                    TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER
                ? _currentTreasurerId!
                : monk.primaryId,
            status: TransactionStatus.completed,
          );
          await _dbHelper.insertTransaction(transaction, txn: txn);

          // 2. Update MonkFundAtTreasurer for this monk
          MonkFundAtTreasurer? monkFund = await _dbHelper
              .getMonkFundAtTreasurer(
                monk.primaryId,
                _currentTreasurerId!,
                txn: txn, // Use the transaction object
              );
          monkFund ??= MonkFundAtTreasurer(
            monkPrimaryId: monk.primaryId,
            treasurerPrimaryId: _currentTreasurerId!,
            balance: 0,
            lastUpdated: timestamp,
          );

          monkFund.balance +=
              (_transactionType ==
                  TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER
              ? amount
              : -amount);
          monkFund.lastUpdated = timestamp;
          await _dbHelper.insertOrUpdateMonkFundAtTreasurer(monkFund, txn: txn);
        }

        // 3. Update TempleFundAccount (once for the total batch amount)
        if (_transactionType ==
            TransactionType.MONK_WITHDRAWAL_FROM_TREASURER) {
          await _dbHelper.updateTempleFundBalance(
            _currentTreasurerId!,
            -totalAmount,
            txn: txn,
          );
        } else if (_transactionType ==
            TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER) {
          await _dbHelper.updateTempleFundBalance(
            _currentTreasurerId!,
            totalAmount,
            txn: txn,
          );
        }
      }); // End transaction

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกรายการกลุ่มสำเร็จ!')),
        );
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
      appBar: AppBar(title: const Text('บันทึกฝาก/ถอน (กลุ่ม)')),
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
                    Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.3,
                      ),
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
                                final monkUser = _sortableMonks[index].monk;
                                return CheckboxListTile(
                                  title: Text(monkUser.displayName),
                                  subtitle: Text(
                                    'ID: ${monkUser.primaryId} ${(_sortableMonks[index].lastActivity != null ? DateFormat("dd/MM/yy HH:mm").format(_sortableMonks[index].lastActivity!) : "")}',
                                  ),
                                  value: _selectedMonks.contains(monkUser),
                                  onChanged: (bool? value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedMonks.add(monkUser);
                                      } else {
                                        _selectedMonks.remove(monkUser);
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
                      value: _transactionType,
                      items: const [
                        DropdownMenuItem(
                          value: TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER,
                          child: Text('พระฝากเงิน (เข้าบัญชีไวยาวัจกรณ์)'),
                        ),
                        DropdownMenuItem(
                          value: TransactionType.MONK_WITHDRAWAL_FROM_TREASURER,
                          child: Text('พระเบิกเงิน (จากบัญชีไวยาวัจกรณ์)'),
                        ),
                      ],
                      onChanged: (TransactionType? newValue) {
                        if (newValue != null) {
                          setState(() => _transactionType = newValue);
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
                      onPressed: _isLoading ? null : _submitBatchTransaction,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('บันทึกรายการกลุ่ม'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
