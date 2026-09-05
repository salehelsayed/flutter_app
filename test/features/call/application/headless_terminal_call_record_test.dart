import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/headless_terminal_call_record.dart';
import 'package:flutter_app/features/call/application/missed_call_notifier.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';

/// 408: the killed-app path writes its row AND posts its card.
///
/// Plan 406 gave this path the history row but no notification, which is the
/// case where one matters most: there is no open app in which to notice the
/// call. The post must be AWAITED — the headless isolate tears down as soon as
/// the session finishes, and a fire-and-forget card would race that teardown.
void main() {
  const callerAccount = 'caller-account';
  const localAccount = 'local-account';

  CallSignal signal({
    required CallSignalType event,
    int createdAtMs = 1800000000000,
  }) => CallSignal.create(
    callId: CallId.parse('a2f0a1d6-0000-4000-8000-000000000408'),
    messageId: '44444444-4444-4444-8444-444444444444',
    event: event,
    senderAccountPeerId: callerAccount,
    senderDevicePeerId: 'caller-device',
    recipientAccountPeerId: localAccount,
    recipientDevicePeerId: 'local-device',
    senderSequence: event == CallSignalType.invite ? 1 : 2,
    iceGeneration: 0,
    createdAtMs: createdAtMs,
    expiresAtMs: createdAtMs + 40000,
    payload: event == CallSignalType.invite
        ? const <String, Object?>{
            'capabilities': <Object?>['audio'],
            'metadata': <String, Object?>{'media': 'audio', 'video': false},
          }
        : const <String, Object?>{'reason': 'caller_cancelled'},
  );

  ({List<String> posted, MissedCallNotifier notifier}) buildNotifier({
    Completer<void>? gate,
    Object? error,
  }) {
    final posted = <String>[];
    return (
      posted: posted,
      notifier: MissedCallNotifier(
        post:
            ({
              required String contactAccountPeerId,
              required String title,
              required String body,
            }) async {
              if (gate != null) await gate.future;
              if (error != null) throw error;
              posted.add('$title|$body');
            },
        resolveContactName: (_) async => 'Alice',
        isSuppressed: (_) async => false,
        missedBody: 'Missed voice call',
        unknownCallerTitle: 'Someone',
      ),
    );
  }

  test('TC-408-10 a new killed-app terminal call projects a row and posts a '
      'card', () async {
    final repository = _Repository();
    final rig = buildNotifier();

    await recordHeadlessTerminalCall(
      repository: repository,
      projector: CallHistoryProjector(repository),
      notifier: rig.notifier,
      terminal: signal(event: CallSignalType.terminate),
      reason: CallEndReason.callerCancelled,
      invite: signal(event: CallSignalType.invite),
    );

    expect(repository.rows, hasLength(1));
    final row = repository.rows.single;
    expect(row.direction, CallDirection.incoming);
    expect(row.status, CallHistoryStatus.cancelled);
    expect(row.contactAccountPeerId, callerAccount);
    expect(rig.posted, <String>['Alice|Missed voice call']);
  });

  test(
    'TC-408-11 a replayed call adds no row and posts no second card',
    () async {
      final repository = _Repository();
      final projector = CallHistoryProjector(repository);
      final rig = buildNotifier();

      for (var i = 0; i < 2; i++) {
        await recordHeadlessTerminalCall(
          repository: repository,
          projector: projector,
          notifier: rig.notifier,
          terminal: signal(event: CallSignalType.terminate),
          reason: CallEndReason.callerCancelled,
          invite: signal(event: CallSignalType.invite),
        );
      }

      expect(repository.rows, hasLength(1));
      expect(
        rig.posted,
        hasLength(1),
        reason: 'the user was already told the first time',
      );
    },
  );

  test(
    'TC-408-12 the card is awaited, so the isolate cannot tear down first',
    () async {
      final repository = _Repository();
      final gate = Completer<void>();
      final rig = buildNotifier(gate: gate);

      var finished = false;
      unawaited(
        recordHeadlessTerminalCall(
          repository: repository,
          projector: CallHistoryProjector(repository),
          notifier: rig.notifier,
          terminal: signal(event: CallSignalType.terminate),
          reason: CallEndReason.callerCancelled,
        ).then((_) => finished = true),
      );
      await Future<void>.delayed(Duration.zero);

      expect(finished, isFalse, reason: 'still waiting on the post');
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isTrue);
    },
  );

  test('TC-408-13 a failing card never loses the row', () async {
    final repository = _Repository();
    final rig = buildNotifier(error: StateError('no notification service'));

    await recordHeadlessTerminalCall(
      repository: repository,
      projector: CallHistoryProjector(repository),
      notifier: rig.notifier,
      terminal: signal(event: CallSignalType.terminate),
      reason: CallEndReason.callerCancelled,
    );

    expect(repository.rows, hasLength(1));
  });

  test(
    'TC-408-14 a terminal row that predates its invite still constructs',
    () async {
      final repository = _Repository();
      final rig = buildNotifier();

      await recordHeadlessTerminalCall(
        repository: repository,
        projector: CallHistoryProjector(repository),
        notifier: rig.notifier,
        // A clock skew between devices can put the terminate BEFORE the invite;
        // CallHistoryEntry refuses a non-monotonic pair.
        terminal: signal(
          event: CallSignalType.terminate,
          createdAtMs: 1800000000000,
        ),
        reason: CallEndReason.callerCancelled,
        invite: signal(
          event: CallSignalType.invite,
          createdAtMs: 1800000005000,
        ),
      );

      expect(repository.rows, hasLength(1));
      final row = repository.rows.single;
      expect(row.endedAt.isBefore(row.startedAt), isFalse);
    },
  );
}

final class _Repository implements CallHistoryRepository {
  final rows = <CallHistoryEntry>[];

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async =>
      rows.where((row) => row.callId == callId).firstOrNull;

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async => rows
      .where((row) => row.contactAccountPeerId == peerId)
      .toList(growable: false);

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    if (rows.any((row) => row.callId == entry.callId)) return;
    rows.add(entry);
  }
}
