import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/call/application/call_history_access.dart';
import 'package:flutter_app/features/call/application/call_redial_controller.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';

final _id = CallId.parse('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
final _otherId = CallId.parse('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
CallHistoryEntry _row(CallId id) => CallHistoryEntry(
  callId: id,
  contactAccountPeerId: 'synthetic-contact',
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
  @override
  Future<CallHistoryEntry?> findCall(CallId id) async =>
      row?.callId == id ? row : null;
  @override
  Future<List<CallHistoryEntry>> recentCallsForContact(String peerId) async =>
      latest ?? [?row];
}

class _Capability implements OutgoingCallCapability {
  bool available = true;
  bool contactAvailable = true;
  int lookups = 0;
  final starts = <String>[];
  OutgoingCallStartResult result = OutgoingCallStartResult.started;
  Completer<void>? pending;
  @override
  bool get isOutgoingCallAvailable => available;
  @override
  Stream<bool> get outgoingCallAvailabilityChanges => const Stream.empty();
  @override
  Future<bool> isOutgoingCallAvailableFor(String peerId) async {
    lookups++;
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
}
