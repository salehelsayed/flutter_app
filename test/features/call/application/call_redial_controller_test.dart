import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_history_access.dart';
import 'package:flutter_app/features/call/application/call_redial_controller.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';

final _id = CallId.parse('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
final _otherId = CallId.parse('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
CallHistoryEntry _row(CallId id, {String peer = 'synthetic-contact'}) =>
    CallHistoryEntry(
      callId: id,
      contactAccountPeerId: peer,
      direction: CallDirection.incoming,
      terminalReason: CallEndReason.noAnswer,
      status: CallHistoryStatus.missed,
      startedAt: DateTime.utc(2026, 10, 13),
      endedAt: DateTime.utc(2026, 10, 13, 0, 0, 30),
      connectedAt: null,
      transportRoute: null,
      createdAt: DateTime.utc(2026, 10, 13),
      updatedAt: DateTime.utc(2026, 10, 13),
    );

class _History implements CallHistoryAccess {
  CallHistoryEntry? row = _row(_id);
  List<CallHistoryEntry>? latest;
  Map<CallId, CallHistoryEntry>? rows;
  Future<void> Function(String)? beforeRead;
  @override
  Future<CallHistoryEntry?> findCall(CallId id) async {
    await beforeRead?.call('history');
    return rows != null
        ? rows![id]
        : row?.callId == id
        ? row
        : null;
  }

  @override
  Future<List<CallHistoryEntry>> recentCallsForContact(String peerId) async {
    await beforeRead?.call('recent-history');
    return latest ??
        (rows?.values.where((r) => r.contactAccountPeerId == peerId).toList() ??
            [?row]);
  }
}

class _Capability implements OutgoingCallCapability {
  bool available = true;
  bool contactAvailable = true;
  int lookups = 0;
  final starts = <String>[];
  OutgoingCallStartResult result = OutgoingCallStartResult.started;
  Completer<void>? pending;
  Future<void> Function(String)? beforeLookup;
  @override
  bool get isOutgoingCallAvailable => available;
  @override
  Stream<bool> get outgoingCallAvailabilityChanges => const Stream.empty();
  @override
  Future<bool> isOutgoingCallAvailableFor(String peerId) async {
    lookups++;
    await beforeLookup?.call('endpoint-lookup');
    return contactAvailable;
  }

  @override
  Future<OutgoingCallStartResult> startOutgoingCall(
    String peerId, {
    OutgoingCallStartRequest? request,
  }) async {
    request?.checkPending();
    starts.add(peerId);
    await pending?.future;
    return result;
  }
}

class _TerminalRepository implements CallHistoryRepository {
  final rows = <CallId, CallHistoryEntry>{};
  @override
  Future<CallHistoryEntry?> getByCallId(CallId id) async => rows[id];
  @override
  Future<List<CallHistoryEntry>> listForContact(String peer) async =>
      rows.values.where((r) => r.contactAccountPeerId == peer).toList();
  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    rows.putIfAbsent(entry.callId, () => entry);
  }
}

/// Uses the actual coordinator admission predicate/onApplied transfer, just as
/// ProductionCallSignalingGraph does. No call/media runtime is launched.
class _CanonicalCapability extends _Capability {
  _CanonicalCapability() {
    coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(const []),
      historyProjector: CallHistoryProjector(_TerminalRepository()),
      clock: () => DateTime.utc(2026, 10, 13),
      idSource: () => CallId.parse(
        'cccccccc-cccc-4ccc-8ccc-${(++ids).toString().padLeft(12, '0')}',
      ),
    );
  }
  late final CallCoordinator coordinator;
  int ids = 0;
  Future<void> Function(String)? beforeAdmission;
  Completer<void>? afterAdmission;
  final admitted = Completer<void>();
  final requests = <OutgoingCallStartRequest>[];
  @override
  Future<OutgoingCallStartResult> startOutgoingCall(
    String peerId, {
    OutgoingCallStartRequest? request,
  }) async {
    if (request != null) {
      requests.add(request);
    }
    await beforeAdmission?.call('outgoing-preflight');
    request?.checkPending();
    final reduction = await coordinator.placeCall(
      contactPeerId: peerId,
      localAccountPeerId: 'synthetic-local',
      localDeviceId: 'synthetic-device',
      canPlace: () => request?.isCanceled != true,
      onApplied: (reduction) {
        if (reduction.decision == CallEventDecision.applied) {
          request?.admit();
          starts.add(peerId);
          if (!admitted.isCompleted) admitted.complete();
        }
      },
    );
    if (reduction.decision != CallEventDecision.applied) {
      return OutgoingCallStartResult.unavailable;
    }
    await afterAdmission?.future;
    return OutgoingCallStartResult.started;
  }
}

class _Barrier {
  _Barrier(this.stage);
  final String stage;
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<void> hold(String current) async {
    if (current != stage || entered.isCompleted) return;
    entered.complete();
    await release.future;
  }
}

void main() {
  late _Capability owner;
  late _History history;
  late CallRedialController redial;
  late CallBackActionHandler actions;
  late List<OutgoingCallStartResult> results;
  bool ready = true;
  bool contactAllowed = true;
  setUp(() {
    owner = _Capability();
    history = _History();
    ready = true;
    contactAllowed = true;
    results = [];
    redial = CallRedialController(
      capability: () => owner,
      contactAllowed: (_) async => contactAllowed,
    );
    actions = CallBackActionHandler(
      history: () => history,
      ready: () async => ready,
      redial: redial,
      onResult: results.add,
    );
  });
  test(
    'current local history resolves the contact and creates a fresh outgoing request',
    () async {
      await actions.submit(_id);
      expect(owner.starts, ['synthetic-contact']);
      expect(owner.lookups, 1);
      expect(results, [OutgoingCallStartResult.started]);
    },
  );
  for (final policy in ['deleted', 'blocked']) {
    test(
      '$policy contact refuses redial before authenticated lookup',
      () async {
        contactAllowed = false;
        await actions.submit(_id);
        expect(owner.starts, isEmpty);
        expect(owner.lookups, 0);
        expect(results, [OutgoingCallStartResult.unavailable]);
      },
    );
  }
  for (final policy in ['unaccepted', 'unsupported']) {
    test('$policy current endpoint refuses redial', () async {
      owner.contactAvailable = false;
      await actions.submit(_id);
      expect(owner.starts, isEmpty);
      expect(owner.lookups, 1);
    });
  }
  for (final outcome in [
    OutgoingCallStartResult.microphoneDenied,
    OutgoingCallStartResult.failed,
    OutgoingCallStartResult.unavailable,
  ]) {
    test('outgoing preflight preserves ${outcome.name}', () async {
      owner.result = outcome;
      await actions.submit(_id);
      expect(results, [outcome]);
    });
  }
  test(
    'cold callback waits for canonical runtime readiness and unlock',
    () async {
      ready = false;
      await actions.submit(_id);
      expect(owner.starts, isEmpty);
      ready = true;
      await actions.retryPending();
      expect(owner.starts, hasLength(1));
    },
  );
  test(
    'duplicate in-flight and completed actions do not double dial',
    () async {
      owner.pending = Completer();
      final first = actions.submit(_id);
      await Future<void>.delayed(Duration.zero);
      final duplicate = actions.submit(_id);
      owner.pending!.complete();
      await first;
      await duplicate;
      await actions.submit(_id);
      expect(owner.starts, hasLength(1));
    },
  );
  test(
    'superseded notification and forged absent local call id refuse',
    () async {
      history.latest = [_row(_otherId), _row(_id)];
      await actions.submit(_id);
      await actions.submit(_otherId);
      expect(owner.starts, isEmpty);
      expect(results, everyElement(OutgoingCallStartResult.unavailable));
    },
  );
  test(
    'duplicate callback while history is pending keeps its valid generation',
    () async {
      final gate = _Barrier('history');
      history.beforeRead = gate.hold;
      final first = actions.submit(_id);
      await gate.entered.future;
      final duplicate = actions.submit(_id);
      gate.release.complete();
      await Future.wait([first, duplicate]);
      expect(owner.starts, hasLength(1));
      expect(results, [OutgoingCallStartResult.started]);
    },
  );

  for (final stage in [
    'startup-readiness',
    'history',
    'recent-history',
    'unlock-readiness',
    'contact-policy',
    'endpoint-lookup',
    'outgoing-preflight',
  ]) {
    test(
      'new callback supersedes A at $stage before canonical admission',
      () async {
        final canonical = _CanonicalCapability();
        addTearDown(canonical.coordinator.dispose);
        final gate = _Barrier(stage);
        history.rows = {
          _id: _row(_id, peer: 'contact-a'),
          _otherId: _row(_otherId, peer: 'contact-b'),
        };
        history.beforeRead = gate.hold;
        canonical.beforeLookup = gate.hold;
        canonical.beforeAdmission = gate.hold;
        var readyCalls = 0;
        final observations = <(CallBackActionObservation, CallId)>[];
        final handler = CallBackActionHandler(
          history: () => history,
          ready: () async {
            await gate.hold(
              ++readyCalls == 1 ? 'startup-readiness' : 'unlock-readiness',
            );
            return true;
          },
          redial: CallRedialController(
            capability: () => canonical,
            contactAllowed: (_) async {
              await gate.hold('contact-policy');
              return true;
            },
          ),
          onResult: results.add,
          observe: (event, id, _) => observations.add((event, id)),
        );
        final a = handler.submit(_id);
        await gate.entered.future;
        final b = handler.submit(_otherId);
        gate.release.complete();
        await Future.wait([a, b]);
        expect(canonical.starts, ['contact-b']);
        expect(canonical.coordinator.activeSession?.contactPeerId, 'contact-b');
        expect(
          canonical.coordinator.activeSession?.callId,
          isNot(anyOf(_id, _otherId)),
        );
        expect(canonical.requests.where((r) => r.isAdmitted), hasLength(1));
        expect(
          observations
              .where((e) => e.$1 == CallBackActionObservation.submitted)
              .map((e) => e.$2),
          [_id, _otherId],
        );
        if (stage == 'startup-readiness' || stage == 'unlock-readiness') {
          expect(
            observations
                .where((e) => e.$1 == CallBackActionObservation.redialRequested)
                .map((e) => e.$2),
            [_otherId],
          );
        }
        await handler.submit(_id);
        await handler.submit(_otherId);
        expect(canonical.starts, hasLength(1));
      },
    );
  }

  test(
    'a failing read-only observer cannot change callback admission',
    () async {
      final handler = CallBackActionHandler(
        history: () => history,
        ready: () async => true,
        redial: redial,
        onResult: results.add,
        observe: (_, _, _) => throw StateError('diagnostic sink failed'),
      );
      await handler.submit(_id);
      expect(owner.starts, ['synthetic-contact']);
      expect(results, [OutgoingCallStartResult.started]);
    },
  );

  for (final stage in ['unlock-readiness', 'endpoint-lookup']) {
    test(
      'local history superseded during $stage refuses before admission',
      () async {
        final canonical = _CanonicalCapability();
        addTearDown(canonical.coordinator.dispose);
        final gate = _Barrier(stage);
        canonical.beforeLookup = gate.hold;
        var checks = 0;
        final handler = CallBackActionHandler(
          history: () => history,
          ready: () async {
            if (++checks == 2) await gate.hold('unlock-readiness');
            return true;
          },
          redial: CallRedialController(
            capability: () => canonical,
            contactAllowed: (_) async => true,
          ),
          onResult: results.add,
        );
        final a = handler.submit(_id);
        await gate.entered.future;
        history.latest = [_row(_otherId), _row(_id)];
        gate.release.complete();
        await a;
        expect(canonical.starts, isEmpty);
        expect(canonical.coordinator.activeSession, isNull);
        expect(results, [OutgoingCallStartResult.unavailable]);
      },
    );
  }

  test(
    'callback B after admission cannot cancel A or bypass canonical busy',
    () async {
      final canonical = _CanonicalCapability()
        ..afterAdmission = Completer<void>();
      addTearDown(canonical.coordinator.dispose);
      history.rows = {
        _id: _row(_id, peer: 'contact-a'),
        _otherId: _row(_otherId, peer: 'contact-b'),
      };
      final handler = CallBackActionHandler(
        history: () => history,
        ready: () async => true,
        redial: CallRedialController(
          capability: () => canonical,
          contactAllowed: (_) async => true,
        ),
        onResult: results.add,
      );
      final a = handler.submit(_id);
      await canonical.admitted.future;
      final session = canonical.coordinator.activeSession!;
      final b = handler.submit(_otherId);
      expect(canonical.requests.single.isAdmitted, isTrue);
      expect(canonical.requests.single.isCanceled, isFalse);
      canonical.afterAdmission!.complete();
      await Future.wait([a, b]);
      expect(canonical.starts, ['contact-a']);
      expect(canonical.coordinator.activeSession?.callId, session.callId);
      expect(canonical.coordinator.activeSession?.isTerminal, isFalse);
      expect(results, [
        OutgoingCallStartResult.started,
        OutgoingCallStartResult.unavailable,
      ]);
    },
  );

  test(
    'timeout fences late preflight and releases a current callback with fake time',
    () {
      fakeAsync((time) {
        final gate = _Barrier('contact-policy');
        final canonical = _CanonicalCapability();
        history.rows = {
          _id: _row(_id, peer: 'contact-a'),
          _otherId: _row(_otherId, peer: 'contact-b'),
        };
        final handler = CallBackActionHandler(
          history: () => history,
          ready: () async => true,
          redial: CallRedialController(
            capability: () => canonical,
            timeout: const Duration(seconds: 12),
            contactAllowed: (_) async {
              await gate.hold('contact-policy');
              return true;
            },
          ),
          onResult: results.add,
        );
        var done = false;
        unawaited(handler.submit(_id).then((_) => done = true));
        time.flushMicrotasks();
        expect(gate.entered.isCompleted, isTrue);
        time.elapse(const Duration(seconds: 12));
        time.flushMicrotasks();
        expect(done, isTrue);
        expect(results, [OutgoingCallStartResult.failed]);
        unawaited(handler.submit(_otherId));
        time.flushMicrotasks();
        gate.release.complete();
        time.flushMicrotasks();
        expect(canonical.starts, ['contact-b']);
        expect(canonical.requests.where((r) => r.isAdmitted), hasLength(1));
        unawaited(canonical.coordinator.dispose());
        time.flushMicrotasks();
      });
    },
  );

  test(
    'expired preflight cannot start later or hold the next action busy',
    () async {
      final allow = Completer<bool>();
      final bounded = CallRedialController(
        capability: () => owner,
        contactAllowed: (_) => allow.future,
        timeout: const Duration(milliseconds: 5),
      );
      expect(
        await bounded.start('synthetic-contact'),
        OutgoingCallStartResult.failed,
      );
      allow.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(owner.starts, isEmpty);
    },
  );

  for (final lateResult in ['timeout', 'error']) {
    test('superseded callback reports cancellation for late $lateResult', () {
      fakeAsync((time) {
        final canonical = _CanonicalCapability();
        final allowA = Completer<bool>();
        history.rows = {
          _id: _row(_id, peer: 'contact-a'),
          _otherId: _row(_otherId, peer: 'contact-b'),
        };
        final handler = CallBackActionHandler(
          history: () => history,
          ready: () async => true,
          redial: CallRedialController(
            capability: () => canonical,
            contactAllowed: (peer) =>
                peer == 'contact-a' ? allowA.future : Future<bool>.value(true),
          ),
          onResult: results.add,
        );
        unawaited(handler.submit(_id));
        time.flushMicrotasks();
        expect(canonical.starts, isEmpty);
        unawaited(handler.submit(_otherId));
        time.flushMicrotasks();
        if (lateResult == 'timeout') {
          time.elapse(const Duration(seconds: 12));
          time.flushMicrotasks();
          allowA.complete(true);
        } else {
          allowA.completeError(StateError('synthetic preflight failure'));
        }
        time.flushMicrotasks();
        expect(canonical.starts, ['contact-b']);
        expect(results, [
          OutgoingCallStartResult.canceled,
          OutgoingCallStartResult.started,
        ]);
        expect(canonical.requests.where((r) => r.isAdmitted), hasLength(1));
        unawaited(canonical.coordinator.dispose());
        time.flushMicrotasks();
      });
    });
  }
}
