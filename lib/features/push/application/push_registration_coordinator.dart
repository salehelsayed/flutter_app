import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/push_diagnostics_logger.dart';
import 'package:flutter_app/features/push/application/push_registration_health_notifier.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart';
import 'package:flutter_app/features/push/domain/push_registration_health.dart';
import 'package:flutter_app/features/push/infrastructure/push_registration_health_store.dart';

enum _PushPermissionState { unknown, granted, denied }

typedef _PushRegistrationHealthAuthority = ({
  int epoch,
  PushRegistrationHealthBinding? binding,
});

class PushRegistrationCoordinator {
  final Future<bool> Function() requestPermission;
  final Future<RegisterPushTokenResult> Function() registerPushToken;
  final Stream<String> tokenRefreshStream;
  final Duration retryDelay;
  final bool Function() isEnabled;
  final Map<String, dynamic> Function()? registrationSuccessDetails;
  final PushRegistrationHealthStorage? healthStore;
  final PushRegistrationHealthNotifier? healthNotifier;
  final DateTime Function() now;

  StreamSubscription<String>? _tokenRefreshSubscription;
  Timer? _retryTimer;
  Future<void>? _inFlightAttempt;
  _PushRegistrationHealthAuthority? _inFlightAuthority;
  Future<void> _healthOperationTail = Future<void>.value();
  _PushPermissionState _permissionState = _PushPermissionState.unknown;
  PushRegistrationHealthBinding? _healthBinding;
  int _healthAuthorityEpoch = 0;
  PushRegistrationHealthRecord? _healthRecord;
  bool _healthLoaded = false;
  bool _started = false;
  bool _disposed = false;

  PushRegistrationCoordinator({
    required this.requestPermission,
    required this.registerPushToken,
    required this.tokenRefreshStream,
    this.retryDelay = const Duration(seconds: 15),
    bool Function()? isEnabled,
    this.registrationSuccessDetails,
    this.healthStore,
    this.healthNotifier,
    DateTime Function()? now,
  }) : isEnabled = isEnabled ?? (() => true),
       now = now ?? DateTime.now;

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

  /// Synchronously fences all registration-health work owned by the account
  /// being replaced.
  ///
  /// Call this before an in-process account import/cutover starts mutating the
  /// canonical identity. Any old registration future may still complete, but
  /// its captured authority can no longer publish or persist health state.
  void beginAccountBindingCutover() {
    if (_disposed) return;
    _healthAuthorityEpoch++;
    _healthBinding = null;
    _healthRecord = null;
    _healthLoaded = false;
    _permissionState = _PushPermissionState.unknown;
    _retryTimer?.cancel();
    _retryTimer = null;
    healthNotifier?.clear();
  }

  /// Resolves the post-cutover binding and runs a fresh registration attempt.
  /// This is intentionally separate from [beginAccountBindingCutover] so the
  /// stale-attempt fence is established before identity replacement begins.
  Future<void> completeAccountBindingCutover() => retryNow();

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
  }) async {
    _retryTimer?.cancel();
    _retryTimer = null;

    final authority = await _resolveAndHydrateHealthAuthority();
    if (authority == null || _disposed || !isEnabled()) {
      return;
    }

    final inFlightAttempt = _inFlightAttempt;
    if (inFlightAttempt != null) {
      final inFlightAuthority = _inFlightAuthority;
      await inFlightAttempt;
      if (inFlightAuthority == authority ||
          !_isCurrentHealthAuthority(authority) ||
          _disposed ||
          !isEnabled()) {
        return;
      }
      // A trigger observed a new binding while an old-account attempt was in
      // flight. Let the fenced attempt settle, then register for the latest
      // authority instead of dropping the cutover trigger.
      await _attemptRegistration(
        checkPermission: checkPermission,
        trigger: trigger,
      );
      return;
    }

    final attempt = _runAttempt(
      checkPermission: checkPermission,
      trigger: trigger,
      authority: authority,
    );
    _inFlightAuthority = authority;
    _inFlightAttempt = attempt;
    try {
      await attempt;
    } finally {
      if (identical(_inFlightAttempt, attempt)) {
        _inFlightAttempt = null;
        _inFlightAuthority = null;
      }
    }
  }

  Future<void> _runAttempt({
    required bool checkPermission,
    required String trigger,
    required _PushRegistrationHealthAuthority authority,
  }) async {
    if (!checkPermission && _permissionState == _PushPermissionState.denied) {
      return;
    }
    final previousHealth = _healthRecord;
    final attemptAt = now().toUtc();
    if (!await _publishAndPersistHealth(
      PushRegistrationHealthRecord.checking(
        at: attemptAt,
        previous: previousHealth,
      ),
      authority: authority,
    )) {
      return;
    }
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
        if (!_isCurrentHealthAuthority(authority)) return;
        _permissionState = granted
            ? _PushPermissionState.granted
            : _PushPermissionState.denied;
        if (!granted) {
          await _publishAndPersistHealth(
            PushRegistrationHealthRecord.permissionDenied(
              at: now().toUtc(),
              lastSuccessAt: previousHealth?.lastSuccessAt,
            ),
            authority: authority,
          );
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
      if (!_isCurrentHealthAuthority(authority)) return;
      switch (result) {
        case RegisterPushTokenResult.success:
          final published = await _publishAndPersistHealth(
            PushRegistrationHealthRecord.healthy(at: now().toUtc()),
            authority: authority,
          );
          if (!published) return;
          logPushDiagnostic(
            'registration_success',
            details: {'trigger': trigger},
          );
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_REGISTER_COORDINATOR_SUCCESS',
            details: <String, dynamic>{
              'trigger': trigger,
              ...?registrationSuccessDetails?.call(),
            },
          );
          return;
        case RegisterPushTokenResult.noToken:
        case RegisterPushTokenResult.failed:
          await _recordTransientFailure(
            previous: previousHealth,
            reason: result == RegisterPushTokenResult.noToken
                ? PushRegistrationHealthReason.noToken
                : PushRegistrationHealthReason.registrationFailed,
            authority: authority,
          );
          if (!_isCurrentHealthAuthority(authority)) return;
          logPushDiagnostic(
            'registration_retry_needed',
            details: {'trigger': trigger, 'result': result.name},
          );
          _scheduleRetry(
            result: result,
            trigger: trigger,
            authority: authority,
          );
          return;
        case RegisterPushTokenResult.accountMigrationBlocked:
          await _restoreNeutralHealth(previousHealth, authority: authority);
          if (!_isCurrentHealthAuthority(authority)) return;
          logPushDiagnostic(
            'registration_account_migration_blocked',
            details: {'trigger': trigger},
          );
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_REGISTER_COORDINATOR_ACCOUNT_MIGRATION_BLOCKED',
            details: {'trigger': trigger},
          );
          return;
      }
    } catch (e) {
      if (!_isCurrentHealthAuthority(authority)) return;
      await _recordTransientFailure(
        previous: previousHealth,
        reason: PushRegistrationHealthReason.exception,
        authority: authority,
      );
      if (!_isCurrentHealthAuthority(authority)) return;
      logPushDiagnostic(
        'registration_exception',
        details: {'trigger': trigger, 'error': e.toString()},
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_REGISTER_COORDINATOR_EXCEPTION',
        details: {'trigger': trigger, 'error': e.toString()},
      );
      _scheduleRetry(trigger: trigger, error: e, authority: authority);
    }
  }

  Future<_PushRegistrationHealthAuthority?>
  _resolveAndHydrateHealthAuthority() async {
    final store = healthStore;
    PushRegistrationHealthBinding? resolvedBinding;
    final resolutionEpoch = _healthAuthorityEpoch;
    if (store is BindingScopedPushRegistrationHealthStorage) {
      try {
        resolvedBinding = await store.resolveBinding();
      } catch (error) {
        _emitHealthPersistenceFailure('resolve_binding', error);
        return null;
      }
    }

    return _serializeHealthOperation(() async {
      if (_disposed || resolutionEpoch != _healthAuthorityEpoch) return null;
      if (resolvedBinding != _healthBinding) {
        _healthAuthorityEpoch++;
        _healthBinding = resolvedBinding;
        _healthRecord = null;
        _healthLoaded = false;
        _permissionState = _PushPermissionState.unknown;
        healthNotifier?.clear();
      }
      final authority = (epoch: _healthAuthorityEpoch, binding: _healthBinding);
      if (_healthLoaded) return authority;
      _healthLoaded = true;
      if (store == null) return authority;
      try {
        final record = await _readHealthForAuthority(store, authority);
        if (!_isCurrentHealthAuthority(authority)) return null;
        _healthRecord = record;
        if (record == null) {
          healthNotifier?.clear();
        } else {
          healthNotifier?.publish(record);
        }
      } catch (error) {
        _emitHealthPersistenceFailure('read', error);
      }
      return _isCurrentHealthAuthority(authority) ? authority : null;
    });
  }

  Future<bool> _publishAndPersistHealth(
    PushRegistrationHealthRecord record, {
    required _PushRegistrationHealthAuthority authority,
  }) {
    return _serializeHealthOperation(() async {
      if (!_isCurrentHealthAuthority(authority)) return false;
      _healthRecord = record;
      healthNotifier?.publish(record);
      final store = healthStore;
      if (store == null) return true;
      try {
        await _writeHealthForAuthority(store, authority, record);
      } catch (error) {
        _emitHealthPersistenceFailure('write', error);
      }
      return _isCurrentHealthAuthority(authority);
    });
  }

  Future<bool> _restoreNeutralHealth(
    PushRegistrationHealthRecord? previous, {
    required _PushRegistrationHealthAuthority authority,
  }) async {
    if (previous != null) {
      return _publishAndPersistHealth(previous, authority: authority);
    }
    return _serializeHealthOperation(() async {
      if (!_isCurrentHealthAuthority(authority)) return false;
      _healthRecord = null;
      healthNotifier?.clear();
      final store = healthStore;
      if (store == null) return true;
      try {
        await _clearHealthForAuthority(store, authority);
      } catch (error) {
        _emitHealthPersistenceFailure('clear', error);
      }
      return _isCurrentHealthAuthority(authority);
    });
  }

  Future<bool> _recordTransientFailure({
    required PushRegistrationHealthRecord? previous,
    required PushRegistrationHealthReason reason,
    required _PushRegistrationHealthAuthority authority,
  }) {
    final firstFailure = previous?.firstFailureAt;
    final continuesExistingFailure =
        previous != null &&
        previous.reason.isTransient &&
        firstFailure != null &&
        (previous.lastSuccessAt == null ||
            !previous.lastSuccessAt!.isAfter(firstFailure));
    final at = now().toUtc();
    return _publishAndPersistHealth(
      PushRegistrationHealthRecord.retrying(
        reason: reason,
        consecutiveFailures: continuesExistingFailure
            ? previous.consecutiveFailures + 1
            : 1,
        firstFailureAt: continuesExistingFailure ? firstFailure : at,
        lastAttemptAt: at,
        lastSuccessAt: previous?.lastSuccessAt,
      ),
      authority: authority,
    );
  }

  bool _isCurrentHealthAuthority(_PushRegistrationHealthAuthority authority) {
    return !_disposed &&
        authority.epoch == _healthAuthorityEpoch &&
        authority.binding == _healthBinding;
  }

  Future<PushRegistrationHealthRecord?> _readHealthForAuthority(
    PushRegistrationHealthStorage store,
    _PushRegistrationHealthAuthority authority,
  ) {
    if (store is BindingScopedPushRegistrationHealthStorage) {
      final binding = authority.binding;
      if (binding != null) return store.readForBinding(binding);
    }
    return store.read();
  }

  Future<void> _writeHealthForAuthority(
    PushRegistrationHealthStorage store,
    _PushRegistrationHealthAuthority authority,
    PushRegistrationHealthRecord record,
  ) {
    if (store is BindingScopedPushRegistrationHealthStorage) {
      final binding = authority.binding;
      if (binding != null) return store.writeForBinding(binding, record);
    }
    return store.write(record);
  }

  Future<void> _clearHealthForAuthority(
    PushRegistrationHealthStorage store,
    _PushRegistrationHealthAuthority authority,
  ) {
    if (store is BindingScopedPushRegistrationHealthStorage) {
      final binding = authority.binding;
      if (binding != null) return store.clearForBinding(binding);
    }
    return store.clear();
  }

  Future<T> _serializeHealthOperation<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _healthOperationTail = _healthOperationTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  void _emitHealthPersistenceFailure(String operation, Object error) {
    logPushDiagnostic(
      'registration_health_persistence_failed',
      details: {
        'operation': operation,
        'errorType': error.runtimeType.toString(),
      },
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_REGISTER_HEALTH_PERSISTENCE_FAILED',
      details: {
        'operation': operation,
        'errorType': error.runtimeType.toString(),
      },
    );
  }

  void _scheduleRetry({
    RegisterPushTokenResult? result,
    required String trigger,
    Object? error,
    required _PushRegistrationHealthAuthority authority,
  }) {
    if (!_isCurrentHealthAuthority(authority) || !isEnabled()) {
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
      if (!_isCurrentHealthAuthority(authority)) {
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
