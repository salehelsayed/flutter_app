import 'package:flutter/foundation.dart';

import 'app_diagnostics.dart';

/// Installs observation alongside the existing framework/engine error policy.
/// Returning false to the engine preserves its normal uncaught-error handling.
void installAppDiagnosticErrorHandlers() {
  final previousFlutter = FlutterError.onError;
  final previousPlatform = PlatformDispatcher.instance.onError;
  FlutterError.onError = (details) {
    AppDiagnostics.instance.captureError(
      details.exception,
      details.stack,
      reason: 'flutter_error',
    );
    // The framework's debug overflow paint can be visible on screen without
    // an error line in Android logcat. Emit only a fixed marker; exception text
    // may contain message content or local paths.
    if (kDebugMode &&
        details.exceptionAsString().contains('A RenderFlex overflowed by')) {
      debugPrint('RenderFlex overflowed (Mknoon layout)');
    }
    if (previousFlutter != null) {
      previousFlutter(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppDiagnostics.instance.captureError(error, stack);
    return previousPlatform?.call(error, stack) ?? false;
  };
}
