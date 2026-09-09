import '../diagnostics/call_diagnostics.dart';
import 'dart:async';

import '../domain/call_authority_lifetime.dart';
import 'call_authority_client.dart';

typedef IosVoipTokenMethodInvoker =
    Future<Object?> Function(String method, Map<String, Object?> arguments);
typedef IosVoipTokenPublicationAllowed = Future<bool> Function();
typedef IosVoipTokenInitialSnapshotTimeout =
    Future<void> Function(Duration timeout);

enum _IosVoipInitialStartKind {
  read,
  streamEvent,
  streamError,
  nativeFailure,
  timeout,
  closed,
}

typedef _IosVoipInitialStartOutcome = ({
  _IosVoipInitialStartKind kind,
  Object? value,
});

enum IosVoipTokenErrorCode {
  closed,
  malformedSnapshot,
  nativeFailure,
  authorityFailure,
}

/// Fixed-shape token error. PushKit token bytes and metadata are deliberately
/// absent from errors and from this class's string representation.
final class IosVoipTokenException implements Exception {
  const IosVoipTokenException(this.code);

  final IosVoipTokenErrorCode code;

  @override
  String toString() => 'IosVoipTokenException(${code.name})';
}

/// Outcome of one native refresh-epoch advance requested after the relay
/// rejected a registration as stale. Fixed cardinality; the graph maps it to
/// an identifier-free diagnostic (this coordinator never emits diagnostics).
enum IosVoipTokenEpochAdvanceOutcome {
  advanced('advanced'),
  refused('refused'),
  nativeFailure('native_failure'),
  relayRejected('relay_rejected');

  const IosVoipTokenEpochAdvanceOutcome(this.wireName);

  final String wireName;
}

final class IosVoipTokenSnapshot {
  const IosVoipTokenSnapshot._({
    required this.token,
    required this.environment,
    required this.topic,
    required this.capabilityVersion,
    required this.refreshEpoch,
    required this.invalidated,
    this.invalidationReason = 'unknown',
    this.operationId,
    this.parentOperationId,
  });

  static const int protocolVersion = 1;

  final String token;
  final String environment;
  final String topic;
  final int capabilityVersion;
  final int refreshEpoch;
  final bool invalidated;
  final String invalidationReason;
  final String? operationId;
  final String? parentOperationId;

  String get relayEnvironment => switch (environment) {
    'development' => 'sandbox',
    'production' => 'production',
    _ => throw const IosVoipTokenException(
      IosVoipTokenErrorCode.malformedSnapshot,
    ),
  };

  bool sameRegistration(IosVoipTokenSnapshot other) =>
      !invalidated &&
      !other.invalidated &&
      token == other.token &&
      environment == other.environment &&
      topic == other.topic &&
      capabilityVersion == other.capabilityVersion &&
      refreshEpoch == other.refreshEpoch;

  bool sameSnapshot(IosVoipTokenSnapshot other) =>
      token == other.token &&
      environment == other.environment &&
      topic == other.topic &&
      capabilityVersion == other.capabilityVersion &&
      refreshEpoch == other.refreshEpoch &&
      invalidated == other.invalidated;

  bool sameMetadata(IosVoipTokenSnapshot other) =>
      environment == other.environment &&
      topic == other.topic &&
      capabilityVersion == other.capabilityVersion;

  factory IosVoipTokenSnapshot.parse(Object? value) {
    if (value is! Map) {
      throw const IosVoipTokenException(
        IosVoipTokenErrorCode.malformedSnapshot,
      );
    }
    final map = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String || map.containsKey(entry.key)) {
        throw const IosVoipTokenException(
          IosVoipTokenErrorCode.malformedSnapshot,
        );
      }
      map[entry.key! as String] = entry.value;
    }
    const keys = <String>{
      'version',
      'token',
      'environment',
      'topic',
      'capabilityVersion',
      'refreshEpoch',
      'invalidated',
    };
    const diagnosticKeys = <String>{
      'invalidationReason',
      'operationId',
      'parentOperationId',
    };
    if (map.keys.toSet().difference({...keys, ...diagnosticKeys}).isNotEmpty ||
        keys.difference(map.keys.toSet()).isNotEmpty ||
        map['version'] != protocolVersion ||
        map['token'] is! String ||
        map['environment'] is! String ||
        map['topic'] is! String ||
        map['capabilityVersion'] is! int ||
        map['refreshEpoch'] is! int ||
        map['invalidated'] is! bool) {
      throw const IosVoipTokenException(
        IosVoipTokenErrorCode.malformedSnapshot,
      );
    }
    final token = map['token']! as String;
    final environment = map['environment']! as String;
    final topic = map['topic']! as String;
    final capabilityVersion = map['capabilityVersion']! as int;
    final refreshEpoch = map['refreshEpoch']! as int;
    final invalidated = map['invalidated']! as bool;
    final validToken =
        token.isNotEmpty &&
        token.length.isEven &&
        token.length <= 512 &&
        _lowercaseHex.hasMatch(token);
    if ((environment != 'development' && environment != 'production') ||
        !_apnsTopic.hasMatch(topic) ||
        topic.length > 255 ||
        capabilityVersion != 1 ||
        refreshEpoch <= 0 ||
        (invalidated ? token.isNotEmpty : !validToken)) {
      throw const IosVoipTokenException(
        IosVoipTokenErrorCode.malformedSnapshot,
      );
    }
    return IosVoipTokenSnapshot._(
      token: token,
      environment: environment,
      topic: topic,
      capabilityVersion: capabilityVersion,
      refreshEpoch: refreshEpoch,
      invalidated: invalidated,
      invalidationReason:
          const <String>{
            'calls_disabled',
            'pushkit_token_invalidated',
            'native_token_updated',
            'stale_epoch',
          }.contains(map['invalidationReason'])
          ? map['invalidationReason'] as String
          : 'unknown',
      operationId: _diagnosticUuid(map['operationId']),
      parentOperationId: _diagnosticUuid(map['parentOperationId']),
    );
  }

  static String? _diagnosticUuid(Object? value) =>
      value is String &&
          RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ).hasMatch(value)
      ? value
      : null;

  static final RegExp _lowercaseHex = RegExp(r'^[0-9a-f]+$');
  static final RegExp _apnsTopic = RegExp(
    r'^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\.voip$',
  );
}

/// Owns publication of exactly the iOS VoIP token kind. Standard notification
/// tokens are outside this component and cannot be revoked by its API.
final class IosVoipTokenCoordinator {
  IosVoipTokenCoordinator({
    required IosVoipTokenMethodInvoker invokeMethod,
    required Stream<Object?> nativeEvents,
    required CallAuthorityClient authorityClient,
    required DateTime Function() clock,
    IosVoipTokenPublicationAllowed? publicationAllowed,
    this.registrationTtl = callBackgroundReachabilityLifetime,
    this.initialSnapshotWait = const Duration(seconds: 5),
    IosVoipTokenInitialSnapshotTimeout? waitForInitialReadTimeout,
    IosVoipTokenInitialSnapshotTimeout? waitForInitialSnapshotTimeout,
  }) : _invokeMethod = invokeMethod,
       _nativeEvents = nativeEvents,
       _authorityClient = authorityClient,
       _clock = clock,
       _publicationAllowed = publicationAllowed ?? _alwaysAllowed,
       _waitForInitialReadTimeout =
           waitForInitialReadTimeout ?? _defaultInitialSnapshotTimeout,
       _waitForInitialSnapshotTimeout =
           waitForInitialSnapshotTimeout ?? _defaultInitialSnapshotTimeout {
    if (registrationTtl <= Duration.zero ||
        registrationTtl > const Duration(days: 90)) {
      throw ArgumentError.value(
        registrationTtl,
        'registrationTtl',
        'must be positive and no longer than ninety days',
      );
    }
    if (initialSnapshotWait <= Duration.zero ||
        initialSnapshotWait > const Duration(seconds: 10)) {
      throw ArgumentError.value(
        initialSnapshotWait,
        'initialSnapshotWait',
        'must be positive and no longer than ten seconds',
      );
    }
  }

  static const int protocolVersion = 1;

  /// Native method that moves the durable PushKit registration to a fresh
  /// refresh epoch after the relay rejected the current one as stale.
  static const String advanceRefreshEpochMethod = 'advanceRefreshEpoch';
  static const String methodChannelName = 'mknoon/ios_voip_token';
  static const String eventChannelName = 'mknoon/ios_voip_token/events';
  static const int maxBufferedInitialSnapshots = 32;

  final IosVoipTokenMethodInvoker _invokeMethod;
  final Stream<Object?> _nativeEvents;
  final CallAuthorityClient _authorityClient;
  final DateTime Function() _clock;
  final IosVoipTokenPublicationAllowed _publicationAllowed;
  final IosVoipTokenInitialSnapshotTimeout _waitForInitialReadTimeout;
  final IosVoipTokenInitialSnapshotTimeout _waitForInitialSnapshotTimeout;
  final Duration registrationTtl;
  final Duration initialSnapshotWait;

  final StreamController<void> _authorityInvalidations =
      StreamController<void>.broadcast(sync: true);

  final StreamController<IosVoipTokenEpochAdvanceOutcome> _epochAdvances =
      StreamController<IosVoipTokenEpochAdvanceOutcome>.broadcast(sync: true);
  StreamSubscription<Object?>? _nativeSubscription;
  Future<void> _tail = Future<void>.value();
  Future<void>? _startFuture;
  Future<void>? _closeFuture;
  Future<bool>? _initialPublicationFuture;
  IosVoipTokenSnapshot? _snapshot;
  IosVoipTokenSnapshot? _publishedSnapshot;
  final Set<int> _revokedEpochs = <int>{};
  final Set<int> _relayRejectedEpochs = <int>{};
  final List<Object?> _initialNativeValues = <Object?>[];
  final Completer<_IosVoipInitialStartOutcome> _initialStartSignal =
      Completer<_IosVoipInitialStartOutcome>();
  Completer<void> _initialSnapshotChanged = Completer<void>();
  int _initialSnapshotWaiters = 0;
  bool _authorityReady = false;
  bool _initialReadComplete = false;
  bool _initialPublicationComplete = false;
  bool _initialStreamFailed = false;
  bool _invalid = false;
  bool _closed = false;
  bool _invalidationPublished = false;
  String invalidationDiagnosticReason = 'unknown';
  String? invalidationDiagnosticOperationId;

  Stream<void> get authorityInvalidations => _authorityInvalidations.stream;

  /// One event per native refresh-epoch advance attempt (see
  /// [IosVoipTokenEpochAdvanceOutcome]). Never carries token material.
  Stream<IosVoipTokenEpochAdvanceOutcome> get epochAdvances =>
      _epochAdvances.stream;
  Future<void> start() => _startFuture ??= _startOnce();

  Future<void> _startOnce() async {
    if (_closed) {
      throw const IosVoipTokenException(IosVoipTokenErrorCode.closed);
    }
    _nativeSubscription = _nativeEvents.listen(
      _onNativeValue,
      onError: (_) => _onNativeError(),
    );
    final outcome = await Future.any<_IosVoipInitialStartOutcome>(
      <Future<_IosVoipInitialStartOutcome>>[
        _readInitialSnapshot(),
        _initialStartSignal.future,
        _waitForInitialReadDeadline(),
      ],
    );
    if (outcome.kind == _IosVoipInitialStartKind.closed || _closed) {
      throw const IosVoipTokenException(IosVoipTokenErrorCode.closed);
    }
    if (outcome.kind
        case _IosVoipInitialStartKind.streamError ||
            _IosVoipInitialStartKind.nativeFailure ||
            _IosVoipInitialStartKind.timeout) {
      invalidationDiagnosticReason = switch (outcome.kind) {
        _IosVoipInitialStartKind.timeout => 'native_read_timeout',
        _IosVoipInitialStartKind.streamError => 'native_stream_failed',
        _ => 'native_lifecycle_failed',
      };
      invalidationDiagnosticOperationId = CallDiagnostics.instance
          .beginOperation(reason: invalidationDiagnosticReason);
      CallDiagnostics.instance.record(
        stage: 'authority',
        action: 'invalidate',
        outcome: 'failed',
        reason: invalidationDiagnosticReason,
        operationId: invalidationDiagnosticOperationId,
      );
      _invalid = true;
      _signalInitialSnapshotChange();
      await _schedule<void>(_revokeAndPublishInvalidation);
      throw const IosVoipTokenException(IosVoipTokenErrorCode.nativeFailure);
    }
    final current = outcome.kind == _IosVoipInitialStartKind.read
        ? outcome.value
        : null;
    try {
      await _schedule<void>(() async {
        if (_initialStreamFailed) {
          throw const IosVoipTokenException(
            IosVoipTokenErrorCode.nativeFailure,
          );
        }
        if (current != null) {
          _acceptSnapshot(IosVoipTokenSnapshot.parse(current));
        }
        for (final value in _initialNativeValues) {
          _acceptSnapshot(IosVoipTokenSnapshot.parse(value));
        }
        _initialNativeValues.clear();
        _initialReadComplete = true;
      });
    } on IosVoipTokenException {
      await _failClosedNative();
      rethrow;
    }
  }

  Future<_IosVoipInitialStartOutcome> _readInitialSnapshot() async {
    try {
      return (
        kind: _IosVoipInitialStartKind.read,
        value: await _invokeMethod('readCurrent', const <String, Object?>{
          'version': protocolVersion,
        }),
      );
    } catch (_) {
      return (kind: _IosVoipInitialStartKind.nativeFailure, value: null);
    }
  }

  Future<_IosVoipInitialStartOutcome> _waitForInitialReadDeadline() async {
    try {
      await _waitForInitialReadTimeout(initialSnapshotWait);
      return (kind: _IosVoipInitialStartKind.timeout, value: null);
    } catch (_) {
      return (kind: _IosVoipInitialStartKind.nativeFailure, value: null);
    }
  }

  /// Marks relay authority ready and publishes before an iOS endpoint may be
  /// advertised. Literal success is required; no native snapshot means the
  /// endpoint remains uncallable.
  Future<bool> publishForAuthenticatedGraph() {
    if (_initialPublicationComplete) {
      return _publishForAuthenticatedGraphOnce();
    }
    final inFlight = _initialPublicationFuture;
    if (inFlight != null) return inFlight;
    late final Future<bool> attempt;
    attempt = _publishForAuthenticatedGraphOnce().whenComplete(() {
      _initialPublicationComplete = true;
      if (identical(_initialPublicationFuture, attempt)) {
        _initialPublicationFuture = null;
      }
    });
    _initialPublicationFuture = attempt;
    return attempt;
  }

  Future<bool> _publishForAuthenticatedGraphOnce() async {
    await start();
    _authorityReady = true;
    if (_needsFirstCallableSnapshot && !_invalid && !_closed) {
      _initialSnapshotWaiters += 1;
      var callableSnapshotReady = false;
      try {
        callableSnapshotReady = await _waitForFirstCallableSnapshot();
      } finally {
        _initialSnapshotWaiters -= 1;
      }
      if (!callableSnapshotReady && _invalid && !_closed) {
        await _schedule<void>(_revokeAndPublishInvalidation);
      }
    }
    return _schedule<bool>(() => _reconcileAuthority(refreshExisting: true));
  }

  bool get _needsFirstCallableSnapshot =>
      !_initialPublicationComplete &&
      (_snapshot == null || _snapshot!.invalidated);

  Future<bool> _waitForFirstCallableSnapshot() async {
    final deadline = _waitForInitialSnapshotDeadline();
    while (!_invalid && !_closed) {
      while (_needsFirstCallableSnapshot && !_invalid && !_closed) {
        final snapshotChanged = _initialSnapshotChanged.future;
        if (!_needsFirstCallableSnapshot) break;
        var changedBeforeDeadline = false;
        try {
          changedBeforeDeadline = await Future.any<bool>(<Future<bool>>[
            snapshotChanged.then((_) => true),
            deadline,
          ]);
        } catch (_) {
          changedBeforeDeadline = false;
        }
        if (!changedBeforeDeadline) {
          if (!_invalid && !_closed) {
            // Deadline is an atomic authority transition. A same-turn native
            // event may already be queued, but it can no longer be accepted.
            _invalid = true;
            _signalInitialSnapshotChange();
          }
          return false;
        }
      }
      if (_invalid || _closed) return false;
      final callableStillCurrent = await _schedule<bool>(
        () async => !_needsFirstCallableSnapshot && !_invalid && !_closed,
      );
      if (callableStillCurrent) return true;
    }
    return false;
  }

  Future<bool> _waitForInitialSnapshotDeadline() async {
    try {
      await _waitForInitialSnapshotTimeout(initialSnapshotWait);
    } catch (_) {
      // A broken timer seam is treated exactly like expiry.
    }
    return false;
  }

  void _onNativeValue(Object? value) {
    if (_closed || _invalid) return;
    if (!_initialReadComplete) {
      if (_initialNativeValues.length >= maxBufferedInitialSnapshots) {
        _initialStreamFailed = true;
        _completeInitialStart(_IosVoipInitialStartKind.streamError);
        return;
      }
      _initialNativeValues.add(value);
      _completeInitialStart(_IosVoipInitialStartKind.streamEvent);
      return;
    }
    unawaited(
      _schedule<void>(() async {
        if (_closed || _invalid) return;
        try {
          _acceptSnapshot(IosVoipTokenSnapshot.parse(value));
        } catch (_) {
          // A malformed native snapshot is a native failure: latch closed.
          await _failClosedNative();
          return;
        }
        if (_authorityReady && _initialSnapshotWaiters == 0) {
          await _reconcileAuthority();
        }
      }),
    );
  }

  void _onNativeError() {
    if (_closed) return;
    if (!_initialReadComplete) {
      _initialStreamFailed = true;
      _completeInitialStart(_IosVoipInitialStartKind.streamError);
      return;
    }
    unawaited(
      _schedule<void>(() => _failClosedNative(reason: 'native_stream_failed')),
    );
  }

  void _completeInitialStart(_IosVoipInitialStartKind kind) {
    if (!_initialStartSignal.isCompleted) {
      _initialStartSignal.complete((kind: kind, value: null));
    }
  }

  void _acceptSnapshot(IosVoipTokenSnapshot next) {
    final current = _snapshot;
    if (current != null) {
      if (next.refreshEpoch < current.refreshEpoch) {
        throw const IosVoipTokenException(
          IosVoipTokenErrorCode.malformedSnapshot,
        );
      }
      if (next.refreshEpoch == current.refreshEpoch &&
          !next.sameSnapshot(current)) {
        final sameEpochInvalidation =
            !current.invalidated &&
            next.invalidated &&
            next.sameMetadata(current);
        if (!sameEpochInvalidation) {
          throw const IosVoipTokenException(
            IosVoipTokenErrorCode.malformedSnapshot,
          );
        }
      }
    }
    _snapshot = next;
    _signalInitialSnapshotChange();
  }

  Future<bool> _reconcileAuthority({bool refreshExisting = false}) {
    final diagnostics = CallDiagnostics.instance;
    final snapshot = _snapshot;
    final reason = snapshot?.invalidated == true
        ? snapshot!.invalidationReason
        : refreshExisting
        ? 'resume_refresh'
        : 'bootstrap';
    final operationId = snapshot?.invalidated == true
        ? diagnostics.beginOperation(
            reason: reason,
            parentOperationId: snapshot?.operationId,
          )
        : diagnostics.currentOperationId ??
              diagnostics.beginOperation(reason: reason);
    invalidationDiagnosticReason = reason;
    invalidationDiagnosticOperationId = operationId;
    if (snapshot?.invalidated == true) {
      diagnostics.record(
        stage: 'authority',
        action: 'invalidate',
        outcome: 'ok',
        reason: reason,
        operationId: operationId,
        parentOperationId: snapshot?.operationId,
        values: <String, Object?>{'epoch': snapshot!.refreshEpoch},
      );
    }
    return diagnostics.runWithOperation(
      operationId,
      () => _reconcileAuthorityInOperation(refreshExisting: refreshExisting),
    );
  }

  Future<bool> _reconcileAuthorityInOperation({
    bool refreshExisting = false,
  }) async {
    if (_closed || _invalid) return false;
    if (!await _publicationAllowed() || _closed || _invalid) return false;
    final initial = _snapshot;
    if (initial == null) return false;
    if (initial.invalidated) {
      await _revokeEpoch(initial.refreshEpoch);
      _publishedSnapshot = null;
      _publishInvalidation();
      return false;
    }
    IosVoipTokenSnapshot snapshot = initial;
    final prior = _publishedSnapshot;
    if (!refreshExisting && prior != null && prior.sameRegistration(snapshot)) {
      return true;
    }
    var epochAdvanced = false;
    while (true) {
      try {
        final publication = await _authorityClient.publishToken(
          CallTokenRecord(
            kind: CallTokenKind.iosVoip,
            platform: CallEndpointPlatform.ios,
            token: snapshot.token,
            expiresAtMs: _boundedExpiryMs(),
            environment: snapshot.relayEnvironment,
            topic: snapshot.topic,
            capabilityVersion: snapshot.capabilityVersion,
            refreshEpoch: snapshot.refreshEpoch,
          ),
        );
        if (!publication.accepted ||
            publication.serverGeneration == null ||
            publication.serverGeneration! <= 0 ||
            publication.refreshEpoch != snapshot.refreshEpoch) {
          throw const IosVoipTokenException(
            IosVoipTokenErrorCode.authorityFailure,
          );
        }
        _publishedSnapshot = snapshot;
        _revokedEpochs.remove(snapshot.refreshEpoch);
        _relayRejectedEpochs.remove(snapshot.refreshEpoch);
        _invalidationPublished = false;
        if (prior != null && prior.refreshEpoch != snapshot.refreshEpoch) {
          // Set is authoritative first; the stale-epoch CAS can only remove the
          // prior generation and can never delete the just-published row.
          await _revokeEpoch(prior.refreshEpoch, bestEffort: true);
        }
        return true;
      } on CallAuthorityException catch (error) {
        if (error.isStaleEpoch && !epochAdvanced) {
          // The relay's refresh-epoch high-water refused this epoch (it
          // survives revokes). Move the native registration to a fresh epoch
          // once and re-publish the same token instead of failing closed.
          epochAdvanced = true;
          final advanced = await _advanceRefreshEpoch(snapshot);
          if (advanced != null) {
            snapshot = advanced;
            continue;
          }
        } else if (error.isStaleEpoch) {
          _reportEpochAdvance(IosVoipTokenEpochAdvanceOutcome.relayRejected);
        }
        await _failClosedAuthority(rejectedEpoch: snapshot.refreshEpoch);
        return false;
      } catch (_) {
        await _failClosedAuthority(rejectedEpoch: snapshot.refreshEpoch);
        return false;
      }
    }
  }

  /// Asks native for a strictly newer refresh epoch for the exact rejected
  /// registration. Any refusal, native failure, or non-monotonic answer
  /// yields null and the caller fails closed (retryable, never latched).
  Future<IosVoipTokenSnapshot?> _advanceRefreshEpoch(
    IosVoipTokenSnapshot rejected,
  ) async {
    _relayRejectedEpochs.add(rejected.refreshEpoch);
    Object? value;
    try {
      value = await _invokeMethod(advanceRefreshEpochMethod, <String, Object?>{
        'version': protocolVersion,
        'expectedRefreshEpoch': rejected.refreshEpoch,
        'diagnostics': ?CallDiagnostics.instance.contextForWire(
          reason: 'stale_epoch',
        ),
      });
    } catch (_) {
      _reportEpochAdvance(IosVoipTokenEpochAdvanceOutcome.nativeFailure);
      return null;
    }
    IosVoipTokenSnapshot advanced;
    try {
      advanced = IosVoipTokenSnapshot.parse(value);
    } catch (_) {
      _reportEpochAdvance(IosVoipTokenEpochAdvanceOutcome.refused);
      return null;
    }
    if (advanced.invalidated ||
        advanced.refreshEpoch <= rejected.refreshEpoch ||
        advanced.token != rejected.token ||
        !advanced.sameMetadata(rejected)) {
      _reportEpochAdvance(IosVoipTokenEpochAdvanceOutcome.refused);
      return null;
    }
    try {
      _acceptSnapshot(advanced);
    } catch (_) {
      _reportEpochAdvance(IosVoipTokenEpochAdvanceOutcome.refused);
      return null;
    }
    _reportEpochAdvance(IosVoipTokenEpochAdvanceOutcome.advanced);
    return advanced;
  }

  void _reportEpochAdvance(IosVoipTokenEpochAdvanceOutcome outcome) {
    if (!_epochAdvances.isClosed) _epochAdvances.add(outcome);
  }

  int _boundedExpiryMs() {
    final now = _clock().toUtc();
    return now.add(registrationTtl).millisecondsSinceEpoch;
  }

  Future<void> _revokeEpoch(int refreshEpoch, {bool bestEffort = false}) async {
    if (refreshEpoch <= 0 ||
        _revokedEpochs.contains(refreshEpoch) ||
        _relayRejectedEpochs.contains(refreshEpoch)) {
      return;
    }
    try {
      final revoked = await _authorityClient.revokeToken(
        CallTokenKind.iosVoip,
        refreshEpoch: refreshEpoch,
      );
      if (!revoked) {
        throw const IosVoipTokenException(
          IosVoipTokenErrorCode.authorityFailure,
        );
      }
      _revokedEpochs.add(refreshEpoch);
    } catch (_) {
      if (!bestEffort) rethrow;
    }
  }

  Future<void> _failClosedNative({
    String reason = 'native_snapshot_invalid',
  }) async {
    invalidationDiagnosticReason = reason;
    invalidationDiagnosticOperationId = CallDiagnostics.instance.beginOperation(
      reason: invalidationDiagnosticReason,
    );
    CallDiagnostics.instance.record(
      stage: 'authority',
      action: 'invalidate',
      outcome: 'failed',
      reason: invalidationDiagnosticReason,
      operationId: invalidationDiagnosticOperationId,
    );
    _invalid = true;
    _signalInitialSnapshotChange();
    await _revokeAndPublishInvalidation();
  }

  /// A relay rejection (or an unreachable relay) holds nothing for the
  /// attempted registration, so nothing is revoked and the coordinator stays
  /// retryable: the next publish re-sets the token. A CAS revoke here is
  /// what poisons the relay's refresh-epoch high-water and turns one rejected
  /// re-set into a permanent `CALL_STALE_EPOCH` loop for this epoch.
  Future<void> _failClosedAuthority({int? rejectedEpoch}) async {
    invalidationDiagnosticReason = 'authority_rejected';
    invalidationDiagnosticOperationId =
        CallDiagnostics.instance.currentOperationId ??
        CallDiagnostics.instance.beginOperation(
          reason: invalidationDiagnosticReason,
        );
    if (rejectedEpoch != null) {
      _relayRejectedEpochs.add(rejectedEpoch);
      if (_publishedSnapshot?.refreshEpoch == rejectedEpoch) {
        _publishedSnapshot = null;
      }
    }
    _signalInitialSnapshotChange();
    _publishInvalidation();
  }

  void _signalInitialSnapshotChange() {
    final changed = _initialSnapshotChanged;
    _initialSnapshotChanged = Completer<void>();
    if (!changed.isCompleted) {
      changed.complete();
    }
  }

  Future<void> _revokeAndPublishInvalidation() =>
      CallDiagnostics.instance.runWithOperation(
        invalidationDiagnosticOperationId,
        _revokeAndPublishInvalidationInOperation,
      );

  Future<void> _revokeAndPublishInvalidationInOperation() async {
    Object? error;
    StackTrace? stackTrace;
    try {
      await _revokeKnownEpoch();
    } catch (caught, caughtStack) {
      error = caught;
      stackTrace = caughtStack;
    }
    _publishInvalidation();
    if (error != null) Error.throwWithStackTrace(error, stackTrace!);
  }

  Future<void> _revokeKnownEpoch() async {
    final epoch = _publishedSnapshot?.refreshEpoch ?? _snapshot?.refreshEpoch;
    if (epoch != null && !_relayRejectedEpochs.contains(epoch)) {
      await _revokeEpoch(epoch);
    }
    _publishedSnapshot = null;
  }

  /// Withdraws the exact currently known iOS VoIP registration. Cleanup is
  /// intentionally independent of the publication/network gate so logout and
  /// account-migration teardown still perform the server-side CAS.
  Future<void> revokeForCallabilityRollback() =>
      _schedule<void>(_revokeKnownEpoch);

  void _publishInvalidation() {
    if (_invalidationPublished || _authorityInvalidations.isClosed) return;
    _invalidationPublished = true;
    _authorityInvalidations.add(null);
  }

  Future<T> _schedule<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then<void>((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> close() => _closeFuture ??= _closeOnce();

  Future<void> _closeOnce() async {
    if (_closed) return;
    _closed = true;
    _completeInitialStart(_IosVoipInitialStartKind.closed);
    _signalInitialSnapshotChange();
    final subscription = _nativeSubscription;
    _nativeSubscription = null;
    await subscription?.cancel();
    Object? error;
    StackTrace? stackTrace;
    try {
      await _tail;
      await _revokeKnownEpoch();
    } catch (caught, caughtStack) {
      error = caught;
      stackTrace = caughtStack;
    } finally {
      if (!_authorityInvalidations.isClosed) {
        await _authorityInvalidations.close();
      }
      if (!_epochAdvances.isClosed) {
        await _epochAdvances.close();
      }
    }
    if (error != null) Error.throwWithStackTrace(error, stackTrace!);
  }

  static Future<bool> _alwaysAllowed() async => true;

  static Future<void> _defaultInitialSnapshotTimeout(Duration timeout) =>
      Future<void>.delayed(timeout);
}
