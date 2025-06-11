// lib/screens/treasurer/manage_monks_screen.dart
import 'package:flutter/material.dart';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/services/database_helper.dart';
// Import a screen for adding/editing a monk (to be created)
import 'package:moneywat/screens/treasurer/add_edit_monk_screen.dart';
import 'package:moneywat/screens/treasurer/record_monk_fund_at_treasurer_transaction_screen.dart';
import 'package:moneywat/models/account_balance_models.dart';
import 'package:moneywat/screens/treasurer/monk_financial_history_screen.dart'; // Import history screen
import 'package:moneywat/screens/treasurer/batch_monk_fund_transaction_screen.dart'; // Import batch screen
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

// Helper class to hold monk and their last activity timestamp
class MonkWithDetails {
  final User monk;
  final MonkFundAtTreasurer? fund;
  final DateTime? lastActivityTimestamp;

  MonkWithDetails({required this.monk, this.fund, this.lastActivityTimestamp});
}

class ManageMonksScreen extends StatefulWidget {
  const ManageMonksScreen({super.key});

  @override
  State<ManageMonksScreen> createState() => _ManageMonksScreenState();
}

class _ManageMonksScreenState extends State<ManageMonksScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'th_TH',
    symbol: '฿',
  );
  List<MonkWithDetails> _monksWithDetails = [];
  bool _isLoading = true;
  String? _currentTreasurerId;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
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
      // Fetch monks with their last activity timestamp
      final List<Map<String, dynamic>> monkMaps = await _dbHelper
          .getUsersByRoleWithLastActivity(UserRole.monk);

      List<MonkWithDetails> tempMonksWithDetails = [];
      for (var monkMap in monkMaps) {
        final monkUser = User.fromMap(monkMap);
        final fund = await _dbHelper.getMonkFundAtTreasurer(
          monkUser.primaryId,
          _currentTreasurerId!,
        );
        final lastActivityString =
            monkMap['last_activity_timestamp'] as String?;
        final lastActivity = lastActivityString != null
            ? DateTime.tryParse(lastActivityString)
            : null;
        tempMonksWithDetails.add(
          MonkWithDetails(
            monk: monkUser,
            fund: fund,
            lastActivityTimestamp: lastActivity,
          ),
        );
      }

      // Sort monks: most recent activity first, then by display name for those with no activity or same activity time
      tempMonksWithDetails.sort((a, b) {
        if (a.lastActivityTimestamp == null && b.lastActivityTimestamp == null)
          return a.monk.displayName.compareTo(b.monk.displayName);
        if (a.lastActivityTimestamp == null) return 1; // nulls go to bottom
        if (b.lastActivityTimestamp == null) return -1;
        int dateComparison = b.lastActivityTimestamp!.compareTo(
          a.lastActivityTimestamp!,
        );
        return dateComparison == 0
            ? a.monk.displayName.compareTo(b.monk.displayName)
            : dateComparison;
      });

      if (mounted) {
        setState(() {
          _monksWithDetails = tempMonksWithDetails;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถโหลดข้อมูลพระได้: $e')),
        );
      }
    }
  }

  void _navigateToAddMonkScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddEditMonkScreen()),
    );
    if (result == true && mounted) {
      _loadInitialData(); // Reload monks list and funds
    }
  }

  void _navigateToEditMonkScreen(User monk) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddEditMonkScreen(monk: monk)),
    );
    if (result == true && mounted) {
      _loadInitialData();
    }
  }

  void _navigateToRecordTransaction(User monk, bool isDeposit) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecordMonkFundAtTreasurerTransactionScreen(
          monk: monk,
          isDeposit: isDeposit,
        ),
      ),
    );
    if (result == true && mounted) {
      _loadInitialData(); // Reload data to reflect new balance
    }
  }

  void _navigateToBatchTransactionScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BatchMonkFundTransactionScreen(),
      ),
    );
    if (result == true && mounted) {
      _loadInitialData(); // Reload data to reflect new balances
    }
  }

  void _navigateToMonkHistory(User monk, MonkFundAtTreasurer? fund) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MonkFinancialHistoryScreen(monk: monk, monkFundAtTreasurer: fund),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการบัญชีพระ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: _navigateToAddMonkScreen,
            tooltip: 'เพิ่มพระใหม่',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _monksWithDetails.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'ยังไม่มีข้อมูลพระ',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มพระใหม่'),
                    onPressed: _navigateToAddMonkScreen,
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _monksWithDetails.length,
              itemBuilder: (context, index) {
                final monkDetail = _monksWithDetails[index];
                final monk = monkDetail.monk;
                final fund = monkDetail.fund;
                final balanceText = fund != null
                    ? _currencyFormat.format(fund.balance)
                    : 'N/A';
                final Color balanceColor = (fund?.balance ?? 0) < 0
                    ? Colors.red
                    : Colors.black54;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColorLight,
                    child: Text(
                      monk.displayName.isNotEmpty
                          ? monk.displayName[0].toUpperCase()
                          : 'M',
                      style: TextStyle(
                        color: Theme.of(context).primaryColorDark,
                      ),
                    ),
                  ),
                  title: Text(
                    monk.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'ID: ${monk.primaryId}\nยอดฝากกับคุณ: $balanceText',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  isThreeLine: true,
                  onTap: () => _navigateToMonkHistory(monk, fund),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _navigateToEditMonkScreen(monkDetail.monk);
                      } else if (value == 'deposit') {
                        _navigateToRecordTransaction(monkDetail.monk, true);
                      } else if (value == 'withdraw') {
                        _navigateToRecordTransaction(monkDetail.monk, false);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'edit',
                            child: ListTile(
                              leading: Icon(Icons.edit),
                              title: Text('แก้ไขข้อมูลพระ'),
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'deposit',
                            child: ListTile(
                              leading: Icon(Icons.input),
                              title: Text('บันทึกเงินฝาก'),
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'withdraw',
                            child: ListTile(
                              leading: Icon(Icons.output),
                              title: Text('บันทึกเงินถอน'),
                            ),
                          ),
                        ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToBatchTransactionScreen,
        tooltip: 'บันทึกฝาก/ถอน (กลุ่ม)',
        child: const Icon(Icons.group_add_outlined),
      ),
    );
  }
}
