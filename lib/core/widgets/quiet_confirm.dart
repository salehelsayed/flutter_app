import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a quiet, success-styled confirmation for an action whose result is
/// otherwise invisible — e.g. copy-to-clipboard, where the long-press overlay
/// is already popped before the copy completes, leaving no persistent control.
///
/// It fires a tactile [HapticFeedback.selectionClick] and a short, visually
/// distinct, auto-dismissing cue keyed `quiet-confirm`. This is deliberately
/// NOT the standard (error-style) [SnackBar], so the snackbar channel stays
/// reserved for real errors — a quiet success no longer trains the user to
/// ignore the channel.
///
/// Lifecycle: callers usually invoke this after an `await`. Guard the context
/// BEFORE the messenger lookup, because [ScaffoldMessenger.maybeOf] *throws* (a
/// debug assert on a deactivated element) — it does NOT return null. A null
/// result means only "active element with no ScaffoldMessenger ancestor".
void showQuietConfirm(BuildContext context, String message) {
  if (!context.mounted) return;
  HapticFeedback.selectionClick();
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final scheme = Theme.of(context).colorScheme;
  final availableWidth = MediaQuery.sizeOf(context).width - 32;
  final pillWidth = availableWidth.clamp(180.0, 320.0).toDouble();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const ValueKey('quiet-confirm'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurface),
              ),
            ),
          ],
        ),
        backgroundColor: scheme.surfaceContainerHighest,
        behavior: SnackBarBehavior.floating,
        width: pillWidth,
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        duration: const Duration(milliseconds: 1200),
      ),
    );
}
