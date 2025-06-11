// lib/screens/treasurer/all_monks_financial_history_screen.dart
import 'package:flutter/material.dart';
import 'package:moneywat/models/transaction_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:intl/intl.dart';
import 'package:moneywat/models/user_model.dart'; // Import User model
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences

class AllMonksFinancialHistoryScreen extends StatefulWidget {
  const AllMonksFinancialHistoryScreen({super.key});

  @override
  State<AllMonksFinancialHistoryScreen> createState() =>
      _AllMonksFinancialHistoryScreenState();
}

class _AllMonksFinancialHistoryScreenState
    extends State<AllMonksFinancialHistoryScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  List<Transaction> _allMonkTransactions = [];
  bool _isLoading = true;
  String? _currentTreasurerId;
  final Map<String, User> _userCache = {}; // Cache for user details
  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  ); // Default to today, no time part

  @override
  void initState() {
    super.initState();
    // _loadAllMonkTransactions(); // Will be called by _initializeScreen
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    await _loadTreasurerId(); // Ensure treasurer ID is loaded first
    _loadAllMonkTransactions(); // Then load transactions for the initial date
  }

  Future<void> _loadTreasurerId() async {
    setState(() => _isLoading = true);
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
    // If treasurer ID is loaded, no need to set _isLoading here,
    // _loadAllMonkTransactions will handle it.
  }

  Future<void> _loadAllMonkTransactions() async {
    if (_currentTreasurerId == null) {
      // If treasurer ID wasn't loaded (e.g., in initState before _initializeScreen completes fully)
      // or if it somehow became null, try loading it again or handle error.
      // For simplicity, we assume _loadTreasurerId in _initializeScreen handles this.
      // If still null, we can't proceed.
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
    setState(() => _isLoading = true);

    try {
      final db = await _dbHelper.database;
      // Fetch all transactions that involve monks, either directly with the treasurer
      // or reconciled transactions from drivers.
      final List<Map<String, dynamic>> maps = await db.rawQuery(
        '''
        SELECT * FROM ${DatabaseHelper.tableTransactions}
        WHERE strftime('%Y-%m-%d', timestamp) = strftime('%Y-%m-%d', ?) AND (
          ( -- Transactions directly involving treasurer and a monk
            (type = ? AND sourceAccountId IN (SELECT primaryId FROM ${DatabaseHelper.tableUsers} WHERE role = ?)) OR
            (type = ? AND destinationAccountId IN (SELECT primaryId FROM ${DatabaseHelper.tableUsers} WHERE role = ?)) OR
            (type = ? AND sourceAccountId IN (SELECT primaryId FROM ${DatabaseHelper.tableUsers} WHERE role = ?))
          ) OR
          ( -- Reconciled transactions from drivers involving a monk
            (type = ? OR type = ?)
            AND status = ?
            AND processedByPrimaryId = ?
            AND (
                  sourceAccountId IN (SELECT primaryId FROM ${DatabaseHelper.tableUsers} WHERE role = ?) OR
                  destinationAccountId IN (SELECT primaryId FROM ${DatabaseHelper.tableUsers} WHERE role = ?)
                )
          )
        )
        ORDER BY timestamp DESC
      ''',
        [
          _selectedDate.toIso8601String().substring(
            0,
            10,
          ), // Date part for comparison
          TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER.name,
          UserRole.monk.name,
          TransactionType.MONK_WITHDRAWAL_FROM_TREASURER.name,
          UserRole.monk.name,
          TransactionType.TRANSFER_MONK_FUND_TO_DRIVER.name,
          UserRole.monk.name,
          TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER.name,
          TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER.name,
          TransactionStatus.reconciledByTreasurer.name,
          _currentTreasurerId,
          UserRole.monk.name,
          UserRole.monk.name,
        ],
      );

      List<Transaction> transactions = List.generate(maps.length, (i) {
        return Transaction.fromMap(maps[i]);
      });

      // Pre-fetch user details for display
      Set<String> userIdsToFetch = {};
      for (var tx in transactions) {
        userIdsToFetch.add(tx.recordedByPrimaryId);
        if (tx.sourceAccountId != null && tx.sourceAccountId!.isNotEmpty) {
          userIdsToFetch.add(tx.sourceAccountId!);
        }
        if (tx.destinationAccountId != null &&
            tx.destinationAccountId!.isNotEmpty) {
          userIdsToFetch.add(tx.destinationAccountId!);
        }
        if (tx.processedByPrimaryId != null &&
            tx.processedByPrimaryId!.isNotEmpty) {
          userIdsToFetch.add(tx.processedByPrimaryId!);
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
          _allMonkTransactions = transactions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถโหลดประวัติธุรกรรมของพระได้: $e')),
        );
      }
    }
  }

  String _getUserDisplayName(String? userId) {
    if (userId == null || userId.isEmpty) return 'N/A';
    return _userCache[userId]?.displayName ?? userId;
  }

  String _getMonkNameForTransaction(Transaction tx) {
    // TODO: Determine monk involved in the transaction and get their name
    // This will depend on tx.type, tx.sourceAccountId, tx.destinationAccountId
    User? monkUser;
    switch (tx.type) {
      case TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER:
      case TransactionType.TRANSFER_MONK_FUND_TO_DRIVER:
        monkUser = _userCache[tx.sourceAccountId];
        break;
      case TransactionType.MONK_WITHDRAWAL_FROM_TREASURER:
        monkUser = _userCache[tx.destinationAccountId];
        break;
      case TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER:
        // For reconciled driver transactions, monk is source
        monkUser = _userCache[tx.sourceAccountId];
        break;
      case TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER:
        // For reconciled driver transactions, monk is destination
        monkUser = _userCache[tx.destinationAccountId];
        break;
      default:
        // Try to infer if not explicitly covered
        if (_userCache[tx.sourceAccountId]?.role == UserRole.monk) {
          monkUser = _userCache[tx.sourceAccountId];
        } else if (_userCache[tx.destinationAccountId]?.role == UserRole.monk) {
          monkUser = _userCache[tx.destinationAccountId];
        }
    }
    return monkUser?.displayName ?? "พระ (ไม่พบชื่อ)";
  }

  String _getTransactionDetail(Transaction tx) {
    String recordedBy = _getUserDisplayName(tx.recordedByPrimaryId);
    String processedBy = tx.processedByPrimaryId != null
        ? " (กระทบยอดโดย: ${_getUserDisplayName(tx.processedByPrimaryId)})"
        : "";
    return 'จำนวน: ${_currencyFormat.format(tx.amount)}\nหมายเหตุ: ${tx.note}\nบันทึกโดย: $recordedBy$processedBy\nเวลา: ${_dateTimeFormat.format(tx.timestamp)}';
  }

  Widget _buildDateNavigationControls() {
    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'วันก่อนหน้า',
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _selectedDate = _selectedDate.subtract(
                          const Duration(days: 1),
                        );
                      });
                      _loadAllMonkTransactions();
                    },
            ),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ), // Allow future for safety
                        locale: const Locale('th', 'TH'),
                      );
                      if (picked != null && picked != _selectedDate) {
                        setState(() {
                          _selectedDate = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                          );
                        });
                        _loadAllMonkTransactions();
                      }
                    },
              child: Text(
                DateFormat('EEE d MMM yyyy', 'th_TH').format(_selectedDate),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'วันถัดไป',
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _selectedDate = _selectedDate.add(
                          const Duration(days: 1),
                        );
                      });
                      _loadAllMonkTransactions();
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
      appBar: AppBar(title: const Text('ประวัติการเงินของพระทั้งหมด')),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _allMonkTransactions.isEmpty
                ? const Center(
                    child: Text(
                      'ไม่มีรายการธุรกรรมของพระ',
                      style: TextStyle(fontSize: 18),
                    ),
                  )
                : ListView.builder(
                    itemCount: _allMonkTransactions.length,
                    itemBuilder: (context, index) {
                      final transaction = _allMonkTransactions[index];
                      String title = _getMonkNameForTransaction(transaction);
                      Color amountColor = Colors.grey;
                      String amountPrefix = "";
                      IconData icon = Icons.receipt_long_outlined;

                      // Determine color and prefix based on effect on monk's balance (conceptual)
                      if (transaction.type ==
                              TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER ||
                          (transaction.type ==
                                  TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER &&
                              transaction.status ==
                                  TransactionStatus.reconciledByTreasurer)) {
                        title += " - ฝากเงิน";
                        amountColor = Colors.green.shade700;
                        amountPrefix = "+";
                        icon = Icons.input;
                      } else if (transaction.type ==
                              TransactionType.MONK_WITHDRAWAL_FROM_TREASURER ||
                          (transaction.type ==
                                  TransactionType
                                      .WITHDRAWAL_FOR_MONK_FROM_DRIVER &&
                              transaction.status ==
                                  TransactionStatus.reconciledByTreasurer)) {
                        title += " - เบิกเงิน";
                        amountColor = Colors.red.shade700;
                        amountPrefix = "-";
                        icon = Icons.output;
                      } else if (transaction.type ==
                          TransactionType.TRANSFER_MONK_FUND_TO_DRIVER) {
                        title += " - โอนให้คนขับรถ";
                        amountColor = Colors.orange.shade800;
                        amountPrefix =
                            "-"; // From monk's perspective with treasurer
                        icon = Icons.sync_alt;
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 4.0,
                        ),
                        child: ListTile(
                          leading: Icon(icon, color: amountColor, size: 30),
                          title: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(_getTransactionDetail(transaction)),
                          trailing: Text(
                            '$amountPrefix${_currencyFormat.format(transaction.amount)}',
                            style: TextStyle(
                              color: amountColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          isThreeLine: true,
                          // Add more details as needed
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildDateNavigationControls(),
    );
  }
}
