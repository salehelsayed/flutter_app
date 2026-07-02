import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 172 (INV-2): the "couldn't display N messages" affordance.
///
/// Surfaces kept-but-undisplayed staged inbox entries (quarantined decrypt
/// failures, attempt-cap-exhausted recoverables, and historical
/// recoverable-class rejections) whose relay copies were already ACK-deleted —
/// without this banner those entries are silent, permanent-looking loss.
/// Renders nothing when [count] <= 0. The retry action re-drives the staged
/// drain so a since-healed cause (contact materialized, key arrived, original
/// edit target landed) gets its message displayed.
class UndeliveredMessagesBanner extends StatelessWidget {
  static const bannerKey = ValueKey('undelivered-messages-banner');
  static const retryKey = ValueKey('undelivered-messages-retry');

  final int count;
  final VoidCallback? onRetry;

  const UndeliveredMessagesBanner({super.key, required this.count, this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;

    return Container(
      key: bannerKey,
      decoration: const BoxDecoration(
        color: Color.fromRGBO(255, 255, 255, 0.04),
        border: Border(
          bottom: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.08)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline,
              size: 16,
              color: Color.fromRGBO(255, 255, 255, 0.35),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.conversation_undelivered_banner(count),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Color.fromRGBO(255, 255, 255, 0.5),
                ),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                key: retryKey,
                onTap: onRetry,
                child: Text(
                  l10n.conversation_undelivered_retry,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
