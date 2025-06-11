// lib/screens/treasurer/monk_transaction_type_selection_dialog.dart
import 'package:flutter/material.dart';

enum MonkTransactionMode { single, batch }

class MonkTransactionTypeSelectionDialog extends StatelessWidget {
  const MonkTransactionTypeSelectionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เลือกวิธีการบันทึกรายการพระ'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('บันทึกรายบุคคล'),
            onTap: () {
              Navigator.pop(context, MonkTransactionMode.single);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('บันทึกแบบกลุ่ม'),
            onTap: () {
              Navigator.pop(context, MonkTransactionMode.batch);
            },
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('ยกเลิก'),
          onPressed: () {
            Navigator.pop(context, null); // No selection
          },
        ),
      ],
    );
  }
}
