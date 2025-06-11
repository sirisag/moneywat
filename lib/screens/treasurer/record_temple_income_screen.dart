// lib/screens/treasurer/record_temple_income_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moneywat/models/transaction_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart'; // For currency formatting

class RecordTempleIncomeScreen extends StatefulWidget {
  const RecordTempleIncomeScreen({super.key});

  @override
  State<RecordTempleIncomeScreen> createState() =>
      _RecordTempleIncomeScreenState();
}

class _RecordTempleIncomeScreenState extends State<RecordTempleIncomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Uuid _uuid = const Uuid();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );

  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  bool _isLoading = false;
  String? _currentTreasurerId;

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
      Navigator.pop(context); // Pop if treasurer ID is not found
    }
  }

  Future<void> _submitIncome() async {
    if (!_formKey.currentState!.validate() || _currentTreasurerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วน')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final amount = int.tryParse(_amountController.text) ?? 0;
    final note = _noteController.text.isNotEmpty
        ? _noteController.text
        : "รายรับวัด";
    final timestamp = DateTime.now();

    // Show confirmation dialog
    bool? confirmSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('ยืนยันการบันทึกรายรับ'),
          content: Text(
            'คุณต้องการบันทึกรายรับจำนวน ${_currencyFormat.format(amount)}\n'
            'หมายเหตุ: "$note"\n'
            'ใช่หรือไม่?',
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
      type: TransactionType.TEMPLE_INCOME,
      amount: amount,
      timestamp: timestamp,
      note: note,
      recordedByPrimaryId: _currentTreasurerId!,
      sourceAccountId:
          EXTERNAL_SOURCE_ACCOUNT_ID, // Income from external source
      destinationAccountId:
          _currentTreasurerId!, // Income goes to temple fund (managed by treasurer)
      status: TransactionStatus.completed,
    );

    try {
      await _dbHelper.insertTransaction(transaction);

      // Update TempleFundAccount
      await _dbHelper.updateTempleFundBalance(_currentTreasurerId!, amount);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('บันทึกรายรับสำเร็จ!')));
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
      appBar: AppBar(title: const Text('บันทึกรายรับของวัด')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: <Widget>[
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
                  labelText: 'หมายเหตุ (เช่น เงินบริจาคจาก...)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitIncome,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('บันทึกรายรับ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
