import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_content_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_reaction_target_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_receive.dart';
import 'package:flutter_app/features/groups/data/repositories/group_notification_display_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bridge/fake_bridge.dart' as test_bridge;
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

const _groupId = 'group-visibility-staging';
const _localPeerId = 'peer-local';
const _localTransportPeerId = 'transport-local';
const _senderPeerId = 'peer-sender';
const _senderTransportPeerId = 'transport-sender';
const _senderDeviceId = 'device-sender';
const _physicalPeerId = 'physical-peer-local';
const _currentOpaqueBinding =
    'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _eventTimestamp = '2026-08-15T10:20:00.000000Z';
final _projectionNow = DateTime.utc(2030, 1, 1);
const _backgroundVisibility = AppVisibilityEvaluation(
  isForegroundActive: false,
  maySuppress: false,
  lifecycle: AppVisibilityLifecycle.background,
  revision: 1,
  lifecycleGeneration: 1,
);
const _exactVisibleVisibility = AppVisibilityEvaluation(
  isForegroundActive: true,
  maySuppress: true,
  lifecycle: AppVisibilityLifecycle.foregroundActive,
  revision: 2,
  lifecycleGeneration: 1,
);

enum _ProtectedKind { message, reaction }

enum _VisibilityCase {
  visibleAtStageThenBackground,
  backgroundAtStageThenExactVisible,
}

final class _MutableVisibility extends AppVisibilitySuppressionReader {
  _MutableVisibility({required this.expectedGroupId, required this.evaluation});

  final String expectedGroupId;
  AppVisibilityEvaluation evaluation;
  final evaluations = <AppVisibilityConversationIdentity?>[];

  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async {
    evaluations.add(identity);
    if (evaluation.maySuppress &&
        identity?.normalizedId != 'group:$expectedGroupId') {
      return const AppVisibilityEvaluation(
        isForegroundActive: true,
        maySuppress: false,
      );
    }
    return evaluation;
  }
}

final class _SqlMessageRepository extends InMemoryGroupMessageRepository {
  _SqlMessageRepository(this.database);

  final Database database;

  @override
  Future<GroupMessage?> getMessage(String id) async {
    final row = await dbLoadGroupMessage(database, id);
    return row == null
        ? null
        : GroupMessage.fromMap(Map<String, dynamic>.from(row));
  }

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await dbLoadGroupMessagesPage(
      database,
      groupId,
      limit: limit,
      offset: offset,
    );
    return rows
        .map((row) => GroupMessage.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }
}

final class _SqlReactionRepository extends FakeReactionRepository {
  _SqlReactionRepository(this.database);

  final Database database;

  @override
  Future<MessageReaction?> getReactionForSenderIncludingRemoved({
    required String messageId,
    required String senderPeerId,
  }) async {
    final row = await dbLoadActiveOrTombstonedReactionForSender(
      database,
      messageId,
      senderPeerId,
    );
    return row == null
        ? null
        : MessageReaction.fromMap(Map<String, dynamic>.from(row));
  }
}

final class _NoopRecentRemoteNotificationGate
    extends RecentRemoteNotificationGate {
  _NoopRecentRemoteNotificationGate()
    : super(
        filePath:
            '${Directory.systemTemp.path}/unused-plan371-group-visibility-gate',
      );

  @override
  Future<bool> consumeIfRecentAnnouncement({
    required String payload,
    String? messageId,
  }) async => false;

  @override
  Future<void> markAnnouncement({
    required String payload,
    String? messageId,
  }) async {}
}

final class _DurableFakeNotificationService extends FakeNotificationService
    implements MessageNotificationDurableFinalEffectBoundary {
  _DurableFakeNotificationService(this.registry);

  final DurableConversationNotificationIdRegistry registry;
  int? _activeNotificationId;
  final durableResults = <DurableLocalNotificationEffectResult>[];

  @override
  Future<DurableLocalNotificationEffectResult>
  showMessageNotificationWithDurableFinalEffect({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    required ConversationNotificationContentKind contentKind,
    required String contentEventIdentity,
    ConversationNotificationSnapshot? snapshot,
    required DurableLocalNotificationEffectContext durableEffectContext,
    required AppVisibilitySuppressionReader finalVisibility,
    required AppVisibilityConversationIdentity conversationIdentity,
    required PublishNativeMessageNotificationAtDurableBarrier publishNative,
  }) async {
    final notificationId = await registry.resolve(
      contactPeerId,
      activeNotificationIds: () async => _activeNotificationId == null
          ? const <Object?>[]
          : <Object?>[_activeNotificationId],
    );
    final metadata = ConversationNotificationContentMetadata(
      kind: contentKind,
      eventIdentity: durableEffectContext.eventCorrelation,
      generation: durableLocalNotificationContentGeneration(
        durableEffectContext.eventCorrelation,
      ),
    );

    Future<void> showNative({required bool silent}) async {
      await super.showMessageNotification(
        contactPeerId: contactPeerId,
        senderUsername: senderUsername,
        messageText: messageText,
        payload: payload,
        silent: silent,
        contentKind: contentKind,
        contentEventIdentity: contentEventIdentity,
        snapshot: snapshot,
      );
      _activeNotificationId = notificationId;
    }

    final result = await registry.runFinalEffect(
      context: durableEffectContext,
      appVisibility: finalVisibility,
      conversationIdentity: conversationIdentity,
      conversationKey: contactPeerId,
      notificationId: notificationId,
      metadata: metadata,
      retireCurrent: () async => _activeNotificationId = null,
      publishNative: () async {
        final entered = await publishNative(showNative, () async => true);
        if (!entered) {
          throw StateError('durable native entry was not authorized');
        }
      },
      publishNativeSilently: () => showNative(silent: true),
      publishNativeAtFinalBarrier: (authorize) =>
          publishNative(showNative, authorize),
      activeNotificationIds: () async => _activeNotificationId == null
          ? const <Object?>[]
          : <Object?>[_activeNotificationId],
    );
    durableResults.add(result);
    return result;
  }
}

final class _SqlDisplayOutbox {
  _SqlDisplayOutbox(Database database) {
    repository = GroupNotificationDisplayOutboxRepositoryImpl(
      dbStage: (row) =>
          dbStageGroupNotificationDisplayOutboxEntry(database, row),
      dbLoadByEventId: (eventId) =>
          dbLoadGroupNotificationDisplayOutboxEntry(database, eventId),
      dbBindDurableCorrelationIfExact:
          ({
            required eventId,
            required expectedRevision,
            required expectedEventKind,
            required expectedGroupId,
            required expectedMessageId,
            required expectedActorPeerId,
            required expectedEventTimestamp,
            required expectedReactionId,
            required expectedReactionAction,
            required expectedReactionTombstone,
            required durableEventCorrelation,
            required updatedAt,
          }) => dbBindGroupNotificationDisplayOutboxDurableCorrelationIfExact(
            database,
            eventId: eventId,
            expectedRevision: expectedRevision,
            expectedEventKind: expectedEventKind,
            expectedGroupId: expectedGroupId,
            expectedMessageId: expectedMessageId,
            expectedActorPeerId: expectedActorPeerId,
            expectedEventTimestamp: expectedEventTimestamp,
            expectedReactionId: expectedReactionId,
            expectedReactionAction: expectedReactionAction,
            expectedReactionTombstone: expectedReactionTombstone,
            durableEventCorrelation: durableEventCorrelation,
            updatedAt: updatedAt,
          ),
      dbPromoteReadyIfExact:
          ({required eventId, required expectedRevision, required updatedAt}) =>
              dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
                database,
                eventId: eventId,
                expectedRevision: expectedRevision,
                updatedAt: updatedAt,
              ),
      dbLoadReady: ({limit = 20, required eligibleAt}) =>
          dbLoadReadyGroupNotificationDisplayOutboxEntries(
            database,
            limit: limit,
            eligibleAt: eligibleAt,
          ),
      dbLoadEarliestNextAttemptAt: () =>
          dbLoadEarliestGroupNotificationDisplayOutboxNextAttemptAt(database),
      dbRecordRetryIfExact:
          ({
            required eventId,
            required expectedRevision,
            required lastErrorCode,
            required lastAttemptAt,
            required nextAttemptAt,
            required updatedAt,
          }) => dbRecordGroupNotificationDisplayOutboxRetryIfExact(
            database,
            eventId: eventId,
            expectedRevision: expectedRevision,
            lastErrorCode: lastErrorCode,
            lastAttemptAt: lastAttemptAt,
            nextAttemptAt: nextAttemptAt,
            updatedAt: updatedAt,
          ),
      dbCompleteIfExact:
          ({
            required eventId,
            required expectedRevision,
            required expectedEventKind,
            required expectedGroupId,
            required expectedMessageId,
            required expectedActorPeerId,
            required expectedEventTimestamp,
            required expectedReactionId,
            required expectedReactionAction,
            required expectedReactionTombstone,
            required completedAt,
            outcome,
          }) async {
            completionOutcomes.add(outcome);
            return dbCompleteGroupNotificationDisplayOutboxEntryIfExact(
              database,
              eventId: eventId,
              expectedRevision: expectedRevision,
              expectedEventKind: expectedEventKind,
              expectedGroupId: expectedGroupId,
              expectedMessageId: expectedMessageId,
              expectedActorPeerId: expectedActorPeerId,
              expectedEventTimestamp: expectedEventTimestamp,
              expectedReactionId: expectedReactionId,
              expectedReactionAction: expectedReactionAction,
              expectedReactionTombstone: expectedReactionTombstone,
              completedAt: completedAt,
              outcome: outcome,
            );
          },
      dbCompleteOrVerifyIfExact:
          ({
            required eventId,
            required expectedRevision,
            required expectedEventKind,
            required expectedGroupId,
            required expectedMessageId,
            required expectedActorPeerId,
            required expectedEventTimestamp,
            required expectedReactionId,
            required expectedReactionAction,
            required expectedReactionTombstone,
            required completedAt,
            outcome,
            durableEventCorrelation,
          }) async {
            completionOutcomes.add(outcome);
            return dbCompleteOrVerifyGroupNotificationDisplayOutboxEntryIfExact(
              database,
              eventId: eventId,
              expectedRevision: expectedRevision,
              expectedEventKind: expectedEventKind,
              expectedGroupId: expectedGroupId,
              expectedMessageId: expectedMessageId,
              expectedActorPeerId: expectedActorPeerId,
              expectedEventTimestamp: expectedEventTimestamp,
              expectedReactionId: expectedReactionId,
              expectedReactionAction: expectedReactionAction,
              expectedReactionTombstone: expectedReactionTombstone,
              completedAt: completedAt,
              outcome: outcome,
              durableEventCorrelation: durableEventCorrelation,
            );
          },
      dbRetireAfterDurableSettlementIfExact:
          ({
            required eventId,
            required expectedRevision,
            required expectedEventKind,
            required expectedGroupId,
            required expectedMessageId,
            required expectedActorPeerId,
            required expectedEventTimestamp,
            required expectedReactionId,
            required expectedReactionAction,
            required expectedReactionTombstone,
            durableEventCorrelation,
          }) =>
              dbRetireGroupNotificationDisplayOutboxAfterDurableSettlementIfExact(
                database,
                eventId: eventId,
                expectedRevision: expectedRevision,
                expectedEventKind: expectedEventKind,
                expectedGroupId: expectedGroupId,
                expectedMessageId: expectedMessageId,
                expectedActorPeerId: expectedActorPeerId,
                expectedEventTimestamp: expectedEventTimestamp,
                expectedReactionId: expectedReactionId,
                expectedReactionAction: expectedReactionAction,
                expectedReactionTombstone: expectedReactionTombstone,
                durableEventCorrelation: durableEventCorrelation,
              ),
      dbRetireIfExact:
          ({
            required eventId,
            required expectedRevision,
            required expectedEventKind,
            required expectedGroupId,
            required expectedMessageId,
            required expectedActorPeerId,
            required expectedEventTimestamp,
            required expectedReactionId,
            required expectedReactionAction,
            required expectedReactionTombstone,
          }) => dbRetireGroupNotificationDisplayOutboxEntryIfExact(
            database,
            eventId: eventId,
            expectedRevision: expectedRevision,
            expectedEventKind: expectedEventKind,
            expectedGroupId: expectedGroupId,
            expectedMessageId: expectedMessageId,
            expectedActorPeerId: expectedActorPeerId,
            expectedEventTimestamp: expectedEventTimestamp,
            expectedReactionId: expectedReactionId,
            expectedReactionAction: expectedReactionAction,
            expectedReactionTombstone: expectedReactionTombstone,
          ),
      dbReconcileMessageAliasReady:
          ({
            required aliasEventId,
            required canonicalEventId,
            required groupId,
            required actorPeerId,
            required eventTimestamp,
            required updatedAt,
          }) => dbReconcileGroupNotificationDisplayOutboxMessageAliasReady(
            database,
            aliasEventId: aliasEventId,
            canonicalEventId: canonicalEventId,
            groupId: groupId,
            actorPeerId: actorPeerId,
            eventTimestamp: eventTimestamp,
            updatedAt: updatedAt,
          ),
      dbDeleteForGroup: (groupId) =>
          dbDeleteGroupNotificationDisplayOutboxForGroup(database, groupId),
      dbDeleteForMessage: ({required groupId, required messageId}) =>
          dbDeleteGroupNotificationDisplayOutboxForMessage(
            database,
            groupId: groupId,
            messageId: messageId,
          ),
      dbDeleteForReaction:
          ({required groupId, required messageId, required reactionId}) =>
              dbDeleteGroupNotificationDisplayOutboxForReaction(
                database,
                groupId: groupId,
                messageId: messageId,
                reactionId: reactionId,
              ),
      dbDeleteForReactionActor:
          ({required groupId, required messageId, required actorPeerId}) =>
              dbDeleteGroupNotificationDisplayOutboxForReactionActor(
                database,
                groupId: groupId,
                messageId: messageId,
                actorPeerId: actorPeerId,
              ),
      now: () => _projectionNow,
    );
  }

  late final GroupNotificationDisplayOutboxRepositoryImpl repository;
  final completionOutcomes = <NotificationCompletedOutcomeCandidate?>[];
}

final class _ReplayAuthority {
  const _ReplayAuthority({
    required this.bridge,
    required this.groupRepository,
    required this.authority,
  });

  final test_bridge.FakeBridge bridge;
  final InMemoryGroupRepository groupRepository;
  final ProtectedGroupContentAuthority authority;
}

Future<_ReplayAuthority> _buildReplayAuthority(Database database) async {
  final bridge = test_bridge.FakeBridge();
  final groupRepository = InMemoryGroupRepository();
  final group = GroupModel(
    id: _groupId,
    name: 'Visibility staging',
    type: GroupType.chat,
    topicName: 'topic-visibility-staging',
    createdAt: DateTime.utc(2026, 8, 15, 9),
    createdBy: _senderPeerId,
    myRole: GroupRole.member,
  );
  const senderDevice = GroupMemberDeviceIdentity(
    deviceId: _senderDeviceId,
    transportPeerId: _senderTransportPeerId,
    deviceSigningPublicKey: 'pk-sender',
  );
  const localDevice = GroupMemberDeviceIdentity(
    deviceId: 'device-local',
    transportPeerId: _localTransportPeerId,
    deviceSigningPublicKey: 'pk-local',
  );
  final sender = GroupMember(
    groupId: _groupId,
    peerId: _senderPeerId,
    username: 'Sender',
    role: MemberRole.writer,
    publicKey: 'pk-sender',
    devices: const <GroupMemberDeviceIdentity>[senderDevice],
    joinedAt: group.createdAt,
  );
  final local = GroupMember(
    groupId: _groupId,
    peerId: _localPeerId,
    username: 'Local',
    role: MemberRole.writer,
    publicKey: 'pk-local',
    devices: const <GroupMemberDeviceIdentity>[localDevice],
    joinedAt: group.createdAt,
  );
  await groupRepository.saveGroup(group);
  await groupRepository.saveMember(sender);
  await groupRepository.saveMember(local);
  await groupRepository.saveKey(
    GroupKeyInfo(
      groupId: _groupId,
      keyGeneration: 7,
      encryptedKey: 'group-key-7',
      createdAt: group.createdAt,
    ),
  );
  await dbInsertGroup(database, group.toMap());

  final observed = AuthenticatedGroupAuthorityProof(
    eventId: 'authority-visibility-staging',
    groupId: _groupId,
    eventAt: DateTime.utc(2026, 8, 15, 10),
    keyEpoch: 7,
    control: 'bootstrap_genesis',
    actorAccountPeerId: _senderPeerId,
    actorAccountPublicKey: 'pk-sender',
    senderTransportPeerId: _senderTransportPeerId,
    senderTransportPublicKey: 'pk-sender',
    authorityData: const <String, Object?>{},
    signature: 'fake-signature',
  );
  return _ReplayAuthority(
    bridge: bridge,
    groupRepository: groupRepository,
    authority: ProtectedGroupContentAuthority(
      observed: observed,
      groupType: GroupType.chat,
      members: <GroupMember>[sender, local],
      terminalFacts: <AuthenticatedGroupAuthorityProof>[observed],
    ),
  );
}

Future<void> _exerciseVisibilityCase({
  required Database database,
  required _ReplayAuthority replay,
  required DurableConversationNotificationIdRegistry durableRegistry,
  required _ProtectedKind kind,
  required _VisibilityCase visibilityCase,
}) async {
  final caseToken = '${kind.name}-${visibilityCase.name}';
  final messageId = kind == _ProtectedKind.message
      ? 'protected-$caseToken'
      : 'reaction-target-$caseToken';
  final reactionId = deterministicGroupReactionStateId(
    groupId: _groupId,
    messageId: messageId,
    logicalActorPeerId: _senderPeerId,
  );
  final reactionAt = DateTime.parse(_eventTimestamp);
  final reactionEventId = buildGroupReactionTransitionId(
    groupId: _groupId,
    messageId: messageId,
    logicalActorPeerId: _senderPeerId,
    action: GroupReactionPayload.actionAdd,
    emoji: '👍',
    timestamp: reactionAt,
  );
  final eventId = kind == _ProtectedKind.message ? messageId : reactionEventId;
  final durableCorrelation = tryComputeNotificationCompletedOutcomeCorrelation(
    physicalPeerId: _physicalPeerId,
    producerKind: kind == _ProtectedKind.message
        ? NotificationCompletedOutcomeProducerKind.groupMessage
        : NotificationCompletedOutcomeProducerKind.groupReaction,
    eventKey: eventId,
  )!;

  if (kind == _ProtectedKind.reaction) {
    final target = GroupMessage(
      id: messageId,
      groupId: _groupId,
      senderPeerId: _localPeerId,
      senderUsername: 'Local',
      text: 'Self-authored protected reaction target',
      timestamp: DateTime.utc(2026, 8, 15, 10, 10),
      isIncoming: false,
      createdAt: DateTime.utc(2026, 8, 15, 10, 10),
    );
    expect(await dbInsertGroupMessage(database, target.toMap()), isTrue);
  }

  final initialVisibility =
      visibilityCase == _VisibilityCase.visibleAtStageThenBackground
      ? _exactVisibleVisibility
      : _backgroundVisibility;
  final visibility = _MutableVisibility(
    expectedGroupId: _groupId,
    evaluation: initialVisibility,
  );
  final notifications = _DurableFakeNotificationService(durableRegistry);
  final messages = _SqlMessageRepository(database);
  final reactions = _SqlReactionRepository(database);
  final outbox = _SqlDisplayOutbox(database);
  final listener = GroupMessageListener(
    groupRepo: replay.groupRepository,
    msgRepo: messages,
    bridge: replay.bridge,
    getSelfPeerId: () async => _localPeerId,
    notificationService: notifications,
    appVisibility: visibility,
    reactionRepo: reactions,
    remoteNotificationGate: _NoopRecentRemoteNotificationGate(),
    notificationDisplayOutbox: outbox.repository,
    resolveCompletedOutcomePhysicalPeerId: () async => _physicalPeerId,
    resolveCurrentOpaqueBinding: () async => _currentOpaqueBinding,
    durableLocalNotificationEffectRegistry: durableRegistry,
    durableNotificationCoordinatorResolver: () async {
      throw StateError('durable tone claims are outside TC-371-05b');
    },
  );

  final envelope = await buildGroupOfflineReplayEnvelope(
    bridge: replay.bridge,
    groupRepo: replay.groupRepository,
    groupId: _groupId,
    payloadType: kind == _ProtectedKind.message
        ? groupOfflineReplayPayloadTypeMessage
        : groupOfflineReplayPayloadTypeReaction,
    plaintext: jsonEncode(
      kind == _ProtectedKind.message
          ? <String, Object?>{
              'groupId': _groupId,
              'senderId': _senderPeerId,
              'senderDeviceId': _senderDeviceId,
              'transportPeerId': _senderTransportPeerId,
              'messageId': messageId,
              'logicalDeliveryId': messageId,
              'keyEpoch': 7,
              'text': 'Protected visibility staging',
              'timestamp': _eventTimestamp,
            }
          : <String, Object?>{
              'id': reactionId,
              'messageId': messageId,
              'emoji': '👍',
              'action': GroupReactionPayload.actionAdd,
              'senderPeerId': _senderPeerId,
              'timestamp': _eventTimestamp,
              'eventId': reactionEventId,
            },
    ),
    senderPeerId: _senderPeerId,
    senderPublicKey: 'pk-sender',
    senderPrivateKey: 'sk-sender',
    senderDeviceId: _senderDeviceId,
    senderTransportPeerId: _senderTransportPeerId,
    recipientPeerIds: const <String>[_localTransportPeerId],
    messageId: eventId,
    contentEventId: eventId,
    contentAuthorityVersion: GroupContentAuthorityVersion(
      eventAt: replay.authority.observed.eventAt,
      eventId: replay.authority.observed.eventId,
      keyEpoch: replay.authority.observed.keyEpoch,
    ),
    reactionNotificationExtension: kind == _ProtectedKind.reaction
        ? GroupReactionNotificationExtensionInput(
            transitionId: reactionEventId,
            action: GroupReactionPayload.actionAdd,
            targetMessageId: messageId,
            reactorPeerId: _senderPeerId,
            reactorTransportPeerId: _senderTransportPeerId,
            notificationRecipientTransportPeerIds: const <String>[
              _localTransportPeerId,
            ],
          )
        : null,
  );

  final applied = await handleProtectedGroupContentReplay(
    bridge: replay.bridge,
    groupRepository: replay.groupRepository,
    message: ChatMessage(
      from: _senderTransportPeerId,
      to: _localTransportPeerId,
      content: envelope,
      timestamp: _eventTimestamp,
      isIncoming: true,
    ),
    localLogicalPeerId: _localPeerId,
    localTransportPeerId: _localTransportPeerId,
    loadAuthority: (_, _) async => replay.authority,
    hasPendingAuthority: (_) async => false,
    hasTerminal:
        ({required groupId, required payloadType, required contentEventId}) =>
            dbHasProtectedGroupContentTerminalInTransaction(
              database,
              groupId: groupId,
              payloadType: payloadType,
              contentEventId: contentEventId,
            ),
    commitMessage:
        ({
          required groupId,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required eventPayload,
          required messageRow,
          required mediaAttachmentRows,
          required incomingMediaCustodyRows,
          readyDisplayOutboxRow,
        }) => dbCommitProtectedGroupMessage(
          database,
          groupId: groupId,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
          messageRow: messageRow,
          mediaAttachmentRows: mediaAttachmentRows,
          incomingMediaCustodyRows: incomingMediaCustodyRows,
          readyDisplayOutboxRow: readyDisplayOutboxRow,
        ),
    commitReaction:
        ({
          required groupId,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required eventPayload,
          required reactionRow,
          required transitionId,
          required action,
          readyDisplayOutboxRow,
        }) => dbCommitProtectedGroupReaction(
          database,
          groupId: groupId,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
          reactionRow: reactionRow,
          transitionId: transitionId,
          action: action,
          readyDisplayOutboxRow: readyDisplayOutboxRow,
        ),
    commitTerminal:
        ({
          required groupId,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required eventPayload,
        }) => dbCommitProtectedGroupContentTerminal(
          database,
          groupId: groupId,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
        ),
    resolveReactionTarget: (groupId, targetMessageId) =>
        dbClassifyProtectedGroupReactionTarget(
          database,
          groupId: groupId,
          messageId: targetMessageId,
        ),
    buildMessageDisplayRow: listener.buildProtectedMessageDisplayReadyRow,
    buildReactionDisplayRow: listener.buildProtectedReactionDisplayReadyRow,
    nowUtc: () => DateTime.utc(2026, 8, 15, 12),
  );
  expect(
    applied.disposition,
    ProtectedGroupContentApplyDisposition.applied,
    reason: '$caseToken: ${applied.reasonCode} ${applied.reasonDetail}',
  );
  expect(
    visibility.evaluations,
    isEmpty,
    reason: '$caseToken must stage before consulting mutable visibility',
  );

  final staged = await outbox.repository.loadByEventId(eventId);
  expect(staged, isNotNull, reason: caseToken);
  expect(staged!.isReady, isTrue, reason: caseToken);
  expect(
    staged.eventKind,
    kind == _ProtectedKind.message
        ? GroupNotificationDisplayOutboxKind.message
        : GroupNotificationDisplayOutboxKind.reaction,
  );
  expect(await dbLoadGroupMessage(database, messageId), isNotNull);
  if (kind == _ProtectedKind.reaction) {
    expect(
      await dbLoadActiveOrTombstonedReactionForSender(
        database,
        messageId,
        _senderPeerId,
      ),
      isNotNull,
    );
  }

  final shouldPost =
      visibilityCase == _VisibilityCase.visibleAtStageThenBackground;
  visibility.evaluation = shouldPost
      ? _backgroundVisibility
      : _exactVisibleVisibility;
  final flowEvents = <Map<String, dynamic>>[];
  debugSetFlowEventSink(flowEvents.add);
  try {
    await listener.retryPendingNotificationDisplays();
  } finally {
    debugSetFlowEventSink(null);
  }

  expect(
    visibility.evaluations,
    hasLength(2),
    reason:
        '$caseToken must use the post-stage preflight and final durable barrier',
  );
  expect(
    visibility.evaluations.map((identity) => identity?.normalizedId),
    everyElement('group:$_groupId'),
  );
  expect(
    await outbox.repository.loadByEventId(eventId),
    isNull,
    reason: '$caseToken must complete exact READY custody',
  );
  expect(outbox.completionOutcomes, <NotificationCompletedOutcomeCandidate?>[
    null,
  ]);
  expect(
    await database.query('notification_completed_outcome_outbox'),
    isEmpty,
    reason: '$caseToken must not emit osPosted or inChat outcome custody',
  );
  expect(
    notifications.durableResults.map((result) => result.disposition),
    <DurableLocalNotificationEffectDisposition>[
      shouldPost
          ? DurableLocalNotificationEffectDisposition.osPosted
          : DurableLocalNotificationEffectDisposition.inChat,
    ],
    reason: '$caseToken must terminate at the durable final barrier',
  );

  final freshVisibleSuppressions = flowEvents.where(
    (event) =>
        event['event'] == 'NOTIFICATION_SUPPRESSED' &&
        (event['details'] as Map?)?['reason'] == 'fresh_visible_conversation',
  );
  if (shouldPost) {
    expect(notifications.shown, hasLength(1), reason: caseToken);
    expect(notifications.shown.single.contactPeerId, 'group:$_groupId');
    expect(
      notifications.shown.single.contentKind,
      kind == _ProtectedKind.message
          ? ConversationNotificationContentKind.message
          : ConversationNotificationContentKind.reaction,
    );
    expect(freshVisibleSuppressions, isEmpty, reason: caseToken);
  } else {
    expect(notifications.shown, isEmpty, reason: caseToken);
    expect(
      freshVisibleSuppressions,
      isEmpty,
      reason: '$caseToken must bypass the legacy pre-ledger suppression exit',
    );
  }

  if (kind == _ProtectedKind.message) {
    final row = await dbLoadGroupMessage(database, messageId);
    expect(row?['notification_display_terminal_event_id'], durableCorrelation);
  } else {
    final row = await dbLoadActiveOrTombstonedReactionForSender(
      database,
      messageId,
      _senderPeerId,
    );
    expect(row?['notification_display_terminal_event_id'], durableCorrelation);
  }

  await listener.stop();
  listener.dispose();
}

/// Builds the protected/replay reaction display row for one seeded target.
///
/// Plan 386 TC-386-09. The staging case above is the ONLY exercise the
/// protected twin has, and it seeds an author-owned target
/// (`senderPeerId: _localPeerId`, `isIncoming: false`), so the author-only
/// clause at `group_message_listener.dart:3651` could be deleted without
/// reddening anything. These rows drive the twin directly with the two
/// audiences PRD §6.5 says must stay silent.
Future<Map<String, Object?>?> _protectedReactionRowFor({
  required Database database,
  required _ReplayAuthority replay,
  required DurableConversationNotificationIdRegistry durableRegistry,
  required String targetSenderPeerId,
  required bool targetIsIncoming,
  required String reactorPeerId,
  required String caseToken,
}) async {
  final messageId = 'audience-target-$caseToken';
  final target = GroupMessage(
    id: messageId,
    groupId: _groupId,
    senderPeerId: targetSenderPeerId,
    senderUsername: targetSenderPeerId == _localPeerId ? 'Local' : 'Sender',
    text: 'Audience rule target',
    timestamp: DateTime.utc(2026, 8, 15, 10, 10),
    isIncoming: targetIsIncoming,
    createdAt: DateTime.utc(2026, 8, 15, 10, 10),
  );
  expect(await dbInsertGroupMessage(database, target.toMap()), isTrue);

  final notifications = _DurableFakeNotificationService(durableRegistry);
  final outbox = _SqlDisplayOutbox(database);
  final listener = GroupMessageListener(
    groupRepo: replay.groupRepository,
    msgRepo: _SqlMessageRepository(database),
    bridge: replay.bridge,
    getSelfPeerId: () async => _localPeerId,
    notificationService: notifications,
    appVisibility: _MutableVisibility(
      expectedGroupId: _groupId,
      evaluation: _backgroundVisibility,
    ),
    reactionRepo: _SqlReactionRepository(database),
    remoteNotificationGate: _NoopRecentRemoteNotificationGate(),
    notificationDisplayOutbox: outbox.repository,
    resolveCompletedOutcomePhysicalPeerId: () async => _physicalPeerId,
    resolveCurrentOpaqueBinding: () async => _currentOpaqueBinding,
    durableLocalNotificationEffectRegistry: durableRegistry,
    durableNotificationCoordinatorResolver: () async {
      throw StateError('durable tone claims are outside TC-386-09');
    },
  );
  addTearDown(() async {
    await listener.stop();
    listener.dispose();
  });

  final reactionAt = DateTime.parse(_eventTimestamp);
  return listener.buildProtectedReactionDisplayReadyRow(
    _groupId,
    GroupReactionPayload(
      id: deterministicGroupReactionStateId(
        groupId: _groupId,
        messageId: messageId,
        logicalActorPeerId: reactorPeerId,
      ),
      messageId: messageId,
      emoji: '👍',
      action: GroupReactionPayload.actionAdd,
      senderPeerId: reactorPeerId,
      timestamp: _eventTimestamp,
      eventId: buildGroupReactionTransitionId(
        groupId: _groupId,
        messageId: messageId,
        logicalActorPeerId: reactorPeerId,
        action: GroupReactionPayload.actionAdd,
        emoji: '👍',
        timestamp: reactionAt,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'TC-371-05b protected message and reaction stage before the canonical visibility decision',
    () async {
      final previousFlowLogging = flowEventLoggingEnabled;
      flowEventLoggingEnabled = false;
      addTearDown(() {
        debugSetFlowEventSink(null);
        flowEventLoggingEnabled = previousFlowLogging;
      });
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
        ),
      );
      addTearDown(() async {
        if (database.isOpen) await database.close();
      });
      final replay = await _buildReplayAuthority(database);
      final ledgerRoot = await Directory.systemTemp.createTemp(
        'plan372-group-visibility-',
      );
      addTearDown(() async {
        if (await ledgerRoot.exists()) {
          await ledgerRoot.delete(recursive: true);
        }
      });
      final ledgerDirectory = Directory(
        '${ledgerRoot.path}${Platform.pathSeparator}'
        '${DurableConversationNotificationIdRegistry.directoryName}',
      );
      final ledgerStore = LocalNotificationLedgerStore(
        directory: ledgerDirectory,
        nowUtc: () => _projectionNow,
      );
      expect(
        await ledgerStore.initializeOrRebind(
          currentOpaqueBinding: _currentOpaqueBinding,
        ),
        isNotNull,
      );
      final durableRegistry = DurableConversationNotificationIdRegistry(
        directory: ledgerDirectory,
        localNotificationEffectCoordinator:
            DurableLocalNotificationEffectCoordinator(
              ledgerStore: ledgerStore,
              nowUtc: () => _projectionNow,
            ),
      );

      for (final kind in _ProtectedKind.values) {
        for (final visibilityCase in _VisibilityCase.values) {
          await _exerciseVisibilityCase(
            database: database,
            replay: replay,
            durableRegistry: durableRegistry,
            kind: kind,
            visibilityCase: visibilityCase,
          );
        }
      }
    },
  );

  // ---------------------------------------------------------------------
  // Plan 386 W3 (G18, partial) — PRD §6.5 / AC-13: a group reaction alerts
  // ONLY the target's author, and never the reactor.
  //
  // The live twin is covered at host tier (`group_message_listener_test.dart`
  // :17159-17258, :16983, :17074, :17033). The PROTECTED/replay twin was not:
  // its only exercise seeds an author-owned target, so both guards were dead
  // weight the suite could not see.
  // ---------------------------------------------------------------------
  group('Plan 386 protected reaction audience', () {
    late Database database;
    late _ReplayAuthority replay;
    late DurableConversationNotificationIdRegistry durableRegistry;

    setUp(() async {
      final previousFlowLogging = flowEventLoggingEnabled;
      flowEventLoggingEnabled = false;
      addTearDown(() {
        debugSetFlowEventSink(null);
        flowEventLoggingEnabled = previousFlowLogging;
      });
      database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
        ),
      );
      addTearDown(() async {
        if (database.isOpen) await database.close();
      });
      replay = await _buildReplayAuthority(database);
      final ledgerRoot = await Directory.systemTemp.createTemp(
        'plan386-protected-audience-',
      );
      addTearDown(() async {
        if (await ledgerRoot.exists()) {
          await ledgerRoot.delete(recursive: true);
        }
      });
      final ledgerDirectory = Directory(
        '${ledgerRoot.path}${Platform.pathSeparator}'
        '${DurableConversationNotificationIdRegistry.directoryName}',
      );
      final ledgerStore = LocalNotificationLedgerStore(
        directory: ledgerDirectory,
        nowUtc: () => _projectionNow,
      );
      expect(
        await ledgerStore.initializeOrRebind(
          currentOpaqueBinding: _currentOpaqueBinding,
        ),
        isNotNull,
      );
      durableRegistry = DurableConversationNotificationIdRegistry(
        directory: ledgerDirectory,
        localNotificationEffectCoordinator:
            DurableLocalNotificationEffectCoordinator(
              ledgerStore: ledgerStore,
              nowUtc: () => _projectionNow,
            ),
      );
    });

    test('protected reaction row is staged for the target author', () async {
      // The positive control. Without it "returns null" is satisfied by a
      // twin that returns null for everything, including a real alert.
      expect(
        await _protectedReactionRowFor(
          database: database,
          replay: replay,
          durableRegistry: durableRegistry,
          targetSenderPeerId: _localPeerId,
          targetIsIncoming: false,
          reactorPeerId: _senderPeerId,
          caseToken: 'author',
        ),
        isNotNull,
      );
    });

    test('protected reaction row is null for a non-author target', () async {
      // Someone else's message was reacted to. The local device must still
      // RECEIVE and store the reaction (PRD :226/:229/:232) — it just must not
      // alert. This is the shape the audience rule actually meets in
      // production: a foreign author and an incoming row.
      expect(
        await _protectedReactionRowFor(
          database: database,
          replay: replay,
          durableRegistry: durableRegistry,
          targetSenderPeerId: _senderPeerId,
          targetIsIncoming: true,
          reactorPeerId: _senderPeerId,
          caseToken: 'non-author',
        ),
        isNull,
      );
    });

    test(
      'protected reaction row is null for a non-author target that is not '
      'flagged incoming',
      () async {
        // The row above is ALSO caught by the `target.isIncoming` guard, so on
        // its own it cannot tell whether the author check does any work:
        // deleting `target.senderPeerId != selfPeerId` leaves it green
        // (verified by mutation). This row separates the two by asserting on
        // authorship alone — a foreign author whose row is not flagged
        // incoming. Deleting the author-only clause at
        // `group_message_listener.dart:3651` turns this null into a staged
        // row, which is the whole point of keeping the clause.
        expect(
          await _protectedReactionRowFor(
            database: database,
            replay: replay,
            durableRegistry: durableRegistry,
            targetSenderPeerId: _senderPeerId,
            targetIsIncoming: false,
            reactorPeerId: _senderPeerId,
            caseToken: 'non-author-not-incoming',
          ),
          isNull,
        );
      },
    );

    test('protected reaction row is null for a self-reaction', () async {
      // The local device authored the target AND the reaction. Deleting the
      // self clause at `group_message_listener.dart:3648` makes the device
      // alert its own user about their own reaction.
      expect(
        await _protectedReactionRowFor(
          database: database,
          replay: replay,
          durableRegistry: durableRegistry,
          targetSenderPeerId: _localPeerId,
          targetIsIncoming: false,
          reactorPeerId: _localPeerId,
          caseToken: 'self',
        ),
        isNull,
      );
    });
  });
}
