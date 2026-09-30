import 'package:flutter/material.dart';

/// Shows a bounded media notice above the message composer controls.
void showVideoProcessingNotice(
  BuildContext context, {
  required String message,
  String? retryLabel,
  VoidCallback? onRetry,
}) {
  assert((retryLabel == null) == (onRetry == null));
  final colors = Theme.of(context).colorScheme;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message, style: TextStyle(color: colors.onInverseSurface)),
      backgroundColor: colors.inverseSurface,
      action: onRetry == null
          ? null
          : SnackBarAction(
              label: retryLabel!,
              textColor: colors.inversePrimary,
              onPressed: onRetry,
            ),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 96),
      duration: const Duration(seconds: 8),
      persist: false,
      showCloseIcon: true,
      closeIconColor: colors.onInverseSurface,
    ),
  );
}
