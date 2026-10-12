import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../application/update_check_service.dart';
import '../infrastructure/update_check_state_store.dart';
import 'update_check_background_runner.dart';
import 'update_check_notifier.dart';

/// Android minimal engine for the T4a background check (`main.dart` exposes
/// it as `androidUpdateCheckMinimalMain`).
///
/// The WorkManager worker starts this engine only when the canonical runtime
/// lease is free and no main engine is registered, so the app cannot be in
/// the foreground. The engine never takes the lease. Its import graph is
/// limited to update_check, path_provider, pinenacl, the notification helper
/// and the l10n lookup: no Go bridge, SQLCipher, bootstrap or Firebase
/// (test/features/update_check/background/update_check_import_graph_test.dart).
///
/// Arguments: [reason, budgetMs, installedBuildNumber, inCall].
Future<void> runUpdateCheckMinimalEngine(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  const channel = MethodChannel(updateCheckBackgroundChannelName);
  UpdateCheckBackgroundResult result;
  try {
    final reason = arguments.isNotEmpty ? arguments[0] : 'unknown';
    final budgetMs = arguments.length > 1 ? int.tryParse(arguments[1]) : null;
    final installedBuild = arguments.length > 2 ? arguments[2] : '';
    final inCall = arguments.length > 3 && arguments[3] == 'true';
    final store = UpdateCheckStateStore();
    final runner = UpdateCheckBackgroundRunner(
      service: UpdateCheckService(
        store: store,
        installedBuildNumber: () async => installedBuild,
      ),
      store: store,
      poster: const MethodChannelUpdateNotificationPoster(channel: channel),
      isForeground: () async => false,
      isInCall: () async => inCall,
    );
    result = await runner.run(
      reason: reason,
      budget: Duration(milliseconds: budgetMs ?? 18000),
    );
  } catch (_) {
    result = const UpdateCheckBackgroundResult(
      UpdateCheckBackgroundOutcome.failed,
    );
  }
  try {
    await channel.invokeMethod<void>('complete', result.toWire());
  } on PlatformException {
    // The worker timed out and already tore the engine down.
  } on MissingPluginException {
    // Same.
  }
}
