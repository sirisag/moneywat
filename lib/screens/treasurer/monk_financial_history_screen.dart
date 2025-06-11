// lib/screens/treasurer/monk_financial_history_screen.dart
import 'package:flutter/material.dart';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/models/transaction_model.dart';
import 'package:moneywat/models/account_balance_models.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class MonkFinancialHistoryScreen extends StatefulWidget {
  final User monk;
  final MonkFundAtTreasurer? monkFundAtTreasurer;

  const MonkFinancialHistoryScreen({
    super.key,
    required this.monk,
    this.monkFundAtTreasurer,
  });

  @override
  State<MonkFinancialHistoryScreen> createState() =>
      _MonkFinancialHistoryScreenState();
}

class _MonkFinancialHistoryScreenState
    extends State<MonkFinancialHistoryScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  List<Transaction> _transactions = [];
  bool _isLoading = true;
  String? _currentTreasurerId;
  final Map<String, User> _userCache = {}; // Cache for user details

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
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
      final transactionsFromDb = await _dbHelper.getMonkFinancialHistory(
        widget.monk.primaryId,
        _currentTreasurerId!,
      );

      // Pre-fetch user details for display (recorders, other parties)
      Set<String> userIdsToFetch = {};
      for (var tx in transactionsFromDb) {
        userIdsToFetch.add(tx.recordedByPrimaryId);
        if (tx.sourceAccountId != null &&
            tx.sourceAccountId != widget.monk.primaryId &&
            tx.sourceAccountId != _currentTreasurerId &&
            tx.sourceAccountId != EXTERNAL_SOURCE_ACCOUNT_ID &&
            tx.sourceAccountId != EXPENSE_DESTINATION_ACCOUNT_ID) {
          userIdsToFetch.add(tx.sourceAccountId!);
        }
        if (tx.destinationAccountId != null &&
            tx.destinationAccountId != widget.monk.primaryId &&
            tx.destinationAccountId != _currentTreasurerId &&
            tx.destinationAccountId != EXTERNAL_SOURCE_ACCOUNT_ID &&
            tx.destinationAccountId != EXPENSE_DESTINATION_ACCOUNT_ID) {
          userIdsToFetch.add(tx.destinationAccountId!);
        }
      }
      for (String userId in userIdsToFetch) {
        if (!_userCache.containsKey(userId)) {
          final user = await _dbHelper.getUser(userId);
          if (user != null) {
            _userCache[userId] = user;
          }
        }
      }

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

  String _getUserDisplayName(String? userId) {
    if (userId == null || userId.isEmpty) return 'N/A';
    return _userCache[userId]?.displayName ?? userId;
  }

  Widget _buildTransactionTile(Transaction transaction) {
    String title = transaction.type.name; // Default title
    String detail = transaction.note;
    Color amountColor = Colors.black;
    String amountPrefix = '';
    IconData iconData = Icons.receipt_long;

    String recordedBy = _getUserDisplayName(transaction.recordedByPrimaryId);

    // Customize display based on transaction type
    if (transaction.type == TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER) {
      title = 'พระ ${widget.monk.displayName} ฝากเงินกับคุณ';
      amountColor = Colors.green.shade700;
      amountPrefix = '+ ';
      iconData = Icons.input;
    } else if (transaction.type ==
        TransactionType.MONK_WITHDRAWAL_FROM_TREASURER) {
      title = 'คุณจ่ายเงินให้พระ ${widget.monk.displayName}';
      amountColor = Colors.red.shade700;
      amountPrefix = '- ';
      iconData = Icons.output;
    } else if (transaction.type ==
        TransactionType.TRANSFER_MONK_FUND_TO_DRIVER) {
      title =
          'คุณโอนเงินของพระ ${widget.monk.displayName} ให้คนขับ ${_getUserDisplayName(transaction.destinationAccountId)}';
      amountColor = Colors.orange.shade800;
      amountPrefix = '- '; // From monk's balance with treasurer
      iconData = Icons.sync_alt;
    } else if (transaction.type ==
            TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER &&
        transaction.processedByPrimaryId == _currentTreasurerId) {
      title =
          'รับเงินจากคนขับ $recordedBy (พระ ${widget.monk.displayName} ฝาก)';
      amountColor = Colors.green.shade700;
      amountPrefix =
          '+ '; // To monk's balance with treasurer after reconciliation
      iconData = Icons.call_received;
    } else if (transaction.type ==
            TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER &&
        transaction.processedByPrimaryId == _currentTreasurerId) {
      title =
          'จ่ายเงินให้คนขับ $recordedBy (พระ ${widget.monk.displayName} เบิก)';
      amountColor = Colors.red.shade700;
      amountPrefix =
          '- '; // From monk's balance with treasurer after reconciliation
      iconData = Icons.call_made;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ListTile(
        leading: Icon(iconData, color: amountColor, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '$detail\nบันทึกโดย: $recordedBy\n${_dateTimeFormat.format(transaction.timestamp)}',
        ),
        trailing: Text(
          '$amountPrefix${_currencyFormat.format(transaction.amount)}',
          style: TextStyle(
            color: amountColor,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        isThreeLine: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ประวัติการเงินพระ ${widget.monk.displayName}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'ยอดคงเหลือกับไวยาวัจกรณ์: ${_currencyFormat.format(widget.monkFundAtTreasurer?.balance ?? 0)}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _transactions.isEmpty
                ? const Center(
                    child: Text(
                      'ยังไม่มีรายการธุรกรรม',
                      style: TextStyle(fontSize: 18),
                    ),
                  )
                : ListView.builder(
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      return _buildTransactionTile(_transactions[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
