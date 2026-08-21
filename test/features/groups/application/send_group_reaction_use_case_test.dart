import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_authoring_resolver.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_group_reaction_replay_outbox_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../test/features/conversation/domain/repositories/fake_reaction_repository.dart';

/// A [FakeBridge] that throws when the live reaction publish is attempted,
/// while letting every other command (sign / inboxStore) succeed normally.
class _ThrowingPublishReactionBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    if (parsed['cmd'] == 'group:publishReaction') {
      throw Exception('FakeBridge: publishReaction error');
    }
    return super.send(message);
  }
}

Map<String, dynamic> _replayEnvelopeFromRetryPayload(String retryPayload) {
  final payload = jsonDecode(retryPayload) as Map<String, dynamic>;
  return jsonDecode(payload['message'] as String) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _inboxStoreCommands(FakeBridge bridge) => bridge
    .sentMessages
    .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
    .where((message) => message['cmd'] == 'group:inboxStore')
    .toList(growable: false);

List<String> _stringList(Object? value) =>
    (value as List<dynamic>).cast<String>();

void _expectSignedReactionReplayEnvelope(Map<String, dynamic> envelope) {
  expect(envelope['kind'], 'group_offline_replay');
  expect(envelope['payloadType'], 'group_reaction');
  expect(envelope['senderPeerId'], 'peer-1');
  expect(envelope['senderPublicKey'], 'pk-1');
  expect(envelope['signatureAlgorithm'], 'ed25519');
  expect(envelope['signedPayload'], isA<String>());
  expect(envelope['signature'], isA<String>());
  final signedPayload =
      jsonDecode(envelope['signedPayload'] as String) as Map<String, dynamic>;
  expect(signedPayload['kind'], 'group_offline_replay');
  expect(signedPayload['payloadType'], 'group_reaction');
  expect(signedPayload['senderPeerId'], 'peer-1');
  expect(signedPayload['senderSigningPublicKey'], 'pk-1');
  expect(signedPayload['messageId'], envelope['messageId']);
  expect(signedPayload['plaintextHash'], isA<String>());
}

Future<T> _captureFlowEvents<T>(
  List<Map<String, dynamic>> events,
  Future<T> Function() action,
) async {
  debugSetFlowEventSink(events.add);
  try {
    return await action();
  } finally {
    debugSetFlowEventSink(null);
  }
}

class _StrictReactionOutbox extends FakeGroupReactionReplayOutboxRepository
    implements
        GroupReactionReplayPayloadCasRepository,
        GroupReactionStrictContentCompletionRepository,
        GroupReactionStrictLocalTerminalRepository,
        GroupReactionStrictPreparedRepository {
  final List<Map<String, Object?>> completedRows = <Map<String, Object?>>[];

  bool _same(
    GroupReactionReplayOutboxEntry current,
    GroupReactionReplayOutboxEntry expected,
  ) =>
      current.reactionId == expected.reactionId &&
      current.groupId == expected.groupId &&
      current.messageId == expected.messageId &&
      current.senderPeerId == expected.senderPeerId &&
      current.emoji == expected.emoji &&
      current.action == expected.action &&
      current.inboxRetryPayload == expected.inboxRetryPayload &&
      current.deliveryStatus == expected.deliveryStatus &&
      current.createdAt == expected.createdAt &&
      current.updatedAt == expected.updatedAt;

  @override
  Future<bool> replaceInboxRetryPayloadIfExact(
    GroupReactionReplayOutboxEntry expected,
    String replacement,
  ) async {
    final current = await getEntry(expected.reactionId);
    if (current == null || !_same(current, expected)) return false;
    return saveEntry(
      current.copyWith(
        inboxRetryPayload: replacement,
        updatedAt: current.updatedAt,
      ),
    );
  }

  @override
  Future<bool> completeStrictContentIfExact(
    GroupReactionReplayOutboxEntry expected, {
    required Map<String, Object?> reactionRow,
    required String action,
    required String transitionId,
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> eventPayload,
  }) async {
    final current = await getEntry(expected.reactionId);
    if (current == null ||
        !_same(current, expected) ||
        current.action != action) {
      return false;
    }
    completedRows.add(
      Map<String, Object?>.unmodifiable(<String, Object?>{
        ...reactionRow,
        'transition_id': transitionId,
        'source_peer_id': sourcePeerId,
        'source_event_id': sourceEventId,
        'source_timestamp': sourceTimestamp,
        'event_payload': eventPayload,
      }),
    );
    return saveEntry(
      current.copyWith(
        deliveryStatus: GroupReactionReplayOutboxStatus.stored,
        lastError: null,
        updatedAt: current.updatedAt,
      ),
    );
  }

  @override
  Future<bool> stageAndCompleteStrictLocalContent(
    GroupReactionReplayOutboxEntry entry, {
    required Map<String, Object?> reactionRow,
    required String action,
    required String transitionId,
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> eventPayload,
  }) async {
    if (await getEntry(entry.reactionId) != null) return false;
    completedRows.add(
      Map<String, Object?>.unmodifiable(<String, Object?>{
        ...reactionRow,
        'transition_id': transitionId,
        'source_peer_id': sourcePeerId,
        'source_event_id': sourceEventId,
        'source_timestamp': sourceTimestamp,
        'event_payload': eventPayload,
      }),
    );
    return saveEntry(entry);
  }

  @override
  Future<bool> stageStrictContentPrepared(
    GroupReactionReplayOutboxEntry entry, {
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> preparedEventPayload,
  }) async {
    if (await getEntry(entry.reactionId) != null) return false;
    completedRows.add(<String, Object?>{
      'source_peer_id': sourcePeerId,
      'source_event_id': sourceEventId,
      'source_timestamp': sourceTimestamp,
      'event_payload': preparedEventPayload,
    });
    return saveEntry(entry);
  }
}

class _PersistAwareStrictReactionStore implements AckOrExpiryInboxStore {
  _PersistAwareStrictReactionStore(this.repository);

  final _StrictReactionOutbox repository;
  final List<String> recipients = <String>[];
  bool everyStoreObservedDurableRow = true;

  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async {
    expect(custodyKind, AckCustodyKind.groupContentV1);
    everyStoreObservedDurableRow =
        everyStoreObservedDurableRow && repository.entries.isNotEmpty;
    recipients.add(toPeerId);
    return const InboxStoreOutcome(
      status: InboxStoreStatus.stored,
      storeStatus: 'stored',
      custodyContract: ackOrExpiryInboxCustodyContract,
    );
  }
}

class _ThrowingStrictReactionStore implements AckOrExpiryInboxStore {
  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async {
    throw StateError('injected strict custody outage');
  }
}

class _TerminalizingStrictReactionStore implements AckOrExpiryInboxStore {
  _TerminalizingStrictReactionStore(this.repository);

  final _StrictReactionOutbox repository;
  bool terminalized = false;

  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async {
    final current = repository.entries.single;
    await repository.saveEntry(
      current.copyWith(
        inboxRetryPayload: '',
        deliveryStatus: GroupReactionReplayOutboxStatus.stored,
        lastError: 'protected_content_sender_authority_stale',
      ),
    );
    terminalized = true;
    return const InboxStoreOutcome(
      status: InboxStoreStatus.stored,
      storeStatus: 'stored',
      custodyContract: ackOrExpiryInboxCustodyContract,
    );
  }
}

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late FakeReactionRepository reactionRepo;
  late FakeGroupReactionReplayOutboxRepository reactionReplayOutboxRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-1',
    myRole: GroupRole.admin,
  );

  final testMember = GroupMember(
    groupId: 'group-1',
    peerId: 'peer-1',
    username: 'Alice',
    role: MemberRole.admin,
    publicKey: 'pk-1',
    joinedAt: DateTime.now().toUtc(),
  );

  final testMessage = GroupMessage(
    id: 'msg-1',
    groupId: 'group-1',
    senderPeerId: 'peer-2',
    senderUsername: 'Bob',
    text: 'Hello!',
    timestamp: DateTime.now().toUtc(),
    keyGeneration: 0,
    status: 'delivered',
    isIncoming: true,
    createdAt: DateTime.now().toUtc(),
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    reactionRepo = FakeReactionRepository();
    reactionReplayOutboxRepo = FakeGroupReactionReplayOutboxRepository();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(testMember);
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 0,
        encryptedKey: 'group-key-0',
        createdAt: DateTime.now().toUtc(),
      ),
    );
    await msgRepo.saveMessage(testMessage);

    bridge.responses['group:publishReaction'] = {'ok': true};
  });

  tearDown(() => setGroupContentAuthoringResolver(groupRepo, null));

  test(
    'TC-377-03 self-bound roster keeps legacy reaction add and remove',
    () async {
      // Production creator-stamp shape (create_group_with_members_use_case
      // .dart:229-234): the only device is self-bound, so the roster is NOT
      // initialized under the wave's own definition and both reaction lanes
      // must stay on the incumbent legacy transport.
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'pk-1',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'peer-1',
              transportPeerId: 'peer-1',
              deviceSigningPublicKey: 'pk-1',
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 16),
        ),
      );
      setGroupContentAuthoringResolver(
        groupRepo,
        buildProtectedGroupContentAuthoringResolver(
          loadIdentity: () async => (peerId: 'peer-1', publicKey: 'pk-1'),
          loadMember: groupRepo.getMember,
          loadInstallationAuthority: (_) async =>
              const LinkedInstallationAuthoritySnapshot(
                disposition: LinkedInstallationDisposition.primary,
                credential: null,
                failClosedReason: null,
              ),
          loadLatestSettledAuthority: (_) async => null,
          readCurrentTransportPeerId: () => null,
          inboxStore: _ThrowingStrictReactionStore(),
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
        ),
      );

      final add = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '\u{1F44D}',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );
      expect(add.$1, SendGroupReactionResult.success);
      expect(add.$2, isNotNull);
      expect(await reactionRepo.getReactionsForMessage('msg-1'), hasLength(1));

      final remove = await removeGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '\u{1F44D}',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        msgRepo: msgRepo,
        targetMessage: testMessage,
      );
      expect(remove, RemoveGroupReactionResult.success);
      expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
    },
  );

  test(
    'TC-364-02a strict ADD REMOVE use stable state and deterministic gr1 custody',
    () async {
      final strictOutbox = _StrictReactionOutbox();
      final strictStore = _PersistAwareStrictReactionStore(strictOutbox);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'account-pk',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-key-alias',
              transportPeerId: 'transport-key-alias',
              deviceSigningPublicKey: 'linked-pk',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'device-current',
              transportPeerId: 'transport-current',
              deviceSigningPublicKey: 'linked-pk',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'device-sibling',
              transportPeerId: 'transport-sibling',
              deviceSigningPublicKey: 'sibling-pk',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'device-revoked',
              transportPeerId: 'transport-revoked',
              deviceSigningPublicKey: 'revoked-pk',
              status: GroupMemberDeviceStatus.revoked,
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-remote',
              transportPeerId: 'transport-remote',
              deviceSigningPublicKey: 'remote-pk',
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-3',
          username: 'Mallory',
          role: MemberRole.writer,
          publicKey: 'pk-3',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-remote-collision',
              transportPeerId: 'transport-remote',
              deviceSigningPublicKey: 'remote-collision-pk',
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      final credential = LinkedTransportCredential(
        state: LinkedTransportCredentialState.active,
        accountPeerId: 'peer-1',
        accountPublicKey: 'account-pk',
        deviceId: 'device-current',
        transportPeerId: 'transport-current',
        transportPublicKey: 'linked-pk',
        transportPrivateKey: 'linked-sk',
        createdAt: '2026-08-13T10:00:00.000Z',
        activatedAt: '2026-08-13T10:00:01.000Z',
      );
      final context = GroupContentAuthoringContext(
        directLinkedDeviceSelector: const DirectLinkedDeviceSelector.enabled(),
        multiDeviceSyncEnabled: true,
        authorityVersion: GroupContentAuthorityVersion(
          eventAt: DateTime.utc(2026, 8, 13, 11),
          eventId: 'authority.tc364.02a',
          keyEpoch: 0,
        ),
        inboxStore: strictStore,
        linkedTransportCredential: credential,
        requireLinkedTransportCredential: true,
      );
      final authoredAt = DateTime.utc(2026, 8, 13, 12, 0, 0, 0, 1);

      final strictEvents = <Map<String, dynamic>>[];
      final add = await _captureFlowEvents(
        strictEvents,
        () => sendGroupReaction(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          reactionRepo: reactionRepo,
          reactionReplayOutboxRepo: strictOutbox,
          groupId: 'group-1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: 'peer-1',
          senderPublicKey: 'account-pk',
          senderPrivateKey: 'account-sk',
          groupContentAuthoring: context,
          authoredAt: authoredAt,
        ),
      );
      expect(add.$1, SendGroupReactionResult.success);
      expect(add.$2, isNotNull);
      final queued = strictEvents.singleWhere(
        (event) => event['event'] == 'GROUP_REACTION_SEND_QUEUED',
      );
      expect(
        queued['details'],
        containsPair('deliveryMode', 'strict_inbox_custody'),
      );
      expect(queued['details'], containsPair('deliveryConfirmed', false));
      expect(queued['details'], containsPair('replayStatus', 'stored'));
      expect(queued['details'], containsPair('strictCustodyComplete', true));
      final addEntry = strictOutbox.entries.single;
      final addOrder = GroupReactionTransitionOrder.tryParse(
        addEntry.reactionId,
      );
      expect(addOrder, isNotNull);
      final addRetry = GroupContentRetryPayload.decode(
        addEntry.inboxRetryPayload,
      );
      expect(addRetry.fullRecipientPeerIds, <String>[
        'transport-key-alias',
        'transport-sibling',
      ]);
      final addEnvelope = _replayEnvelopeFromRetryPayload(
        addEntry.inboxRetryPayload,
      );
      expect(addEnvelope['senderDeviceId'], 'device-current');
      expect(addEnvelope['senderTransportPeerId'], 'transport-current');
      expect(addEnvelope['senderPublicKey'], 'linked-pk');
      expect(addEnvelope['messageId'], addEntry.reactionId);
      expect(addEnvelope['contentEventId'], addEntry.reactionId);
      final addPlaintext =
          jsonDecode(addEnvelope['ciphertext'] as String)
              as Map<String, dynamic>;

      strictStore.recipients.clear();
      final remove = await removeGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: strictOutbox,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'account-pk',
        senderPrivateKey: 'account-sk',
        groupContentAuthoring: context,
        msgRepo: msgRepo,
        targetMessage: testMessage,
        authoredAt: authoredAt,
      );
      expect(remove, RemoveGroupReactionResult.success);
      final removeEntry = strictOutbox.entries.last;
      final removeOrder = GroupReactionTransitionOrder.tryParse(
        removeEntry.reactionId,
      );
      expect(removeOrder, isNotNull);
      expect(removeEntry.reactionId, isNot(addEntry.reactionId));
      final addVsRemove = compareGroupReactionTransitionIds(
        addEntry.reactionId,
        removeEntry.reactionId,
      );
      expect(
        addVsRemove,
        isNot(0),
        reason:
            'equal-time strict transitions require the deterministic ID tie-break',
      );
      expect(
        addVsRemove,
        -compareGroupReactionTransitionIds(
          removeEntry.reactionId,
          addEntry.reactionId,
        ),
      );
      final expectedWinner = addVsRemove > 0
          ? addEntry.reactionId
          : removeEntry.reactionId;
      String converge(Iterable<String> arrivalOrder) {
        var incumbent = arrivalOrder.first;
        for (final candidate in arrivalOrder.skip(1)) {
          if (compareGroupReactionTransitionIds(candidate, incumbent) > 0) {
            incumbent = candidate;
          }
        }
        return incumbent;
      }

      final forwardProjection = converge(<String>[
        addEntry.reactionId,
        removeEntry.reactionId,
      ]);
      final reverseProjection = converge(<String>[
        removeEntry.reactionId,
        addEntry.reactionId,
      ]);
      expect(forwardProjection, expectedWinner);
      expect(reverseProjection, expectedWinner);
      expect(
        converge(<String>[
          forwardProjection,
          addEntry.reactionId,
          removeEntry.reactionId,
        ]),
        expectedWinner,
        reason: 'a restarted reducer must retain the same equal-time winner',
      );
      final removeEnvelope = _replayEnvelopeFromRetryPayload(
        removeEntry.inboxRetryPayload,
      );
      final removePlaintext =
          jsonDecode(removeEnvelope['ciphertext'] as String)
              as Map<String, dynamic>;
      expect(removePlaintext['id'], addPlaintext['id']);
      expect(removePlaintext['eventId'], removeEntry.reactionId);
      expect(strictStore.recipients, <String>[
        'transport-key-alias',
        'transport-sibling',
      ]);
      expect(removeEnvelope['senderDeviceId'], 'device-current');
      expect(removeEnvelope['senderTransportPeerId'], 'transport-current');
      expect(removeEnvelope['senderPublicKey'], 'linked-pk');
      expect(strictStore.everyStoreObservedDurableRow, isTrue);
      expect(
        strictOutbox.completedRows.where(
          (row) =>
              row['source_event_id'] ==
                  localProtectedGroupReactionSourceEventId(
                    addEntry.reactionId,
                  ) ||
              row['source_event_id'] ==
                  localProtectedGroupReactionSourceEventId(
                    removeEntry.reactionId,
                  ),
        ),
        hasLength(2),
      );
      expect(
        bridge.commandLog.where(
          (command) =>
              command == 'group:publishReaction' ||
              command == 'group:publish' ||
              command == 'group:sendReliable',
        ),
        isEmpty,
      );

      final unbound = await removeGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: strictOutbox,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'account-pk',
        senderPrivateKey: 'account-sk',
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: context.authorityVersion,
          inboxStore: strictStore,
          linkedTransportCredential: LinkedTransportCredential(
            state: LinkedTransportCredentialState.active,
            accountPeerId: 'other-account',
            accountPublicKey: 'other-pk',
            deviceId: 'device-current',
            transportPeerId: 'transport-current',
            transportPublicKey: 'linked-pk',
            transportPrivateKey: 'linked-sk',
            createdAt: credential.createdAt,
            activatedAt: credential.activatedAt,
          ),
          requireLinkedTransportCredential: true,
        ),
        msgRepo: msgRepo,
        targetMessage: testMessage,
        authoredAt: authoredAt.add(const Duration(microseconds: 1)),
      );
      expect(unbound, RemoveGroupReactionResult.notMember);

      // Only an exact pending PREPARED owner is a truthful queued result. A
      // terminalized owner is a nonqueued refusal so the wired UI can revert.
      final pendingOutbox = _StrictReactionOutbox();
      final pendingRemove = await removeGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: pendingOutbox,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'account-pk',
        senderPrivateKey: 'account-sk',
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: context.authorityVersion,
          inboxStore: _ThrowingStrictReactionStore(),
          linkedTransportCredential: credential,
          requireLinkedTransportCredential: true,
        ),
        msgRepo: msgRepo,
        targetMessage: testMessage,
        authoredAt: authoredAt.add(const Duration(seconds: 2)),
      );
      expect(pendingRemove, RemoveGroupReactionResult.queuedForRetry);
      expect(
        pendingOutbox.entries.single.deliveryStatus,
        GroupReactionReplayOutboxStatus.pending,
      );

      final terminalOutbox = _StrictReactionOutbox();
      final terminalStore = _TerminalizingStrictReactionStore(terminalOutbox);
      final terminalRemove = await removeGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: terminalOutbox,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'account-pk',
        senderPrivateKey: 'account-sk',
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: context.authorityVersion,
          inboxStore: terminalStore,
          linkedTransportCredential: credential,
          requireLinkedTransportCredential: true,
        ),
        msgRepo: msgRepo,
        targetMessage: testMessage,
        authoredAt: authoredAt.add(const Duration(seconds: 3)),
      );
      expect(terminalStore.terminalized, isTrue);
      expect(terminalRemove, RemoveGroupReactionResult.notMember);
      expect(
        terminalOutbox.entries.single.deliveryStatus,
        GroupReactionReplayOutboxStatus.stored,
      );

      // Authority drift before PREPARED creates no durable owner and is a
      // nonqueued refusal.
      var driftResolutionCalls = 0;
      setGroupContentAuthoringResolver(groupRepo, ({
        required groupId,
        required senderPeerId,
        required senderPublicKey,
        senderDeviceId,
        senderTransportPeerId,
      }) async {
        driftResolutionCalls++;
        return driftResolutionCalls == 1
            ? (
                kind: GroupContentAuthoringResolutionKind.strict,
                context: context,
              )
            : const (
                kind: GroupContentAuthoringResolutionKind.refuse,
                context: null,
              );
      });
      final driftOutbox = _StrictReactionOutbox();
      final preStageDrift = await removeGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: driftOutbox,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'account-pk',
        senderPrivateKey: 'account-sk',
        groupContentAuthoring: context,
        msgRepo: msgRepo,
        targetMessage: testMessage,
        authoredAt: authoredAt.add(const Duration(seconds: 4)),
      );
      expect(preStageDrift, RemoveGroupReactionResult.notMember);
      expect(driftOutbox.entries, isEmpty);
      setGroupContentAuthoringResolver(groupRepo, null);

      // An installed active-linked decision is consulted even with an empty
      // device projection. Both ADD and REMOVE refuse with zero legacy effects.
      final emptyLinkedRepo = InMemoryGroupRepository();
      await emptyLinkedRepo.saveGroup(testGroup);
      await emptyLinkedRepo.saveMember(testMember);
      await emptyLinkedRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 0,
          encryptedKey: 'group-key-0',
          createdAt: DateTime.utc(2026, 8, 13),
        ),
      );
      final emptyLinkedMessages = InMemoryGroupMessageRepository();
      await emptyLinkedMessages.saveMessage(testMessage);
      final emptyLinkedOutbox = _StrictReactionOutbox();
      final emptyLinkedBridge = FakeBridge();
      var emptyLinkedResolutions = 0;
      setGroupContentAuthoringResolver(
        emptyLinkedRepo,
        buildProtectedGroupContentAuthoringResolver(
          loadIdentity: () async => (peerId: 'peer-1', publicKey: 'pk-1'),
          loadMember: emptyLinkedRepo.getMember,
          loadInstallationAuthority: (_) async {
            emptyLinkedResolutions++;
            return LinkedInstallationAuthoritySnapshot(
              disposition: LinkedInstallationDisposition.active,
              credential: LinkedTransportCredential(
                state: LinkedTransportCredentialState.active,
                accountPeerId: 'peer-1',
                accountPublicKey: 'pk-1',
                deviceId: 'device-linked',
                transportPeerId: 'transport-linked',
                transportPublicKey: 'linked-pk',
                transportPrivateKey: 'linked-sk',
                createdAt: '2026-08-13T10:00:00.000Z',
                activatedAt: '2026-08-13T10:00:01.000Z',
              ),
              failClosedReason: null,
            );
          },
          loadLatestSettledAuthority: (_) async => null,
          readCurrentTransportPeerId: () => 'transport-linked',
          inboxStore: _ThrowingStrictReactionStore(),
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
        ),
      );
      final emptyLinkedAdd = await sendGroupReaction(
        bridge: emptyLinkedBridge,
        groupRepo: emptyLinkedRepo,
        msgRepo: emptyLinkedMessages,
        reactionRepo: FakeReactionRepository(),
        reactionReplayOutboxRepo: emptyLinkedOutbox,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '❌',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );
      final emptyLinkedRemove = await removeGroupReaction(
        bridge: emptyLinkedBridge,
        groupRepo: emptyLinkedRepo,
        reactionRepo: FakeReactionRepository(),
        reactionReplayOutboxRepo: emptyLinkedOutbox,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '❌',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        msgRepo: emptyLinkedMessages,
        targetMessage: testMessage,
      );
      expect(emptyLinkedAdd.$1, SendGroupReactionResult.unauthorizedSenderKey);
      expect(emptyLinkedRemove, RemoveGroupReactionResult.authorityUnavailable);
      expect(emptyLinkedResolutions, 2);
      expect(emptyLinkedBridge.commandLog, isEmpty);
      expect(emptyLinkedOutbox.entries, isEmpty);
      setGroupContentAuthoringResolver(emptyLinkedRepo, null);

      // Without installed role authority, the same empty roster is preserved
      // as the ordinary-primary legacy lane.
      final primaryRepo = InMemoryGroupRepository();
      await primaryRepo.saveGroup(testGroup);
      await primaryRepo.saveMember(testMember);
      await primaryRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 0,
          encryptedKey: 'group-key-0',
          createdAt: DateTime.utc(2026, 8, 13),
        ),
      );
      final primaryMessages = InMemoryGroupMessageRepository();
      await primaryMessages.saveMessage(testMessage);
      final primaryBridge = FakeBridge();
      primaryBridge.responses['group:publishReaction'] = {'ok': true};
      final primaryOutbox = FakeGroupReactionReplayOutboxRepository();
      final primaryReactions = FakeReactionRepository();
      var primaryInstallationLoads = 0;
      setGroupContentAuthoringResolver(
        primaryRepo,
        buildProtectedGroupContentAuthoringResolver(
          loadIdentity: () async => (peerId: 'peer-1', publicKey: 'pk-1'),
          loadMember: primaryRepo.getMember,
          loadInstallationAuthority: (_) async {
            primaryInstallationLoads++;
            return const LinkedInstallationAuthoritySnapshot(
              disposition: LinkedInstallationDisposition.primary,
              credential: null,
              failClosedReason: null,
            );
          },
          loadLatestSettledAuthority: (_) async => null,
          readCurrentTransportPeerId: () => null,
          inboxStore: _ThrowingStrictReactionStore(),
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
        ),
      );
      final primaryAdd = await sendGroupReaction(
        bridge: primaryBridge,
        groupRepo: primaryRepo,
        msgRepo: primaryMessages,
        reactionRepo: primaryReactions,
        reactionReplayOutboxRepo: primaryOutbox,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '✅',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );
      final primaryRemove = await removeGroupReaction(
        bridge: primaryBridge,
        groupRepo: primaryRepo,
        reactionRepo: primaryReactions,
        reactionReplayOutboxRepo: primaryOutbox,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '✅',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        msgRepo: primaryMessages,
        targetMessage: testMessage,
      );
      expect(primaryAdd.$1, SendGroupReactionResult.success);
      expect(primaryRemove, RemoveGroupReactionResult.success);
      expect(primaryInstallationLoads, greaterThanOrEqualTo(4));
      expect(
        primaryBridge.commandLog.where(
          (command) => command == 'group:publishReaction',
        ),
        hasLength(2),
      );
      setGroupContentAuthoringResolver(primaryRepo, null);

      final resolverEntered = Completer<void>();
      final releaseResolver = Completer<void>();
      setGroupContentAuthoringResolver(groupRepo, ({
        required groupId,
        required senderPeerId,
        required senderPublicKey,
        senderDeviceId,
        senderTransportPeerId,
      }) async {
        if (!resolverEntered.isCompleted) resolverEntered.complete();
        await releaseResolver.future;
        return (
          kind: GroupContentAuthoringResolutionKind.strict,
          context: context,
        );
      });
      final autoResolved = sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: strictOutbox,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '✅',
        senderPeerId: 'peer-1',
        senderPublicKey: 'account-pk',
        senderPrivateKey: 'account-sk',
        authoredAt: authoredAt.add(const Duration(seconds: 1)),
      );
      await resolverEntered.future;
      var competingAuthorityEntered = false;
      final competingAuthority = runGroupAuthorityPhase(
        groupId: 'group-1',
        action: () async {
          competingAuthorityEntered = true;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        competingAuthorityEntered,
        isFalse,
        reason: 'resolution and strict commit share the keyed authority phase',
      );
      releaseResolver.complete();
      expect((await autoResolved).$1, SendGroupReactionResult.success);
      await competingAuthority;
      expect(competingAuthorityEntered, isTrue);
    },
  );

  test(
    'TC-393-07 strict ADD signs only the target author device wake subset',
    () async {
      await groupRepo.saveMember(
        testMember.copyWith(
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'reactor-device',
              transportPeerId: 'transport-reactor',
              deviceSigningPublicKey: 'pk-1',
            ),
          ],
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'author-device',
              transportPeerId: 'transport-author',
              deviceSigningPublicKey: 'pk-2',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'revoked-author-device',
              transportPeerId: 'transport-author-revoked',
              deviceSigningPublicKey: 'pk-2-revoked',
              status: GroupMemberDeviceStatus.revoked,
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-3',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-3',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'bystander-device',
              transportPeerId: 'transport-bystander',
              deviceSigningPublicKey: 'pk-3',
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      final strictOutbox = _StrictReactionOutbox();
      final strictStore = _PersistAwareStrictReactionStore(strictOutbox);

      final result = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: strictOutbox,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 20, 10),
            eventId: 'authority.tc393.07',
            keyEpoch: 0,
          ),
          inboxStore: strictStore,
        ),
        authoredAt: DateTime.utc(2026, 8, 20, 11),
      );

      expect(result.$1, SendGroupReactionResult.success);
      final envelope = _replayEnvelopeFromRetryPayload(
        strictOutbox.entries.single.inboxRetryPayload,
      );
      expect(envelope['recipientPeerIds'], <String>[
        'transport-author',
        'transport-bystander',
      ]);
      final extension =
          envelope['notificationExtension'] as Map<String, dynamic>;
      expect(extension['notificationRecipientTransportPeerIds'], <String>[
        'transport-author',
      ]);
      expect(
        extension['notificationRecipientTransportPeerIds'],
        isNot(contains('transport-bystander')),
      );
      expect(
        jsonEncode(extension),
        isNot(contains('transport-author-revoked')),
      );
    },
  );

  test(
    'resolver-absent initialized roster preserves legacy ADD REMOVE while installed refusal is all-zero',
    () async {
      await groupRepo.saveMember(
        testMember.copyWith(
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-primary',
              transportPeerId: 'transport-primary',
              deviceSigningPublicKey: 'pk-1',
            ),
          ],
        ),
      );

      final add = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        transitionIdFactory: () => 'legacy-initialized-add',
      );
      final remove = await removeGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        transitionIdFactory: () => 'legacy-initialized-remove',
        msgRepo: msgRepo,
        targetMessage: testMessage,
      );

      expect(add.$1, SendGroupReactionResult.success);
      expect(remove, RemoveGroupReactionResult.success);
      expect(
        bridge.commandLog.where(
          (command) => command == 'group:publishReaction',
        ),
        hasLength(2),
      );
      expect(reactionReplayOutboxRepo.entries, hasLength(2));
      expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);

      setGroupContentAuthoringResolver(
        groupRepo,
        ({
          required groupId,
          required senderPeerId,
          required senderPublicKey,
          senderDeviceId,
          senderTransportPeerId,
        }) async => const (
          kind: GroupContentAuthoringResolutionKind.refuse,
          context: null,
        ),
      );
      final commandCountBeforeRefusal = bridge.commandLog.length;
      final outboxCountBeforeRefusal = reactionReplayOutboxRepo.entries.length;

      final refusedAdd = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '❌',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );
      final refusedRemove = await removeGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '❌',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        msgRepo: msgRepo,
        targetMessage: testMessage,
      );

      expect(refusedAdd.$1, SendGroupReactionResult.unauthorizedSenderKey);
      expect(refusedAdd.$2, isNull);
      expect(refusedRemove, RemoveGroupReactionResult.authorityUnavailable);
      expect(bridge.commandLog, hasLength(commandCountBeforeRefusal));
      expect(
        reactionReplayOutboxRepo.entries,
        hasLength(outboxCountBeforeRefusal),
      );
      expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
    },
  );

  test('build failure stages a rescuable needs-build row', () async {
    // Plan 319 TC-319-02: a throw inside the offline-replay envelope build
    // (bridge encrypt failure) must still leave a durable, rescuable outbox
    // row — on HEAD the stage catch swallows the throw and returns rowless.
    bridge.responses['group.encrypt'] = {
      'ok': false,
      'error': 'NOT_INITIALIZED',
    };

    await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-1',
      messageId: 'msg-1',
      emoji: '\u{1F44D}',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
    );

    final row = await reactionReplayOutboxRepo.getLatestEntryForTarget(
      groupId: 'group-1',
      messageId: 'msg-1',
      senderPeerId: 'peer-1',
    );
    expect(
      row,
      isNotNull,
      reason: 'a build failure must leave a rescuable outbox row',
    );
  });

  test('roster failure stages a rescuable needs-build row', () async {
    // Plan 319 TC-319-02 ordering leg: getMembers is the FIRST throwing step
    // inside the stage try — the durable row must exist before it runs.
    final throwingRepo = _ThrowingGetMembersGroupRepository();
    await throwingRepo.saveGroup(testGroup);
    await throwingRepo.saveMember(testMember);
    await throwingRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 0,
        encryptedKey: 'group-key-0',
        createdAt: DateTime.now().toUtc(),
      ),
    );

    await sendGroupReaction(
      bridge: bridge,
      groupRepo: throwingRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-1',
      messageId: 'msg-1',
      emoji: '\u{1F44D}',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
    );

    final row = await reactionReplayOutboxRepo.getLatestEntryForTarget(
      groupId: 'group-1',
      messageId: 'msg-1',
      senderPeerId: 'peer-1',
    );
    expect(
      row,
      isNotNull,
      reason:
          'the needs-build row must be staged before the first throwing step',
    );
  });

  test('chat member can react', () async {
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-1',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
    );

    expect(result, SendGroupReactionResult.success);
    expect(reaction, isNotNull);
    expect(reaction!.emoji, '👍');
    expect(reaction.messageId, 'msg-1');
    expect(reaction.senderPeerId, 'peer-1');

    // Verify persisted
    final stored = await reactionRepo.getReactionsForMessage('msg-1');
    expect(stored, hasLength(1));
    expect(stored.first.emoji, '👍');
  });

  test(
    'successful reaction add emits queued local delivery contract',
    () async {
      final events = <Map<String, dynamic>>[];

      final (result, reaction) = await _captureFlowEvents(
        events,
        () => sendGroupReaction(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          reactionRepo: reactionRepo,
          reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          groupId: 'group-1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
        ),
      );

      expect(result, SendGroupReactionResult.success);
      expect(reaction, isNotNull);
      expect(
        events.where(
          (event) => event['event'] == 'GROUP_REACTION_SEND_SUCCESS',
        ),
        isEmpty,
      );

      final queued = events.singleWhere(
        (event) => event['event'] == 'GROUP_REACTION_SEND_QUEUED',
      );
      final details = queued['details'] as Map<String, dynamic>;
      expect(details['deliveryMode'], 'live_publish_replay_queued');
      expect(details['deliveryConfirmed'], isFalse);
      expect(details['localState'], 'optimistic');
      expect(details['replayStatus'], 'pending');
    },
  );

  test(
    'PL-009 active member publishes reaction command and stores local reaction once',
    () async {
      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, SendGroupReactionResult.success);
      expect(reaction, isNotNull);
      expect(reaction!.messageId, 'msg-1');
      expect(reaction.senderPeerId, 'peer-1');
      expect(reaction.emoji, '🔥');

      final publishCommands = bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:publishReaction')
          .toList(growable: false);
      expect(publishCommands, hasLength(1));
      final payload = publishCommands.single['payload'] as Map<String, dynamic>;
      expect(payload['groupId'], 'group-1');
      expect(payload['senderPeerId'], 'peer-1');
      final reactionPayload =
          jsonDecode(payload['reactionPayload'] as String)
              as Map<String, dynamic>;
      expect(reactionPayload['messageId'], 'msg-1');
      expect(reactionPayload['senderPeerId'], 'peer-1');
      expect(reactionPayload['emoji'], '🔥');
      expect(reactionPayload['action'], 'add');

      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));
      expect(stored.single.senderPeerId, 'peer-1');
      expect(stored.single.emoji, '🔥');
      expect(reactionRepo.saveReactionCallCount, 1);
    },
  );

  test(
    'G3-014 add reaction id is deterministic for the same add tuple',
    () async {
      final first = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );
      final second = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(first.$1, SendGroupReactionResult.success);
      expect(second.$1, SendGroupReactionResult.success);
      expect(first.$2, isNotNull);
      expect(second.$2, isNotNull);
      expect(second.$2!.id, first.$2!.id);

      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));
      expect(stored.single.id, first.$2!.id);
    },
  );

  test(
    'PL-010 removed member reaction send is rejected without publish or local mutation',
    () async {
      await groupRepo.removeMember('group-1', 'peer-1');

      final sentBefore = bridge.sentMessages.length;
      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, SendGroupReactionResult.notMember);
      expect(reaction, isNull);
      expect(bridge.sentMessages.length, sentBefore);
      expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
      expect(reactionRepo.saveReactionCallCount, 0);
      expect(reactionReplayOutboxRepo.entries, isEmpty);
    },
  );

  test(
    'G3-012 member with unbound sender signing key is rejected before publish',
    () async {
      final sentBefore = bridge.sentMessages.length;

      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-attacker',
        senderPrivateKey: 'sk-attacker',
      );

      expect(result, SendGroupReactionResult.unauthorizedSenderKey);
      expect(reaction, isNull);
      expect(bridge.sentMessages.length, sentBefore);
      expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
      expect(reactionRepo.saveReactionCallCount, 0);
      expect(reactionReplayOutboxRepo.entries, isEmpty);
    },
  );

  test(
    'PL-011 re-added initialized member uses strict custody and stores once',
    () async {
      final now = DateTime.now().toUtc();
      const charliePeerId = 'peer-charlie';
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie-old',
          mlKemPublicKey: 'mlkem-charlie-old',
          joinedAt: now.subtract(const Duration(minutes: 5)),
        ),
      );
      await groupRepo.removeMember('group-1', charliePeerId);
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'group-key-1',
          createdAt: now,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie-current',
          mlKemPublicKey: 'mlkem-charlie-current',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'device-charlie-current',
              transportPeerId: 'transport-charlie-current',
              deviceSigningPublicKey: 'pk-charlie-current',
              mlKemPublicKey: 'mlkem-charlie-current',
              keyPackageId: 'kp-charlie-current',
            ),
          ],
          joinedAt: now.add(const Duration(minutes: 1)),
        ),
      );
      await msgRepo.saveMessage(
        GroupMessage(
          id: 'pl011-target',
          groupId: 'group-1',
          senderPeerId: 'peer-1',
          senderUsername: 'Alice',
          text: 'PL-011 post-readd visible target',
          timestamp: now.add(const Duration(minutes: 2)),
          keyGeneration: 1,
          status: 'delivered',
          isIncoming: true,
          createdAt: now.add(const Duration(minutes: 2)),
        ),
      );

      final strictOutbox = _StrictReactionOutbox();
      final strictStore = _PersistAwareStrictReactionStore(strictOutbox);
      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: strictOutbox,
        groupId: 'group-1',
        messageId: 'pl011-target',
        emoji: '✅',
        senderPeerId: charliePeerId,
        senderPublicKey: 'pk-charlie-current',
        senderPrivateKey: 'sk-charlie-current',
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 13, 11),
            eventId: 'authority.pl011-readd',
            keyEpoch: 1,
          ),
          inboxStore: strictStore,
        ),
      );

      expect(result, SendGroupReactionResult.success);
      expect(reaction, isNotNull);
      expect(reaction!.messageId, 'pl011-target');
      expect(reaction.senderPeerId, charliePeerId);
      expect(reaction.emoji, '✅');

      expect(strictStore.recipients, <String>['peer-1']);
      expect(
        strictOutbox.completedRows.where(
          (row) =>
              row['source_event_id'] ==
              localProtectedGroupReactionSourceEventId(
                strictOutbox.entries.single.reactionId,
              ),
        ),
        hasLength(1),
      );
      expect(
        bridge.commandLog.where(
          (command) => command == 'group:publishReaction',
        ),
        isEmpty,
      );
      expect(reactionRepo.saveReactionCallCount, 0);

      final entry = strictOutbox.entries.single;
      expect(entry.deliveryStatus, GroupReactionReplayOutboxStatus.stored);
      final envelope = _replayEnvelopeFromRetryPayload(entry.inboxRetryPayload);
      expect(envelope['payloadType'], 'group_reaction');
      expect(envelope['keyEpoch'], 1);
      expect(envelope['senderPeerId'], charliePeerId);
      expect(envelope['senderDeviceId'], 'device-charlie-current');
      expect(envelope['senderTransportPeerId'], 'transport-charlie-current');
      expect(envelope['senderKeyPackageId'], 'kp-charlie-current');
    },
  );

  test('announcement member can react', () async {
    final announcementGroup = GroupModel(
      id: 'group-ann',
      name: 'Announcements',
      type: GroupType.announcement,
      topicName: 'group-topic-ann',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );
    await groupRepo.saveGroup(announcementGroup);
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-ann',
        keyGeneration: 0,
        encryptedKey: 'group-ann-key-0',
        createdAt: DateTime.now().toUtc(),
      ),
    );

    final readerMember = GroupMember(
      groupId: 'group-ann',
      peerId: 'peer-reader',
      username: 'Reader',
      role: MemberRole.writer,
      publicKey: 'pk-reader',
      joinedAt: DateTime.now().toUtc(),
    );
    await groupRepo.saveMember(readerMember);

    final adminMsg = GroupMessage(
      id: 'msg-ann-1',
      groupId: 'group-ann',
      senderPeerId: 'peer-admin',
      senderUsername: 'Admin',
      text: 'Announcement!',
      timestamp: DateTime.now().toUtc(),
      keyGeneration: 0,
      status: 'delivered',
      isIncoming: true,
      createdAt: DateTime.now().toUtc(),
    );
    await msgRepo.saveMessage(adminMsg);

    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-ann',
      messageId: 'msg-ann-1',
      emoji: '👍',
      senderPeerId: 'peer-reader',
      senderPublicKey: 'pk-reader',
      senderPrivateKey: 'sk-reader',
    );

    expect(result, SendGroupReactionResult.success);
    expect(reaction, isNotNull);
  });

  test(
    'dissolved chat group rejects reactions without publishing or storing',
    () async {
      await groupRepo.updateGroup(
        testGroup.copyWith(
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 22, 9),
          dissolvedBy: 'peer-1',
        ),
      );

      final sentBefore = bridge.sentMessages.length;
      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, SendGroupReactionResult.groupDissolved);
      expect(reaction, isNull);
      expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
      expect(reactionReplayOutboxRepo.entries, isEmpty);
      expect(bridge.sentMessages.length, sentBefore);
    },
  );

  test('dissolved announcement member cannot add a reaction', () async {
    final announcementGroup = GroupModel(
      id: 'group-ann-dissolved',
      name: 'Announcements',
      type: GroupType.announcement,
      topicName: 'group-topic-ann-dissolved',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
      isDissolved: true,
      dissolvedAt: DateTime.utc(2026, 4, 22, 10),
      dissolvedBy: 'peer-admin',
    );
    await groupRepo.saveGroup(announcementGroup);
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-ann-dissolved',
        keyGeneration: 0,
        encryptedKey: 'group-ann-dissolved-key-0',
        createdAt: DateTime.now().toUtc(),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-ann-dissolved',
        peerId: 'peer-reader',
        username: 'Reader',
        role: MemberRole.writer,
        publicKey: 'pk-reader',
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await msgRepo.saveMessage(
      GroupMessage(
        id: 'msg-ann-dissolved-1',
        groupId: 'group-ann-dissolved',
        senderPeerId: 'peer-admin',
        senderUsername: 'Admin',
        text: 'Ended announcement',
        timestamp: DateTime.now().toUtc(),
        keyGeneration: 0,
        status: 'delivered',
        isIncoming: true,
        createdAt: DateTime.now().toUtc(),
      ),
    );

    final sentBefore = bridge.sentMessages.length;
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-ann-dissolved',
      messageId: 'msg-ann-dissolved-1',
      emoji: '🔥',
      senderPeerId: 'peer-reader',
      senderPublicKey: 'pk-reader',
      senderPrivateKey: 'sk-reader',
    );

    expect(result, SendGroupReactionResult.groupDissolved);
    expect(reaction, isNull);
    expect(
      await reactionRepo.getReactionsForMessage('msg-ann-dissolved-1'),
      isEmpty,
    );
    expect(bridge.sentMessages.length, sentBefore);
  });

  test('non-member is rejected', () async {
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-1',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'outsider',
      senderPublicKey: 'pk-out',
      senderPrivateKey: 'sk-out',
    );

    expect(result, SendGroupReactionResult.notMember);
    expect(reaction, isNull);
  });

  test('unknown messageId is rejected', () async {
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-1',
      messageId: 'nonexistent-msg',
      emoji: '👍',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
    );

    expect(result, SendGroupReactionResult.messageNotFound);
    expect(reaction, isNull);
  });

  test(
    'G3-011 target message from another group is rejected without publish',
    () async {
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-2',
          name: 'Other Group',
          type: GroupType.chat,
          topicName: 'group-topic-2',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-1',
          myRole: GroupRole.admin,
        ),
      );
      await msgRepo.saveMessage(
        GroupMessage(
          id: 'msg-other-group',
          groupId: 'group-2',
          senderPeerId: 'peer-2',
          senderUsername: 'Bob',
          text: 'Wrong group target',
          timestamp: DateTime.now().toUtc(),
          keyGeneration: 0,
          status: 'delivered',
          isIncoming: true,
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final sentBefore = bridge.sentMessages.length;
      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-other-group',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, SendGroupReactionResult.messageNotFound);
      expect(reaction, isNull);
      expect(bridge.sentMessages.length, sentBefore);
      expect(
        await reactionRepo.getReactionsForMessage('msg-other-group'),
        isEmpty,
      );
      expect(reactionReplayOutboxRepo.entries, isEmpty);
    },
  );

  test('unknown group is rejected', () async {
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'nonexistent',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
    );

    expect(result, SendGroupReactionResult.groupNotFound);
    expect(reaction, isNull);
  });

  test(
    'INV-R1 publish failure queues reaction for retry and persists optimistically',
    () async {
      bridge.responses['group:publishReaction'] = {
        'ok': false,
        'errorCode': 'GROUP_ERROR',
      };

      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      // No longer a hard drop: the reaction is queued for retry.
      expect(result, SendGroupReactionResult.queuedForRetry);
      expect(reaction, isNotNull);
      expect(reaction!.emoji, '👍');

      // INV-R1(b): optimistic local state IS persisted despite the failure.
      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));
      expect(stored.single.id, reaction.id);
      expect(reactionRepo.saveReactionCallCount, 1);

      // INV-R1(a): a durable custody row exists regardless of publish outcome.
      await pumpEventQueue();
      final entry = await reactionReplayOutboxRepo.getEntry(reaction.id);
      expect(entry, isNotNull);
      expect(entry!.messageId, 'msg-1');
      expect(entry.action, 'add');
    },
  );

  test(
    'INV-R2 publish + relay store failure leaves a retryable durable row',
    () async {
      bridge.responses['group:publishReaction'] = {
        'ok': false,
        'errorCode': 'GROUP_ERROR',
      };
      bridge.responses['group:inboxStore'] = {
        'ok': false,
        'errorCode': 'GROUP_INBOX_STORE_FAILED',
      };

      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, SendGroupReactionResult.queuedForRetry);
      expect(reaction, isNotNull);

      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));

      await pumpEventQueue();

      // The existing retry driver re-drives pending/failed rows with no change.
      final entry = await reactionReplayOutboxRepo.getEntry(reaction!.id);
      expect(entry, isNotNull);
      expect(entry!.deliveryStatus, GroupReactionReplayOutboxStatus.failed);
      final retryable = await reactionReplayOutboxRepo.loadRetryableEntries();
      expect(retryable, hasLength(1));
      expect(retryable.single.reactionId, startsWith('group-reaction-event-'));
      expect(
        _replayEnvelopeFromRetryPayload(
          retryable.single.inboxRetryPayload,
        )['messageId'],
        reaction.id,
      );
    },
  );

  test(
    'INV-R1 thrown publish error queues reaction for retry with custody',
    () async {
      final throwingBridge = _ThrowingPublishReactionBridge();

      final (result, reaction) = await sendGroupReaction(
        bridge: throwingBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, SendGroupReactionResult.queuedForRetry);
      expect(reaction, isNotNull);

      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));

      await pumpEventQueue();
      final entry = await reactionReplayOutboxRepo.getEntry(reaction!.id);
      expect(entry, isNotNull);
    },
  );

  test(
    'INV-R3 repeated publish-failed add re-stages a single durable row',
    () async {
      bridge.responses['group:publishReaction'] = {
        'ok': false,
        'errorCode': 'GROUP_ERROR',
      };

      final first = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );
      final second = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(first.$1, SendGroupReactionResult.queuedForRetry);
      expect(second.$1, SendGroupReactionResult.queuedForRetry);
      expect(second.$2!.id, first.$2!.id);

      await pumpEventQueue();
      expect(reactionReplayOutboxRepo.entries, hasLength(1));
    },
  );

  test(
    'EK004 stores signed offline replay envelope for group_reaction add',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, SendGroupReactionResult.success);
      expect(reaction, isNotNull);

      await pumpEventQueue();

      final entry = await reactionReplayOutboxRepo.getEntry(reaction!.id);
      expect(entry, isNotNull);
      expect(entry!.groupId, 'group-1');
      expect(entry.messageId, 'msg-1');
      expect(entry.senderPeerId, 'peer-1');
      expect(entry.emoji, '🔥');
      expect(entry.action, 'add');
      expect(entry.deliveryStatus, GroupReactionReplayOutboxStatus.stored);
      expect(bridge.commandLog, contains('group:inboxStore'));
      final envelope = _replayEnvelopeFromRetryPayload(entry.inboxRetryPayload);
      _expectSignedReactionReplayEnvelope(envelope);
      expect(envelope['recipientPeerIds'], <String>['peer-2']);
      final extension =
          envelope['notificationExtension'] as Map<String, dynamic>;
      expect(extension['notificationRecipientTransportPeerIds'], <String>[
        'peer-2',
      ]);
    },
  );

  test('cross-phone reaction nominates the target author transport', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-2',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'pk-2',
        joinedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    final result = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-1',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      transitionIdFactory: () => 'transition-cross-phone-author',
    );
    await pumpEventQueue();

    expect(result.$1, SendGroupReactionResult.success);
    final envelope = _replayEnvelopeFromRetryPayload(
      reactionReplayOutboxRepo.entries.single.inboxRetryPayload,
    );
    final replayRecipients = _stringList(envelope['recipientPeerIds']);
    final extension = envelope['notificationExtension'] as Map<String, dynamic>;
    final notificationRecipients = _stringList(
      extension['notificationRecipientTransportPeerIds'],
    );
    expect(notificationRecipients, <String>['peer-2']);
    expect(replayRecipients, containsAll(notificationRecipients));
  });

  test(
    'reaction to an author absent from the roster still nominates the author for wake',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-bystander',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-bystander',
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final events = <Map<String, dynamic>>[];

      late (SendGroupReactionResult, dynamic) result;
      await _captureFlowEvents(events, () async {
        result = await sendGroupReaction(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          reactionRepo: reactionRepo,
          reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          groupId: 'group-1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          transitionIdFactory: () => 'transition-missing-author',
        );
        await pumpEventQueue();
      });

      expect(result.$1, SendGroupReactionResult.success);
      final envelope = _replayEnvelopeFromRetryPayload(
        reactionReplayOutboxRepo.entries.single.inboxRetryPayload,
      );
      final replayRecipients = _stringList(envelope['recipientPeerIds']);
      final extension =
          envelope['notificationExtension'] as Map<String, dynamic>;
      final notificationRecipients = _stringList(
        extension['notificationRecipientTransportPeerIds'],
      );
      expect(replayRecipients, <String>['peer-2', 'peer-bystander']);
      expect(notificationRecipients, <String>['peer-2']);
      expect(replayRecipients, containsAll(notificationRecipients));
      expect(_inboxStoreCommands(bridge), hasLength(1));
      expect(
        events.where(
          (event) =>
              event['event'] == 'GROUP_REACTION_NOMINATION_AUTHOR_FALLBACK',
        ),
        hasLength(1),
      );
      expect(
        events.where(
          (event) => event['event'] == 'GROUP_REACTION_OUTBOX_STAGE_FAILED',
        ),
        isEmpty,
      );
    },
  );

  test(
    'reaction to a removed author\'s message does not nominate or re-custody the removed member',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-bystander',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-bystander',
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await groupRepo.saveRemovedMemberSnapshot(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-removed-author',
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
        removedAt: DateTime.utc(2026, 7, 30),
      );
      final events = <Map<String, dynamic>>[];

      await _captureFlowEvents(events, () async {
        await sendGroupReaction(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          reactionRepo: reactionRepo,
          reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          groupId: 'group-1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          transitionIdFactory: () => 'transition-removed-author',
        );
        await pumpEventQueue();
      });

      final envelope = _replayEnvelopeFromRetryPayload(
        reactionReplayOutboxRepo.entries.single.inboxRetryPayload,
      );
      expect(envelope['recipientPeerIds'], <String>['peer-bystander']);
      final extension =
          envelope['notificationExtension'] as Map<String, dynamic>;
      expect(extension['notificationRecipientTransportPeerIds'], isEmpty);
      expect(jsonEncode(envelope), isNot(contains('peer-2')));
      expect(
        events.where(
          (event) =>
              event['event'] == 'GROUP_REACTION_NOMINATION_AUTHOR_FALLBACK',
        ),
        isEmpty,
      );
    },
  );

  test('self-reaction nominates no wake recipients', () async {
    await msgRepo.saveMessage(
      testMessage.copyWith(senderPeerId: 'peer-1', senderUsername: 'Alice'),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-1',
        username: 'Alice',
        role: MemberRole.admin,
        devices: const <GroupMemberDeviceIdentity>[
          GroupMemberDeviceIdentity(
            deviceId: 'reactor-primary',
            transportPeerId: 'transport-reactor-primary',
            deviceSigningPublicKey: 'pk-1',
          ),
          GroupMemberDeviceIdentity(
            deviceId: 'reactor-sibling',
            transportPeerId: 'transport-reactor-sibling',
            deviceSigningPublicKey: 'pk-1-sibling',
          ),
        ],
        joinedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-bystander',
        username: 'Charlie',
        role: MemberRole.writer,
        publicKey: 'pk-bystander',
        joinedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    final strictOutbox = _StrictReactionOutbox();
    final strictStore = _PersistAwareStrictReactionStore(strictOutbox);
    final result = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: strictOutbox,
      groupId: 'group-1',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      transitionIdFactory: () => 'transition-self-reaction',
      groupContentAuthoring: GroupContentAuthoringContext(
        directLinkedDeviceSelector: const DirectLinkedDeviceSelector.enabled(),
        multiDeviceSyncEnabled: true,
        authorityVersion: GroupContentAuthorityVersion(
          eventAt: DateTime.utc(2026, 8, 13, 11),
          eventId: 'authority.self-reaction',
          keyEpoch: 0,
        ),
        inboxStore: strictStore,
      ),
    );
    expect(result.$1, SendGroupReactionResult.success);

    final envelope = _replayEnvelopeFromRetryPayload(
      strictOutbox.entries.single.inboxRetryPayload,
    );
    expect(envelope['recipientPeerIds'], <String>[
      'peer-bystander',
      'transport-reactor-sibling',
    ]);
    final extension = envelope['notificationExtension'] as Map<String, dynamic>;
    expect(extension['notificationRecipientTransportPeerIds'], isEmpty);
  });

  test(
    'empty replay recipient set marks the outbox row failed and never reports stored',
    () async {
      await msgRepo.saveMessage(
        testMessage.copyWith(senderPeerId: 'peer-1', senderUsername: 'Alice'),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-keyless',
          username: 'Keyless',
          role: MemberRole.writer,
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final events = <Map<String, dynamic>>[];

      await _captureFlowEvents(events, () async {
        await sendGroupReaction(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          reactionRepo: reactionRepo,
          reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          groupId: 'group-1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          transitionIdFactory: () => 'transition-empty-recipients',
        );
        await pumpEventQueue();
      });

      final entry = reactionReplayOutboxRepo.entries.single;
      expect(entry.deliveryStatus, GroupReactionReplayOutboxStatus.failed);
      expect(entry.lastError, 'custody_unroutable_empty_recipients');
      expect(_inboxStoreCommands(bridge), isEmpty);
      expect(
        events.where(
          (event) => event['event'] == 'GROUP_REACTION_CUSTODY_UNROUTABLE',
        ),
        hasLength(1),
      );
      expect(
        events.where(
          (event) => event['event'] == 'GROUP_FL_BRIDGE_INBOX_STORE_REQUEST',
        ),
        isEmpty,
      );
    },
  );

  test(
    'exactRetry re-send of an unroutable row stays failed with zero bridge calls',
    () async {
      await msgRepo.saveMessage(
        testMessage.copyWith(senderPeerId: 'peer-1', senderUsername: 'Alice'),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-keyless',
          username: 'Keyless',
          role: MemberRole.writer,
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        transitionIdFactory: () => 'transition-unroutable-exact-retry',
      );
      await pumpEventQueue();
      bridge.sentMessages.clear();
      bridge.commandLog.clear();
      final events = <Map<String, dynamic>>[];

      await _captureFlowEvents(events, () async {
        await sendGroupReaction(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          reactionRepo: reactionRepo,
          reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          groupId: 'group-1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          transitionIdFactory: () => throw StateError(
            'exact retry must reuse the persisted transition id',
          ),
        );
        await pumpEventQueue();
      });

      final entry = reactionReplayOutboxRepo.entries.single;
      expect(entry.deliveryStatus, GroupReactionReplayOutboxStatus.failed);
      expect(entry.lastError, 'custody_unroutable_empty_recipients');
      expect(_inboxStoreCommands(bridge), isEmpty);
      expect(
        events.where(
          (event) => event['event'] == 'GROUP_REACTION_CUSTODY_UNROUTABLE',
        ),
        hasLength(1),
      );
      expect(
        events.where(
          (event) => event['event'] == 'GROUP_FL_BRIDGE_INBOX_STORE_REQUEST',
        ),
        isEmpty,
      );
    },
  );

  test(
    'all-revoked author devices are neither replay nor notification recipients',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'legacy-author-key-must-not-resurrect',
          devices: <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'author-revoked-device',
              transportPeerId: 'transport-author-revoked',
              deviceSigningPublicKey: 'author-revoked-key',
              status: GroupMemberDeviceStatus.revoked,
              revokedAt: DateTime.utc(2026, 7, 12),
            ),
          ],
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-bystander',
          username: 'Charlie',
          role: MemberRole.writer,
          devices: <GroupMemberDeviceIdentity>[
            const GroupMemberDeviceIdentity(
              deviceId: 'bystander-device',
              transportPeerId: 'transport-bystander',
              deviceSigningPublicKey: 'bystander-key',
            ),
          ],
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final result = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        transitionIdFactory: () => 'transition-all-revoked-author',
      );
      await pumpEventQueue();

      expect(result.$1, SendGroupReactionResult.success);
      final envelope = _replayEnvelopeFromRetryPayload(
        reactionReplayOutboxRepo.entries.single.inboxRetryPayload,
      );
      expect(envelope['recipientPeerIds'], <String>['transport-bystander']);
      final extension =
          envelope['notificationExtension'] as Map<String, dynamic>;
      expect(extension['notificationRecipientTransportPeerIds'], isEmpty);
      expect(jsonEncode(envelope), isNot(contains('transport-author-revoked')));
      expect(
        jsonEncode(envelope),
        isNot(contains('legacy-author-key-must-not-resurrect')),
      );
    },
  );

  test(
    'ADD remove same ADD persists unique transition ids and exact retry reuses one',
    () async {
      final firstAdd = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        transitionIdFactory: () => 'transition-add-1',
      );
      await pumpEventQueue();

      final remove = await removeGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        transitionIdFactory: () => 'transition-remove-1',
      );
      await pumpEventQueue();

      final secondAdd = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        transitionIdFactory: () => 'transition-add-2',
      );
      await pumpEventQueue();

      expect(firstAdd.$1, SendGroupReactionResult.success);
      expect(remove, RemoveGroupReactionResult.success);
      expect(secondAdd.$1, SendGroupReactionResult.success);
      expect(firstAdd.$2!.id, secondAdd.$2!.id);
      expect(
        reactionReplayOutboxRepo.entries.map((entry) => entry.reactionId),
        ['transition-add-1', 'transition-remove-1', 'transition-add-2'],
      );

      final envelopes = reactionReplayOutboxRepo.entries
          .map(
            (entry) => _replayEnvelopeFromRetryPayload(entry.inboxRetryPayload),
          )
          .toList(growable: false);
      expect(envelopes[0]['messageId'], firstAdd.$2!.id);
      expect(envelopes[2]['messageId'], firstAdd.$2!.id);
      expect(envelopes[1]['messageId'], isNot(firstAdd.$2!.id));
      for (var index = 0; index < envelopes.length; index++) {
        final expectedTransition =
            reactionReplayOutboxRepo.entries[index].reactionId;
        final extension =
            envelopes[index]['notificationExtension'] as Map<String, dynamic>;
        expect(extension['transitionId'], expectedTransition);
        final plaintext =
            jsonDecode(envelopes[index]['ciphertext'] as String)
                as Map<String, dynamic>;
        expect(plaintext['eventId'], expectedTransition);
      }

      final beforeRetryBytes =
          reactionReplayOutboxRepo.entries.last.inboxRetryPayload;
      final exactRetry = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        transitionIdFactory: () => throw StateError(
          'exact retry must reuse the persisted transition id',
        ),
      );
      await pumpEventQueue();

      expect(exactRetry.$1, SendGroupReactionResult.success);
      expect(reactionReplayOutboxRepo.entries, hasLength(3));
      expect(
        reactionReplayOutboxRepo.entries.last.inboxRetryPayload,
        beforeRetryBytes,
      );
      expect(
        reactionReplayOutboxRepo.entries.last.reactionId,
        'transition-add-2',
      );
    },
  );

  test(
    'sibling-device REMOVE prevents reuse of this device old ADD transition',
    () async {
      final firstAdd = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        transitionIdFactory: () => 'transition-add-before-sibling-remove',
      );
      await pumpEventQueue();

      // The sibling REMOVE converges through ReactionRepository, but it does
      // not write this device's replay outbox. The next local ADD is therefore
      // a new transition, not a retry of the old ADD row.
      await reactionRepo.removeReaction(
        'msg-1',
        'peer-1',
        removedAtTimestamp: DateTime.now().toUtc().toIso8601String(),
      );

      final reAdd = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        transitionIdFactory: () => 'transition-add-after-sibling-remove',
      );
      await pumpEventQueue();

      expect(firstAdd.$1, SendGroupReactionResult.success);
      expect(reAdd.$1, SendGroupReactionResult.success);
      expect(
        reactionReplayOutboxRepo.entries.map((entry) => entry.reactionId),
        <String>[
          'transition-add-before-sibling-remove',
          'transition-add-after-sibling-remove',
        ],
      );
      final replay = _replayEnvelopeFromRetryPayload(
        reactionReplayOutboxRepo.entries.last.inboxRetryPayload,
      );
      final plaintext =
          jsonDecode(replay['ciphertext'] as String) as Map<String, dynamic>;
      expect(plaintext['eventId'], 'transition-add-after-sibling-remove');
    },
  );

  test(
    'replay store failure still returns success and leaves a failed durable row',
    () async {
      bridge.responses['group:inboxStore'] = {
        'ok': false,
        'errorCode': 'GROUP_INBOX_STORE_FAILED',
      };

      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, SendGroupReactionResult.success);
      expect(reaction, isNotNull);

      await pumpEventQueue();

      final entry = await reactionReplayOutboxRepo.getEntry(reaction!.id);
      expect(entry, isNotNull);
      expect(entry!.deliveryStatus, GroupReactionReplayOutboxStatus.failed);
      expect(entry.lastError, contains('GROUP_INBOX_STORE_FAILED'));

      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));
      expect(stored.single.id, reaction.id);
    },
  );
}

class _ThrowingGetMembersGroupRepository extends InMemoryGroupRepository {
  @override
  Future<List<GroupMember>> getMembers(String groupId) async {
    throw StateError('roster unavailable');
  }
}
