// lib/screens/treasurer/record_temple_transaction_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moneywat/models/transaction_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

class RecordTempleTransactionDialog extends StatefulWidget {
  const RecordTempleTransactionDialog({super.key});

  @override
  State<RecordTempleTransactionDialog> createState() =>
      _RecordTempleTransactionDialogState();
}

class _RecordTempleTransactionDialogState
    extends State<RecordTempleTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Uuid _uuid = const Uuid();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );

  final _categoryController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  bool _isLoading = false;
  String? _currentTreasurerId;
  bool _isIncomeEntry = true; // true for Income, false for Expense

  @override
  void initState() {
    super.initState();
    _loadTreasurerId();
  }

  Future<void> _loadTreasurerId() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _currentTreasurerId = prefs.getString('user_primary_id');
    });
    if (_currentTreasurerId == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบข้อมูลไวยาวัจกรณ์ปัจจุบัน')),
      );
      Navigator.pop(context, false); // Pop dialog if treasurer ID is not found
    }
  }

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate() || _currentTreasurerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วน')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final category = _categoryController.text;
    final amount = int.tryParse(_amountController.text) ?? 0;
    final note = _noteController.text.isNotEmpty
        ? _noteController.text
        : (_isIncomeEntry ? "รายรับวัด: $category" : "รายจ่ายวัด: $category");
    final timestamp = DateTime.now();

    // Show confirmation dialog before proceeding
    bool? confirmSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('ยืนยันการบันทึกรายการ'),
          content: Text(
            'ประเภทรายการ: ${_isIncomeEntry ? "รายรับวัด" : "รายจ่ายวัด"}\n'
            'รายละเอียด: "$category"\n'
            'จำนวน: ${_currencyFormat.format(amount)}\n'
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

    final transaction = Transaction(
      uuid: _uuid.v4(),
      type: _isIncomeEntry
          ? TransactionType.TEMPLE_INCOME
          : TransactionType.TEMPLE_EXPENSE,
      amount: amount,
      timestamp: timestamp,
      note: note,
      recordedByPrimaryId: _currentTreasurerId!,
      sourceAccountId: _isIncomeEntry
          ? EXTERNAL_SOURCE_ACCOUNT_ID // Income from external source
          : _currentTreasurerId!, // Expense from temple fund
      destinationAccountId: _isIncomeEntry
          ? _currentTreasurerId! // Income goes to temple fund
          : EXPENSE_DESTINATION_ACCOUNT_ID, // General expense destination
      expenseCategory: !_isIncomeEntry ? category : null,
      status: TransactionStatus.completed,
    );

    try {
      final db = await _dbHelper.database;
      await db.transaction((txn) async {
        await _dbHelper.insertTransaction(transaction, txn: txn);

        await _dbHelper.updateTempleFundBalance(
          _currentTreasurerId!,
          _isIncomeEntry ? amount : -amount,
          txn: txn,
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'บันทึก${_isIncomeEntry ? "รายรับ" : "รายจ่าย"}สำเร็จ!',
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
      title: Text('บันทึก${_isIncomeEntry ? "รายรับ" : "รายจ่าย"}ของวัด'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<bool>(
                decoration: const InputDecoration(
                  labelText: 'ประเภทรายการ',
                  border: OutlineInputBorder(),
                ),
                value: _isIncomeEntry,
                items: const [
                  DropdownMenuItem(value: true, child: Text('รายรับวัด')),
                  DropdownMenuItem(value: false, child: Text('รายจ่ายวัด')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _isIncomeEntry = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _categoryController,
                decoration: InputDecoration(
                  labelText: _isIncomeEntry
                      ? 'ประเภทรายรับ (เช่น เงินบริจาค)'
                      : 'ประเภทรายจ่าย (เช่น ค่าน้ำ, ค่าไฟ)',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณาระบุประเภทรายการ';
                  }
                  return null;
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
                  if (int.tryParse(value) == null || int.parse(value) <= 0) {
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
