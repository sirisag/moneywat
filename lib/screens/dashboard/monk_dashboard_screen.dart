// lib/screens/dashboard/monk_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moneywat/screens/auth/universal_login_setup_screen.dart'; // For logout

class MonkDashboardScreen extends StatelessWidget {
  const MonkDashboardScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clears all data, effectively logging out
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const UniversalLoginSetupScreen(),
      ),
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('หน้าหลักพระ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
            tooltip: 'ออกจากระบบ',
          ),
        ],
      ),
      body: const Center(
        child: Text(
          'ยินดีต้อนรับสู่หน้าหลักของพระ!',
          style: TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}
