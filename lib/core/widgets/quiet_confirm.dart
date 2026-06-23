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
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const ValueKey('quiet-confirm'),
        content: Text(
          message,
          style: TextStyle(color: scheme.onSecondaryContainer),
        ),
        backgroundColor: scheme.secondaryContainer,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
}
