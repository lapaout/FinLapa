import 'package:flutter/material.dart';

import '../models/dashboard.dart';
import 'warehouse_linked_info_banner.dart';

class DashboardManageModal extends StatelessWidget {
  final Dashboard dashboard;
  final VoidCallback onArchive;
  final VoidCallback onToggleHidden;
  final VoidCallback onDeleteForever;

  const DashboardManageModal({
    super.key,
    required this.dashboard,
    required this.onArchive,
    required this.onToggleHidden,
    required this.onDeleteForever,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            dashboard.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Управління дашбордом',
            style: TextStyle(color: Colors.black54),
            textAlign: TextAlign.center,
          ),
          if (dashboard.isWarehouseLinked) ...[
            const SizedBox(height: 12),
            const WarehouseLinkedInfoBanner(),
          ],
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              dashboard.isHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: Colors.blueGrey,
            ),
            title: Text(dashboard.isHidden ? 'Показати' : 'Приховати'),
            subtitle: Text(
              dashboard.isHidden
                  ? 'Повернути в основний список'
                  : 'Приховати з основного списку (залишається активним)',
            ),
            onTap: () {
              Navigator.pop(context);
              onToggleHidden();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.archive_outlined, color: Colors.orange),
            title: const Text('В архів'),
            subtitle: const Text('Деактивувати та приховати з усіх списків'),
            onTap: () {
              Navigator.pop(context);
              onArchive();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text('Видалити назавжди'),
            subtitle: const Text('Безповоротно видалить таблицю і всі записи'),
            onTap: () {
              Navigator.pop(context);
              onDeleteForever();
            },
          ),
        ],
      ),
    );
  }
}
