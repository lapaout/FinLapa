import 'package:flutter/material.dart';

/// Інформаційний рядок для складського дашборда доходу.
class WarehouseLinkedInfoBanner extends StatelessWidget {
  const WarehouseLinkedInfoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, color: Colors.teal.shade700, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Підключено до складу',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.teal.shade800,
                  ),
                ),
                Text(
                  'Тип дашборду не можна змінити після створення',
                  style: TextStyle(fontSize: 12, color: Colors.teal.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
