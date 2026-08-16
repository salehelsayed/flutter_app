import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const message = BackgroundGroupMessageNotificationComparand(
    groupId: 'group-a',
    messageId: 'message-a',
    senderPeerId: 'peer-alice',
  );
  const reaction = BackgroundGroupReactionNotificationComparand(
    groupId: 'group-a',
    reactionId: 'reaction-a',
    messageId: 'target-a',
    senderPeerId: 'peer-alice',
    timestamp: '2026-08-03T01:00:00.000Z',
    notificationEventIdentity: 'bounded-event-a',
  );
  const provisionalReaction =
      BackgroundProvisionalGroupReactionNotificationComparand(
        groupId: 'group-a',
        messageId: 'target-a',
        senderPeerId: 'peer-alice',
        notificationEventIdentity: 'bounded-event-a',
      );
  const laterReaction = BackgroundGroupReactionNotificationComparand(
    groupId: 'group-a',
    reactionId: 'reaction-b',
    messageId: 'target-a',
    senderPeerId: 'peer-alice',
    timestamp: '2026-08-03T01:00:02.000Z',
    notificationEventIdentity: 'bounded-event-b',
  );
  const laterProvisionalReaction =
      BackgroundProvisionalGroupReactionNotificationComparand(
        groupId: 'group-a',
        messageId: 'target-a',
        senderPeerId: 'peer-alice',
        notificationEventIdentity: 'bounded-event-b',
      );
  final group = <String, Object?>{
    'id': 'group-a',
    'type': 'chat',
    'is_muted': 0,
    'is_archived': 0,
    'is_dissolved': 0,
    'dissolved_at': null,
    'self_removed_at': null,
  };
  final selfMember = <String, Object?>{
    'group_id': 'group-a',
    'peer_id': 'peer-self',
  };
  final target = <String, Object?>{
    'id': 'target-a',
    'group_id': 'group-a',
    'sender_peer_id': 'peer-self',
    'is_incoming': 0,
  };

  BackgroundGroupNotificationPostShowDecision evaluateMessage({
    Map<String, Object?>? groupRow,
    Map<String, Object?>? messageRow,
    Map<String, Object?>? deletionRow,
    Map<String, Object?>? readAcknowledgementRow,
  }) => evaluateBackgroundGroupNotificationPostShowState(
    comparand: message,
    localPeerId: 'peer-self',
    groupRow: groupRow ?? group,
    localMemberRow: selfMember,
    messageRow: messageRow,
    messageDeletionRow: deletionRow,
    readAcknowledgementRow: readAcknowledgementRow,
  );

  BackgroundGroupNotificationPostShowDecision evaluateReaction({
    Map<String, Object?>? reactionRow,
    Map<String, Object?>? targetRow,
    Map<String, Object?>? deletionRow,
    Map<String, Object?>? readAcknowledgementRow,
  }) => evaluateBackgroundGroupNotificationPostShowState(
    comparand: reaction,
    localPeerId: 'peer-self',
    groupRow: group,
    localMemberRow: selfMember,
    reactionRow: reactionRow,
    targetMessageRow: targetRow ?? target,
    targetDeletionRow: deletionRow,
    readAcknowledgementRow: readAcknowledgementRow,
  );

  BackgroundGroupNotificationPostShowDecision evaluateProvisionalReaction({
    Map<String, Object?>? groupRow,
    Map<String, Object?>? reactionRow,
    Map<String, Object?>? targetRow,
    Map<String, Object?>? deletionRow,
    Map<String, Object?>? readAcknowledgementRow,
    bool targetAbsent = false,
  }) => evaluateBackgroundGroupNotificationPostShowState(
    comparand: provisionalReaction,
    localPeerId: 'peer-self',
    groupRow: groupRow ?? group,
    localMemberRow: selfMember,
    reactionRow: reactionRow,
    targetMessageRow: targetAbsent ? null : (targetRow ?? target),
    targetDeletionRow: deletionRow,
    readAcknowledgementRow: readAcknowledgementRow,
  );

  test('policy flip after show is terminal', () {
    expect(
      evaluateMessage(groupRow: <String, Object?>{...group, 'is_muted': 1}),
      BackgroundGroupNotificationPostShowDecision.retire,
    );
  });

  test('exact message deletion tombstone retires an absent inbox row', () {
    expect(
      evaluateMessage(
        deletionRow: const <String, Object?>{
          'message_id': 'message-a',
          'group_id': 'group-a',
        },
      ),
      BackgroundGroupNotificationPostShowDecision.retire,
    );
  });

  test('push-before-inbox message absence remains unknown and is kept', () {
    expect(
      evaluateMessage(),
      BackgroundGroupNotificationPostShowDecision.unknown,
    );
  });

  test('exact unread authorized incoming message remains visible', () {
    expect(
      evaluateMessage(
        messageRow: const <String, Object?>{
          'id': 'message-a',
          'group_id': 'group-a',
          'sender_peer_id': 'peer-alice',
          'is_incoming': 1,
          'read_at': null,
        },
      ),
      BackgroundGroupNotificationPostShowDecision.keep,
    );
  });

  test(
    'unsupported message policy retires while valid private policy stays',
    () {
      final ordinaryRow = <String, Object?>{
        'id': 'message-a',
        'group_id': 'group-a',
        'sender_peer_id': 'peer-alice',
        'is_incoming': 1,
        'read_at': null,
      };
      expect(
        evaluateMessage(
          messageRow: <String, Object?>{
            ...ordinaryRow,
            'media_policy_version': 7,
            'media_lifecycle': 'future_policy',
            'media_duration_seconds': null,
            'media_protected': 1,
          },
        ),
        BackgroundGroupNotificationPostShowDecision.retire,
      );
      expect(
        evaluateMessage(
          messageRow: <String, Object?>{
            ...ordinaryRow,
            'media_policy_version': 1,
            'media_lifecycle': 'view_once',
            'media_duration_seconds': null,
            'media_protected': 1,
          },
        ),
        BackgroundGroupNotificationPostShowDecision.keep,
      );
    },
  );

  test('a message read after show is terminal', () {
    expect(
      evaluateMessage(
        messageRow: const <String, Object?>{
          'id': 'message-a',
          'group_id': 'group-a',
          'sender_peer_id': 'peer-alice',
          'is_incoming': 1,
          'read_at': '2026-08-03T01:00:01.000Z',
        },
      ),
      BackgroundGroupNotificationPostShowDecision.read,
    );
  });

  test('an exact pending message read acknowledgement is terminal', () {
    const unreadMessage = <String, Object?>{
      'id': 'message-a',
      'group_id': 'group-a',
      'sender_peer_id': 'peer-alice',
      'is_incoming': 1,
      'read_at': null,
    };
    expect(
      evaluateMessage(
        readAcknowledgementRow: const <String, Object?>{
          'group_id': 'group-a',
          'content_kind': 'message',
          'event_identity': 'message-a',
          'generation': 'shown-generation',
          'acknowledged_at': '2026-08-03T01:00:01.000Z',
        },
      ),
      BackgroundGroupNotificationPostShowDecision.read,
    );
    expect(
      evaluateMessage(
        messageRow: unreadMessage,
        readAcknowledgementRow: const <String, Object?>{
          'group_id': 'other-group',
          'content_kind': 'message',
          'event_identity': 'message-a',
        },
      ),
      BackgroundGroupNotificationPostShowDecision.keep,
      reason: 'a mismatched durable row must not suppress this event',
    );
  });

  test('REMOVE at the shown ADD timestamp retires the reaction card', () {
    expect(
      evaluateReaction(
        reactionRow: const <String, Object?>{
          'id': 'reaction-a',
          'message_id': 'target-a',
          'sender_peer_id': 'peer-alice',
          'timestamp': '2026-08-03T01:00:00.000Z',
          'removed_at': '2026-08-03T01:00:00.000Z',
        },
      ),
      BackgroundGroupNotificationPostShowDecision.retire,
    );
  });

  test('newer or different active ADD retires the stale shown ADD', () {
    expect(
      evaluateReaction(
        reactionRow: const <String, Object?>{
          'id': 'reaction-new',
          'message_id': 'target-a',
          'sender_peer_id': 'peer-alice',
          'timestamp': '2026-08-03T01:00:01.000Z',
          'removed_at': null,
        },
      ),
      BackgroundGroupNotificationPostShowDecision.retire,
    );
  });

  test('exact active ADD stays while an absent/older row is unknown', () {
    expect(
      evaluateReaction(
        reactionRow: const <String, Object?>{
          'id': 'reaction-a',
          'message_id': 'target-a',
          'sender_peer_id': 'peer-alice',
          'timestamp': '2026-08-03T01:00:00.000Z',
          'removed_at': null,
          'notification_display_terminal_event_id': 'bounded-event-a',
        },
      ),
      BackgroundGroupNotificationPostShowDecision.keep,
    );
    expect(
      evaluateReaction(),
      BackgroundGroupNotificationPostShowDecision.unknown,
    );
    expect(
      evaluateReaction(
        reactionRow: const <String, Object?>{
          'id': 'reaction-old',
          'message_id': 'target-a',
          'sender_peer_id': 'peer-alice',
          'timestamp': '2026-08-03T00:59:59.000Z',
          'removed_at': null,
        },
      ),
      BackgroundGroupNotificationPostShowDecision.unknown,
    );
  });

  test(
    'acknowledged canonical reaction and exact pending read both retire',
    () {
      final activeReaction = <String, Object?>{
        'id': 'reaction-a',
        'message_id': 'target-a',
        'sender_peer_id': 'peer-alice',
        'timestamp': '2026-08-03T01:00:00.000Z',
        'removed_at': null,
        'notification_display_terminal_event_id': 'bounded-event-a',
      };
      expect(
        evaluateReaction(
          reactionRow: <String, Object?>{
            ...activeReaction,
            'notification_acknowledged_at': '2026-08-03T01:00:01.000Z',
          },
        ),
        BackgroundGroupNotificationPostShowDecision.read,
      );
      expect(
        evaluateReaction(
          readAcknowledgementRow: const <String, Object?>{
            'group_id': 'group-a',
            'content_kind': 'reaction',
            'event_identity': 'bounded-event-a',
            'generation': 'shown-generation',
            'acknowledged_at': '2026-08-03T01:00:01.000Z',
          },
        ),
        BackgroundGroupNotificationPostShowDecision.read,
      );
      expect(
        evaluateReaction(
          reactionRow: activeReaction,
          readAcknowledgementRow: const <String, Object?>{
            'group_id': 'group-a',
            'content_kind': 'reaction',
            'event_identity': 'different-event',
          },
        ),
        BackgroundGroupNotificationPostShowDecision.keep,
        reason: 'the acknowledgement must bind the exact bounded event',
      );
    },
  );

  test('acknowledged prior reaction cannot retire a later distinct event', () {
    final acknowledgedPrior = <String, Object?>{
      'id': 'reaction-a',
      'message_id': 'target-a',
      'sender_peer_id': 'peer-alice',
      'timestamp': '2026-08-03T01:00:00.000Z',
      'removed_at': null,
      'notification_display_terminal_event_id': 'bounded-event-a',
      'notification_acknowledged_at': '2026-08-03T01:00:01.000Z',
    };
    expect(
      evaluateBackgroundGroupNotificationPostShowState(
        comparand: laterReaction,
        localPeerId: 'peer-self',
        groupRow: group,
        localMemberRow: selfMember,
        reactionRow: acknowledgedPrior,
        targetMessageRow: target,
      ),
      BackgroundGroupNotificationPostShowDecision.unknown,
      reason: 'the later ADD still awaits canonical inbox materialization',
    );
    expect(
      evaluateBackgroundGroupNotificationPostShowState(
        comparand: laterProvisionalReaction,
        localPeerId: 'peer-self',
        groupRow: group,
        localMemberRow: selfMember,
        reactionRow: acknowledgedPrior,
        targetMessageRow: target,
      ),
      BackgroundGroupNotificationPostShowDecision.unknown,
      reason:
          'a provisional event can bind acknowledgement only by exact terminal identity',
    );
  });

  test('target deletion or non-local target retires reaction content', () {
    expect(
      evaluateReaction(
        deletionRow: const <String, Object?>{
          'message_id': 'target-a',
          'group_id': 'group-a',
        },
      ),
      BackgroundGroupNotificationPostShowDecision.retire,
    );
    expect(
      evaluateReaction(
        targetRow: <String, Object?>{
          ...target,
          'sender_peer_id': 'peer-someone-else',
        },
      ),
      BackgroundGroupNotificationPostShowDecision.retire,
    );
    expect(
      evaluateReaction(
        targetRow: <String, Object?>{
          ...target,
          'media_policy_version': 1,
          'media_lifecycle': 'view_once',
          'media_duration_seconds': null,
          'media_protected': 1,
        },
      ),
      BackgroundGroupNotificationPostShowDecision.retire,
    );
  });

  test(
    'terminal identity mismatch retires while malformed time is unknown',
    () {
      expect(
        evaluateReaction(
          reactionRow: const <String, Object?>{
            'id': 'reaction-a',
            'message_id': 'target-a',
            'sender_peer_id': 'peer-alice',
            'timestamp': '2026-08-03T01:00:00.000Z',
            'removed_at': null,
            'notification_display_terminal_event_id': 'different-event',
          },
        ),
        BackgroundGroupNotificationPostShowDecision.retire,
      );
      expect(
        evaluateReaction(
          reactionRow: const <String, Object?>{
            'id': 'reaction-a',
            'message_id': 'target-a',
            'sender_peer_id': 'peer-alice',
            'timestamp': 'not-a-time',
            'removed_at': null,
          },
        ),
        BackgroundGroupNotificationPostShowDecision.unknown,
      );
    },
  );

  test(
    'provisional reaction keeps only an active exact event and retires its tombstone',
    () {
      final matchingRow = <String, Object?>{
        'id': 'locally-materialized-reaction',
        'message_id': 'target-a',
        'sender_peer_id': 'peer-alice',
        'timestamp': '2026-08-03T01:00:00.000Z',
        'removed_at': null,
        'notification_display_terminal_event_id': 'bounded-event-a',
      };
      expect(
        evaluateProvisionalReaction(reactionRow: matchingRow),
        BackgroundGroupNotificationPostShowDecision.keep,
      );
      expect(
        evaluateProvisionalReaction(
          reactionRow: <String, Object?>{
            ...matchingRow,
            'removed_at': '2026-08-03T01:00:01.000Z',
          },
        ),
        BackgroundGroupNotificationPostShowDecision.retire,
      );
    },
  );

  test(
    'provisional reaction retires canonical or exact pending acknowledgement',
    () {
      final matchingRow = <String, Object?>{
        'id': 'locally-materialized-reaction',
        'message_id': 'target-a',
        'sender_peer_id': 'peer-alice',
        'timestamp': '2026-08-03T01:00:00.000Z',
        'removed_at': null,
        'notification_display_terminal_event_id': 'bounded-event-a',
      };
      expect(
        evaluateProvisionalReaction(
          reactionRow: <String, Object?>{
            ...matchingRow,
            'notification_acknowledged_at': '2026-08-03T01:00:01.000Z',
          },
        ),
        BackgroundGroupNotificationPostShowDecision.read,
      );
      expect(
        evaluateProvisionalReaction(
          readAcknowledgementRow: const <String, Object?>{
            'group_id': 'group-a',
            'content_kind': 'reaction',
            'event_identity': 'bounded-event-a',
          },
        ),
        BackgroundGroupNotificationPostShowDecision.read,
      );
    },
  );

  test(
    'provisional reaction absence and ambiguous or malformed rows stay unknown',
    () {
      expect(
        evaluateProvisionalReaction(),
        BackgroundGroupNotificationPostShowDecision.unknown,
      );
      expect(
        evaluateProvisionalReaction(targetAbsent: true),
        BackgroundGroupNotificationPostShowDecision.unknown,
      );
      expect(
        evaluateProvisionalReaction(
          reactionRow: const <String, Object?>{
            'id': 'other-reaction',
            'message_id': 'target-a',
            'sender_peer_id': 'peer-alice',
            'timestamp': '2026-08-03T01:00:00.000Z',
            'removed_at': null,
            'notification_display_terminal_event_id': 'different-event',
          },
        ),
        BackgroundGroupNotificationPostShowDecision.unknown,
      );
      expect(
        evaluateProvisionalReaction(
          reactionRow: const <String, Object?>{
            'id': 'malformed-reaction',
            'message_id': 'target-a',
            'sender_peer_id': 'peer-alice',
            'timestamp': 'not-a-time',
            'removed_at': null,
            'notification_display_terminal_event_id': 'bounded-event-a',
          },
        ),
        BackgroundGroupNotificationPostShowDecision.unknown,
      );
    },
  );

  test(
    'provisional reaction current policy and target invalidation retire',
    () {
      expect(
        evaluateProvisionalReaction(
          groupRow: <String, Object?>{...group, 'is_muted': 1},
        ),
        BackgroundGroupNotificationPostShowDecision.retire,
      );
      expect(
        evaluateProvisionalReaction(
          targetAbsent: true,
          deletionRow: const <String, Object?>{
            'message_id': 'target-a',
            'group_id': 'group-a',
          },
        ),
        BackgroundGroupNotificationPostShowDecision.retire,
      );
      expect(
        evaluateProvisionalReaction(
          targetRow: <String, Object?>{
            ...target,
            'sender_peer_id': 'peer-someone-else',
          },
        ),
        BackgroundGroupNotificationPostShowDecision.retire,
      );
    },
  );
}
