import 'package:flutter_app/core/database/helpers/group_exit_intents_db_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

final _createdAt = DateTime.utc(2026, 7, 21, 8);
final _joinedAt = DateTime.utc(2026, 7, 21, 8, 1);
final _eventAt = DateTime.utc(2026, 7, 21, 8, 3);

GroupExitIntent _intent({
  GroupExitIntentState state = GroupExitIntentState.queued,
  int revision = 0,
  String? sourceEventId,
  DateTime? eventAt,
}) => GroupExitIntent(
  groupId: 'group-1',
  intentId: 'intent-1',
  selfPeerId: 'peer-self',
  selfJoinedAt: _joinedAt,
  state: state,
  pendingBroadcastId: 'leave-outbox-1',
  sourceEventId: sourceEventId,
  eventAt: eventAt,
  revision: revision,
  createdAt: _createdAt,
  updatedAt: _createdAt,
);

DbGroupExitIntentMutationResult _committed(Map<String, Object?>? current) =>
    DbGroupExitIntentMutationResult(
      disposition: DbGroupExitIntentMutationDisposition.committed,
      current: current,
    );

void main() {
  test(
    'typed repository round-trips state and maps every compound storage payload exactly',
    () async {
      final queued = _intent();
      Map<String, Object?>? enqueued;
      Map<String, Object?>? preparedExpected;
      Map<String, Object?>? preparedTimeline;
      Map<String, Object?>? preparedPending;
      String? preparedUpdatedAt;
      String? advancedState;
      String? advancedError;
      var terminalizedGroup = '';

      final repository = GroupExitIntentRepositoryImpl(
        dbLoadForGroup: (groupId) async => queued.toMap(),
        dbLoadAll: () async => <Map<String, Object?>>[queued.toMap()],
        dbEnqueue: (row) async {
          enqueued = row;
          return _committed(row);
        },
        dbCancelQueued: ({required expected, required updatedAt}) async {
          return _committed(null);
        },
        dbPrepareLeaveNotice:
            ({
              required expected,
              required timelineRow,
              required pendingBroadcastRow,
              required updatedAt,
            }) async {
              preparedExpected = expected;
              preparedTimeline = timelineRow;
              preparedPending = pendingBroadcastRow;
              preparedUpdatedAt = updatedAt;
              return _committed(<String, Object?>{
                ...expected,
                'state': 'leave_notice_pending',
                'source_event_id': pendingBroadcastRow['source_message_id'],
                'event_at': pendingBroadcastRow['event_at'],
                'revision': 1,
                'updated_at': updatedAt,
              });
            },
        dbCompleteLeaveNoticeAttempt:
            ({
              required expected,
              required pendingBroadcastRow,
              required completionCode,
              required updatedAt,
            }) async => _committed(<String, Object?>{
              ...expected,
              'state': 'leave_notice_attempted',
              'revision': (expected['revision'] as int) + 1,
              'last_error_code': completionCode,
              'updated_at': updatedAt,
            }),
        dbAdvance:
            ({
              required expected,
              required nextState,
              required updatedAt,
              lastErrorCode,
            }) async {
              advancedState = nextState;
              advancedError = lastErrorCode;
              return _committed(<String, Object?>{
                ...expected,
                'state': nextState,
                'revision': (expected['revision'] as int) + 1,
                'last_error_code': lastErrorCode,
                'updated_at': updatedAt,
              });
            },
        dbCleanupOrRetire: ({required expected, required updatedAt}) async {
          return _committed(null);
        },
        dbRetireExact: (expected) async => _committed(null),
        dbTerminalizeForGroup: (groupId) async {
          terminalizedGroup = groupId;
          return 1;
        },
      );

      expect(
        (await repository.forGroup('group-1'))!.state,
        GroupExitIntentState.queued,
      );
      expect(await repository.all(), hasLength(1));
      expect((await repository.enqueue(queued)).committed, isTrue);
      expect(enqueued, queued.toMap());

      final timeline = GroupMessage(
        id: 'timeline-1',
        groupId: 'group-1',
        senderPeerId: 'peer-self',
        text: '{"__sys":"member_removed"}',
        timestamp: _eventAt,
        isIncoming: false,
        createdAt: _createdAt,
      );
      final pending = GroupPendingBroadcast(
        id: 'leave-outbox-1',
        groupId: 'group-1',
        kind: groupPendingBroadcastKindExitLeaveNotice,
        sysText: '{"signed":true}',
        recipientPeerIds: const ['peer-other'],
        eventAt: _eventAt,
        sourceMessageId: 'source-1',
        createdAt: _createdAt,
        updatedAt: _createdAt,
      );
      final prepared = await repository.prepareLeaveNotice(
        expected: queued,
        timelineMessage: timeline,
        pendingBroadcast: pending,
        updatedAt: _eventAt,
      );
      expect(prepared.committed, isTrue);
      expect(prepared.current!.state, GroupExitIntentState.leaveNoticePending);
      expect(prepared.current!.sourceEventId, 'source-1');
      expect(preparedExpected, queued.toMap());
      expect(preparedTimeline, timeline.toMap());
      expect(preparedPending, pending.toMap());
      expect(preparedUpdatedAt, _eventAt.toIso8601String());

      final completed = await repository.completeLeaveNoticeAttempt(
        expected: prepared.current!,
        pendingBroadcast: pending,
        completionCode: 'delivered',
        updatedAt: _eventAt.add(const Duration(minutes: 1)),
      );
      expect(
        completed.current!.state,
        GroupExitIntentState.leaveNoticeAttempted,
      );
      expect(completed.current!.lastErrorCode, 'delivered');

      final advanced = await repository.advance(
        expected: completed.current!,
        nextState: GroupExitIntentState.rotationClaimed,
        updatedAt: _eventAt.add(const Duration(minutes: 2)),
        lastErrorCode: 'rotation_deferred',
      );
      expect(advanced.current!.state, GroupExitIntentState.rotationClaimed);
      expect(advancedState, 'rotation_claimed');
      expect(advancedError, 'rotation_deferred');
      expect(advanced.current!.preventsRejoin, isTrue);

      expect(await repository.terminalizeForGroup('group-1'), 1);
      expect(terminalizedGroup, 'group-1');
    },
  );

  test('unknown persisted state fails closed', () {
    final row = _intent().toMap()..['state'] = 'future_state';
    expect(() => GroupExitIntent.fromMap(row), throwsFormatException);
  });
}
