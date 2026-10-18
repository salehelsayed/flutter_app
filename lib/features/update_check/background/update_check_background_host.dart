import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';

import '../application/update_check_service.dart';
import '../application/update_check_switch.dart';
import '../domain/update_check_models.dart';
import '../infrastructure/update_check_state_store.dart';
import '../presentation/update_store_launcher.dart';
import 'update_check_background_runner.dart';
import 'update_check_notifier.dart';

/// Main-engine side of the T4a background check.
///
/// [install] runs at the top of `main()`, before the app bootstrap, so it
/// needs no first frame, Go bridge or SQLCipher. It answers native code on
/// [updateCheckBackgroundChannelName]:
/// - `run` (iOS BG task; Android worker handoff while the main engine holds
///   the lease): one [UpdateCheckBackgroundRunner] run.
/// - `openStore` (iOS notification tap): opens the built-in store page with
///   the T2 launcher. Call arguments are ignored: never a URL from a payload.
///
/// It also sends `configure` once: `enabled` false (E2E, SIMS, the debug
/// default or MKNOON_UPDATE_CHECK=off) makes native code cancel any schedule;
/// true schedules it.
class UpdateCheckBackgroundHost {
  UpdateCheckBackgroundHost({
    MethodChannel channel = const MethodChannel(
      updateCheckBackgroundChannelName,
    ),
    UpdateCheckSwitch? updateSwitch,
    UpdateCheckBackgroundRunner Function(bool inCall)? runnerFactory,
    UpdateStoreLauncher launcher = launchUpdateStore,
    UpdatePlatform? platform,
  }) : _channel = channel,
       _switch = updateSwitch ?? UpdateCheckSwitch.fromEnvironment(),
       _runnerFactory = runnerFactory ?? _productionRunner,
       _launcher = launcher,
       _platform = platform;

  /// The run's budget when native code gives none. Native code stops waiting
  /// a little later (iOS 25 s, Android 20 s).
  static const Duration defaultBudget = Duration(seconds: 18);

  final MethodChannel _channel;
  final UpdateCheckSwitch _switch;
  final UpdateCheckBackgroundRunner Function(bool inCall) _runnerFactory;
  final UpdateStoreLauncher _launcher;
  final UpdatePlatform? _platform;

  Future<Map<String, Object?>>? _inFlight;

  void install() {
    _channel.setMethodCallHandler(_handle);
    unawaited(configure());
  }

  /// Schedules ordinary enabled builds. The opted-in fixture cancels automatic
  /// OS work and explicitly drives the production runner and native poster.
  Future<void> configure() async {
    try {
      await _channel.invokeMethod<void>('configure', {
        // The opted-in fixture drives the real runner explicitly. A periodic
        // worker on the real clock would race its controlled elapsed time.
        'enabled': _switch.enabled && !_switch.testProfileEnabled,
      });
    } on PlatformException {
      // No native side (tests, desktop): nothing to schedule.
    } on MissingPluginException {
      // Same.
    }
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'run':
        final args = call.arguments is Map
            ? call.arguments as Map
            : const <Object?, Object?>{};
        final reason = args['reason'] is String
            ? args['reason'] as String
            : 'unknown';
        final budgetMs = args['budgetMs'];
        final budget = budgetMs is int && budgetMs > 0
            ? Duration(milliseconds: budgetMs)
            : defaultBudget;
        final inCall = args['inCall'] == true;
        // A second trigger while one runs shares it.
        return _inFlight ??= _runnerFactory(inCall)
            .run(reason: reason, budget: budget)
            .then((result) => result.toWire())
            .whenComplete(() => _inFlight = null);
      case 'openStore':
        return _launcher(
          updateStoreUrlForPlatform(_platform ?? _hostPlatform()),
        );
      default:
        throw MissingPluginException(call.method);
    }
  }

  static UpdatePlatform _hostPlatform() =>
      Platform.isIOS ? UpdatePlatform.ios : UpdatePlatform.android;

  static UpdateCheckBackgroundRunner _productionRunner(bool inCall) {
    final store = UpdateCheckStateStore();
    final visibility = AppVisibilityAuthority(
      platformBridge: MethodChannelAppVisibilityPlatformBridge(),
    );
    return UpdateCheckBackgroundRunner(
      service: UpdateCheckService(store: store),
      store: store,
      poster: const MethodChannelUpdateNotificationPoster(),
      isForeground: visibility.isForegroundActive,
      isInCall: () async => inCall,
    );
  }
}
