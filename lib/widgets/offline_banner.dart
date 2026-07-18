import 'package:flutter/material.dart';

enum OfflineBannerVariant {
  /// Червоний банер «тільки читання» (дашборди, історія).
  readOnly,

  /// Помаранчевий банер про дані з кешу (аналітика).
  cached,
}

/// Уніфікований офлайн-банер з [Icons.cloud_off].
class OfflineBanner extends StatelessWidget {
  final OfflineBannerVariant variant;
  final String? message;

  /// Компактна смуга на всю ширину (історія, огляд дашборда).
  final bool compact;

  const OfflineBanner({
    super.key,
    this.variant = OfflineBannerVariant.readOnly,
    this.message,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case OfflineBannerVariant.cached:
        return _buildCachedBanner();
      case OfflineBannerVariant.readOnly:
        return compact ? _buildCompactReadOnlyBanner() : _buildCardReadOnlyBanner();
    }
  }

  Widget _buildCachedBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message ?? 'Офлайн: показано збережені дані з кешу',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactReadOnlyBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.redAccent.withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, color: Colors.redAccent, size: 20),
          const SizedBox(width: 8),
          Text(
            message ?? 'Офлайн режим (тільки читання)',
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardReadOnlyBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, color: Colors.redAccent),
          const SizedBox(width: 10),
          Text(
            message ?? 'Офлайн режим (тільки читання)',
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
