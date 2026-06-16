import 'package:flutter/material.dart';

/// 04-P0 / QW-2: user-visible feedback for a group push that can't be resolved
/// to a live group or a pending invite.
///
/// Without this the tap dead-ends silently (no navigation, no toast). We route
/// the navigator back to the app root so the user lands somewhere coherent, and
/// show a SnackBar — optionally with a Retry that re-runs the tap handler (a
/// single user-driven re-invoke, never an unbounded loop).
///
/// Extracted from the inline main.dart handler because main.dart is not
/// host-importable; this keeps the SnackBar/route-home decision unit-testable.
void showGroupMissingNotificationFeedback({
  required ScaffoldMessengerState? messenger,
  required NavigatorState? navigator,
  required String message,
  String? retryLabel,
  VoidCallback? onRetry,
}) {
  navigator?.popUntil((route) => route.isFirst);

  if (messenger == null) {
    return;
  }

  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: (retryLabel != null && onRetry != null)
            ? SnackBarAction(label: retryLabel, onPressed: onRetry)
            : null,
      ),
    );
}
