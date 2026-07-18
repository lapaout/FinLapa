import 'package:flutter/material.dart';

import 'package:finlapa/core/money_formatter.dart';

/// Один показник складу (залишок / витрачено / зароблено).
class WarehouseStatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const WarehouseStatItem({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Вертикальний розділювач між показниками складу.
class WarehouseStatDivider extends StatelessWidget {
  const WarehouseStatDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.grey.withValues(alpha: 0.2),
    );
  }
}

/// Смуга «Прибуток» для складської статистики.
class WarehouseProfitBar extends StatelessWidget {
  final num profit;

  const WarehouseProfitBar({
    super.key,
    required this.profit,
  });

  @override
  Widget build(BuildContext context) {
    final Color profitColor;
    final IconData profitIcon;
    if (profit > 0) {
      profitColor = Colors.green.shade600;
      profitIcon = Icons.arrow_upward_rounded;
    } else if (profit < 0) {
      profitColor = Colors.redAccent;
      profitIcon = Icons.arrow_downward_rounded;
    } else {
      profitColor = Colors.grey.shade600;
      profitIcon = Icons.remove_rounded;
    }

    final sign = profit > 0 ? '+' : '';

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: profitColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: profitColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(profitIcon, color: profitColor, size: 20),
          const SizedBox(width: 8),
          Text(
            'Прибуток',
            style: TextStyle(
              color: profitColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '$sign${MoneyFormatter.formatNumber(profit)} ₴',
                maxLines: 1,
                style: TextStyle(
                  color: profitColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
