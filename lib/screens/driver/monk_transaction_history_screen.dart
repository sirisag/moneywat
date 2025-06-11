// lib/screens/driver/monk_transaction_history_screen.dart
import 'package:flutter/material.dart';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/models/transaction_model.dart';
import 'package:moneywat/services/database_helper.dart';
import 'package:moneywat/models/account_balance_models.dart'; // For MonkFundAtDriver
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'detailed_monk_history_screen.dart'; // New screen for detailed history

class MonkSummaryCardData {
  final User monk;
  final MonkFundAtDriver? fundAtDriver;
  final Transaction? latestTransaction;
  final DateTime lastActivityTimestamp;

  MonkSummaryCardData({
    required this.monk,
    this.fundAtDriver,
    this.latestTransaction,
    required this.lastActivityTimestamp,
  });
}

class MonkTransactionHistoryScreen extends StatefulWidget {
  const MonkTransactionHistoryScreen({super.key});

  @override
  State<MonkTransactionHistoryScreen> createState() =>
      _MonkTransactionHistoryScreenState();
}

class _MonkTransactionHistoryScreenState
    extends State<MonkTransactionHistoryScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );
  List<User> _monks = [];
  User? _selectedMonk;
  List<MonkSummaryCardData> _monkSummaries = [];
  bool _isLoading = true;
  String? _currentDriverId;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _currentDriverId = prefs.getString('user_primary_id');

    if (_currentDriverId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบข้อมูลคนขับรถปัจจุบัน')),
        );
        Navigator.pop(context);
      }
      return;
    }

    try {
      final activeMonks = await _dbHelper.getActiveMonks();
      List<MonkSummaryCardData> summaries = [];

      for (var monk in activeMonks) {
        final fundAtDriver = await _dbHelper.getMonkFundAtDriver(
          monk.primaryId,
          _currentDriverId!,
        );
        final transactions = await _dbHelper.getMonkHistoryForDriverView(
          monk.primaryId,
          _currentDriverId!,
        );

        if (fundAtDriver == null && transactions.isEmpty) {
          continue; // Skip monks with no activity or funds with this driver
        }

        Transaction? latestTx = transactions.isNotEmpty
            ? transactions.first
            : null;
        DateTime? latestTxTimestamp = latestTx?.timestamp;
        DateTime? fundLastUpdated = fundAtDriver?.lastUpdated;
        DateTime lastActivity;

        if (latestTxTimestamp != null && fundLastUpdated != null) {
          lastActivity = latestTxTimestamp.isAfter(fundLastUpdated)
              ? latestTxTimestamp
              : fundLastUpdated;
        } else if (latestTxTimestamp != null) {
          lastActivity = latestTxTimestamp;
        } else if (fundLastUpdated != null) {
          lastActivity = fundLastUpdated;
        } else {
          // Should not happen if we skipped monks with no activity/funds
          // but as a fallback, use a very old date or handle error
          continue;
        }

        summaries.add(
          MonkSummaryCardData(
            monk: monk,
            fundAtDriver: fundAtDriver,
            latestTransaction: latestTx,
            lastActivityTimestamp: lastActivity,
          ),
        );
      }

      // Sort by lastActivityTimestamp descending
      summaries.sort(
        (a, b) => b.lastActivityTimestamp.compareTo(a.lastActivityTimestamp),
      );

      if (mounted) {
        setState(() {
          _monkSummaries = summaries;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถโหลดข้อมูลสรุปของพระได้: $e')),
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
      // Add other relevant types if necessary
      default:
        return type.name;
    }
  }

  void _navigateToDetailedHistory(User monk) {
    if (_currentDriverId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DetailedMonkHistoryScreen(monk: monk, driverId: _currentDriverId!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('สรุปข้อมูลพระ (คนขับรถ)')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _monkSummaries.isEmpty
          ? const Center(
              child: Text(
                'ไม่มีข้อมูลพระที่มีกิจกรรมกับคุณ',
                style: TextStyle(fontSize: 18),
              ),
            )
          : ListView.builder(
              itemCount: _monkSummaries.length,
              itemBuilder: (context, index) {
                final summary = _monkSummaries[index];
                final monk = summary.monk;
                final latestTx = summary.latestTransaction;
                final fundBalance = summary.fundAtDriver?.balance ?? 0;

                String latestTxText = "ไม่มีรายการล่าสุด";
                Color latestTxAmountColor = Colors.grey;
                String latestTxAmountPrefix = "";
                int latestTxAmount = 0;

                if (latestTx != null) {
                  latestTxText =
                      'ล่าสุด: ${_getTransactionTypeDisplayName(latestTx.type)}';
                  latestTxAmount = latestTx.amount;
                  if (latestTx.type ==
                      TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER) {
                    latestTxAmountColor = Colors.green.shade700;
                    latestTxAmountPrefix = "+";
                  } else if (latestTx.type ==
                      TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER) {
                    latestTxAmountColor = Colors.orange.shade800;
                    latestTxAmountPrefix = "-";
                  } else if (latestTx.type ==
                      TransactionType.INITIAL_MONK_FUND_AT_DRIVER) {
                    latestTxAmountColor = Colors.purple.shade700;
                    latestTxAmountPrefix = "+";
                  }
                }

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        monk.displayName.isNotEmpty ? monk.displayName[0] : 'P',
                      ),
                    ),
                    title: Text(
                      monk.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ID: ${monk.primaryId}'),
                        if (latestTx != null)
                          Text(
                            '$latestTxText ${_currencyFormat.format(latestTxAmount)}',
                            style: TextStyle(color: latestTxAmountColor),
                          ),
                        if (latestTx == null && summary.fundAtDriver != null)
                          Text(
                            'ยอดเริ่มต้น: ${_currencyFormat.format(fundBalance)}',
                            style: TextStyle(color: Colors.purple.shade700),
                          ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'ยอดคงเหลือ:',
                          style: TextStyle(fontSize: 12),
                        ),
                        Text(
                          _currencyFormat.format(fundBalance),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: fundBalance < 0
                                ? Colors.red
                                : Colors.black87,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    onTap: () => _navigateToDetailedHistory(monk),
                  ),
                );
              },
            ),
    );
  }
}
