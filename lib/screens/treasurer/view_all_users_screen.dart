// lib/screens/treasurer/view_all_users_screen.dart
import 'package:flutter/material.dart';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/services/database_helper.dart';

class ViewAllUsersScreen extends StatefulWidget {
  const ViewAllUsersScreen({super.key});

  @override
  State<ViewAllUsersScreen> createState() => _ViewAllUsersScreenState();
}

class _ViewAllUsersScreenState extends State<ViewAllUsersScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<User> _allUsers = [];
  bool _isLoading = true;
  UserRole? _selectedRoleFilter; // For filtering by role

  @override
  void initState() {
    super.initState();
    _loadAllUsers();
  }

  Future<void> _loadAllUsers() async {
    setState(() => _isLoading = true);
    try {
      final users = await _dbHelper.getAllUsers();
      if (mounted) {
        setState(() {
          _allUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถโหลดข้อมูลผู้ใช้ได้: $e')),
        );
      }
    }
  }

  List<User> get _filteredUsers {
    if (_selectedRoleFilter == null) {
      return _allUsers;
    }
    return _allUsers.where((user) => user.role == _selectedRoleFilter).toList();
  }

  String _getRoleDisplayName(UserRole role) {
    switch (role) {
      case UserRole.treasurer:
        return 'ไวยาวัจกรณ์';
      case UserRole.driver:
        return 'คนขับรถ';
      case UserRole.monk:
        return 'พระ';
      default:
        return role.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ข้อมูลผู้ใช้ทั้งหมดในระบบ'),
        // Optional: Add a filter button here if needed
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredUsers.isEmpty
          ? const Center(
              child: Text(
                'ยังไม่มีข้อมูลผู้ใช้ในระบบ',
                style: TextStyle(fontSize: 18),
              ),
            )
          : ListView.builder(
              itemCount: _filteredUsers.length,
              itemBuilder: (context, index) {
                final user = _filteredUsers[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: ListTile(
                    title: Text(
                      '${user.displayName} (${_getRoleDisplayName(user.role)})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Primary ID: ${user.primaryId}\nSecondary ID: ${user.secondaryId}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }
}
