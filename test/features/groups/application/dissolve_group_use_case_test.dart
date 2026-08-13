import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/groups/application/dissolve_group_use_case.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    as group_send;
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_group_dissolve_preflight.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

class _DissolveCleanupTrackingGroupRepository extends InMemoryGroupRepository
    implements
        AtomicGroupDissolveRepository,
        AtomicProtectedGroupDissolveRepository,
        AtomicProtectedGroupKeyAuthorityRepository {
  final displayRowsByGroup = <String, Set<String>>{};
  int terminalCommitCalls = 0;
  int protectedTerminalCommitCalls = 0;
  Future<void> Function({
    required GroupModel group,
    required ProtectedGroupAuthorityCompleteFact authorityComplete,
    required List<GroupPendingBroadcast> expectedBroadcasts,
  })?
  onProtectedCommit;
  Future<void> Function({
    required GroupKeyInfo key,
    required ProtectedGroupAuthorityCompleteFact authorityComplete,
  })?
  onProtectedKeyCommit;

  @override
  Future<void> commitDissolvedGroup(GroupModel group) async {
    terminalCommitCalls++;
    await updateGroup(group);
    displayRowsByGroup.remove(group.id);
  }

  @override
  Future<void> commitProtectedGroupDissolve({
    required GroupModel group,
    required ProtectedGroupAuthorityCompleteFact authorityComplete,
    required List<GroupPendingBroadcast> expectedBroadcasts,
  }) async {
    protectedTerminalCommitCalls++;
    final commit = onProtectedCommit;
    if (commit == null) {
      throw StateError('protected dissolve test commit is unavailable');
    }
    await commit(
      group: group,
      authorityComplete: authorityComplete,
      expectedBroadcasts: expectedBroadcasts,
    );
  }

  @override
  Future<void> commitProtectedGroupKeyAuthority({
    required GroupKeyInfo key,
    required ProtectedGroupAuthorityCompleteFact authorityComplete,
  }) async {
    final commit = onProtectedKeyCommit;
    if (commit == null) {
      throw StateError('protected key test commit is unavailable');
    }
    await commit(key: key, authorityComplete: authorityComplete);
  }
}

class _DissolvePendingRepository implements GroupPendingBroadcastRepository {
  final Map<String, GroupPendingBroadcast> rows = {};

  @override
  Future<void> enqueue(GroupPendingBroadcast broadcast) async {
    rows[broadcast.id] = broadcast;
  }

  @override
  Future<List<GroupPendingBroadcast>> forGroup(String groupId) async => rows
      .values
      .where((row) => row.groupId == groupId)
      .toList(growable: false);

  @override
  Future<List<GroupPendingBroadcast>> all() async =>
      rows.values.toList(growable: false);

  @override
  Future<int> countForGroup(String groupId) async =>
      rows.values.where((row) => row.groupId == groupId).length;

  @override
  Future<void> remove(String id) async {
    rows.remove(id);
  }

  @override
  Future<void> removeForGroup(String groupId) async {
    rows.removeWhere((_, row) => row.groupId == groupId);
  }
}

class _DissolveCustodyStore implements AckOrExpiryInboxStore {
  _DissolveCustodyStore(List<InboxStoreOutcome> outcomes, {this.beforeStore})
    : outcomes = List<InboxStoreOutcome>.from(outcomes);

  final List<InboxStoreOutcome> outcomes;
  final void Function()? beforeStore;
  final List<String> recipients = [];

  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async {
    beforeStore?.call();
    expect(custodyKind, AckCustodyKind.groupAuthorityV1);
    recipients.add(toPeerId);
    return outcomes.removeAt(0);
  }
}

void main() {
  late FakeBridge bridge;
  late _DissolveCleanupTrackingGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  final now = DateTime.utc(2026, 4, 5, 12, 0, 0);
  final baseGroup = GroupModel(
    id: 'group-1',
    name: 'Project Group',
    type: GroupType.chat,
    topicName: 'topic-group-1',
    createdAt: now,
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = _DissolveCleanupTrackingGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();

    await groupRepo.saveGroup(baseGroup);
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 1,
        encryptedKey: 'test-group-key-1',
        createdAt: now,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        joinedAt: now,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-bob',
        username: 'Bob',
        role: MemberRole.writer,
        joinedAt: now,
      ),
    );
  });

  Future<
    ({
      _DissolvePendingRepository pending,
      Map<String, AuthenticatedGroupAuthorityProof> history,
      _DissolveCustodyStore store,
    })
  >
  installProtectedDissolve({
    required List<InboxStoreOutcome> outcomes,
    bool failFirstTerminalCommit = false,
    bool includeSecondRecipient = false,
    void Function()? beforeStore,
  }) async {
    const source = GroupMemberDeviceIdentity(
      deviceId: 'admin-device',
      transportPeerId: 'admin-transport',
      deviceSigningPublicKey: 'pk-admin',
      mlKemPublicKey: 'admin-mlkem',
    );
    const recipient = GroupMemberDeviceIdentity(
      deviceId: 'bob-device',
      transportPeerId: 'bob-transport',
      deviceSigningPublicKey: 'bob-device-public',
      mlKemPublicKey: 'bob-mlkem',
    );
    const secondRecipient = GroupMemberDeviceIdentity(
      deviceId: 'carol-device',
      transportPeerId: 'carol-transport',
      deviceSigningPublicKey: 'carol-device-public',
      mlKemPublicKey: 'carol-mlkem',
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        publicKey: 'pk-admin',
        mlKemPublicKey: source.mlKemPublicKey,
        devices: const <GroupMemberDeviceIdentity>[source],
        joinedAt: now,
      ),
    );
    if (includeSecondRecipient) {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-carol',
          username: 'Carol',
          role: MemberRole.writer,
          publicKey: 'pk-carol',
          mlKemPublicKey: secondRecipient.mlKemPublicKey,
          devices: const <GroupMemberDeviceIdentity>[secondRecipient],
          joinedAt: now,
        ),
      );
    }
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-bob',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'pk-bob',
        mlKemPublicKey: recipient.mlKemPublicKey,
        devices: const <GroupMemberDeviceIdentity>[recipient],
        joinedAt: now,
      ),
    );

    final pending = _DissolvePendingRepository();
    final history = <String, AuthenticatedGroupAuthorityProof>{};
    final store = _DissolveCustodyStore(outcomes, beforeStore: beforeStore);
    var failCommit = failFirstTerminalCommit;
    groupRepo.onProtectedCommit =
        ({
          required group,
          required authorityComplete,
          required expectedBroadcasts,
        }) async {
          if (failCommit) {
            failCommit = false;
            throw StateError('simulated crash before terminal transaction');
          }
          final proof = AuthenticatedGroupAuthorityProof.tryParse(
            authorityComplete.payload['proof'],
          );
          if (proof == null) {
            throw StateError('missing complete proof');
          }
          for (final expected in expectedBroadcasts) {
            final current = pending.rows[expected.id];
            if (current == null ||
                !sameExactGroupPendingBroadcast(current, expected)) {
              throw StateError('protected dissolve row changed');
            }
          }
          await groupRepo.updateGroup(group);
          history['${AuthenticatedGroupAuthorityPhase.complete.name}:'
                  '${proof.eventId}'] =
              proof;
          for (final expected in expectedBroadcasts) {
            pending.rows.remove(expected.id);
          }
        };

    setProtectedGroupAuthorityAdapter(
      prepare: (request) async {
        final key = await groupRepo.getLatestKey(request.groupId);
        final preparation = await buildProtectedGroupAuthorityRows(
          groupId: request.groupId,
          transitionId: request.transitionId,
          control: request.control,
          replayData: request.replayData,
          keyEpoch: key!.keyGeneration,
          actorAccountPeerId: request.actorAccountPeerId,
          actorAccountPublicKey: request.actorAccountPublicKey,
          actorAccountPrivateKey: request.actorAccountPrivateKey,
          senderDevice: request.senderDevice,
          frozenRecipients: request.frozenRecipients,
          deliveryRecipients: request.deliveryRecipients,
          sharedAuthorityProof: request.sharedAuthorityProof,
          callSign: (data, _) async => <String, dynamic>{
            'ok': true,
            'signature': 'sig:${data.hashCode}',
          },
          callEncrypt:
              ({required recipientMlKemPublicKey, required plaintext}) async =>
                  <String, dynamic>{
                    'ok': true,
                    'kem': 'kem-$recipientMlKemPublicKey',
                    'ciphertext': 'ciphertext-$recipientMlKemPublicKey',
                    'nonce': 'nonce-$recipientMlKemPublicKey',
                  },
          now: () =>
              DateTime.parse(request.replayData['timestamp'] as String).toUtc(),
        );
        final proof = preparation.authorityProof;
        if (proof == null) return preparation;
        history['${AuthenticatedGroupAuthorityPhase.prepared.name}:'
                '${proof.eventId}'] =
            proof;
        for (final row in preparation.rows) {
          await pending.enqueue(row);
        }
        return preparation;
      },
      activate: (preparation, {required requireAllCustody}) =>
          recoverPreparedProtectedGroupDissolve(
            groupId: preparation.groupId,
            eventId: preparation.authorityProof!.eventId,
            groupRepository: groupRepo,
            pendingRepository: pending,
            protectedInboxStore: store,
            pendingSiblingDeviceRepository: groupRepo,
            loadAuthorityProof:
                ({required groupId, required phase, required eventId}) async =>
                    history['${phase.name}:$eventId'],
          ),
      cancel: (preparation) async {
        for (final row in preparation.rows) {
          pending.rows.remove(row.id);
        }
        return true;
      },
    );
    addTearDown(() => setProtectedGroupAuthorityAdapter());
    return (pending: pending, history: history, store: store);
  }

  test(
    'TC-363-02d protected dissolve proves custody before atomic terminal COMPLETE',
    () async {
      final harness = await installProtectedDissolve(
        outcomes: const <InboxStoreOutcome>[
          InboxStoreOutcome(
            status: InboxStoreStatus.stored,
            storeStatus: 'stored',
            custodyContract: ackOrExpiryInboxCustodyContract,
          ),
        ],
        beforeStore: () => expect(
          bridge.commandLog,
          isNot(contains('group:publish')),
          reason: 'strict custody must precede live dissolve publication',
        ),
      );

      final (result, dissolved) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        actorDeviceId: 'admin-device',
        actorTransportPeerId: 'admin-transport',
        dissolvedAt: now.add(const Duration(minutes: 2)),
      );

      expect(result, DissolveGroupResult.success);
      expect(dissolved?.isDissolved, isTrue);
      expect(groupRepo.protectedTerminalCommitCalls, 1);
      expect(groupRepo.terminalCommitCalls, 0);
      expect(harness.store.recipients, <String>['bob-transport']);
      expect(harness.pending.rows, isEmpty);
      expect(
        harness.history.keys,
        contains(
          startsWith('${AuthenticatedGroupAuthorityPhase.complete.name}:'),
        ),
      );
      expect(
        bridge.commandLog.indexOf('group:publish'),
        greaterThanOrEqualTo(0),
      );
    },
  );

  test(
    'TC-363-02e protected dissolve restart repairs rowless custody-complete pre-terminal crash',
    () async {
      final harness = await installProtectedDissolve(
        failFirstTerminalCommit: true,
        outcomes: const <InboxStoreOutcome>[
          InboxStoreOutcome(
            status: InboxStoreStatus.stored,
            storeStatus: 'stored',
            custodyContract: ackOrExpiryInboxCustodyContract,
          ),
          InboxStoreOutcome(
            status: InboxStoreStatus.duplicate,
            storeStatus: 'duplicate',
            custodyContract: ackOrExpiryInboxCustodyContract,
          ),
        ],
      );

      final (result, _) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        actorDeviceId: 'admin-device',
        actorTransportPeerId: 'admin-transport',
        dissolvedAt: now.add(const Duration(minutes: 3)),
      );
      expect(result, DissolveGroupResult.bridgeError);
      expect((await groupRepo.getGroup('group-1'))?.isDissolved, isFalse);
      expect(
        harness.pending.rows,
        isEmpty,
        reason: 'accepted custody is the durable per-target receipt',
      );
      expect(
        harness.history.keys,
        isNot(
          contains(
            startsWith('${AuthenticatedGroupAuthorityPhase.complete.name}:'),
          ),
        ),
      );
      expect(bridge.commandLog, isNot(contains('group:publish')));

      final prepared = harness.history.values.single;
      final repaired = await recoverPreparedProtectedGroupDissolve(
        groupId: prepared.groupId,
        eventId: prepared.eventId,
        groupRepository: groupRepo,
        pendingRepository: harness.pending,
        protectedInboxStore: harness.store,
        pendingSiblingDeviceRepository: groupRepo,
        loadAuthorityProof:
            ({required groupId, required phase, required eventId}) async =>
                harness.history['${phase.name}:$eventId'],
      );
      expect(repaired, isTrue);
      expect((await groupRepo.getGroup('group-1'))?.isDissolved, isTrue);
      expect(harness.pending.rows, isEmpty);
      expect(
        harness.store.recipients,
        <String>['bob-transport'],
        reason: 'rowless PREPARED recovery must not contact an accepted target',
      );
      expect(groupRepo.protectedTerminalCommitCalls, 2);
    },
  );

  test(
    'TC-363-02h protected dissolve persists A receipt and restarts from B survivor',
    () async {
      const accepted = InboxStoreOutcome(
        status: InboxStoreStatus.stored,
        storeStatus: 'stored',
        custodyContract: ackOrExpiryInboxCustodyContract,
      );
      const ambiguous = InboxStoreOutcome(
        status: InboxStoreStatus.stored,
        storeStatus: 'stored',
      );
      const duplicate = InboxStoreOutcome(
        status: InboxStoreStatus.duplicate,
        storeStatus: 'duplicate',
        custodyContract: ackOrExpiryInboxCustodyContract,
      );
      final harness = await installProtectedDissolve(
        includeSecondRecipient: true,
        outcomes: const <InboxStoreOutcome>[accepted, ambiguous, duplicate],
      );

      final (result, _) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        actorDeviceId: 'admin-device',
        actorTransportPeerId: 'admin-transport',
        dissolvedAt: now.add(const Duration(minutes: 4)),
      );
      expect(result, DissolveGroupResult.bridgeError);
      expect((await groupRepo.getGroup('group-1'))?.isDissolved, isFalse);
      expect(harness.pending.rows.values, hasLength(1));
      expect(harness.pending.rows.values.single.recipientPeerIds, <String>[
        'carol-transport',
      ]);
      expect(harness.store.recipients, <String>[
        'bob-transport',
        'carol-transport',
      ]);

      final prepared = harness.history.values.single;
      final repaired = await recoverPreparedProtectedGroupDissolve(
        groupId: prepared.groupId,
        eventId: prepared.eventId,
        groupRepository: groupRepo,
        pendingRepository: harness.pending,
        protectedInboxStore: harness.store,
        pendingSiblingDeviceRepository: groupRepo,
        loadAuthorityProof:
            ({required groupId, required phase, required eventId}) async =>
                harness.history['${phase.name}:$eventId'],
      );
      expect(repaired, isTrue);
      expect((await groupRepo.getGroup('group-1'))?.isDissolved, isTrue);
      expect(harness.pending.rows, isEmpty);
      expect(harness.store.recipients, <String>[
        'bob-transport',
        'carol-transport',
        'carol-transport',
      ]);
      expect(
        harness.history.keys,
        contains(
          '${AuthenticatedGroupAuthorityPhase.complete.name}:'
          '${prepared.eventId}',
        ),
      );
    },
  );

  test(
    'TC-363-02i prepared-only discovery repairs zero-target key and dissolve after restart',
    () async {
      final keyAt = now.add(const Duration(minutes: 5));
      final dissolveAt = keyAt.add(const Duration(microseconds: 1));
      const keyEventId = 'group_key_update:group-1:peer-admin:zero-target';
      const dissolveEventId = 'group_dissolved:group-1:peer-admin:zero-target';
      final draft = GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 2,
        encryptedKey: 'zero-target-key-v2',
        createdAt: keyAt,
      );
      await groupRepo.savePendingKeyRotation(draft);
      final keyProof = AuthenticatedGroupAuthorityProof(
        eventId: keyEventId,
        groupId: 'group-1',
        eventAt: keyAt,
        keyEpoch: 2,
        control: ProtectedGroupAuthorityControl.groupKeyUpdate.wireValue,
        actorAccountPeerId: 'peer-admin',
        actorAccountPublicKey: 'pk-admin',
        senderTransportPeerId: 'admin-transport',
        senderTransportPublicKey: 'pk-admin',
        authorityData: secretFreeProtectedAuthorityData(
          control: ProtectedGroupAuthorityControl.groupKeyUpdate.wireValue,
          replayData: <String, dynamic>{
            'groupId': 'group-1',
            'keyGeneration': 2,
            'encryptedKey': draft.encryptedKey,
            'from': 'admin-transport',
            'timestamp': keyAt.toIso8601String(),
          },
          frozenRecipientPeerIds: const <String>[],
        ),
        signature: 'key-signature',
      );
      final dissolveText = jsonEncode(<String, dynamic>{
        '__sys': 'group_dissolved',
        'dissolvedAt': dissolveAt.toIso8601String(),
        'dissolvedBy': 'peer-admin',
        'signedTransitionAudit': <String, dynamic>{
          'transitionType': 'group_dissolved',
          'groupId': 'group-1',
          'sourceEventId': dissolveEventId,
          'eventAt': dissolveAt.toIso8601String(),
        },
      });
      final dissolveProof = AuthenticatedGroupAuthorityProof(
        eventId: dissolveEventId,
        groupId: 'group-1',
        eventAt: dissolveAt,
        keyEpoch: 2,
        control: ProtectedGroupAuthorityControl.groupDissolve.wireValue,
        actorAccountPeerId: 'peer-admin',
        actorAccountPublicKey: 'pk-admin',
        senderTransportPeerId: 'admin-transport',
        senderTransportPublicKey: 'pk-admin',
        authorityData: secretFreeProtectedAuthorityData(
          control: ProtectedGroupAuthorityControl.groupDissolve.wireValue,
          replayData: <String, dynamic>{
            'groupId': 'group-1',
            'senderId': 'peer-admin',
            'senderUsername': 'Admin',
            'text': dissolveText,
            'timestamp': dissolveAt.toIso8601String(),
            'messageId': dissolveEventId,
          },
          frozenRecipientPeerIds: const <String>[],
        ),
        signature: 'dissolve-signature',
      );
      final history = <String, AuthenticatedGroupAuthorityProof>{
        '${AuthenticatedGroupAuthorityPhase.prepared.name}:$keyEventId':
            keyProof,
        '${AuthenticatedGroupAuthorityPhase.prepared.name}:$dissolveEventId':
            dissolveProof,
      };
      groupRepo.onProtectedKeyCommit =
          ({required key, required authorityComplete}) async {
            final proof = AuthenticatedGroupAuthorityProof.tryParse(
              authorityComplete.payload['proof'],
            )!;
            await groupRepo.saveKey(key);
            history['${AuthenticatedGroupAuthorityPhase.complete.name}:'
                    '${proof.eventId}'] =
                proof;
          };
      groupRepo.onProtectedCommit =
          ({
            required group,
            required authorityComplete,
            required expectedBroadcasts,
          }) async {
            expect(expectedBroadcasts, isEmpty);
            final proof = AuthenticatedGroupAuthorityProof.tryParse(
              authorityComplete.payload['proof'],
            )!;
            await groupRepo.updateGroup(group);
            history['${AuthenticatedGroupAuthorityPhase.complete.name}:'
                    '${proof.eventId}'] =
                proof;
          };
      Future<AuthenticatedGroupAuthorityProof?> loadProof({
        required String groupId,
        required AuthenticatedGroupAuthorityPhase phase,
        required String eventId,
      }) async => history['${phase.name}:$eventId'];

      final pending = _DissolvePendingRepository();
      final emptyStore = _DissolveCustodyStore(const <InboxStoreOutcome>[]);
      final promoted = <GroupKeyInfo>[];
      final candidates = <ProtectedGroupAuthorityPreparation>[
        ProtectedGroupAuthorityPreparation(
          groupId: 'group-1',
          rows: const <GroupPendingBroadcast>[],
          authorityProof: keyProof,
          control: ProtectedGroupAuthorityControl.groupKeyUpdate,
          replayData: Map<String, dynamic>.from(keyProof.authorityData),
        ),
        ProtectedGroupAuthorityPreparation(
          groupId: 'group-1',
          rows: const <GroupPendingBroadcast>[],
          authorityProof: dissolveProof,
          control: ProtectedGroupAuthorityControl.groupDissolve,
          replayData: Map<String, dynamic>.from(dissolveProof.authorityData),
        ),
      ];
      final runner = GroupPendingBroadcastRunner(
        repository: pending,
        rePush: (_) async => false,
        protectedInboxStore: emptyStore,
        discoverPreparedAuthorities: (groupId) async => candidates
            .where(
              (candidate) => groupId == null || candidate.groupId == groupId,
            )
            .where(
              (candidate) => !history.containsKey(
                '${AuthenticatedGroupAuthorityPhase.complete.name}:'
                '${candidate.authorityProof!.eventId}',
              ),
            )
            .toList(growable: false),
        recoverPreparedAuthority: (preparation) {
          final proof = preparation.authorityProof!;
          if (preparation.control ==
              ProtectedGroupAuthorityControl.groupKeyUpdate) {
            return recoverPreparedProtectedGroupKey(
              proof: proof,
              groupRepository: groupRepo,
              promoteKey: (key) async => promoted.add(key),
              loadAuthorityProof: loadProof,
            );
          }
          return recoverPreparedProtectedGroupDissolve(
            groupId: preparation.groupId,
            eventId: proof.eventId,
            groupRepository: groupRepo,
            pendingRepository: pending,
            protectedInboxStore: emptyStore,
            pendingSiblingDeviceRepository: groupRepo,
            loadAuthorityProof: loadProof,
          );
        },
      );

      expect(await runner.drainProtectedAll(), 2);
      expect(promoted.map((key) => key.keyGeneration), <int>[2]);
      expect(
        (await groupRepo.getKeyByGeneration('group-1', 2))?.encryptedKey,
        draft.encryptedKey,
      );
      expect(await groupRepo.getPendingKeyRotation('group-1'), isNull);
      expect((await groupRepo.getGroup('group-1'))?.isDissolved, isTrue);
      expect(emptyStore.recipients, isEmpty);
      expect(
        history.keys,
        containsAll(<String>[
          '${AuthenticatedGroupAuthorityPhase.complete.name}:$keyEventId',
          '${AuthenticatedGroupAuthorityPhase.complete.name}:$dissolveEventId',
        ]),
      );

      final abortedAt = dissolveAt.add(const Duration(microseconds: 1));
      final abortedDraft = GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 3,
        encryptedKey: 'aborted-nonempty-key-v3',
        createdAt: abortedAt,
      );
      await groupRepo.savePendingKeyRotation(abortedDraft);
      final abortedProof = AuthenticatedGroupAuthorityProof(
        eventId: 'group_key_update:group-1:peer-admin:aborted-nonempty',
        groupId: 'group-1',
        eventAt: abortedAt,
        keyEpoch: 3,
        control: ProtectedGroupAuthorityControl.groupKeyUpdate.wireValue,
        actorAccountPeerId: 'peer-admin',
        actorAccountPublicKey: 'pk-admin',
        senderTransportPeerId: 'admin-transport',
        senderTransportPublicKey: 'pk-admin',
        authorityData: secretFreeProtectedAuthorityData(
          control: ProtectedGroupAuthorityControl.groupKeyUpdate.wireValue,
          replayData: <String, dynamic>{
            'groupId': 'group-1',
            'keyGeneration': 3,
            'encryptedKey': abortedDraft.encryptedKey,
            'from': 'admin-transport',
            'timestamp': abortedAt.toIso8601String(),
          },
          frozenRecipientPeerIds: const <String>['remote-transport'],
        ),
        signature: 'aborted-signature',
      );
      expect(
        await recoverPreparedProtectedGroupKey(
          proof: abortedProof,
          groupRepository: groupRepo,
          promoteKey: (_) async => fail('aborted rows must not promote a key'),
          loadAuthorityProof: loadProof,
        ),
        isFalse,
        reason: 'row absence is not custody evidence for a nonempty ACL',
      );
      expect(await groupRepo.getKeyByGeneration('group-1', 3), isNull);
    },
  );

  test(
    'EK004 dissolve stores signed group_dissolved replay envelope',
    () async {
      final (result, group) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        dissolvedAt: now.add(const Duration(minutes: 5)),
      );

      expect(result, DissolveGroupResult.success);
      expect(group, isNotNull);
      expect(group!.isDissolved, isTrue);
      expect(group.dissolvedAt, now.add(const Duration(minutes: 5)));
      expect(group.dissolvedBy, 'peer-admin');
      expect(group.lastMembershipEventAt, now.add(const Duration(minutes: 5)));

      final stored = await groupRepo.getGroup('group-1');
      expect(stored, isNotNull);
      expect(stored!.isDissolved, isTrue);
      expect(stored.dissolvedAt, now.add(const Duration(minutes: 5)));
      expect(stored.dissolvedBy, 'peer-admin');
      expect(stored.lastMembershipEventAt, now.add(const Duration(minutes: 5)));

      final latest = await msgRepo.getLatestMessage('group-1');
      expect(latest, isNotNull);
      expect(latest!.id.startsWith('sys-group_dissolved:group-1:'), isTrue);
      expect(latest.text, 'Admin dissolved the group');

      expect(
        bridge.commandLog,
        containsAll(['group:publish', 'group:inboxStore', 'group:leave']),
      );
      final inboxStoreMessage = bridge.sentMessages.firstWhere((message) {
        final parsed = jsonDecode(message) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:inboxStore';
      });
      final inboxPayload =
          (jsonDecode(inboxStoreMessage) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      final replayEnvelope =
          jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
      expect(replayEnvelope['kind'], 'group_offline_replay');
      expect(replayEnvelope['payloadType'], 'group_message');
      expect(replayEnvelope['senderPeerId'], 'peer-admin');
      expect(replayEnvelope['senderPublicKey'], 'pk-admin');
      expect(replayEnvelope['signatureAlgorithm'], 'ed25519');
      expect(replayEnvelope['signedPayload'], isA<String>());
      expect(replayEnvelope['signature'], isA<String>());
      final replayPlaintext =
          jsonDecode(replayEnvelope['ciphertext'] as String)
              as Map<String, dynamic>;
      expect(replayEnvelope['messageId'], replayPlaintext['messageId']);
    },
  );

  test(
    'local dissolve terminally clears only exact-group display custody',
    () async {
      groupRepo.displayRowsByGroup['group-1'] = {'message-a', 'reaction-a'};
      groupRepo.displayRowsByGroup['group-sibling'] = {'message-b'};

      final (result, group) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        dissolvedAt: now.add(const Duration(minutes: 5)),
      );

      expect(result, DissolveGroupResult.success);
      expect(group?.isDissolved, isTrue);
      expect(groupRepo.terminalCommitCalls, 1);
      expect(groupRepo.displayRowsByGroup, isNot(contains('group-1')));
      expect(groupRepo.displayRowsByGroup['group-sibling'], <String>{
        'message-b',
      });
    },
  );

  // B4 (Option A signer contract): the published group_dissolved audit must
  // carry the actor device/transport binding when the caller supplies it, so a
  // receiver's observed live binding matches the signed binding and the
  // dissolve verifies. Decode the audit from the proven inboxStore replay path.
  Map<String, dynamic> publishedDissolveAuditActor() {
    final inboxStoreMessage = bridge.sentMessages.firstWhere((message) {
      return (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
          'group:inboxStore';
    });
    final inboxPayload =
        (jsonDecode(inboxStoreMessage) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    final replayEnvelope =
        jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
    final replayPlaintext =
        jsonDecode(replayEnvelope['ciphertext'] as String)
            as Map<String, dynamic>;
    final sysPayload =
        jsonDecode(replayPlaintext['text'] as String) as Map<String, dynamic>;
    final audit =
        sysPayload[signedGroupTransitionAuditField] as Map<String, dynamic>;
    final signedPayload =
        jsonDecode(audit['signedPayload'] as String) as Map<String, dynamic>;
    return signedPayload['actor'] as Map<String, dynamic>;
  }

  test(
    'B4 dissolve WITH actor binding signs an audit whose actor carries device/transport',
    () async {
      final (result, _) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        actorDeviceId: 'dev-admin-1',
        actorTransportPeerId: 'transport-admin-1',
        actorKeyPackageId: 'kp-admin-1',
        dissolvedAt: now.add(const Duration(minutes: 5)),
      );

      expect(result, DissolveGroupResult.success);
      final actor = publishedDissolveAuditActor();
      expect(actor['deviceId'], 'dev-admin-1');
      expect(actor['transportPeerId'], 'transport-admin-1');
      expect(actor['keyPackageId'], 'kp-admin-1');
    },
  );

  test(
    'B4 dissolve WITHOUT actor binding (legacy caller) signs an audit whose actor OMITS device/transport',
    () async {
      final (result, _) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        dissolvedAt: now.add(const Duration(minutes: 5)),
      );

      expect(result, DissolveGroupResult.success);
      final actor = publishedDissolveAuditActor();
      // Documents the omit-on-null signer behavior that, paired with a present
      // observed binding on receivers, produced the field rejection (B4).
      expect(actor.containsKey('deviceId'), isFalse);
      expect(actor.containsKey('transportPeerId'), isFalse);
    },
  );

  test(
    'GM-032 dissolved group disables publish and inbox while preserving history',
    () async {
      final dissolvedAt = now.add(const Duration(minutes: 5));
      final (result, group) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        dissolvedAt: dissolvedAt,
      );

      expect(result, DissolveGroupResult.success);
      expect(group, isNotNull);
      expect(group!.isDissolved, isTrue);

      final historyBefore = await msgRepo.getMessagesPage('group-1');
      expect(historyBefore, hasLength(1));
      expect(historyBefore.single.text, 'Admin dissolved the group');

      bridge.commandLog.clear();
      bridge.sentMessages.clear();

      final (sendResult, sendMessage) = await group_send.sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'GM-032 should not publish',
        senderPeerId: 'peer-admin',
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        senderUsername: 'Admin',
        messageId: 'gm032-after-dissolve',
      );

      expect(sendResult, group_send.SendGroupMessageResult.groupDissolved);
      expect(sendMessage, isNull);
      expect(bridge.commandLog, isNot(contains('group:publish')));
      expect(bridge.commandLog, isNot(contains('group:inboxStore')));

      final historyAfter = await msgRepo.getMessagesPage('group-1');
      expect(historyAfter, hasLength(1));
      expect(historyAfter.single.id, historyBefore.single.id);
      final stored = await groupRepo.getGroup('group-1');
      expect(stored, isNotNull);
      expect(stored!.isDissolved, isTrue);
      expect(stored.dissolvedAt, dissolvedAt);
    },
  );

  test('returns unauthorized for non-admin users', () async {
    await groupRepo.updateGroup(baseGroup.copyWith(myRole: GroupRole.member));
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.writer,
        joinedAt: now,
      ),
    );

    final (result, group) = await dissolveGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
      groupId: 'group-1',
      actorPeerId: 'peer-admin',
      actorUsername: 'Admin',
      actorPublicKey: 'pk-admin',
      actorPrivateKey: 'sk-admin',
    );

    expect(result, DissolveGroupResult.unauthorized);
    expect(group, isNotNull);
    expect(group!.isDissolved, isFalse);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'former creator who is no longer admin cannot dissolve the group',
    () async {
      await groupRepo.updateGroup(baseGroup.copyWith(myRole: GroupRole.member));
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.writer,
          joinedAt: now,
        ),
      );

      final (result, group) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
      );

      expect(result, DissolveGroupResult.unauthorized);
      expect(group, isNotNull);
      expect(group!.isDissolved, isFalse);
      expect(bridge.commandLog, isEmpty);
    },
  );

  test('returns alreadyDissolved when the group is already closed', () async {
    await groupRepo.updateGroup(
      baseGroup.copyWith(
        isDissolved: true,
        dissolvedAt: now,
        dissolvedBy: 'peer-admin',
        lastMembershipEventAt: now,
      ),
    );

    final (result, group) = await dissolveGroup(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
      groupId: 'group-1',
      actorPeerId: 'peer-admin',
      actorUsername: 'Admin',
      actorPublicKey: 'pk-admin',
      actorPrivateKey: 'sk-admin',
    );

    expect(result, DissolveGroupResult.alreadyDissolved);
    expect(group, isNotNull);
    expect(group!.isDissolved, isTrue);
    expect(group.dissolvedAt, now);
    expect(group.dissolvedBy, 'peer-admin');
    expect(group.lastMembershipEventAt, now);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'repeated dissolve preserves closure state and does not publish again',
    () async {
      final firstDissolvedAt = now.add(const Duration(minutes: 5));
      final secondDissolvedAt = now.add(const Duration(minutes: 30));

      final (firstResult, firstGroup) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        dissolvedAt: firstDissolvedAt,
      );

      expect(firstResult, DissolveGroupResult.success);
      expect(firstGroup, isNotNull);
      expect(firstGroup!.isDissolved, isTrue);

      bridge.commandLog.clear();
      bridge.sentMessages.clear();

      final (secondResult, secondGroup) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin Again',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        dissolvedAt: secondDissolvedAt,
      );

      expect(secondResult, DissolveGroupResult.alreadyDissolved);
      expect(secondGroup, isNotNull);
      expect(secondGroup!.isDissolved, isTrue);
      expect(secondGroup.dissolvedAt, firstDissolvedAt);
      expect(secondGroup.dissolvedBy, 'peer-admin');
      expect(secondGroup.lastMembershipEventAt, firstDissolvedAt);
      expect(bridge.commandLog, isEmpty);
      expect(bridge.sentMessages, isEmpty);

      final stored = await groupRepo.getGroup('group-1');
      expect(stored, isNotNull);
      expect(stored!.isDissolved, isTrue);
      expect(stored.dissolvedAt, firstDissolvedAt);
      expect(stored.dissolvedBy, 'peer-admin');
      expect(stored.lastMembershipEventAt, firstDissolvedAt);

      final dissolvedMessages = (await msgRepo.getMessagesPage('group-1'))
          .where((message) => message.id.startsWith('sys-group_dissolved:'))
          .toList();
      expect(dissolvedMessages, hasLength(1));
      expect(
        groupRepo.terminalCommitCalls,
        2,
        reason: 'an already-dissolved replay must retry terminal cleanup',
      );
    },
  );

  test(
    'returns bridgeError when inbox fallback fails but still marks the group dissolved',
    () async {
      bridge.responses['group:inboxStore'] = {
        'ok': false,
        'errorCode': 'INBOX_STORE_FAILED',
      };

      final (result, group) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        dissolvedAt: now.add(const Duration(minutes: 10)),
      );

      expect(result, DissolveGroupResult.bridgeError);
      expect(group, isNotNull);
      expect(group!.isDissolved, isTrue);
      expect(group.dissolvedAt, now.add(const Duration(minutes: 10)));
      expect(bridge.commandLog, contains('group:leave'));

      final stored = await groupRepo.getGroup('group-1');
      expect(stored, isNotNull);
      expect(stored!.isDissolved, isTrue);
    },
  );

  test(
    'GSPR-001 dissolve inbox store failure leaves timeline row retryable',
    () async {
      bridge.responses['group:inboxStore'] = {
        'ok': false,
        'errorCode': 'INBOX_STORE_FAILED',
      };

      final (result, group) = await dissolveGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        preflightAuthority: fakeClearGroupDissolvePreflightAuthority(),
        groupId: 'group-1',
        actorPeerId: 'peer-admin',
        actorUsername: 'Admin',
        actorPublicKey: 'pk-admin',
        actorPrivateKey: 'sk-admin',
        dissolvedAt: now.add(const Duration(minutes: 15)),
      );

      expect(result, DissolveGroupResult.bridgeError);
      expect(group, isNotNull);
      expect(group!.isDissolved, isTrue);
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('group:inboxStore'));
      expect(bridge.commandLog, contains('group:leave'));

      final latest = await msgRepo.getLatestMessage('group-1');
      expect(latest, isNotNull);
      expect(latest!.id.startsWith('sys-group_dissolved:group-1:'), isTrue);
      expect(latest.inboxStored, isFalse);
      expect(latest.inboxRetryPayload, isNotNull);
      expect(latest.isIncoming, isFalse);
      expect(latest.status, 'sent');

      final eligible = await msgRepo.getMessagesWithFailedInboxStore();
      expect(eligible.map((message) => message.id), contains(latest.id));

      bridge.responses['group:inboxStore'] = {'ok': true};
      final retried = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: msgRepo,
      );

      expect(retried, 1);
      final retriedRow = await msgRepo.getMessage(latest.id);
      expect(retriedRow, isNotNull);
      expect(retriedRow!.inboxStored, isTrue);
      expect(retriedRow.inboxRetryPayload, isNull);
      expect(retriedRow.status, 'sent');
    },
  );
}
