// lib/screens/treasurer/reconcile_transactions_screen.dart
import 'package:flutter/material.dart';
import 'package:moneywat/models/transaction_model.dart';
import 'package:moneywat/models/user_model.dart'; // For User model to display names
import 'package:moneywat/models/account_balance_models.dart'; // Import AccountBalance models
import 'package:moneywat/services/database_helper.dart';
import 'package:intl/intl.dart';
// import 'package:flutter/services.dart'; // Import for FilteringTextInputFormatter - Not used here
import 'package:shared_preferences/shared_preferences.dart';

class ReconcileTransactionsScreen extends StatefulWidget {
  const ReconcileTransactionsScreen({super.key});

  @override
  State<ReconcileTransactionsScreen> createState() =>
      _ReconcileTransactionsScreenState();
}

class _ReconcileTransactionsScreenState
    extends State<ReconcileTransactionsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );
  final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  List<Transaction> _pendingTransactions = [];
  bool _isLoading = true;
  String? _currentTreasurerId;
  final Map<String, User> _userCache = {}; // Cache for user details

  @override
  void initState() {
    super.initState();
    _loadPendingTransactions();
  }

  Future<void> _loadTreasurerId() async {
    final prefs = await SharedPreferences.getInstance();
    _currentTreasurerId = prefs.getString('user_primary_id');
  }

  Future<void> _loadPendingTransactions() async {
    await _loadTreasurerId();
    if (_currentTreasurerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบข้อมูลไวยาวัจกรณ์ปัจจุบัน')),
        );
        setState(() => _isLoading = false);
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final transactions = await _dbHelper.getTransactionsByStatusAndProcessor(
        TransactionStatus.pendingReconciliationByTreasurer,
        _currentTreasurerId!,
      );

      Set<String> userIdsToFetch = {};
      for (var tx in transactions) {
        if (tx.recordedByPrimaryId.isNotEmpty) {
          userIdsToFetch.add(tx.recordedByPrimaryId);
        }
        if (tx.sourceAccountId != null && tx.sourceAccountId!.isNotEmpty) {
          userIdsToFetch.add(tx.sourceAccountId!);
        }
        if (tx.destinationAccountId != null &&
            tx.destinationAccountId!.isNotEmpty) {
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
          _pendingTransactions = transactions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถโหลดรายการธุรกรรมได้: $e')),
        );
      }
    }
  }

  String _getUserDisplayName(String? userId) {
    if (userId == null || userId.isEmpty) return 'N/A';
    if (userId == EXTERNAL_SOURCE_ACCOUNT_ID) return 'แหล่งภายนอก';
    if (userId == EXPENSE_DESTINATION_ACCOUNT_ID) return 'ปลายทางค่าใช้จ่าย';
    return _userCache[userId]?.displayName ?? userId;
  }

  Future<void> _reconcileTransaction(Transaction transaction) async {
    if (_currentTreasurerId == null) return;

    bool? confirmReconcile = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('ยืนยันการกระทบยอด'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('คุณต้องการกระทบยอดรายการนี้ใช่หรือไม่?'),
                const SizedBox(height: 8),
                Text('ประเภท: ${transaction.type.name}'),
                Text('จำนวน: ${_currencyFormat.format(transaction.amount)}'),
                Text(
                  'บันทึกโดย: ${_getUserDisplayName(transaction.recordedByPrimaryId)}',
                ),
                Text('หมายเหตุ: ${transaction.note}'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ยกเลิก'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: const Text('ยืนยันกระทบยอด'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmReconcile == null || !confirmReconcile) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ยกเลิกการกระทบยอดรายการ')));
      return;
    }

    final db = await _dbHelper.database;
    try {
      await db.transaction((txn) async {
        // Ensure all DB operations are in a transaction
        // 1. Update relevant account balances based on transaction type
        if (transaction.type ==
            TransactionType.FORWARD_MONK_FUND_TO_TREASURER) {
          // This is the net amount driver is forwarding for a specific monk.
          // sourceAccountId is monk's ID, destinationAccountId is treasurer's ID.
          final monkId = transaction.sourceAccountId;
          final treasurerId = transaction.destinationAccountId;

          if (treasurerId != _currentTreasurerId) {
            throw Exception(
              'Treasurer ID in transaction does not match current treasurer.',
            );
          }

          if (monkId != null && monkId.isNotEmpty) {
            MonkFundAtTreasurer? monkFund = await _dbHelper
                .getMonkFundAtTreasurer(monkId, _currentTreasurerId!, txn: txn);
            monkFund ??= MonkFundAtTreasurer(
              monkPrimaryId: monkId,
              treasurerPrimaryId: _currentTreasurerId!,
              balance: 0,
              lastUpdated: DateTime.now(),
            );
            monkFund.balance +=
                transaction.amount; // Increase monk's fund with treasurer
            monkFund.lastUpdated = DateTime.now();
            await _dbHelper.insertOrUpdateMonkFundAtTreasurer(
              monkFund,
              txn: txn,
            );

            // Update Temple Fund
            await _dbHelper.updateTempleFundBalance(
              // Money comes into temple
              _currentTreasurerId!,
              transaction.amount,
              txn: txn,
            );
          } else {
            throw Exception(
              'ไม่พบ Monk ID สำหรับ FORWARD_MONK_FUND_TO_TREASURER',
            );
          }
        } else if (transaction.type ==
                TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER ||
            transaction.type ==
                TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER) {
          // These are original transactions from the driver for audit.
          // Their financial impact on treasurer's books is handled by FORWARD_MONK_FUND_TO_TREASURER.
          // So, just mark them as reconciled. No balance changes here.
          print(
            "Reconciling driver's original monk transaction ${transaction.uuid} for audit. No balance change.",
          );
        } else if (transaction.type == TransactionType.TRIP_EXPENSE_BY_DRIVER) {
          // When a trip expense is reconciled, it means the treasurer accepts this expense
          // and it should be deducted from the driver's advance balance held by the treasurer.
          // Also, the temple fund is reduced as the temple effectively covers this expense.
          final driverId = transaction.recordedByPrimaryId;
          DriverAdvanceAccount? advanceAccount = await _dbHelper
              .getDriverAdvance(driverId, txn: txn);
          if (advanceAccount != null) {
            advanceAccount.balance -= transaction.amount; // Deduct expense
            advanceAccount.lastUpdated = DateTime.now();
            await _dbHelper.insertOrUpdateDriverAdvance(
              advanceAccount,
              txn: txn,
            );
            print(
              "Reconciled TRIP_EXPENSE: Driver $driverId advance reduced by ${transaction.amount}. New balance: ${advanceAccount.balance}",
            );
          } else {
            print(
              "DriverAdvanceAccount not found for driver $driverId during reconciliation.",
            );
            throw Exception('ไม่พบ DriverAdvanceAccount สำหรับคนขับ $driverId');
          }
          // Reduce Temple Fund as well
          await _dbHelper.updateTempleFundBalance(
            _currentTreasurerId!,
            -transaction.amount,
            txn: txn,
          );
        } else if (transaction.type ==
            TransactionType.RETURN_DRIVER_ADVANCE_TO_TREASURER) {
          final driverId =
              transaction.sourceAccountId; // Driver who returned the advance
          if (driverId != null) {
            // Increase Temple Fund
            await _dbHelper.updateTempleFundBalance(
              _currentTreasurerId!,
              transaction.amount,
              txn: txn,
            );
            // Decrease Driver's Advance Account
            DriverAdvanceAccount? advanceAccount = await _dbHelper
                .getDriverAdvance(driverId, txn: txn);
            if (advanceAccount != null) {
              advanceAccount.balance -= transaction.amount;
              advanceAccount.lastUpdated = DateTime.now();
              await _dbHelper.insertOrUpdateDriverAdvance(
                advanceAccount,
                txn: txn,
              );
            } else {
              print(
                "DriverAdvanceAccount not found for driver $driverId when returning advance.",
              );
              throw Exception(
                'ไม่พบ DriverAdvanceAccount สำหรับคนขับ $driverId ขณะคืนเงินสำรอง',
              );
            }
          } else {
            throw Exception(
              'ไม่พบ Driver ID สำหรับการกระทบยอดรายการคืนเงินสำรอง',
            );
          }
        }

        // 2. Update transaction status to reconciled
        await _dbHelper.updateTransactionStatus(
          transaction.uuid,
          TransactionStatus.reconciledByTreasurer,
          txn: txn,
        );
      }); // End transaction

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กระทบยอดรายการสำเร็จ!')));
      _loadPendingTransactions(); // Refresh the list
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('การกระทบยอดล้มเหลว: ${e.toString()}')),
      );
    }
  }

  // _showMonkFundUpdateDialog was removed as per previous discussions.
  // The reconciliation now directly uses the transaction.amount.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('กระทบยอดธุรกรรม')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pendingTransactions.isEmpty
          ? const Center(
              child: Text(
                'ไม่มีรายการที่รอการกระทบยอด',
                style: TextStyle(fontSize: 18),
              ),
            )
          : ListView.builder(
              itemCount: _pendingTransactions.length,
              itemBuilder: (context, index) {
                final transaction = _pendingTransactions[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: ListTile(
                    title: Text(
                      '${transaction.type.name} - ${_currencyFormat.format(transaction.amount)}',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'บันทึกโดย: ${_getUserDisplayName(transaction.recordedByPrimaryId)}',
                        ),
                        if (transaction.sourceAccountId != null &&
                            transaction.sourceAccountId !=
                                transaction.recordedByPrimaryId &&
                            transaction.sourceAccountId !=
                                EXTERNAL_SOURCE_ACCOUNT_ID && // Don't show if it's a generic source
                            transaction.sourceAccountId !=
                                EXPENSE_DESTINATION_ACCOUNT_ID)
                          Text(
                            'จาก: ${_getUserDisplayName(transaction.sourceAccountId)}',
                          ),
                        if (transaction.destinationAccountId != null &&
                            transaction.destinationAccountId !=
                                transaction.recordedByPrimaryId &&
                            transaction.destinationAccountId !=
                                EXPENSE_DESTINATION_ACCOUNT_ID && // Don't show if it's a generic dest
                            transaction.destinationAccountId !=
                                EXTERNAL_SOURCE_ACCOUNT_ID)
                          Text(
                            'ถึง: ${_getUserDisplayName(transaction.destinationAccountId)}',
                          ),
                        if (transaction.expenseCategory != null &&
                            transaction.expenseCategory!.isNotEmpty)
                          Text(
                            'ประเภทค่าใช้จ่าย: ${transaction.expenseCategory}',
                          ),
                        Text('หมายเหตุ: ${transaction.note}'),
                        Text(_dateTimeFormat.format(transaction.timestamp)),
                      ],
                    ),
                    isThreeLine: true, // Adjust based on content
                    trailing: ElevatedButton(
                      onPressed: () => _reconcileTransaction(transaction),
                      child: const Text('กระทบยอด'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
