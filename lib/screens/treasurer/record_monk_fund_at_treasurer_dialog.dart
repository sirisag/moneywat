// lib/screens/treasurer/record_monk_fund_at_treasurer_dialog.dart
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
class MonkForDialog {
  final User monk;
  final DateTime? lastActivity;

  MonkForDialog({required this.monk, this.lastActivity});
}

class RecordMonkFundAtTreasurerDialog extends StatefulWidget {
  const RecordMonkFundAtTreasurerDialog({super.key});

  @override
  State<RecordMonkFundAtTreasurerDialog> createState() =>
      _RecordMonkFundAtTreasurerDialogState();
}

class _RecordMonkFundAtTreasurerDialogState
    extends State<RecordMonkFundAtTreasurerDialog> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Uuid _uuid = const Uuid();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );

  List<MonkForDialog> _sortableMonks = [];
  User? _selectedMonk;
  bool _isDeposit = true; // true for Monk Deposit, false for Monk Withdrawal

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
        Navigator.pop(context, false);
      }
      return;
    }

    try {
      final List<Map<String, dynamic>> monkMaps = await _dbHelper
          .getUsersByRoleWithLastActivity(UserRole.monk);

      List<MonkForDialog> tempSortableMonks = [];
      for (var monkMap in monkMaps) {
        final monkUser = User.fromMap(monkMap);
        final lastActivityString =
            monkMap['last_activity_timestamp'] as String?;
        final lastActivity = lastActivityString != null
            ? DateTime.tryParse(lastActivityString)
            : null;
        tempSortableMonks.add(
          MonkForDialog(monk: monkUser, lastActivity: lastActivity),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถโหลดรายชื่อพระได้: $e')),
        );
        Navigator.pop(context, false);
      }
    }
  }

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate() ||
        _currentTreasurerId == null ||
        _selectedMonk == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลและเลือกพระให้ครบถ้วน')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final amount = int.tryParse(_amountController.text) ?? 0;
    final note = _noteController.text.isNotEmpty
        ? _noteController.text
        : (_isDeposit
              ? 'พระ ${_selectedMonk!.displayName} ฝากเงิน'
              : 'พระ ${_selectedMonk!.displayName} เบิกเงิน');
    final timestamp = DateTime.now();

    // Show confirmation dialog
    bool? confirmSave = await showDialog<bool>(
      context: context, // Use the dialog's own context for this inner dialog
      barrierDismissible: false,
      builder: (BuildContext innerDialogContext) {
        return AlertDialog(
          title: Text('ยืนยันการบันทึกรายการของพระ'),
          content: Text(
            'พระ: ${_selectedMonk!.displayName}\n'
            'ประเภทรายการ: ${_isDeposit ? "ฝากเงิน" : "เบิกเงิน"}\n'
            'จำนวน: ${_currencyFormat.format(amount)}\n'
            'หมายเหตุ: "$note"\n'
            'คุณต้องการบันทึกรายการนี้ใช่หรือไม่?',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () => Navigator.of(innerDialogContext).pop(false),
            ),
            TextButton(
              child: const Text('ยืนยัน'),
              onPressed: () => Navigator.of(innerDialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmSave == null || !confirmSave) {
      setState(() => _isLoading = false);
      return; // User cancelled
    }

    final transaction = Transaction(
      uuid: _uuid.v4(),
      type: _isDeposit
          ? TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER
          : TransactionType.MONK_WITHDRAWAL_FROM_TREASURER,
      amount: amount,
      timestamp: timestamp,
      note: note,
      recordedByPrimaryId: _currentTreasurerId!,
      sourceAccountId: _isDeposit
          ? _selectedMonk!.primaryId
          : _currentTreasurerId!,
      destinationAccountId: _isDeposit
          ? _currentTreasurerId!
          : _selectedMonk!.primaryId,
      status: TransactionStatus.completed,
    );

    try {
      final db = await _dbHelper.database;
      await db.transaction((txn) async {
        // 1. Insert the transaction
        await _dbHelper.insertTransaction(transaction, txn: txn);

        // 2. Update MonkFundAtTreasurer
        MonkFundAtTreasurer? monkFund = await _dbHelper.getMonkFundAtTreasurer(
          _selectedMonk!.primaryId,
          _currentTreasurerId!,
          txn: txn,
        );

        monkFund ??= MonkFundAtTreasurer(
          monkPrimaryId: _selectedMonk!.primaryId,
          treasurerPrimaryId: _currentTreasurerId!,
          balance: 0,
          lastUpdated: timestamp,
        );

        monkFund.balance += (_isDeposit ? amount : -amount);
        monkFund.lastUpdated = timestamp;
        await _dbHelper.insertOrUpdateMonkFundAtTreasurer(monkFund, txn: txn);

        // 3. Update TempleFundAccount
        await _dbHelper.updateTempleFundBalance(
          _currentTreasurerId!,
          _isDeposit ? amount : -amount,
          txn: txn,
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'บันทึกรายการของพระ ${_selectedMonk!.displayName} สำเร็จ!',
            ),
          ),
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
    return AlertDialog(
      title: Text('บันทึกรายการรับ/จ่ายปัจจัยพระ'),
      content: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DropdownButtonFormField<User>(
                      decoration: const InputDecoration(
                        labelText: 'เลือกพระ',
                        border: OutlineInputBorder(),
                      ),
                      value: _selectedMonk,
                      items: _sortableMonks.map((MonkForDialog monkDetail) {
                        return DropdownMenuItem<User>(
                          value: monkDetail.monk,
                          child: Text(monkDetail.monk.displayName),
                        );
                      }).toList(),
                      onChanged: (User? newValue) {
                        setState(() {
                          _selectedMonk = newValue;
                        });
                      },
                      validator: (value) =>
                          value == null ? 'กรุณาเลือกพระ' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<bool>(
                      decoration: const InputDecoration(
                        labelText: 'ประเภทรายการ',
                        border: OutlineInputBorder(),
                      ),
                      value: _isDeposit,
                      items: const [
                        DropdownMenuItem(
                          value: true,
                          child: Text('พระฝากเงิน'),
                        ),
                        DropdownMenuItem(
                          value: false,
                          child: Text('พระเบิกเงิน'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _isDeposit = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _amountController,
                      decoration: const InputDecoration(
                        labelText: 'จำนวนเงิน',
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
                  ],
                ),
              ),
            ),
      actions: <Widget>[
        TextButton(
          child: const Text('ยกเลิก'),
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitTransaction,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : const Text('บันทึก'),
        ),
      ],
    );
  }
}
