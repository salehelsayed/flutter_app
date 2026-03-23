import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/push_diagnostics_logger.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart';

enum _PushPermissionState { unknown, granted, denied }

class PushRegistrationCoordinator {
  final Future<bool> Function() requestPermission;
  final Future<RegisterPushTokenResult> Function() registerPushToken;
  final Stream<String> tokenRefreshStream;
  final Duration retryDelay;
  final bool Function() isEnabled;

  StreamSubscription<String>? _tokenRefreshSubscription;
  Timer? _retryTimer;
  Future<void>? _inFlightAttempt;
  _PushPermissionState _permissionState = _PushPermissionState.unknown;
  bool _started = false;
  bool _disposed = false;

  PushRegistrationCoordinator({
    required this.requestPermission,
    required this.registerPushToken,
    required this.tokenRefreshStream,
    this.retryDelay = const Duration(seconds: 15),
    bool Function()? isEnabled,
  }) : isEnabled = isEnabled ?? (() => true);

  Future<void> ensureStarted() async {
    if (_disposed || !isEnabled()) {
      return;
    }

    if (_started) {
      return _inFlightAttempt ?? Future<void>.value();
    }

    _started = true;
    _tokenRefreshSubscription = tokenRefreshStream.listen((_) {
      logPushDiagnostic('token_refresh_event');
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_REGISTER_TOKEN_REFRESH_EVENT',
        details: {},
      );
      unawaited(
        _attemptRegistration(checkPermission: false, trigger: 'token_refresh'),
      );
    });

    await _attemptRegistration(checkPermission: true, trigger: 'startup');
  }

  Future<void> retryNow() async {
    if (_disposed || !isEnabled()) {
      return;
    }

    if (!_started) {
      await ensureStarted();
      return;
    }

    await _attemptRegistration(
      checkPermission: _permissionState != _PushPermissionState.granted,
      trigger: 'resume',
    );
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_tokenRefreshSubscription?.cancel());
    _tokenRefreshSubscription = null;
  }

  Future<void> _attemptRegistration({
    required bool checkPermission,
    required String trigger,
  }) {
    _retryTimer?.cancel();
    _retryTimer = null;

    final inFlightAttempt = _inFlightAttempt;
    if (inFlightAttempt != null) {
      return inFlightAttempt;
    }

    final attempt = _runAttempt(
      checkPermission: checkPermission,
      trigger: trigger,
    );
    _inFlightAttempt = attempt.whenComplete(() {
      _inFlightAttempt = null;
    });
    return _inFlightAttempt!;
  }

  Future<void> _runAttempt({
    required bool checkPermission,
    required String trigger,
  }) async {
    logPushDiagnostic(
      'registration_attempt',
      details: {'trigger': trigger, 'checkPermission': checkPermission},
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_REGISTER_COORDINATOR_ATTEMPT',
      details: {'trigger': trigger},
    );

    try {
      if (checkPermission || _permissionState == _PushPermissionState.unknown) {
        final granted = await requestPermission();
        _permissionState = granted
            ? _PushPermissionState.granted
            : _PushPermissionState.denied;
        if (!granted) {
          logPushDiagnostic('permission_denied', details: {'trigger': trigger});
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED',
            details: {'trigger': trigger},
          );
          return;
        }
      } else if (_permissionState == _PushPermissionState.denied) {
        return;
      }

      final result = await registerPushToken();
      switch (result) {
        case RegisterPushTokenResult.success:
          logPushDiagnostic(
            'registration_success',
            details: {'trigger': trigger},
          );
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_REGISTER_COORDINATOR_SUCCESS',
            details: {'trigger': trigger},
          );
          return;
        case RegisterPushTokenResult.noToken:
        case RegisterPushTokenResult.failed:
          logPushDiagnostic(
            'registration_retry_needed',
            details: {'trigger': trigger, 'result': result.name},
          );
          _scheduleRetry(result: result, trigger: trigger);
          return;
      }
    } catch (e) {
      logPushDiagnostic(
        'registration_exception',
        details: {'trigger': trigger, 'error': e.toString()},
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_REGISTER_COORDINATOR_EXCEPTION',
        details: {'trigger': trigger, 'error': e.toString()},
      );
      _scheduleRetry(trigger: trigger, error: e);
    }
  }

  void _scheduleRetry({
    RegisterPushTokenResult? result,
    required String trigger,
    Object? error,
  }) {
    if (_disposed || !isEnabled()) {
      return;
    }

    logPushDiagnostic(
      'registration_retry_scheduled',
      details: {
        'trigger': trigger,
        'retryDelayMs': retryDelay.inMilliseconds,
        if (result != null) 'result': result.name,
        if (error != null) 'error': error.toString(),
      },
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_REGISTER_COORDINATOR_RETRY_SCHEDULED',
      details: {
        'trigger': trigger,
        'retryDelayMs': retryDelay.inMilliseconds,
        if (result != null) 'result': result.name,
        if (error != null) 'error': error.toString(),
      },
    );

    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay, () {
      if (_disposed) {
        return;
      }
      unawaited(
        _attemptRegistration(
          checkPermission: false,
          trigger: 'scheduled_retry',
        ),
      );
    });
  }
}
