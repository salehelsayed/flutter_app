import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app/app/bootstrap/application_bootstrap.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';

/// Foreground-only contention policy. The native broker remains the sole grant
/// authority; headless callers retain their immediate, fail-closed acquisition.
final class ForegroundCanonicalRuntimeStartup<T> {
  ForegroundCanonicalRuntimeStartup({
    required CanonicalRuntimeLeaseGateway gateway,
    required Future<void> Function(T) closeDatabase,
    required bool Function(T) isDatabaseOpen,
    Future<void> Function()? waitForRetry,
    Duration waitBudget = const Duration(seconds: 30),
    Duration pollInterval = const Duration(milliseconds: 250),
    Duration Function()? elapsed,
    Future<void> Function(Duration)? delay,
  }) : _gateway = gateway,
       _closeDatabase = closeDatabase,
       _isDatabaseOpen = isDatabaseOpen,
       _waitForRetry = waitForRetry {
    if (waitBudget <= Duration.zero || pollInterval <= Duration.zero) {
      throw ArgumentError('foreground lease wait durations must be positive');
    }
    final clock = Stopwatch()..start();
    _waitingGateway = _ForegroundLeaseGateway(
      gateway: gateway,
      current: () => !_cancelled,
      cancelled: _cancellation.future,
      waitForRetry: waitForRetry,
      waitBudget: waitBudget,
      pollInterval: pollInterval,
      elapsed: elapsed ?? (() => clock.elapsed),
      delay: delay ?? Future<void>.delayed,
    );
    _session = CanonicalWritableRuntimeSession(gateway: _waitingGateway);
  }

  final CanonicalRuntimeLeaseGateway _gateway;
  final Future<void> Function(T) _closeDatabase;
  final bool Function(T) _isDatabaseOpen;
  final Future<void> Function()? _waitForRetry;
  final _cancellation = Completer<void>();
  late final _ForegroundLeaseGateway _waitingGateway;
  late final CanonicalWritableRuntimeSession _session;
  Future<T>? _opening;
  Future<bool>? _shutdown;
  bool _cancelled = false;
  bool _openStarted = false;
  bool _openCompleted = false;
  late T _database;

  bool get databaseClosed =>
      !_openStarted || (_openCompleted && !_isDatabaseOpen(_database));

  Future<T> open({
    required String binding,
    required Future<T> Function() openDatabase,
  }) {
    if (_cancelled) throw const ApplicationBootstrapCancelled();
    if (_opening != null) {
      throw StateError('foreground startup has already started');
    }
    final operation = _openWithRecovery(binding, openDatabase);
    _opening = operation;
    return operation.then((database) {
      if (_cancelled) throw const ApplicationBootstrapCancelled();
      return database;
    });
  }

  Future<T> _openWithRecovery(
    String binding,
    Future<T> Function() openDatabase,
  ) async {
    while (true) {
      try {
        return await _session.acquireThenOpen<T>(
          binding: binding,
          openDatabase: () async {
            _waitingGateway.ensureCurrentGrant();
            _openStarted = true;
            _database = await openDatabase();
            _openCompleted = true;
            return _database;
          },
          closeAfterOpenFailure: () async => databaseClosed,
          closeDatabaseOnRuntimeAttachFailure: (database) async {
            await _closeDatabase(database);
            return !_isDatabaseOpen(database);
          },
        );
      } on _LateForegroundLeaseGrant {
        final retry = _waitForRetry;
        if (_cancelled) throw const ApplicationBootstrapCancelled();
        if (_openStarted || _session.hasWritableLease || retry == null) rethrow;
        await Future.any<void>([retry(), _cancellation.future]);
        if (_cancelled) throw const ApplicationBootstrapCancelled();
      } catch (_) {
        if (_cancelled) throw const ApplicationBootstrapCancelled();
        rethrow;
      }
    }
  }

  /// Cancels before awaiting anything. An in-flight grant/open settles before
  /// cleanup, and database closure is never inferred from engine disposal.
  Future<bool> shutdown() {
    _cancelled = true;
    if (!_cancellation.isCompleted) _cancellation.complete();
    return _shutdown ??= _shutdownOwnedRuntime().whenComplete(() {
      _shutdown = null;
    });
  }

  Future<bool> _shutdownOwnedRuntime() async {
    try {
      try {
        await _opening;
      } catch (_) {
        // The session retains any uncertain open/attach failure fail-closed.
      }
      await _session.drainCloseRelease(
        stopRuntime: () async {
          if (!await _gateway.quiesceRuntime()) {
            throw StateError('Go runtime did not quiesce');
          }
        },
        closeDatabase: () async {
          if (_openCompleted && _isDatabaseOpen(_database)) {
            await _closeDatabase(_database);
          }
          if (!databaseClosed) {
            throw StateError('database close is unproven');
          }
        },
      );
      final state = await _gateway.status();
      return databaseClosed &&
          state.state == CanonicalRuntimeLeaseState.released;
    } catch (_) {
      return false;
    }
  }
}

final class _LateForegroundLeaseGrant implements Exception {
  const _LateForegroundLeaseGrant();
}

final class _ForegroundLeaseGateway implements CanonicalRuntimeLeaseGateway {
  _ForegroundLeaseGateway({
    required this.gateway,
    required this.current,
    required this.cancelled,
    required this.waitForRetry,
    required this.waitBudget,
    required this.pollInterval,
    required this.elapsed,
    required this.delay,
  });

  final CanonicalRuntimeLeaseGateway gateway;
  final bool Function() current;
  final Future<void> cancelled;
  final Future<void> Function()? waitForRetry;
  final Duration waitBudget;
  final Duration pollInterval;
  final Duration Function() elapsed;
  final Future<void> Function(Duration) delay;
  bool _grantWithinBudget = false;

  void ensureCurrentGrant() {
    if (!current()) throw const ApplicationBootstrapCancelled();
    if (!_grantWithinBudget) {
      throw const _LateForegroundLeaseGrant();
    }
  }

  @override
  Future<CanonicalRuntimeLeaseSnapshot> acquire(String binding) async {
    var start = elapsed();
    var attempts = 0;
    PlatformException? contention;
    final maximumAttempts =
        waitBudget.inMicroseconds ~/ pollInterval.inMicroseconds + 1;
    while (true) {
      if (!current()) throw const ApplicationBootstrapCancelled();
      if (contention != null && elapsed() - start >= waitBudget) {
        final retry = waitForRetry;
        if (retry == null) throw contention;
        await Future.any<void>([retry(), cancelled]);
        if (!current()) throw const ApplicationBootstrapCancelled();
        start = elapsed();
        attempts = 0;
        contention = null;
      }
      try {
        final snapshot = await gateway.acquire(binding);
        // Return even a late/cancelled grant to the session so it owns and
        // retires that exact token before any database callback can proceed.
        _grantWithinBudget = elapsed() - start < waitBudget;
        return snapshot;
      } on PlatformException catch (error) {
        if (error.code != 'lease_unavailable') rethrow;
        contention = error;
        if (!current()) throw const ApplicationBootstrapCancelled();
        attempts += 1;
        final remaining = waitBudget - (elapsed() - start);
        if (remaining <= Duration.zero || attempts >= maximumAttempts) {
          final retry = waitForRetry;
          if (retry == null) rethrow;
          await Future.any<void>([retry(), cancelled]);
          if (!current()) throw const ApplicationBootstrapCancelled();
          start = elapsed();
          attempts = 0;
        } else {
          await Future.any<void>([
            delay(remaining < pollInterval ? remaining : pollInterval),
            cancelled,
          ]);
        }
      }
    }
  }

  @override
  Future<bool> attachRuntime() =>
      current() ? gateway.attachRuntime() : Future<bool>.value(false);
  @override
  Future<bool> beginDrain() => gateway.beginDrain();
  @override
  Future<bool> quiesceRuntime() => gateway.quiesceRuntime();
  @override
  Future<bool> release({required bool databaseClosed}) =>
      gateway.release(databaseClosed: databaseClosed);
  @override
  Future<CanonicalRuntimeLeaseSnapshot> rebind(String binding) =>
      gateway.rebind(binding);
  @override
  Future<CanonicalRuntimeLeaseSnapshot> status() => gateway.status();
}
