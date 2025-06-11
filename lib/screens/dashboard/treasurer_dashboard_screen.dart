// lib/screens/dashboard/treasurer_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moneywat/screens/auth/universal_login_setup_screen.dart'; // For logout
// Import new screens for managing users
import 'package:moneywat/screens/treasurer/manage_drivers_screen.dart';
import 'package:moneywat/screens/treasurer/manage_monks_screen.dart';
// import 'package:money/screens/treasurer/view_all_users_screen.dart'; // Already imported if used, ensure it is.
import 'package:moneywat/screens/treasurer/reconcile_transactions_screen.dart'; // Import reconcile screen
// For file operations (not directly used in this dashboard but good to keep if other parts use it)
// import 'package:file_picker/file_picker.dart';
import 'package:moneywat/models/account_balance_models.dart'; // For TempleFundAccount
import 'package:moneywat/services/database_helper.dart'; // For DatabaseHelper
import 'package:intl/intl.dart'; // For NumberFormat
// Import record income/expense screens (though now replaced by dialog)
// import 'package:money/screens/treasurer/record_temple_income_screen.dart';
// import 'package:money/screens/treasurer/record_temple_expense_screen.dart';
// import 'package:money/screens/treasurer/view_all_users_screen.dart'; // Ensure this is imported if used elsewhere
// import 'package:money/services/file_export_service.dart'; // For import functionality (if used directly here)
import 'package:moneywat/screens/treasurer/temple_fund_history_screen.dart'; // Import history screen
// Import the new dialog
import 'package:moneywat/screens/treasurer/record_temple_transaction_dialog.dart';
// Import the AllMonksFinancialHistoryScreen (even if placeholder for now)
import 'package:moneywat/screens/treasurer/all_monks_financial_history_screen.dart';
// Import the new dialog for monk transactions with treasurer
import 'package:moneywat/screens/treasurer/record_monk_fund_at_treasurer_dialog.dart';
// Import the new selection dialog for monk transaction type
import 'package:moneywat/screens/treasurer/monk_transaction_type_selection_dialog.dart';
// Import batch transaction screen
import 'package:moneywat/screens/treasurer/batch_monk_fund_transaction_screen.dart';

class TreasurerDashboardScreen extends StatefulWidget {
  const TreasurerDashboardScreen({super.key});

  @override
  State<TreasurerDashboardScreen> createState() =>
      _TreasurerDashboardScreenState();
}

class _TreasurerDashboardScreenState extends State<TreasurerDashboardScreen> {
  // final FileExportService _fileExportService = FileExportService(); // Not used directly here
  final DatabaseHelper _dbHelper = DatabaseHelper();
  // final NumberFormat _currencyFormat =
  //     NumberFormat.currency(locale: 'th_TH', symbol: '฿'); // Not used directly here for main balance
  final NumberFormat _integerDisplayFormat = NumberFormat.decimalPattern(
    'th_TH',
  ); // For temple fund display

  TempleFundAccount? _templeFundAccount;
  // bool _isLoading = false; // Not used directly here
  bool _isLoadingBalance = true;
  String? _currentTreasurerId;

  @override
  void initState() {
    super.initState();
    _loadTempleFundBalance();
  }

  Future<void> _loadTempleFundBalance() async {
    if (!mounted) return;
    setState(() => _isLoadingBalance = true);
    final prefs = await SharedPreferences.getInstance();
    _currentTreasurerId = prefs.getString('user_primary_id');
    if (_currentTreasurerId != null) {
      try {
        _templeFundAccount = await _dbHelper.getTempleFund(
          _currentTreasurerId!,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ไม่สามารถโหลดยอดเงินกองกลางได้: $e')),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบ ID ไวยาวัจกรณ์ปัจจุบัน')),
        );
      }
    }
    if (mounted) setState(() => _isLoadingBalance = false);
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clears all data, effectively logging out
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const UniversalLoginSetupScreen(),
        ),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('หน้าหลักไวยาวัจกรณ์'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
            tooltip: 'ออกจากระบบ',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          // 1. ยอดเงินกองกลางคงเหลือ
          Card(
            elevation: 4,
            margin: const EdgeInsets.only(bottom: 20),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    'ยอดเงินกองกลางวัดคงเหลือ',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  _isLoadingBalance
                      ? const CircularProgressIndicator()
                      : Text(
                          '${_integerDisplayFormat.format(_templeFundAccount?.balance ?? 0)} บาท', // Added " บาท"
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: (_templeFundAccount?.balance ?? 0) < 0
                                    ? Colors.red
                                    : Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                ],
              ),
            ),
          ),

          // 2. ประวัติเงินกองกลางวัด
          ListTile(
            leading: const Icon(Icons.history_edu_outlined),
            title: const Text('ประวัติเงินกองกลางวัด'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TempleFundHistoryScreen(),
                ),
              );
            },
          ),
          const Divider(),

          // 3. ประวัติการเงินของพระทั้งหมด
          ListTile(
            leading: const Icon(Icons.summarize_outlined),
            title: const Text('ประวัติการเงินของพระทั้งหมด'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AllMonksFinancialHistoryScreen(),
                ),
              );
            },
          ),
          const Divider(),

          // 4. บันทึกรายรับรายจ่ายของวัด
          ListTile(
            leading: const Icon(Icons.edit_document),
            title: const Text('บันทึกรายรับ/จ่ายของวัด'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () async {
              final result = await showDialog<bool>(
                context: context,
                builder: (context) => const RecordTempleTransactionDialog(),
              );
              if (result == true && mounted) _loadTempleFundBalance();
            },
          ),
          const Divider(),

          // 5. บันทึกรายรับรายจ่ายของพระ
          ListTile(
            leading: const Icon(
              Icons.person_pin_circle_outlined,
            ), // ไอคอนสำหรับรายการของพระ
            title: const Text('บันทึกรายรับ/จ่ายของพระ'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () async {
              final MonkTransactionMode? mode =
                  await showDialog<MonkTransactionMode>(
                    context: context,
                    builder: (context) =>
                        const MonkTransactionTypeSelectionDialog(),
                  );

              if (mode != null && mounted) {
                bool? transactionMade = false;
                if (mode == MonkTransactionMode.single) {
                  transactionMade = await showDialog<bool>(
                    context: context,
                    builder: (context) =>
                        const RecordMonkFundAtTreasurerDialog(),
                  );
                } else if (mode == MonkTransactionMode.batch) {
                  transactionMade = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const BatchMonkFundTransactionScreen(),
                    ),
                  );
                }
                // Reload balance for both temple and potentially monk funds (though monk funds not directly shown here)
                if (transactionMade == true && mounted) {
                  _loadTempleFundBalance();
                }
              }
            },
          ),
          const Divider(),

          // 6. จัดการบัญชีพระ
          ListTile(
            leading: const Icon(Icons.person_search_outlined),
            title: const Text('จัดการบัญชีพระ'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ManageMonksScreen(),
                ),
              );
            },
          ),
          const Divider(),

          // 7. จัดการบัญชีคนขับรถ
          ListTile(
            leading: const Icon(Icons.directions_car),
            title: const Text('จัดการบัญชีคนขับรถ'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ManageDriversScreen(),
                ),
              );
            },
          ),
          const Divider(),

          // 8. กระทบยอดธุรกรรม
          ListTile(
            leading: const Icon(Icons.playlist_add_check_circle_outlined),
            title: const Text('กระทบยอดธุรกรรม'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ReconcileTransactionsScreen(),
                ),
              );
            },
          ),
          const Divider(),
        ],
      ),
    );
  }
}
