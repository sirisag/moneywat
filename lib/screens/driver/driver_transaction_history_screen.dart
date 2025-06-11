// lib/screens/driver/driver_transaction_history_screen.dart
import 'package:flutter/material.dart';
import 'package:moneywat/models/transaction_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moneywat/models/user_model.dart'; // For User model
import 'package:moneywat/models/account_balance_models.dart'; // For MonkFundAtDriver
import 'package:intl/intl.dart'; // For date and currency formatting

class DriverTransactionHistoryScreen extends StatefulWidget {
  const DriverTransactionHistoryScreen({super.key});

  @override
  State<DriverTransactionHistoryScreen> createState() =>
      _DriverTransactionHistoryScreenState();
}

class _DriverTransactionHistoryScreenState
    extends State<DriverTransactionHistoryScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  final Map<String, User> _monkDetailsCache = {}; // Cache for monk details
  List<Transaction> _transactions = [];
  bool _isLoading = true;
  String? _currentDriverId;

  @override
  void initState() {
    super.initState();
    _loadDriverTransactions();
  }

  Future<void> _loadDriverTransactions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _currentDriverId = prefs.getString('user_primary_id');

    if (_currentDriverId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบข้อมูลคนขับรถปัจจุบัน')),
        );
        // Optionally pop or disable functionality
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final transactionsFromDb = await _dbHelper.getTransactionsByRecordedUser(
        _currentDriverId!,
      );

      // Pre-fetch monk details for transactions involving monks
      Set<String> monkIdsToFetch = {};
      for (var tx in transactionsFromDb) {
        if (tx.type == TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER &&
            tx.sourceAccountId != null) {
          monkIdsToFetch.add(tx.sourceAccountId!);
        } else if (tx.type == TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER &&
            tx.destinationAccountId != null) {
          monkIdsToFetch.add(tx.destinationAccountId!);
        }
      }
      for (String monkId in monkIdsToFetch) {
        if (!_monkDetailsCache.containsKey(monkId)) {
          final monkUser = await _dbHelper.getUser(monkId);
          if (monkUser != null) {
            _monkDetailsCache[monkId] = monkUser;
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

  String _getTransactionTypeDisplayName(TransactionType type) {
    // This function can be expanded to provide user-friendly names for all transaction types
    switch (type) {
      case TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER:
        return 'พระฝากเงิน';
      case TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER:
        return 'เบิกเงินให้พระ';
      case TransactionType.TRIP_EXPENSE_BY_DRIVER:
        return 'ค่าใช้จ่ายเดินทาง';
      case TransactionType.INITIAL_DRIVER_ADVANCE:
        return 'รับเงินสำรองเริ่มต้น';
      case TransactionType.RECEIVE_DRIVER_ADVANCE:
        return 'รับเงินสำรอง';
      case TransactionType.INITIAL_MONK_FUND_AT_DRIVER:
        return 'ยอดเริ่มต้นของพระ (ฝากกับคนขับ)';
      // Add more cases as needed
      default:
        return type.name; // Fallback to enum name
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ประวัติธุรกรรมของฉัน')),
      body: _isLoading
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
                final transaction = _transactions[index];
                String titleText = _getTransactionTypeDisplayName(
                  transaction.type,
                );
                String firstLineDetail = transaction.note.isNotEmpty
                    ? transaction.note
                    : '-';
                Color amountColor = Colors
                    .grey
                    .shade700; // Default color for non-monk transactions
                IconData transactionIcon = Icons.receipt_long;
                String amountPrefix = "";
                Widget? trailingWidget;

                if (transaction.type ==
                    TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER) {
                  amountColor = Colors.green.shade700;
                  transactionIcon = Icons.arrow_downward_rounded;
                  amountPrefix = "+ ";
                  final monk = _monkDetailsCache[transaction.sourceAccountId];
                  if (monk != null) {
                    titleText = '${monk.displayName} (ID: ${monk.primaryId})';
                    firstLineDetail =
                        'ฝากเงิน : ${transaction.note.isNotEmpty ? transaction.note : '-'}';
                    trailingWidget = FutureBuilder<MonkFundAtDriver?>(
                      future: _dbHelper.getMonkFundAtDriver(
                        monk.primaryId,
                        _currentDriverId!,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done &&
                            snapshot.hasData &&
                            snapshot.data != null) {
                          return Text(
                            'ยอดฝาก: ${_currencyFormat.format(snapshot.data!.balance)}',
                            style: TextStyle(color: Colors.blue.shade700),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    );
                  }
                } else if (transaction.type ==
                    TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER) {
                  amountColor = Colors.orange.shade800;
                  transactionIcon = Icons.arrow_upward_rounded;
                  amountPrefix = "- ";
                  final monk =
                      _monkDetailsCache[transaction.destinationAccountId];
                  if (monk != null) {
                    titleText = '${monk.displayName} (ID: ${monk.primaryId})';
                    firstLineDetail =
                        'เบิกเงิน : ${transaction.note.isNotEmpty ? transaction.note : '-'}';
                    trailingWidget = FutureBuilder<MonkFundAtDriver?>(
                      future: _dbHelper.getMonkFundAtDriver(
                        monk.primaryId,
                        _currentDriverId!,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done &&
                            snapshot.hasData &&
                            snapshot.data != null) {
                          return Text(
                            'ยอดฝาก: ${_currencyFormat.format(snapshot.data!.balance)}',
                            style: TextStyle(color: Colors.blue.shade700),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    );
                  }
                } else if (transaction.type ==
                    TransactionType.TRIP_EXPENSE_BY_DRIVER) {
                  amountColor = Colors.red.shade700;
                  transactionIcon = Icons.directions_car_filled_outlined;
                  amountPrefix = "- ";
                  firstLineDetail =
                      '${transaction.expenseCategory ?? "ค่าใช้จ่าย"}: ${transaction.note.isNotEmpty ? transaction.note : '-'}';
                } else if (transaction.type ==
                        TransactionType.RECEIVE_DRIVER_ADVANCE ||
                    transaction.type ==
                        TransactionType.INITIAL_DRIVER_ADVANCE) {
                  amountColor = Colors.blue.shade700;
                  transactionIcon = Icons.account_balance_wallet_outlined;
                  amountPrefix = "+ ";
                  firstLineDetail =
                      'รับเงินสำรอง: ${transaction.note.isNotEmpty ? transaction.note : '-'}';
                } else if (transaction.type ==
                    TransactionType.INITIAL_MONK_FUND_AT_DRIVER) {
                  amountColor =
                      Colors.purple.shade700; // Different color for distinction
                  transactionIcon = Icons.savings_outlined;
                  amountPrefix =
                      "+ "; // Represents an initial balance for a monk with the driver
                  final monk =
                      _monkDetailsCache[transaction
                          .destinationAccountId]; // Monk is the destination of this initial fund
                  if (monk != null) {
                    titleText = 'ยอดเริ่มต้นสำหรับ ${monk.displayName}';
                  } else {
                    titleText = 'ยอดเริ่มต้นของพระ (ไม่พบชื่อ)';
                  }
                  firstLineDetail = transaction.note.isNotEmpty
                      ? transaction.note
                      : 'บันทึกยอดเริ่มต้น';
                } else {
                  // Default for other transaction types
                  amountColor = Colors.grey.shade700;
                  transactionIcon = Icons.receipt_long;
                  firstLineDetail = transaction.note.isNotEmpty
                      ? transaction.note
                      : '-';
                  // Determine if it's income or expense for the driver
                  if (transaction.destinationAccountId == _currentDriverId &&
                      transaction.sourceAccountId != _currentDriverId) {
                    amountColor = Colors.green.shade700;
                    amountPrefix = "+ ";
                  } else if (transaction.sourceAccountId == _currentDriverId &&
                      transaction.destinationAccountId != _currentDriverId &&
                      transaction.destinationAccountId !=
                          EXPENSE_DESTINATION_ACCOUNT_ID /* Avoid double marking expenses */ ) {
                    amountColor = Colors.red.shade700;
                    amountPrefix = "- ";
                  }
                }

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 6.0,
                  ),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
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
                          Text(
                            firstLineDetail,
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            '$amountPrefix${_currencyFormat.format(transaction.amount)}',
                            style: TextStyle(
                              color: amountColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            _dateTimeFormat.format(transaction.timestamp),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      trailing: trailingWidget,
                      isThreeLine: true,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
