import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/group_notification_canonical_reconciler.dart';
import 'package:flutter_app/core/notifications/group_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/group_notification_reconciliation_signal.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_notification_reconciliation_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_notification_reconciliation_outbox_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_app_visibility.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

const _groupId = 'group-reconcile';
const _selfPeerId = 'peer-self';
final _now = DateTime.utc(2026, 8, 3, 12);

void main() {
  test(
    'removed reaction card is silently rebuilt from latest unread message',
    () async {
      final state = _CanonicalState()
        ..latestUnread = _incomingMessage('fallback-message')
        ..reactionDecisions['removed-reaction'] =
            GroupNotificationCanonicalContentDecision.retire;
      final notifications = _GenerationNotificationService(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'removed-reaction',
          generation: 'reaction-generation',
        ),
      );
      final outbox = _MemoryReconciliationOutbox()..seed(_entry());
      final fixture = await _buildFixture(
        state: state,
        notifications: notifications,
        outbox: outbox,
      );
      addTearDown(fixture.dispose);

      await fixture.listener.retryPendingNotificationDisplays();

      expect(outbox.entry, isNull);
      expect(notifications.cancelledGenerations, isEmpty);
      expect(notifications.replacements, hasLength(1));
      expect(
        notifications.replacements.single.eventIdentity,
        'fallback-message',
      );
      expect(
        notifications.replacements.single.routePayload,
        contains('fallback-message'),
      );
      expect(
        notifications.metadata?.kind,
        ConversationNotificationContentKind.message,
      );
    },
  );

  test(
    'deleted message with no remaining attention cancels exact generation',
    () async {
      final notifications = _GenerationNotificationService(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'deleted-message',
          generation: 'deleted-generation',
        ),
      );
      final outbox = _MemoryReconciliationOutbox()..seed(_entry());
      final state = _CanonicalState()..deletedMessageIds.add('deleted-message');
      final fixture = await _buildFixture(
        state: state,
        notifications: notifications,
        outbox: outbox,
      );
      addTearDown(fixture.dispose);

      await fixture.listener.retryPendingNotificationDisplays();

      expect(outbox.entry, isNull);
      expect(notifications.replacements, isEmpty);
      expect(notifications.cancelledGenerations, <String>[
        'deleted-generation',
      ]);
      expect(notifications.metadata, isNull);
    },
  );

  test(
    'still-active reaction is silently republished before custody clears',
    () async {
      final state = _CanonicalState()
        ..reactionDecisions['active-reaction'] =
            GroupNotificationCanonicalContentDecision.keep
        ..latestActiveReaction = GroupNotificationCanonicalReaction(
          messageId: 'active-target',
          actorPeerId: 'peer-alice',
          eventIdentity: 'active-reaction',
          timestamp: _now.add(const Duration(minutes: 2)),
        )
        ..canonicalMessages.add(_outgoingTarget('active-target'));
      final notifications = _GenerationNotificationService(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'active-reaction',
          generation: 'active-generation',
        ),
      );
      final outbox = _MemoryReconciliationOutbox()..seed(_entry());
      final fixture = await _buildFixture(
        state: state,
        notifications: notifications,
        outbox: outbox,
      );
      addTearDown(fixture.dispose);

      await fixture.listener.retryPendingNotificationDisplays();

      expect(outbox.entry, isNull);
      expect(notifications.replacements, hasLength(1));
      expect(
        notifications.replacements.single.eventIdentity,
        'active-reaction',
      );
      expect(notifications.cancelledGenerations, isEmpty);
      expect(notifications.metadata?.generation, 'replacement-1');
      expect(state.latestUnreadLoads, 1);
    },
  );

  test(
    'canonical current message republishes even before its terminal marker loads',
    () async {
      final state = _CanonicalState()
        ..canonicalMessages.add(_incomingMessage('current-message'));
      final notifications = _GenerationNotificationService(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'current-message',
          generation: 'current-generation',
        ),
      );
      final outbox = _MemoryReconciliationOutbox()..seed(_entry());
      final fixture = await _buildFixture(
        state: state,
        notifications: notifications,
        outbox: outbox,
      );
      addTearDown(fixture.dispose);

      await fixture.listener.retryPendingNotificationDisplays();

      expect(outbox.entry, isNull);
      expect(notifications.replacements, hasLength(1));
      expect(
        notifications.replacements.single.eventIdentity,
        'current-message',
      );
      expect(notifications.cancelledGenerations, isEmpty);
    },
  );

  test(
    'mute transition retires the current card even when its event exists',
    () async {
      final state = _CanonicalState()
        ..reactionDecisions['active-reaction'] =
            GroupNotificationCanonicalContentDecision.keep;
      final notifications = _GenerationNotificationService(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'active-reaction',
          generation: 'muted-generation',
        ),
      );
      final outbox = _MemoryReconciliationOutbox()..seed(_entry());
      final fixture = await _buildFixture(
        state: state,
        notifications: notifications,
        outbox: outbox,
        group: _group(isMuted: true),
      );
      addTearDown(fixture.dispose);

      await fixture.listener.retryPendingNotificationDisplays();

      expect(outbox.entry, isNull);
      expect(notifications.cancelledGenerations, <String>['muted-generation']);
    },
  );

  test(
    'push-before-inbox message absence retains durable custody without mutation',
    () async {
      final notifications = _GenerationNotificationService(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'message-not-materialized',
          generation: 'push-generation',
        ),
      );
      final outbox = _MemoryReconciliationOutbox()..seed(_entry());
      final fixture = await _buildFixture(
        state: _CanonicalState(),
        notifications: notifications,
        outbox: outbox,
      );
      addTearDown(fixture.dispose);

      await fixture.listener.retryPendingNotificationDisplays();

      expect(outbox.entry, isNotNull);
      expect(outbox.entry?.retryCount, 1);
      expect(notifications.cancelledGenerations, isEmpty);
      expect(notifications.replacements, isEmpty);
      expect(notifications.metadata?.generation, 'push-generation');
    },
  );

  test(
    'reaction absence is unknown but exact REMOVE cancels when attention is empty',
    () async {
      Future<
        ({
          _GenerationNotificationService notifications,
          _MemoryReconciliationOutbox outbox,
          _Fixture fixture,
        })
      >
      build(GroupNotificationCanonicalContentDecision? decision) async {
        final state = _CanonicalState();
        if (decision != null) {
          state.reactionDecisions['reaction-add'] = decision;
        }
        final notifications = _GenerationNotificationService(
          const ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.reaction,
            eventIdentity: 'reaction-add',
            generation: 'reaction-generation',
          ),
        );
        final outbox = _MemoryReconciliationOutbox()..seed(_entry());
        final fixture = await _buildFixture(
          state: state,
          notifications: notifications,
          outbox: outbox,
        );
        return (notifications: notifications, outbox: outbox, fixture: fixture);
      }

      final absent = await build(null);
      addTearDown(absent.fixture.dispose);
      await absent.fixture.listener.retryPendingNotificationDisplays();
      expect(absent.outbox.entry, isNotNull);
      expect(absent.outbox.entry?.retryCount, 1);
      expect(absent.notifications.cancelledGenerations, isEmpty);

      final removed = await build(
        GroupNotificationCanonicalContentDecision.retire,
      );
      addTearDown(removed.fixture.dispose);
      await removed.fixture.listener.retryPendingNotificationDisplays();
      expect(removed.outbox.entry, isNull);
      expect(removed.notifications.cancelledGenerations, <String>[
        'reaction-generation',
      ]);
    },
  );

  test(
    'newer active reaction replaces an older active reaction card',
    () async {
      final state = _CanonicalState()
        ..reactionDecisions['reaction-a'] =
            GroupNotificationCanonicalContentDecision.keep
        ..latestActiveReaction = GroupNotificationCanonicalReaction(
          messageId: 'target-b',
          actorPeerId: 'peer-alice',
          eventIdentity: 'reaction-b',
          timestamp: _now.add(const Duration(minutes: 3)),
        )
        ..canonicalMessages.add(_outgoingTarget('target-b'));
      final notifications = _GenerationNotificationService(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'reaction-a',
          generation: 'reaction-a-generation',
        ),
      );
      final outbox = _MemoryReconciliationOutbox()..seed(_entry());
      final fixture = await _buildFixture(
        state: state,
        notifications: notifications,
        outbox: outbox,
      );
      addTearDown(fixture.dispose);

      await fixture.listener.retryPendingNotificationDisplays();

      expect(outbox.entry, isNull);
      expect(notifications.replacements.single.eventIdentity, 'reaction-b');
      expect(
        notifications.replacements.single.contentKind,
        ConversationNotificationContentKind.reaction,
      );
      expect(
        notifications.replacements.single.messageText,
        isNot(contains('Private target text')),
      );
      expect(
        notifications.replacements.single.messageText,
        isNot(contains('👍')),
      );
    },
  );

  test('newest attention wins across message and reaction kinds', () async {
    Future<CanonicalConversationNotificationReplacement> project({
      required DateTime messageAt,
      required DateTime reactionAt,
    }) async {
      final state = _CanonicalState()
        ..latestUnread = _incomingMessage(
          'message-candidate',
          timestamp: messageAt,
        )
        ..reactionDecisions['invalid-current'] =
            GroupNotificationCanonicalContentDecision.retire
        ..latestActiveReaction = GroupNotificationCanonicalReaction(
          messageId: 'reaction-target',
          actorPeerId: 'peer-alice',
          eventIdentity: 'reaction-candidate',
          timestamp: reactionAt,
        )
        ..canonicalMessages.add(_outgoingTarget('reaction-target'));
      final notifications = _GenerationNotificationService(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'invalid-current',
          generation: 'invalid-generation',
        ),
      );
      final outbox = _MemoryReconciliationOutbox()..seed(_entry());
      final fixture = await _buildFixture(
        state: state,
        notifications: notifications,
        outbox: outbox,
      );
      addTearDown(fixture.dispose);
      await fixture.listener.retryPendingNotificationDisplays();
      return notifications.replacements.single;
    }

    final messageNewest = await project(
      messageAt: _now.add(const Duration(minutes: 5)),
      reactionAt: _now.add(const Duration(minutes: 4)),
    );
    expect(messageNewest.eventIdentity, 'message-candidate');
    expect(
      messageNewest.contentKind,
      ConversationNotificationContentKind.message,
    );

    final reactionNewest = await project(
      messageAt: _now.add(const Duration(minutes: 5)),
      reactionAt: _now.add(const Duration(minutes: 6)),
    );
    expect(reactionNewest.eventIdentity, 'reaction-candidate');
    expect(
      reactionNewest.contentKind,
      ConversationNotificationContentKind.reaction,
    );
  });

  test(
    'native show failure retains custody and the canonical retry republishes',
    () async {
      final state = _CanonicalState()
        ..latestUnread = _incomingMessage('fallback-message')
        ..reactionDecisions['removed-reaction'] =
            GroupNotificationCanonicalContentDecision.retire;
      final notifications = _GenerationNotificationService(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'removed-reaction',
          generation: 'old-generation',
        ),
      )..replacementFailuresAfterMetadata = 1;
      final outbox = _MemoryReconciliationOutbox()..seed(_entry());
      final fixture = await _buildFixture(
        state: state,
        notifications: notifications,
        outbox: outbox,
      );
      addTearDown(fixture.dispose);

      await fixture.listener.retryPendingNotificationDisplays();
      expect(outbox.entry, isNotNull);
      expect(notifications.replacements, hasLength(1));
      expect(notifications.metadata?.eventIdentity, 'fallback-message');

      await fixture.listener.retryPendingNotificationDisplays();
      expect(outbox.entry, isNull);
      expect(notifications.replacements, hasLength(2));
      expect(
        notifications.replacements.map((value) => value.eventIdentity),
        everyElement('fallback-message'),
      );
    },
  );

  test(
    'stop awaits a signal-triggered reconciliation before teardown',
    () async {
      final notifications = _GenerationNotificationService(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'deleted-message',
          generation: 'signal-generation',
        ),
      );
      final outbox = _MemoryReconciliationOutbox();
      final state = _CanonicalState()..deletedMessageIds.add('deleted-message');
      final fixture = await _buildFixture(
        state: state,
        notifications: notifications,
        outbox: outbox,
      );
      addTearDown(fixture.dispose);
      final messages = StreamController<Map<String, dynamic>>();
      addTearDown(messages.close);
      fixture.listener.start(messages.stream);

      fixture.listener.beginCanonicalNotificationRecovery();
      await fixture.listener.endCanonicalNotificationRecovery(
        canonicalStateComplete: true,
        releaseStartupHold: true,
      );
      outbox.seed(_entry());
      notifications.cancelStarted = Completer<void>();
      notifications.cancelBarrier = Completer<void>();

      emitGroupNotificationReconciliationSignal(_groupId);
      await notifications.cancelStarted!.future;
      var stopCompleted = false;
      final stop = fixture.listener.stop().then((_) => stopCompleted = true);
      await Future<void>.delayed(Duration.zero);

      expect(stopCompleted, isFalse);
      expect(outbox.entry, isNotNull);

      notifications.cancelBarrier!.complete();
      await stop;

      expect(stopCompleted, isTrue);
      expect(outbox.entry, isNull);
      expect(notifications.cancelledGenerations, <String>['signal-generation']);
    },
  );

  test(
    'stop still awaits reconciliation when subscription cancellation fails',
    () async {
      final notifications = _GenerationNotificationService(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'deleted-message',
          generation: 'cancel-error-generation',
        ),
      );
      final outbox = _MemoryReconciliationOutbox();
      final state = _CanonicalState()..deletedMessageIds.add('deleted-message');
      final fixture = await _buildFixture(
        state: state,
        notifications: notifications,
        outbox: outbox,
      );
      addTearDown(fixture.dispose);
      final messages = StreamController<Map<String, dynamic>>(
        onCancel: () async => throw StateError('injected cancel failure'),
      );
      addTearDown(messages.close);
      fixture.listener.start(messages.stream);

      fixture.listener.beginCanonicalNotificationRecovery();
      await fixture.listener.endCanonicalNotificationRecovery(
        canonicalStateComplete: true,
        releaseStartupHold: true,
      );
      outbox.seed(_entry());
      notifications.cancelStarted = Completer<void>();
      notifications.cancelBarrier = Completer<void>();

      emitGroupNotificationReconciliationSignal(_groupId);
      await notifications.cancelStarted!.future;
      var stopCompleted = false;
      Object? stopError;
      final stop = fixture.listener.stop().then<void>(
        (_) => stopCompleted = true,
        onError: (Object error) {
          stopError = error;
          stopCompleted = true;
        },
      );
      await Future<void>.delayed(Duration.zero);

      expect(stopCompleted, isFalse);
      expect(outbox.entry, isNotNull);

      notifications.cancelBarrier!.complete();
      await stop;

      expect(stopCompleted, isTrue);
      expect(stopError, isA<StateError>());
      expect(outbox.entry, isNull);
      expect(notifications.cancelledGenerations, <String>[
        'cancel-error-generation',
      ]);
    },
  );
}

final class _CanonicalState {
  GroupMessage? latestUnread;
  GroupNotificationCanonicalReaction? latestActiveReaction;
  final Map<String, GroupNotificationCanonicalContentDecision>
  reactionDecisions = <String, GroupNotificationCanonicalContentDecision>{};
  final List<GroupMessage> canonicalMessages = <GroupMessage>[];
  final Set<String> deletedMessageIds = <String>{};
  int latestUnreadLoads = 0;
}

final class _Fixture {
  const _Fixture(this.listener);

  final GroupMessageListener listener;

  Future<void> dispose() async {
    await listener.stop();
    listener.dispose();
  }
}

Future<_Fixture> _buildFixture({
  required _CanonicalState state,
  required _GenerationNotificationService notifications,
  required _MemoryReconciliationOutbox outbox,
  GroupModel? group,
}) async {
  final groups = InMemoryGroupRepository();
  final messages = InMemoryGroupMessageRepository();
  await groups.saveGroup(group ?? _group());
  await groups.saveMember(
    GroupMember(
      groupId: _groupId,
      peerId: _selfPeerId,
      username: 'Me',
      role: MemberRole.writer,
      joinedAt: _now,
    ),
  );
  await groups.saveMember(
    GroupMember(
      groupId: _groupId,
      peerId: 'peer-alice',
      username: 'Alice',
      role: MemberRole.writer,
      joinedAt: _now,
    ),
  );
  final latest = state.latestUnread;
  if (latest != null) await messages.saveMessage(latest);
  for (final message in state.canonicalMessages) {
    await messages.saveMessage(message);
  }
  for (final messageId in state.deletedMessageIds) {
    messages.seedLocalDeletion(messageId: messageId, groupId: _groupId);
  }
  final listener = GroupMessageListener(
    groupRepo: groups,
    msgRepo: messages,
    getSelfPeerId: () async => _selfPeerId,
    notificationService: notifications,
    appVisibility: FixedAppVisibility(isForegroundActive: true),
    notificationPresentationCoordinator:
        GroupNotificationPresentationCoordinator(),
    groupConversationTracker: ActiveConversationTracker(),
    getAppLifecycleState: () => AppLifecycleState.resumed,
    notificationReconciliationOutbox: outbox,
    loadLatestUnreadNotificationMessage: (_) async {
      state.latestUnreadLoads++;
      return state.latestUnread;
    },
    isActiveGroupNotificationReaction:
        ({
          required groupId,
          required selfPeerId,
          required eventIdentity,
        }) async =>
            state.reactionDecisions[eventIdentity] ??
            GroupNotificationCanonicalContentDecision.unknown,
    loadLatestActiveNotificationReaction:
        ({required groupId, required selfPeerId}) async =>
            state.latestActiveReaction,
  );
  return _Fixture(listener);
}

GroupModel _group({bool isMuted = false}) => GroupModel(
  id: _groupId,
  name: 'Reliable Group',
  type: GroupType.chat,
  topicName: 'topic-reconcile',
  createdAt: _now,
  createdBy: 'peer-admin',
  myRole: GroupRole.member,
  isMuted: isMuted,
);

GroupMessage _incomingMessage(String id, {DateTime? timestamp}) => GroupMessage(
  id: id,
  groupId: _groupId,
  senderPeerId: 'peer-alice',
  senderUsername: 'Alice',
  text: 'Canonical fallback',
  timestamp: timestamp ?? _now.add(const Duration(minutes: 1)),
  isIncoming: true,
  createdAt: timestamp ?? _now.add(const Duration(minutes: 1)),
);

GroupMessage _outgoingTarget(String id) => GroupMessage(
  id: id,
  groupId: _groupId,
  senderPeerId: _selfPeerId,
  senderUsername: 'Me',
  text: 'Private target text must never enter reaction copy',
  timestamp: _now,
  isIncoming: false,
  createdAt: _now,
);

GroupNotificationReconciliationOutboxEntry _entry() =>
    GroupNotificationReconciliationOutboxEntry(
      groupId: _groupId,
      incarnationId: 'incarnation-a',
      revision: 0,
      retryCount: 0,
      lastAttemptAt: null,
      nextAttemptAt: null,
      createdAt: _now.toIso8601String(),
      updatedAt: _now.toIso8601String(),
    );

final class _MemoryReconciliationOutbox
    implements GroupNotificationReconciliationOutboxRepository {
  GroupNotificationReconciliationOutboxEntry? entry;

  void seed(GroupNotificationReconciliationOutboxEntry value) {
    entry = value;
  }

  @override
  Future<List<GroupNotificationReconciliationOutboxEntry>> loadEligible({
    int limit = 20,
  }) async => entry == null
      ? const <GroupNotificationReconciliationOutboxEntry>[]
      : <GroupNotificationReconciliationOutboxEntry>[entry!];

  @override
  Future<DateTime?> loadEarliestNextAttemptAt() async => null;

  @override
  Future<bool> completeIfExact(
    GroupNotificationReconciliationOutboxEntry expected,
  ) async {
    final current = entry;
    if (current == null ||
        current.groupId != expected.groupId ||
        current.incarnationId != expected.incarnationId ||
        current.revision != expected.revision) {
      return false;
    }
    entry = null;
    return true;
  }

  @override
  Future<bool> recordFailureIfExact({
    required GroupNotificationReconciliationOutboxEntry expected,
    required DateTime nextAttemptAt,
  }) async {
    final current = entry;
    if (current == null ||
        current.incarnationId != expected.incarnationId ||
        current.revision != expected.revision) {
      return false;
    }
    entry = current.copyWith(
      revision: current.revision + 1,
      retryCount: current.retryCount + 1,
      nextAttemptAt: nextAttemptAt.toUtc().toIso8601String(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    return true;
  }
}

final class _GenerationNotificationService
    implements
        NotificationService,
        ConversationNotificationGenerationCancellation,
        ConversationNotificationGenerationReplacement {
  _GenerationNotificationService(this.metadata);

  ConversationNotificationContentMetadata? metadata;
  final List<String> cancelledGenerations = <String>[];
  final List<CanonicalConversationNotificationReplacement> replacements =
      <CanonicalConversationNotificationReplacement>[];
  int replacementFailuresAfterMetadata = 0;
  Completer<void>? cancelStarted;
  Completer<void>? cancelBarrier;

  @override
  void Function(String payload)? onNotificationTap;

  @override
  Future<ConversationNotificationContentMetadata?>
  lookupConversationNotificationContentMetadata(String conversationKey) async =>
      metadata;

  @override
  Future<bool> cancelConversationNotificationGeneration(
    String conversationKey,
    String generation,
  ) async {
    if (metadata?.generation != generation) return false;
    final started = cancelStarted;
    if (started != null && !started.isCompleted) started.complete();
    await cancelBarrier?.future;
    cancelledGenerations.add(generation);
    metadata = null;
    return true;
  }

  @override
  Future<bool> replaceConversationNotificationGeneration(
    String conversationKey,
    String expectedGeneration,
    CanonicalConversationNotificationReplacement replacement,
  ) async {
    if (metadata?.generation != expectedGeneration) return false;
    replacements.add(replacement);
    metadata = ConversationNotificationContentMetadata(
      kind: replacement.contentKind,
      eventIdentity: replacement.eventIdentity,
      generation: 'replacement-${replacements.length}',
    );
    if (replacementFailuresAfterMetadata > 0) {
      replacementFailuresAfterMetadata--;
      throw StateError('native replacement show failed');
    }
    return true;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    ConversationNotificationContentKind? contentKind,
    String? contentEventIdentity,
    ConversationNotificationSnapshot? snapshot,
  }) async {}

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {}

  @override
  Future<String?> consumeInitialPayload() async => null;

  @override
  Future<void> clearDeliveredNotifications() async {}

  @override
  void dispose() {}
}
