import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/call/application/missed_call_notifier.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';

/// 406: a call the user never took must leave a notification.
///
/// Neither OS supplies one. Android runs self-managed Telecom, which never
/// writes the system call log and posts nothing; iOS CallKit reports the
/// remote cancel as `.remoteEnded`, which is an ordinary ended call in
/// Recents, not a missed one. Only the app can tell the user.
void main() {
  const contactPeerId = '12D3KooWTestPeerId1234567890';

  CallHistoryEntry entry({
    CallDirection direction = CallDirection.incoming,
    CallHistoryStatus status = CallHistoryStatus.missed,
    CallEndReason reason = CallEndReason.callerCancelled,
    String id = '1',
  }) {
    final startedAt = DateTime.utc(2026, 2, 9, 15, 30);
    return CallHistoryEntry(
      callId: CallId.parse('a2f0a1d6-0000-4000-8000-00000000000$id'),
      contactAccountPeerId: contactPeerId,
      direction: direction,
      terminalReason: reason,
      status: status,
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(seconds: 20)),
      transportRoute: null,
      createdAt: startedAt,
      updatedAt: startedAt,
    );
  }

  ({MissedCallNotifier notifier, List<Map<String, String>> posted}) build({
    String? contactName = 'Alice',
    bool suppressed = false,
    Object? postError,
    Object? nameError,
  }) {
    final posted = <Map<String, String>>[];
    final notifier = MissedCallNotifier(
      post:
          ({
            required String contactAccountPeerId,
            required String title,
            required String body,
          }) async {
            if (postError != null) throw postError;
            posted.add({
              'contact': contactAccountPeerId,
              'title': title,
              'body': body,
            });
          },
      resolveContactName: (peerId) async {
        if (nameError != null) throw nameError;
        return contactName;
      },
      isSuppressed: (peerId) async => suppressed,
      missedBody: 'Missed voice call',
      unknownCallerTitle: 'Someone',
    );
    return (notifier: notifier, posted: posted);
  }

  test(
    'TC-406-01 a missed incoming call notifies with the caller name',
    () async {
      final rig = build();

      final posted = await rig.notifier.notifyTerminal(entry(), inserted: true);

      expect(posted, isTrue);
      expect(rig.posted, hasLength(1));
      expect(rig.posted.single['contact'], contactPeerId);
      expect(rig.posted.single['title'], 'Alice');
      expect(rig.posted.single['body'], 'Missed voice call');
    },
  );

  test(
    'TC-406-02 a cancelled incoming call is a missed call to the callee',
    () async {
      final rig = build();

      final posted = await rig.notifier.notifyTerminal(
        entry(status: CallHistoryStatus.cancelled),
        inserted: true,
      );

      expect(posted, isTrue);
    },
  );

  test('TC-406-03 a busy incoming call notifies too', () async {
    final rig = build();

    expect(
      await rig.notifier.notifyTerminal(
        entry(status: CallHistoryStatus.busy, reason: CallEndReason.busy),
        inserted: true,
      ),
      isTrue,
    );
  });

  test('TC-406-04 a call the user acted on never notifies', () async {
    for (final status in const [
      CallHistoryStatus.completed,
      CallHistoryStatus.declined,
      CallHistoryStatus.failed,
    ]) {
      final rig = build();
      expect(
        await rig.notifier.notifyTerminal(
          entry(status: status, reason: CallEndReason.declined),
          inserted: true,
        ),
        isFalse,
        reason: '$status is not a missed call',
      );
      expect(rig.posted, isEmpty);
    }
  });

  test('TC-406-05 an outgoing call never notifies the caller', () async {
    final rig = build();

    expect(
      await rig.notifier.notifyTerminal(
        entry(direction: CallDirection.outgoing),
        inserted: true,
      ),
      isFalse,
    );
    expect(rig.posted, isEmpty);
  });

  test('TC-406-06 a replayed projection never notifies twice', () async {
    final rig = build();

    expect(
      await rig.notifier.notifyTerminal(entry(), inserted: false),
      isFalse,
      reason: 'the row was already stored; the user was told the first time',
    );
    expect(rig.posted, isEmpty);
  });

  test(
    'TC-406-07 a visible conversation suppresses the notification',
    () async {
      final rig = build(suppressed: true);

      expect(
        await rig.notifier.notifyTerminal(entry(), inserted: true),
        isFalse,
      );
      expect(
        rig.posted,
        isEmpty,
        reason: 'the row appears live in the open chat; a card would be noise',
      );
    },
  );

  test('TC-406-08 an unknown caller still gets a notification', () async {
    final rig = build(contactName: null);

    expect(await rig.notifier.notifyTerminal(entry(), inserted: true), isTrue);
    expect(rig.posted.single['title'], 'Someone');
    expect(rig.posted.single['body'], 'Missed voice call');
  });

  test('TC-406-09 a failing name lookup still notifies', () async {
    final rig = build(nameError: StateError('contacts unavailable'));

    expect(await rig.notifier.notifyTerminal(entry(), inserted: true), isTrue);
    expect(rig.posted.single['title'], 'Someone');
  });

  test('TC-406-10 a failing post never throws into the call path', () async {
    final rig = build(postError: StateError('notifications unavailable'));

    expect(await rig.notifier.notifyTerminal(entry(), inserted: true), isFalse);
  });
}
