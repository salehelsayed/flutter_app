import 'package:flutter/services.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Platform invoker seam so tests can fake the method channel.
typedef MigrationKeepAliveInvoker =
    Future<void> Function(String method, Map<String, Object?> arguments);

/// Keeps the app alive while a Move Account transfer is in flight, so
/// backgrounding the app does not suspend the sender's segment POST loop or
/// the receiver's local HTTP server (audit gap G7, background half).
///
/// Platform behavior behind `mknoon/migration_keepalive`:
/// - Android: starts a `dataSync` foreground service with an ongoing
///   "Moving account" notification, keeping the process alive while
///   backgrounded for the whole transfer.
/// - iOS: holds a `beginBackgroundTask` assertion, which grants roughly 30
///   seconds of continued execution after backgrounding — enough to survive
///   brief app switches, not indefinite background transfer.
///
/// Hold-counted: overlapping holders (e.g. an abandoned transfer run plus its
/// retry) share one platform keep-alive; the last release stops it. If the
/// platform side is missing (tests, unsupported platforms), the first call
/// marks the service unavailable and everything degrades to a silent no-op.
class MigrationTransferKeepAlive {
  static const String channelName = 'mknoon/migration_keepalive';
  static const MethodChannel _channel = MethodChannel(channelName);

  final MigrationKeepAliveInvoker _invoke;
  int _holds = 0;
  bool _platformStarted = false;
  bool _unavailable = false;

  MigrationTransferKeepAlive({MigrationKeepAliveInvoker? invoker})
    : _invoke = invoker ?? _channelInvoke;

  static Future<void> _channelInvoke(
    String method,
    Map<String, Object?> arguments,
  ) {
    return _channel.invokeMethod<void>(method, arguments);
  }

  /// Number of active holds. Exposed for tests and diagnostics.
  int get activeHolds => _holds;

  Future<void> acquire({required String reason}) async {
    _holds++;
    if (_holds > 1 || _unavailable) {
      return;
    }
    try {
      await _invoke('start', {'reason': reason});
      _platformStarted = true;
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_KEEPALIVE_STARTED',
        details: {'reason': reason},
      );
    } on MissingPluginException {
      _unavailable = true;
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_KEEPALIVE_UNAVAILABLE',
        details: {'reason': reason},
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_KEEPALIVE_START_FAILED',
        details: {'reason': reason, 'errorType': error.runtimeType.toString()},
      );
    }
  }

  Future<void> release({required String reason}) async {
    if (_holds == 0) {
      return;
    }
    _holds--;
    if (_holds > 0 || !_platformStarted) {
      return;
    }
    _platformStarted = false;
    try {
      await _invoke('stop', {'reason': reason});
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_KEEPALIVE_STOPPED',
        details: {'reason': reason},
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_KEEPALIVE_STOP_FAILED',
        details: {'reason': reason, 'errorType': error.runtimeType.toString()},
      );
    }
  }
}
