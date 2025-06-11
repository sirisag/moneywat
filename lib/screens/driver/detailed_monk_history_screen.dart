// lib/screens/driver/detailed_monk_history_screen.dart
import 'package:flutter/material.dart';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/models/transaction_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:intl/intl.dart';

class DetailedMonkHistoryScreen extends StatefulWidget {
  final User monk;
  final String driverId;

  const DetailedMonkHistoryScreen({
    super.key,
    required this.monk,
    required this.driverId,
  });

  @override
  State<DetailedMonkHistoryScreen> createState() =>
      _DetailedMonkHistoryScreenState();
}

class _DetailedMonkHistoryScreenState extends State<DetailedMonkHistoryScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );
  List<Transaction> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTransactionsForMonk();
  }

  Future<void> _loadTransactionsForMonk() async {
    setState(() => _isLoading = true);
    try {
      final transactionsFromDb = await _dbHelper.getMonkHistoryForDriverView(
        widget.monk.primaryId,
        widget.driverId,
      );
      if (mounted) {
        setState(() {
          _transactions = transactionsFromDb;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถโหลดประวัติธุรกรรมได้: $e')),
        );
      }
    }
  }

  String _getTransactionTypeDisplayName(TransactionType type) {
    switch (type) {
      case TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER:
        return 'พระฝากเงิน';
      case TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER:
        return 'เบิกเงินให้พระ';
      case TransactionType.INITIAL_MONK_FUND_AT_DRIVER:
        return 'ยอดเริ่มต้น (จากไวยาวัจกรณ์)';
      default:
        return type.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ประวัติธุรกรรม: ${widget.monk.displayName}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty
          ? const Center(
              child: Text('ไม่มีรายการธุรกรรม', style: TextStyle(fontSize: 18)),
            )
          : ListView.builder(
              itemCount: _transactions.length,
              itemBuilder: (context, index) {
                final transaction = _transactions[index];
                String titleText = _getTransactionTypeDisplayName(
                  transaction.type,
                );
                String subtitleText = '';
                Color amountColor = Colors.black;
                String amountPrefix = '';
                IconData transactionIcon = Icons.receipt_long;

                if (transaction.type ==
                    TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER) {
                  amountColor = Colors.green.shade700;
                  amountPrefix = '+ ';
                  transactionIcon = Icons.arrow_downward_rounded;
                  subtitleText = transaction.note.isNotEmpty
                      ? 'หมายเหตุ: ${transaction.note}'
                      : 'พระฝากเงินกับคุณ';
                } else if (transaction.type ==
                    TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER) {
                  amountColor = Colors.orange.shade800;
                  amountPrefix = '- ';
                  transactionIcon = Icons.arrow_upward_rounded;
                  subtitleText = transaction.note.isNotEmpty
                      ? 'หมายเหตุ: ${transaction.note}'
                      : 'คุณเบิกเงินให้พระ';
                } else if (transaction.type ==
                    TransactionType.INITIAL_MONK_FUND_AT_DRIVER) {
                  amountColor = Colors.purple.shade700;
                  amountPrefix = '+ '; // Represents an initial balance
                  transactionIcon = Icons.savings_outlined;
                  subtitleText = transaction.note.isNotEmpty
                      ? transaction.note
                      : 'ยอดเริ่มต้นที่ฝากกับคุณ';
                }

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: ListTile(
                    leading: Icon(
                      transactionIcon,
                      color: amountColor,
                      size: 30,
                    ),
                    title: Text(
                      titleText,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (subtitleText.isNotEmpty) Text(subtitleText),
                        Text(
                          DateFormat(
                            'dd/MM/yyyy HH:mm',
                          ).format(transaction.timestamp),
                        ),
                      ],
                    ),
                    trailing: Text(
                      '$amountPrefix${_currencyFormat.format(transaction.amount)}',
                      style: TextStyle(
                        color: amountColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    isThreeLine: subtitleText.isNotEmpty,
                  ),
                );
              },
            ),
    );
  }
}
