import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/diagnostics/app_diagnostics.dart';
import '../../core/diagnostics/app_diagnostic_error_handlers.dart';

/// Keeps the entrypoint thin while observing the production startup boundary.
Future<void> runWithProductionAppDiagnostics(
  Future<void> Function() launch,
) async {
  installAppDiagnosticErrorHandlers();
  final diagnostics = AppDiagnostics.instance;
  // Metadata, disk and native diagnostic sinks do not own app readiness.
  // Retain the observed result until initialization finishes so a frame or
  // bootstrap failure arriving first is still recorded exactly once.
  final observationReady = initializeProductionAppDiagnostics().then(
    (_) => diagnostics.startAttempt(
      feature: 'startup',
      traceId: diagnostics.supportCode,
    ),
  );
  try {
    await launch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        observationReady.then((trace) {
          diagnostics.record(
            feature: 'startup',
            stage: 'present',
            outcome: 'ok',
            traceId: trace,
            values: {'firstFrame': true},
          );
          diagnostics.finishAttempt(
            feature: 'startup',
            traceId: trace,
            outcome: 'success',
          );
        }),
      );
    });
  } catch (error, stack) {
    unawaited(
      observationReady.then((trace) {
        diagnostics.captureError(error, stack);
        diagnostics.finishAttempt(
          feature: 'startup',
          traceId: trace,
          outcome: 'failed',
          reason: 'bootstrap',
        );
      }),
    );
    rethrow;
  }
}

/// Establish local persistence alongside database/native-node initialization.
/// Reporting remains independent of whether the account can use the network.
Future<void> initializeProductionAppDiagnostics() async {
  try {
    final directory = await getApplicationSupportDirectory().timeout(
      const Duration(seconds: 1),
    );
    var build = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform().timeout(
        const Duration(milliseconds: 300),
      );
      build = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Metadata availability does not decide application readiness.
    }
    await AppDiagnostics.instance
        .initialize(
          directory: Directory('${directory.path}/app_diagnostics'),
          build: build,
        )
        .timeout(const Duration(seconds: 2));
  } catch (_) {
    // Native OS diagnostics may still arrive later; never block startup.
  }
}
