// lib/screens/driver/record_trip_expense_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moneywat/models/transaction_model.dart';
import 'package:moneywat/models/account_balance_models.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

class RecordTripExpenseScreen extends StatefulWidget {
  const RecordTripExpenseScreen({super.key});

  @override
  State<RecordTripExpenseScreen> createState() =>
      _RecordTripExpenseScreenState();
}

class _RecordTripExpenseScreenState extends State<RecordTripExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Uuid _uuid = const Uuid();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );

  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _categoryController = TextEditingController(); // For expense category

  bool _isLoading = false;
  String? _currentDriverId;
  bool _isExpenseEntry = true; // true for Expense, false for Income

  @override
  void initState() {
    super.initState();
    _loadDriverId();
  }

  Future<void> _loadDriverId() async {
    final prefs = await SharedPreferences.getInstance();
    _currentDriverId = prefs.getString('user_primary_id');
    if (_currentDriverId == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบข้อมูลคนขับรถปัจจุบัน')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _submitTravelEntry() async {
    if (!_formKey.currentState!.validate() || _currentDriverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วน')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final amount = int.tryParse(_amountController.text) ?? 0;
    final note = _noteController.text;
    final categoryOrDetail = _categoryController.text;
    final timestamp = DateTime.now();

    final transaction = Transaction(
      uuid: _uuid.v4(),
      type: _isExpenseEntry
          ? TransactionType.TRIP_EXPENSE_BY_DRIVER
          : TransactionType.TRIP_INCOME_FOR_DRIVER,
      amount: amount,
      timestamp: timestamp,
      note: note,
      recordedByPrimaryId: _currentDriverId!,
      sourceAccountId: _isExpenseEntry
          ? _currentDriverId // Expense comes from driver's advance
          : EXTERNAL_SOURCE_ACCOUNT_ID, // Income from external source
      destinationAccountId: _isExpenseEntry
          ? EXPENSE_DESTINATION_ACCOUNT_ID // Special ID for expenses
          : _currentDriverId, // Income goes to driver's advance
      expenseCategory: categoryOrDetail.isNotEmpty ? categoryOrDetail : null,
      status: TransactionStatus
          .pendingExport, // Driver transactions usually need export
    );

    try {
      final db = await _dbHelper.database; // Ensure you get the db instance
      await db.transaction((txn) async {
        // Use the db instance to start a transaction
        await _dbHelper.insertTransaction(transaction, txn: txn); // Pass txn

        // Update DriverAdvanceAccount
        DriverAdvanceAccount? advanceAccount = await _dbHelper.getDriverAdvance(
          _currentDriverId!,
          txn: txn,
        ); // Pass txn

        if (advanceAccount != null) {
          if (_isExpenseEntry) {
            advanceAccount.balance -= amount;
          } else {
            advanceAccount.balance += amount;
          }
          advanceAccount.lastUpdated = timestamp;
          await _dbHelper.insertOrUpdateDriverAdvance(
            advanceAccount,
            txn: txn,
          ); // Pass txn
        } else {
          // This case should ideally not happen if initial data import was successful
          // Or handle by creating a new advance account with negative balance if that's the logic
          print("DriverAdvanceAccount not found for driver $_currentDriverId");
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'บันทึกรายการเดินทาง (${_isExpenseEntry ? "รายจ่าย" : "รายรับ"}) สำเร็จ!',
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
    return Scaffold(
      appBar: AppBar(title: const Text('บันทึกรายการเดินทาง')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: <Widget>[
              DropdownButtonFormField<bool>(
                decoration: const InputDecoration(
                  labelText: 'ประเภทรายการ',
                  border: OutlineInputBorder(),
                ),
                value: _isExpenseEntry,
                items: const [
                  DropdownMenuItem(value: true, child: Text('รายจ่ายเดินทาง')),
                  DropdownMenuItem(
                    value: false,
                    child: Text('รายรับค่าเดินทาง (เช่น เงินทำบุญ)'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _isExpenseEntry = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _categoryController,
                decoration: InputDecoration(
                  labelText: _isExpenseEntry
                      ? 'ประเภทค่าใช้จ่าย (เช่น ค่าน้ำมัน)'
                      : 'รายละเอียดรายรับ (เช่น ทำบุญค่าน้ำมัน)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'กรุณาระบุรายละเอียดรายการ'
                    : null,
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
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitTravelEntry,
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
