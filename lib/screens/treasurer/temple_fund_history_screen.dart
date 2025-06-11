// lib/screens/treasurer/temple_fund_history_screen.dart
import 'package:flutter/material.dart';
import 'package:moneywat/models/transaction_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:moneywat/models/user_model.dart'; // For User model to display names

class TempleFundHistoryScreen extends StatefulWidget {
  const TempleFundHistoryScreen({super.key});

  @override
  State<TempleFundHistoryScreen> createState() =>
      _TempleFundHistoryScreenState();
}

class _TempleFundHistoryScreenState extends State<TempleFundHistoryScreen> {
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
  DateTime _selectedMonthYear = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  ); // Default to current month

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    await _loadTreasurerId();
    _loadTempleFundHistory();
  }

  Future<void> _loadTreasurerId() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    _currentTreasurerId = prefs.getString('user_primary_id');

    if (_currentTreasurerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบข้อมูลไวยาวัจกรณ์ปัจจุบัน')),
        );
        // No need to set _isLoading = false here if we return
      }
      return;
    }
  }

  Future<void> _loadTempleFundHistory() async {
    if (_currentTreasurerId == null) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ไม่สามารถโหลดธุรกรรมได้: ไม่พบ ID ไวยาวัจกรณ์'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final transactionsFromDb = await _dbHelper
          .getTempleFundTransactionsForMonth(
            _currentTreasurerId!,
            _selectedMonthYear,
          );

      // Pre-fetch user details if needed (e.g., for GIVE_DRIVER_ADVANCE)
      Set<String> userIdsToFetch = {};
      for (var tx in transactionsFromDb) {
        if (tx.type == TransactionType.GIVE_DRIVER_ADVANCE &&
            tx.destinationAccountId != null) {
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

  Widget _buildTransactionTile(Transaction transaction) {
    String title = transaction.type.name;
    String subtitle = transaction.note;
    Color amountColor = Colors.black;
    String amountPrefix = '';
    IconData iconData = Icons.receipt_long;

    if (transaction.type == TransactionType.TEMPLE_INCOME) {
      title = 'รายรับวัด';
      amountColor = Colors.green.shade700;
      amountPrefix = '+ ';
      iconData = Icons.arrow_downward_rounded;
    } else if (transaction.type == TransactionType.TEMPLE_EXPENSE) {
      title = 'รายจ่ายวัด: ${transaction.expenseCategory ?? ""}';
      amountColor = Colors.red.shade700;
      amountPrefix = '- ';
      iconData = Icons.arrow_upward_rounded;
    } else if (transaction.type == TransactionType.GIVE_DRIVER_ADVANCE) {
      final driverName =
          _userCache[transaction.destinationAccountId]?.displayName ??
          transaction.destinationAccountId;
      title = 'ให้เงินสำรอง: $driverName';
      amountColor = Colors.orange.shade800;
      amountPrefix = '- ';
      iconData = Icons.directions_car_outlined;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ListTile(
        leading: Icon(iconData, color: amountColor, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '$subtitle\n${_dateTimeFormat.format(transaction.timestamp)}',
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

  Widget _buildMonthNavigationControls() {
    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'เดือนก่อนหน้า',
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _selectedMonthYear = DateTime(
                          _selectedMonthYear.year,
                          _selectedMonthYear.month - 1,
                          1,
                        );
                      });
                      _loadTempleFundHistory();
                    },
            ),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final DateTime? pickedDate = await showDatePicker(
                        context: context,
                        initialDate: _selectedMonthYear,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                        locale: const Locale('th', 'TH'),
                        initialDatePickerMode:
                            DatePickerMode.year, // Start with year selection
                      );
                      if (pickedDate != null) {
                        setState(() {
                          _selectedMonthYear = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            1,
                          );
                        });
                        _loadTempleFundHistory();
                      }
                    },
              child: Text(
                DateFormat('MMMM yyyy', 'th_TH').format(_selectedMonthYear),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'เดือนถัดไป',
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _selectedMonthYear = DateTime(
                          _selectedMonthYear.year,
                          _selectedMonthYear.month + 1,
                          1,
                        );
                      });
                      _loadTempleFundHistory();
                    },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ประวัติเงินกองกลางวัด')),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _transactions.isEmpty
                ? Center(
                    child: Text(
                      'ไม่มีรายการธุรกรรมในเดือน ${DateFormat('MMMM yyyy', 'th_TH').format(_selectedMonthYear)}',
                      style: const TextStyle(fontSize: 18),
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
      bottomNavigationBar: _buildMonthNavigationControls(),
    );
  }
}
