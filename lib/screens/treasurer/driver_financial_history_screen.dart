// lib/screens/treasurer/driver_financial_history_screen.dart
import 'package:flutter/material.dart';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/models/transaction_model.dart';
import 'package:moneywat/models/account_balance_models.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class DriverFinancialHistoryScreen extends StatefulWidget {
  final User driver;
  final DriverAdvanceAccount? driverAdvanceAccount;

  const DriverFinancialHistoryScreen({
    super.key,
    required this.driver,
    this.driverAdvanceAccount,
  });

  @override
  State<DriverFinancialHistoryScreen> createState() =>
      _DriverFinancialHistoryScreenState();
}

class _DriverFinancialHistoryScreenState
    extends State<DriverFinancialHistoryScreen> {
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
      final transactionsFromDb = await _dbHelper.getDriverFinancialHistory(
        widget.driver.primaryId,
        _currentTreasurerId!,
      );

      // Pre-fetch user details for display (recorders, other parties)
      Set<String> userIdsToFetch = {};
      for (var tx in transactionsFromDb) {
        userIdsToFetch.add(tx.recordedByPrimaryId); // Always fetch recorder
        if (tx.processedByPrimaryId != null &&
            tx.processedByPrimaryId!.isNotEmpty) {
          userIdsToFetch.add(tx.processedByPrimaryId!);
        }
        // Add other relevant IDs if needed, e.g., source/destination if not driver/treasurer
      }
      _userCache[_currentTreasurerId!] = (await _dbHelper.getUser(
        _currentTreasurerId!,
      ))!; // Cache treasurer
      _userCache[widget.driver.primaryId] =
          widget.driver; // Cache current driver

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
    String title = transaction.type.name;
    String detail = transaction.note;
    Color amountColor = Colors.black;
    String amountPrefix = '';
    IconData iconData = Icons.receipt_long;

    String recordedBy = _getUserDisplayName(transaction.recordedByPrimaryId);
    String processedBy = _getUserDisplayName(transaction.processedByPrimaryId);

    if (transaction.type == TransactionType.GIVE_DRIVER_ADVANCE) {
      title = 'คุณให้เงินสำรองเดินทาง';
      amountColor = Colors.orange.shade800;
      amountPrefix =
          '- '; // From Temple Fund's perspective, but for driver it's an increase
      iconData = Icons.outbound_outlined;
      detail = 'บันทึกโดย: $recordedBy\n${transaction.note}';
    } else if (transaction.type == TransactionType.TRIP_EXPENSE_BY_DRIVER) {
      title = 'ค่าใช้จ่ายเดินทาง (กระทบยอดแล้ว)';
      amountColor = Colors.red.shade700;
      amountPrefix = '- '; // Expense for driver
      iconData = Icons.directions_car_outlined;
      detail =
          '${transaction.expenseCategory ?? "ค่าใช้จ่าย"}: ${transaction.note}\nบันทึกโดย: $recordedBy (กระทบยอดโดย: $processedBy)';
    } else if (transaction.type == TransactionType.TEMPLE_INCOME &&
        transaction.sourceAccountId == widget.driver.primaryId) {
      // This assumes TEMPLE_INCOME from driver is advance return
      title = 'คนขับรถคืนเงินสำรอง';
      amountColor = Colors.green.shade700;
      amountPrefix =
          '+ '; // To Temple Fund, but for driver it's a decrease in what they hold
      iconData = Icons.savings_outlined;
      detail =
          'บันทึกโดย: $recordedBy (กระทบยอดโดย: $processedBy)\n${transaction.note}';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ListTile(
        leading: Icon(iconData, color: amountColor, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '$detail\n${_dateTimeFormat.format(transaction.timestamp)}',
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
        title: Text('ประวัติการเงินคนขับ ${widget.driver.displayName}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'ยอดเงินสำรองคงเหลือ: ${_currencyFormat.format(widget.driverAdvanceAccount?.balance ?? 0)}',
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
