import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/group_reaction_notification_projection.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/data/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/data/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';

/// Captures [FLOW] log lines emitted during [action] (plan 321 event
/// discriminators: PUBLISHED must appear only on an actual write, DEFERRED
/// only on a caught publish failure).
Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

void main() {
  const oldAccount = 'peer-old-account';
  const newAccount = 'peer-new-account';
  final now = DateTime.utc(2026, 7, 12, 12);

  GroupModel group({
    String name = 'Garden Club',
    GroupType type = GroupType.chat,
    bool muted = false,
    bool dissolved = false,
  }) => GroupModel(
    id: 'group-1',
    name: name,
    type: type,
    topicName: '/mknoon/groups/group-1',
    createdAt: now,
    createdBy: oldAccount,
    myRole: GroupRole.admin,
    isMuted: muted,
    isDissolved: dissolved,
    dissolvedAt: dissolved ? now : null,
    dissolvedBy: dissolved ? oldAccount : null,
  );

  GroupMember member({
    required String peerId,
    required String username,
    String deviceId = 'device-1',
    String transportPeerId = 'transport-1',
  }) => GroupMember(
    groupId: 'group-1',
    peerId: peerId,
    username: username,
    role: MemberRole.writer,
    publicKey: 'must-not-be-projected',
    mlKemPublicKey: 'must-not-be-projected-either',
    devices: <GroupMemberDeviceIdentity>[
      GroupMemberDeviceIdentity(
        deviceId: deviceId,
        transportPeerId: transportPeerId,
        deviceSigningPublicKey: 'must-not-be-projected-signing-key',
      ),
    ],
    joinedAt: now,
  );

  GroupMessage target({String id = 'target-1'}) => GroupMessage(
    id: id,
    groupId: 'group-1',
    senderPeerId: oldAccount,
    senderUsername: 'Local Account',
    text: 'private target text must not be projected',
    timestamp: now,
    keyGeneration: 7,
    status: 'sent',
    // A sibling-device copy can be incoming locally while still authored by
    // the same account and must remain an eligible authored target.
    isIncoming: true,
    createdAt: now,
  );

  MessageReaction reaction({
    String id = 'reaction-state-1',
    String timestamp = '2026-07-12T12:01:00.000Z',
    String? removedAt,
  }) => MessageReaction(
    id: id,
    messageId: 'target-1',
    emoji: '👍',
    senderPeerId: 'peer-alice',
    timestamp: timestamp,
    createdAt: timestamp,
    removedAt: removedAt,
  );

  test(
    'projection tracks group member mute dissolve key and target lifecycle',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(
        store: store,
        maxAuthoredTargets: 2,
      );

      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: 'self-device',
        transportPeerId: 'self-transport',
      );
      await projection.upsertGroup(group());
      await projection.upsertMember(
        member(
          peerId: oldAccount,
          username: 'Local Account',
          deviceId: 'self-device',
          transportPeerId: 'self-transport',
        ),
      );
      await projection.upsertMember(
        member(
          peerId: 'peer-alice',
          username: 'Alice',
          deviceId: 'alice-device',
          transportPeerId: 'alice-transport',
        ),
      );
      await projection.upsertKeyEpoch(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 7,
          encryptedKey: 'private-key-material',
          createdAt: now,
        ),
      );
      await projection.upsertAuthoredTarget(target());
      await projection.upsertReactionComparand(reaction());

      final contexts = await projection.readContexts();
      expect(contexts['localAccountPeerId'], oldAccount);
      expect(contexts['localDeviceId'], 'self-device');
      expect(contexts['localTransportPeerId'], 'self-transport');
      final groups = contexts['groups']! as Map<String, Object?>;
      final first = groups['group-1']! as Map<String, Object?>;
      expect(first['name'], 'Garden Club');
      expect(first['type'], 'chat');
      expect(first['muted'], isFalse);
      expect(first['archived'], isFalse);
      expect(first['dissolved'], isFalse);
      expect(first['keyEpoch'], 7);
      final members = first['members']! as Map<String, Object?>;
      expect(members['peer-alice'], <String, Object?>{
        'username': 'Alice',
        'role': 'writer',
        'deviceIds': <String>['alice-device'],
        'transportPeerIds': <String>['alice-transport'],
      });
      expect(await projection.readAuthoredTargets(), <Map<String, Object?>>[
        <String, Object?>{
          'id': 'target-1',
          'groupId': 'group-1',
          'keyEpoch': 7,
          'timestamp': now.toIso8601String(),
        },
      ]);
      expect(await projection.readReactionComparands(), <Map<String, Object?>>[
        <String, Object?>{
          'groupId': 'group-1',
          'targetMessageId': 'target-1',
          'reactorPeerId': 'peer-alice',
          'timestamp': '2026-07-12T12:01:00.000Z',
        },
      ]);

      final raw = store.values.values.join('\n');
      expect(raw, isNot(contains('private target text')));
      expect(raw, isNot(contains('private-key-material')));
      expect(raw, isNot(contains('must-not-be-projected')));
      expect(raw, isNot(contains('👍')));

      await projection.upsertReactionComparand(
        reaction(
          id: 'reaction-remove-1',
          timestamp: '2026-07-12T12:01:00.000Z',
          removedAt: '2026-07-12T12:02:00.000Z',
        ),
      );
      expect(
        (await projection.readReactionComparands()).single['removedAt'],
        '2026-07-12T12:02:00.000Z',
      );

      await projection.upsertGroup(
        group(
          name: 'Garden Announcements',
          type: GroupType.announcement,
          muted: true,
          dissolved: true,
        ),
      );
      await projection.upsertMember(
        member(peerId: 'peer-alice', username: 'Alice Updated'),
      );
      final updated =
          ((await projection.readContexts())['groups']!
                  as Map<String, Object?>)['group-1']!
              as Map<String, Object?>;
      expect(updated['name'], 'Garden Announcements');
      expect(updated['type'], 'announcement');
      expect(updated['muted'], isTrue);
      expect(updated['dissolved'], isTrue);

      await projection.removeMember(groupId: 'group-1', peerId: 'peer-alice');
      await projection.removeAuthoredTarget('target-1');
      expect(await projection.readAuthoredTargets(), isEmpty);
      expect(await projection.readReactionComparands(), isEmpty);
      await projection.removeGroup('group-1');
      expect((await projection.readContexts())['groups'], isEmpty);
    },
  );

  test(
    'accepted context replacement publishes group roster and key in one strict document write',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: 'self-device',
        transportPeerId: 'self-transport',
      );
      await projection.upsertGroup(group(name: 'Removed generation'));
      await projection.removeGroupStrict('group-1');
      store.writeKeys.clear();

      await projection.replaceAcceptedGroupContextStrict(
        group: group(name: 'Accepted generation', muted: true),
        members: <GroupMember>[
          member(
            peerId: oldAccount,
            username: 'Local Account',
            deviceId: 'self-device',
            transportPeerId: 'self-transport',
          ),
          member(peerId: 'peer-alice', username: 'Alice'),
        ],
        key: GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 9,
          encryptedKey: 'must-not-be-projected',
          createdAt: now,
        ),
      );

      expect(store.writeKeys, <String>[sharedGroupReactionContextsKey]);
      final projected =
          ((await projection.readContexts())['groups']!
                  as Map<String, Object?>)['group-1']!
              as Map<String, Object?>;
      expect(projected['name'], 'Accepted generation');
      expect(projected['muted'], isTrue);
      expect(projected['keyEpoch'], 9);
      expect(
        (projected['members']! as Map<String, Object?>).keys,
        containsAll(<String>[oldAccount, 'peer-alice']),
      );
      expect(
        store.values.values.join('\n'),
        isNot(contains('must-not-be-projected')),
      );

      await projection.removeGroupStrict('group-1');
      store.writeKeys.clear();
      store.failNextWriteKeys.add(sharedGroupReactionContextsKey);
      await expectLater(
        projection.replaceAcceptedGroupContextStrict(
          group: group(name: 'Must fail'),
          members: <GroupMember>[
            member(peerId: oldAccount, username: 'Local Account'),
          ],
          key: GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 10,
            encryptedKey: 'private',
            createdAt: now,
          ),
        ),
        throwsStateError,
      );
      expect(store.writeKeys, <String>[sharedGroupReactionContextsKey]);
      expect((await projection.readContexts())['groups'], isEmpty);
    },
  );

  test(
    'launch replacement self-heals stale and failed projection writes',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );
      await projection.upsertGroup(group(name: 'Stale'));
      await projection.upsertAuthoredTarget(target(id: 'stale-target'));

      store.failWrites = true;
      await projection.replaceContexts(
        groups: <GroupModel>[group(name: 'Ignored Failed Write')],
        membersByGroup: <String, List<GroupMember>>{},
        latestKeysByGroup: <String, GroupKeyInfo?>{},
      );
      store.failWrites = false;

      await projection.replaceContexts(
        groups: <GroupModel>[group(name: 'Current')],
        membersByGroup: <String, List<GroupMember>>{
          'group-1': <GroupMember>[
            member(peerId: oldAccount, username: 'Current Local'),
          ],
        },
        latestKeysByGroup: <String, GroupKeyInfo?>{
          'group-1': GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 9,
            encryptedKey: 'never-projected',
            createdAt: now,
          ),
        },
      );
      await projection.replaceAuthoredTargets(<GroupMessage>[target()]);

      final current =
          ((await projection.readContexts())['groups']!
                  as Map<String, Object?>)['group-1']!
              as Map<String, Object?>;
      expect(current['name'], 'Current');
      expect(current['keyEpoch'], 9);
      expect((await projection.readAuthoredTargets()).single['id'], 'target-1');
    },
  );

  test(
    'projects this installation separately from an active sibling roster',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: 'device-a-revoked',
        transportPeerId: 'transport-a-revoked',
      );
      await projection.upsertGroup(group());
      await projection.upsertMember(
        GroupMember(
          groupId: 'group-1',
          peerId: oldAccount,
          username: 'Local Account',
          role: MemberRole.writer,
          publicKey: 'account-public-key',
          devices: <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-a-revoked',
              transportPeerId: 'transport-a-revoked',
              deviceSigningPublicKey: 'device-a-key',
              status: GroupMemberDeviceStatus.revoked,
              revokedAt: now,
            ),
            const GroupMemberDeviceIdentity(
              deviceId: 'device-b-active',
              transportPeerId: 'transport-b-active',
              deviceSigningPublicKey: 'device-b-key',
            ),
          ],
          joinedAt: now,
        ),
      );

      final contexts = await projection.readContexts();
      expect(contexts['localDeviceId'], 'device-a-revoked');
      expect(contexts['localTransportPeerId'], 'transport-a-revoked');
      final projectedGroup =
          (contexts['groups']! as Map<String, Object?>)['group-1']!
              as Map<String, Object?>;
      final localMember =
          (projectedGroup['members']! as Map<String, Object?>)[oldAccount]!
              as Map<String, Object?>;
      expect(localMember['deviceIds'], <String>['device-b-active']);
      expect(localMember['transportPeerIds'], <String>['transport-b-active']);
    },
  );

  test(
    'retained historical key writes never regress the projected epoch',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );
      await projection.upsertGroup(group());
      await projection.upsertKeyEpoch(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 9,
          encryptedKey: 'current-key',
          createdAt: now,
        ),
      );
      await projection.upsertKeyEpoch(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 8,
          encryptedKey: 'retained-historical-key',
          createdAt: now.subtract(const Duration(minutes: 1)),
        ),
      );

      final projectedGroup =
          ((await projection.readContexts())['groups']!
                  as Map<String, Object?>)['group-1']!
              as Map<String, Object?>;
      expect(projectedGroup['keyEpoch'], 9);
    },
  );

  test(
    'reaction repository projects ADD REMOVE backfill and hard cleanup',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );
      await projection.upsertGroup(group());
      await projection.upsertAuthoredTarget(target());

      Map<String, Object?>? currentRow;
      final repository = ReactionRepositoryImpl(
        dbInsertReaction: (row) async => currentRow = Map.of(row),
        dbApplyIncomingAdd: (row) async {
          currentRow = Map.of(row)..['removed_at'] = null;
          return ReactionAddApplyResult.inserted;
        },
        dbApplyIncomingRemove: (row) async {
          currentRow = Map.of(row)..['removed_at'] = row['timestamp'];
          return ReactionRemoveApplyResult.applied;
        },
        dbLoadReactionsForMessage: (_) async => const [],
        dbLoadReactionsForMessages: (_) async => const [],
        dbLoadActiveOrTombstonedReactionForSender: (_, _) async => currentRow,
        dbDeleteReaction: (_, _, {removedAtTimestamp}) async => 0,
        dbDeleteReactionsForMessage: (_) async {
          currentRow = null;
          return 1;
        },
        dbDeleteReactionsForContact: (_) async => 0,
        groupReactionProjection: projection,
        dbLoadGroupReactionComparandsForProjection: (_, {limit = 1024}) async =>
            currentRow == null
            ? const <Map<String, Object?>>[]
            : <Map<String, Object?>>[currentRow!],
      );

      expect(
        await repository.applyIncomingAdd(reaction()),
        ReactionAddApplyResult.inserted,
      );
      expect(
        (await projection.readReactionComparands()).single,
        isNot(contains('removedAt')),
      );

      expect(
        await repository.applyIncomingRemove(
          reaction(
            id: 'reaction-remove-1',
            timestamp: '2026-07-12T12:02:00.000Z',
          ),
        ),
        ReactionRemoveApplyResult.applied,
      );
      expect(
        (await projection.readReactionComparands()).single['removedAt'],
        '2026-07-12T12:02:00.000Z',
      );

      currentRow = reaction(
        id: 'reaction-backfill-1',
        timestamp: '2026-07-12T12:03:00.000Z',
      ).toMap();
      await repository.mirrorAllGroupReactionNotificationComparands();
      expect(
        (await projection.readReactionComparands()).single['timestamp'],
        '2026-07-12T12:03:00.000Z',
      );

      await repository.deleteReactionsForMessage('target-1');
      expect(await projection.readReactionComparands(), isEmpty);
    },
  );

  test(
    'logout and identity replacement clear all prior-account state',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );
      await projection.upsertGroup(group());
      await projection.upsertAuthoredTarget(target());
      await projection.upsertReactionComparand(reaction());

      await projection.clearForLogout();
      expect(store.values, isNot(contains(sharedGroupReactionContextsKey)));
      expect(
        store.values,
        isNot(contains(sharedGroupReactionAuthoredTargetsKey)),
      );
      expect(store.values, isNot(contains(sharedGroupReactionLatestStatesKey)));

      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );
      await projection.upsertGroup(group());
      await projection.upsertAuthoredTarget(target());
      await projection.replaceLocalIdentity(
        accountPeerId: newAccount,
        deviceId: newAccount,
        transportPeerId: newAccount,
      );

      final contexts = await projection.readContexts();
      expect(contexts['localAccountPeerId'], newAccount);
      expect(contexts['groups'], isEmpty);
      expect(await projection.readAuthoredTargets(), isEmpty);
      expect(await projection.readReactionComparands(), isEmpty);
    },
  );

  test(
    'early identity invalidation failure surfaces and remains wholly old',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );
      await projection.upsertGroup(group(name: 'Old Account Group'));

      store.failWrites = true;
      await expectLater(
        projection.replaceLocalIdentity(
          accountPeerId: newAccount,
          deviceId: newAccount,
          transportPeerId: newAccount,
        ),
        throwsStateError,
      );
      store.failWrites = false;
      await projection.upsertGroup(group(name: 'Must Stay Blocked'));

      final stillOld = await projection.readContexts();
      expect(stillOld['localAccountPeerId'], oldAccount);
      expect(
        ((stillOld['groups']! as Map<String, Object?>)['group-1']!
            as Map<String, Object?>)['name'],
        'Old Account Group',
      );

      await projection.replaceLocalIdentity(
        accountPeerId: newAccount,
        deviceId: newAccount,
        transportPeerId: newAccount,
      );
      final replacedContexts = await projection.readContexts();
      expect(replacedContexts['localAccountPeerId'], newAccount);
      expect(replacedContexts['localDeviceId'], newAccount);
      expect(replacedContexts['localTransportPeerId'], newAccount);
      expect(replacedContexts['groups'], isEmpty);
    },
  );

  test(
    'paused old-account context load cannot fence a same-id new-account group',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );

      final loadCaptured = Completer<void>();
      final releaseLoad = Completer<void>();
      final oldAccountBackfill = projection
          .replaceContextsFromAuthoritativeLoader(() async {
            loadCaptured.complete();
            await releaseLoad.future;
            return (
              groups: <GroupModel>[],
              membersByGroup: <String, List<GroupMember>>{},
              latestKeysByGroup: <String, GroupKeyInfo?>{},
              terminalGroupIds: <String>{'group-1'},
            );
          });
      await loadCaptured.future;

      final replaceIdentity = projection.replaceLocalIdentity(
        accountPeerId: newAccount,
        deviceId: newAccount,
        transportPeerId: newAccount,
      );
      releaseLoad.complete();
      await Future.wait<void>([oldAccountBackfill, replaceIdentity]);

      await projection.replaceContexts(
        groups: <GroupModel>[group(name: 'New Account Group')],
        membersByGroup: <String, List<GroupMember>>{},
        latestKeysByGroup: <String, GroupKeyInfo?>{},
      );

      final contexts = await projection.readContexts();
      expect(contexts['localAccountPeerId'], newAccount);
      expect(
        (contexts['groups']! as Map<String, Object?>),
        contains('group-1'),
      );
    },
  );

  test(
    'identity switch during post-loader read cannot seed a stale terminal fence',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );

      final readBarrierArmed = Completer<void>();
      final oldAccountBackfill = projection
          .replaceContextsFromAuthoritativeLoader(() async {
            store.armNextReadBarrier(sharedGroupReactionContextsKey);
            readBarrierArmed.complete();
            return (
              groups: <GroupModel>[],
              membersByGroup: <String, List<GroupMember>>{},
              latestKeysByGroup: <String, GroupKeyInfo?>{},
              terminalGroupIds: <String>{'group-1'},
            );
          });
      await readBarrierArmed.future;
      await store.readCaptured.future;

      final replaceIdentity = projection.replaceLocalIdentity(
        accountPeerId: newAccount,
        deviceId: newAccount,
        transportPeerId: newAccount,
      );
      store.releaseRead();
      await Future.wait<void>([oldAccountBackfill, replaceIdentity]);

      await projection.replaceContexts(
        groups: <GroupModel>[group(name: 'New Account Group')],
        membersByGroup: <String, List<GroupMember>>{},
        latestKeysByGroup: <String, GroupKeyInfo?>{},
      );

      final contexts = await projection.readContexts();
      expect(contexts['localAccountPeerId'], newAccount);
      expect(
        (contexts['groups']! as Map<String, Object?>),
        contains('group-1'),
      );
    },
  );

  test('failed group eligibility write invalidates prior context', () async {
    final store = _MemorySecureKeyStore();
    final projection = GroupReactionNotificationProjection(store: store);
    await projection.replaceLocalIdentity(
      accountPeerId: oldAccount,
      deviceId: oldAccount,
      transportPeerId: oldAccount,
    );
    await projection.upsertGroup(group(name: 'Eligible Group'));

    store.failNextWriteKeys.add(sharedGroupReactionContextsKey);
    await projection.upsertGroup(group(name: 'Eligible Group', muted: true));

    expect(store.values, isNot(contains(sharedGroupReactionContextsKey)));
    expect((await projection.readContexts())['groups'], isEmpty);
  });

  test(
    'identity repository clears or replaces projection before reuse',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      final directProjection = DirectReactionNotificationProjection(
        store: store,
      );
      await directProjection.replaceLocalIdentity(accountPeerId: oldAccount);
      await directProjection.upsertContact(
        ContactModel(
          peerId: 'peer-old-contact',
          publicKey: 'public',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Old Contact',
          signature: 'signature',
          scannedAt: now.toIso8601String(),
        ),
      );
      await directProjection.upsertAuthoredTarget(
        ConversationMessage(
          id: 'old-direct-target',
          contactPeerId: 'peer-old-contact',
          senderPeerId: oldAccount,
          text: 'old',
          timestamp: now.toIso8601String(),
          status: 'sent',
          isIncoming: false,
          createdAt: now.toIso8601String(),
        ),
      );
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );
      await projection.upsertGroup(group());
      await projection.upsertAuthoredTarget(target());

      Map<String, Object?>? identityRow;
      final identityStore = _MemorySecureKeyStore();
      final repository = IdentityRepositoryImpl(
        dbLoadIdentityRow: () async => identityRow,
        dbUpsertIdentityRow: (row) async => identityRow = row,
        secureKeyStore: identityStore,
        directReactionProjection: directProjection,
        groupReactionProjection: projection,
      );
      await repository.saveIdentity(
        IdentityModel(
          peerId: newAccount,
          publicKey: 'public',
          privateKey: 'private',
          mnemonic12:
              'one two three four five six seven eight nine ten eleven twelve',
          username: 'New Account',
          createdAt: now.toIso8601String(),
          updatedAt: now.toIso8601String(),
        ),
      );

      expect(
        (await projection.readContexts())['localAccountPeerId'],
        newAccount,
      );
      expect((await projection.readContexts())['groups'], isEmpty);
      expect(await projection.readAuthoredTargets(), isEmpty);
      expect(await directProjection.readLocalAccountPeerId(), newAccount);
      expect(await directProjection.readContacts(), isEmpty);
      expect(await directProjection.readAuthoredTargets(), isEmpty);

      identityRow = null;
      repository.invalidateCache();
      expect(await repository.loadIdentity(), isNull);
      expect(store.values, isNot(contains(sharedGroupReactionContextsKey)));
      expect(
        store.values,
        isNot(contains(sharedGroupReactionAuthoredTargetsKey)),
      );
      expect(store.values, isNot(contains(sharedDirectReactionContactsKey)));
      expect(
        store.values,
        isNot(contains(sharedDirectReactionAuthoredTargetsKey)),
      );
    },
  );

  test(
    'failed identity transition never publishes mixed old context and new identity',
    () async {
      for (final failAt in <String>[
        'projection',
        'direct_projection',
        'secret',
        'database',
      ]) {
        final projectionStore = _MemorySecureKeyStore();
        final directProjection = DirectReactionNotificationProjection(
          store: projectionStore,
        );
        final groupProjection = GroupReactionNotificationProjection(
          store: projectionStore,
        );
        await directProjection.replaceLocalIdentity(accountPeerId: oldAccount);
        await directProjection.upsertContact(
          ContactModel(
            peerId: 'peer-old-contact',
            publicKey: 'public',
            rendezvous: '/dns4/relay/tcp/443',
            username: 'Old Contact',
            signature: 'signature',
            scannedAt: now.toIso8601String(),
          ),
        );
        await groupProjection.replaceLocalIdentity(
          accountPeerId: oldAccount,
          deviceId: oldAccount,
          transportPeerId: oldAccount,
        );
        await groupProjection.upsertGroup(group(name: 'Old Eligible Group'));
        if (failAt == 'projection') {
          projectionStore.failNextWrites = 1;
        } else if (failAt == 'direct_projection') {
          projectionStore.failNextWriteKeys.add(
            sharedDirectReactionContactsKey,
          );
        }

        final identityStore = _MemorySecureKeyStore()
          ..failWrites = failAt == 'secret';
        var databaseWrites = 0;
        final repository = IdentityRepositoryImpl(
          dbLoadIdentityRow: () async => null,
          dbUpsertIdentityRow: (_) async {
            databaseWrites++;
            if (failAt == 'database') {
              throw StateError('injected identity database failure');
            }
          },
          secureKeyStore: identityStore,
          directReactionProjection: directProjection,
          groupReactionProjection: groupProjection,
        );

        await expectLater(
          repository.saveIdentity(
            IdentityModel(
              peerId: newAccount,
              publicKey: 'new-public',
              privateKey: 'new-private',
              mnemonic12:
                  'one two three four five six seven eight nine ten eleven twelve',
              username: 'New Account',
              createdAt: now.toIso8601String(),
              updatedAt: now.toIso8601String(),
            ),
          ),
          throwsStateError,
          reason: failAt,
        );

        final contexts = await groupProjection.readContexts();
        expect(contexts['groups'], isEmpty, reason: failAt);
        if (failAt == 'projection') {
          expect(contexts['localAccountPeerId'], isNull, reason: failAt);
          expect(
            await directProjection.readLocalAccountPeerId(),
            oldAccount,
            reason: failAt,
          );
          expect(databaseWrites, 0, reason: failAt);
          expect(identityStore.values, isEmpty, reason: failAt);
        } else if (failAt == 'direct_projection') {
          expect(contexts['localAccountPeerId'], newAccount, reason: failAt);
          expect(
            await directProjection.readLocalAccountPeerId(),
            isNull,
            reason: failAt,
          );
          expect(databaseWrites, 0, reason: failAt);
          expect(identityStore.values, isEmpty, reason: failAt);
        } else {
          expect(contexts['localAccountPeerId'], newAccount, reason: failAt);
          expect(
            await directProjection.readLocalAccountPeerId(),
            newAccount,
            reason: failAt,
          );
          expect(
            await directProjection.readContacts(),
            isEmpty,
            reason: failAt,
          );
        }
      }
    },
  );

  test(
    'repository mutations project only committed rows and startup restores them',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );
      final groupDb = _MemoryGroupPersistence();
      final groupRepository = groupDb.repository(projection);

      await groupRepository.saveGroup(group());
      await groupRepository.saveMember(
        member(
          peerId: oldAccount,
          username: 'Local Account',
          deviceId: 'self-device',
          transportPeerId: 'self-transport',
        ),
      );
      await groupRepository.saveMember(
        member(peerId: 'peer-alice', username: 'Alice'),
      );
      await groupRepository.updateMemberRole(
        'group-1',
        'peer-alice',
        MemberRole.admin,
      );
      var projectedGroup =
          ((await projection.readContexts())['groups']!
                  as Map<String, Object?>)['group-1']!
              as Map<String, Object?>;
      final projectedMembers =
          projectedGroup['members']! as Map<String, Object?>;
      expect(
        (projectedMembers['peer-alice']! as Map<String, Object?>)['role'],
        'admin',
      );
      await groupRepository.archiveGroup('group-1');
      projectedGroup =
          ((await projection.readContexts())['groups']!
                  as Map<String, Object?>)['group-1']!
              as Map<String, Object?>;
      expect(projectedGroup['archived'], isTrue);
      await groupRepository.unarchiveGroup('group-1');
      projectedGroup =
          ((await projection.readContexts())['groups']!
                  as Map<String, Object?>)['group-1']!
              as Map<String, Object?>;
      expect(projectedGroup['archived'], isFalse);
      await groupRepository.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 7,
          encryptedKey: 'secret',
          createdAt: now,
        ),
      );

      groupDb.failNextGroupWrite = true;
      await expectLater(
        groupRepository.saveGroup(
          group(name: 'Must Not Commit').copyWith(id: 'group-failed'),
        ),
        throwsStateError,
      );
      expect(
        (await projection.readContexts())['groups'] as Map<String, Object?>,
        isNot(contains('group-failed')),
      );

      final messageDb = _MemoryGroupMessagePersistence();
      final messageRepository = messageDb.repository(projection);
      await messageRepository.saveMessage(target());
      expect((await projection.readAuthoredTargets()).single['id'], 'target-1');

      messageDb.skipNextInsert = true;
      await messageRepository.saveMessage(target(id: 'not-committed'));
      expect(
        (await projection.readAuthoredTargets()).map((row) => row['id']),
        isNot(contains('not-committed')),
      );

      await messageRepository.deleteMessage('target-1');
      expect(await projection.readAuthoredTargets(), isEmpty);

      // Simulate rows imported while projection writes were unavailable. The
      // two concrete repository backfills are authoritative replacements.
      groupDb.groups['group-1'] = group(name: 'Restored Name').toMap();
      messageDb.messages['restored-target'] = target(
        id: 'restored-target',
      ).toMap();
      await projection.upsertGroup(group(name: 'Stale Name'));
      await groupRepository.mirrorAllGroupReactionNotificationContexts();
      await messageRepository.mirrorAllGroupReactionAuthoredTargets();

      final restored =
          ((await projection.readContexts())['groups']!
                  as Map<String, Object?>)['group-1']!
              as Map<String, Object?>;
      expect(restored['name'], 'Restored Name');
      expect(restored['keyEpoch'], 7);
      expect(
        (await projection.readAuthoredTargets()).map((row) => row['id']),
        <String?>['restored-target'],
      );
    },
  );

  test(
    'authored targets and paused backfills cannot outlive terminal group context',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );
      final groupDb = _MemoryGroupPersistence();
      final groupRepository = groupDb.repository(projection);
      final messageDb = _MemoryGroupMessagePersistence();
      final messageRepository = messageDb.repository(projection);
      await groupRepository.saveGroup(group());
      await messageRepository.saveMessage(target());
      expect(await projection.readAuthoredTargets(), hasLength(1));

      groupDb.armGroupLoadBarrier();
      final groupBackfill = groupRepository
          .mirrorAllGroupReactionNotificationContexts();
      await groupDb.groupLoadCaptured.future;
      final terminalRemoval = projection.removeGroupStrict('group-1');
      try {
        await Future<void>.delayed(Duration.zero);
        expect(
          (await projection.readContexts())['groups'],
          contains('group-1'),
          reason: 'terminal removal queues behind the launch snapshot',
        );
      } finally {
        groupDb.releaseGroupLoad();
      }
      await Future.wait<void>([groupBackfill, terminalRemoval]);
      expect((await projection.readContexts())['groups'], isEmpty);
      expect(await projection.readAuthoredTargets(), isEmpty);

      messageDb.armAuthoredLoadBarrier();
      final targetBackfill = messageRepository
          .mirrorAllGroupReactionAuthoredTargets();
      await messageDb.authoredLoadCaptured.future;
      messageDb.releaseAuthoredLoad();
      await targetBackfill;
      await projection.upsertAuthoredTarget(target(id: 'late-target'));

      expect((await projection.readContexts())['groups'], isEmpty);
      expect(await projection.readAuthoredTargets(), isEmpty);
      expect(store.values.values.join('\n'), isNot(contains('group-1')));

      // A later authenticated membership restoration republishes the group
      // before its authored targets, re-establishing projection authority.
      await projection.upsertGroup(group(name: 'Reaccepted'));
      await projection.upsertAuthoredTarget(target(id: 'accepted-target'));
      expect(
        (await projection.readAuthoredTargets()).single['id'],
        'accepted-target',
      );
    },
  );

  test(
    'launch snapshot queued before removal and accepted re-entry cannot overwrite accepted context',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );
      final groupDb = _MemoryGroupPersistence();
      final repository = groupDb.repository(projection);
      await repository.saveGroup(group(name: 'Old authority'));
      await repository.saveMember(
        member(peerId: oldAccount, username: 'Old Local'),
      );
      await repository.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'old-private',
          createdAt: now,
        ),
      );

      groupDb.armGroupLoadBarrier();
      final backfill = repository.mirrorAllGroupReactionNotificationContexts();
      await groupDb.groupLoadCaptured.future;

      var removalCompleted = false;
      final removal = projection
          .removeGroupStrict('group-1')
          .whenComplete(() => removalCompleted = true);

      final acceptedGroup = group(name: 'Accepted authority');
      final acceptedMember = member(
        peerId: oldAccount,
        username: 'Accepted Local',
        deviceId: 'accepted-device',
        transportPeerId: 'accepted-transport',
      );
      final acceptedKey = GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 12,
        encryptedKey: 'accepted-private',
        createdAt: now.add(const Duration(minutes: 1)),
      );
      groupDb.groups['group-1'] = acceptedGroup.toMap();
      groupDb.members['group-1:$oldAccount'] = acceptedMember.toMap();
      groupDb.keys['group-1:12'] = acceptedKey.toMap();

      var acceptedCompleted = false;
      final accepted = projection
          .replaceAcceptedGroupContextStrict(
            group: acceptedGroup,
            members: <GroupMember>[acceptedMember],
            key: acceptedKey,
          )
          .whenComplete(() => acceptedCompleted = true);

      try {
        await Future<void>.delayed(Duration.zero);
        expect(
          removalCompleted,
          isFalse,
          reason: 'terminal removal queues behind the launch snapshot',
        );
        expect(
          acceptedCompleted,
          isFalse,
          reason: 'accepted replacement queues behind terminal removal',
        );
      } finally {
        groupDb.releaseGroupLoad();
      }

      await Future.wait<void>([backfill, removal, accepted]);
      final projected =
          ((await projection.readContexts())['groups']!
                  as Map<String, Object?>)['group-1']!
              as Map<String, Object?>;
      expect(projected['name'], 'Accepted authority');
      expect(projected['keyEpoch'], 12);
      final projectedMembers = projected['members']! as Map<String, Object?>;
      expect(
        (projectedMembers[oldAccount]! as Map<String, Object?>)['username'],
        'Accepted Local',
      );
    },
  );

  test(
    'authored target snapshot queued before removal and accepted re-entry cannot restore an old target',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );
      await projection.upsertGroup(group(name: 'Old authority'));
      final messageDb = _MemoryGroupMessagePersistence();
      final repository = messageDb.repository(projection);
      await repository.saveMessage(target(id: 'old-target'));

      messageDb.armAuthoredLoadBarrier();
      final backfill = repository.mirrorAllGroupReactionAuthoredTargets();
      await messageDb.authoredLoadCaptured.future;
      messageDb.messages.remove('old-target');

      var removalCompleted = false;
      final removal = projection
          .removeGroupStrict('group-1')
          .whenComplete(() => removalCompleted = true);
      var acceptedCompleted = false;
      final accepted = projection
          .replaceAcceptedGroupContextStrict(
            group: group(name: 'Accepted authority'),
            members: <GroupMember>[
              member(peerId: oldAccount, username: 'Accepted Local'),
            ],
            key: GroupKeyInfo(
              groupId: 'group-1',
              keyGeneration: 12,
              encryptedKey: 'accepted-private',
              createdAt: now.add(const Duration(minutes: 1)),
            ),
          )
          .whenComplete(() => acceptedCompleted = true);

      try {
        await Future<void>.delayed(Duration.zero);
        expect(removalCompleted, isFalse);
        expect(acceptedCompleted, isFalse);
      } finally {
        messageDb.releaseAuthoredLoad();
      }

      await Future.wait<void>([backfill, removal, accepted]);
      expect(await projection.readAuthoredTargets(), isEmpty);

      await projection.upsertAuthoredTarget(target(id: 'accepted-target'));
      expect(
        (await projection.readAuthoredTargets()).map((row) => row['id']),
        <String?>['accepted-target'],
      );
    },
  );

  test(
    'inbox transaction projects after commit but never after rollback',
    () async {
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: oldAccount,
        deviceId: oldAccount,
        transportPeerId: oldAccount,
      );
      await projection.upsertGroup(group());
      final messageDb = _MemoryGroupMessagePersistence();
      final repository = messageDb.repository(
        projection,
        enableTransactions: true,
      );

      messageDb.failNextTransaction = true;
      await expectLater(
        repository.runInboxPageTransaction(
          groupId: 'group-1',
          nextCursor: 'cursor-rollback',
          apply: (transactionRepo) async {
            await transactionRepo.saveMessage(target(id: 'rolled-back-target'));
            expect(await projection.readAuthoredTargets(), isEmpty);
          },
        ),
        throwsStateError,
      );
      expect(messageDb.messages, isNot(contains('rolled-back-target')));
      expect(await projection.readAuthoredTargets(), isEmpty);

      await repository.runInboxPageTransaction(
        groupId: 'group-1',
        nextCursor: 'cursor-commit',
        apply: (transactionRepo) async {
          await transactionRepo.saveMessage(target(id: 'committed-target'));
          expect(await projection.readAuthoredTargets(), isEmpty);
        },
      );
      expect(messageDb.messages, contains('committed-target'));
      expect(
        (await projection.readAuthoredTargets()).map((row) => row['id']),
        <String?>['committed-target'],
      );
    },
  );

  test(
    'startup restore precedes push eligibility and migration rebuilds',
    () async {
      final productionSource = await File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsString();
      final applicationRootSource = await File(
        'lib/app/application_root.dart',
      ).readAsString();
      final identitySource = await File(
        'lib/features/identity/data/repositories/identity_repository_impl.dart',
      ).readAsString();
      final saveStart = identitySource.indexOf(
        'Future<void> saveIdentity(IdentityModel identity) async {',
      );
      final saveGroupOwner = identitySource.indexOf(
        '_groupReactionProjection?.replaceLocalIdentity(',
        saveStart,
      );
      final saveDirectOwner = identitySource.indexOf(
        '_directReactionProjection?.replaceLocalIdentity(',
        saveStart,
      );
      final saveSecret = identitySource.indexOf(
        'await _secureKeyStore.write(\n      identityPrivateKeyStorageKey,',
        saveStart,
      );
      final saveDatabase = identitySource.indexOf(
        'await _dbUpsertIdentityRow(row);',
        saveStart,
      );
      expect(saveGroupOwner, inInclusiveRange(saveStart, saveDirectOwner - 1));
      expect(saveDirectOwner, inInclusiveRange(saveGroupOwner, saveSecret - 1));
      expect(saveSecret, inInclusiveRange(saveDirectOwner, saveDatabase - 1));

      final identityOwner = productionSource.indexOf(
        'groupReactionProjectionIdentityReady = repository.loadIdentity();',
      );
      final contextKickoff = productionSource.indexOf(
        'keychainMirrorBackfill = () async {',
      );
      expect(identityOwner, inInclusiveRange(0, contextKickoff - 1));
      final directContactBackfill = productionSource.indexOf(
        'contactRepository.mirrorAllDirectReactionContacts()',
      );
      final directIdentityAwait = productionSource.lastIndexOf(
        'await groupReactionProjectionIdentityReady;',
        directContactBackfill,
      );
      expect(
        directIdentityAwait,
        inInclusiveRange(identityOwner, directContactBackfill - 1),
      );

      final start = productionSource.indexOf(
        'Future<void> startLiveServices() async {',
      );
      final firebase = productionSource.indexOf(
        'await ensureFirebaseReady();',
        start,
      );
      final contextAwait = productionSource.indexOf(
        'await groupContextBackfill;',
        start,
      );
      final comparandsAwait = productionSource.indexOf(
        'await groupReactionComparandBackfill;',
        start,
      );
      expect(contextAwait, inInclusiveRange(start, firebase - 1));
      expect(comparandsAwait, inInclusiveRange(contextAwait, firebase - 1));

      final migration = applicationRootSource.indexOf(
        'Future<void> _handleAccountMigrationReceiverActivated() async {',
      );
      final migrationEnd = applicationRootSource.indexOf('\n  }', migration);
      final migrationBody = applicationRootSource.substring(
        migration,
        migrationEnd,
      );
      expect(
        migrationBody,
        contains('await widget.repository.loadIdentity();'),
      );
      expect(migrationBody, contains('mirrorAllDirectReactionContacts'));
      expect(migrationBody, contains('mirrorAllDirectReactionAuthoredTargets'));
      expect(
        migrationBody,
        contains('mirrorAllGroupReactionNotificationContexts'),
      );
      expect(migrationBody, contains('mirrorAllGroupReactionAuthoredTargets'));
      expect(
        migrationBody,
        contains('mirrorAllGroupReactionNotificationComparands'),
      );

      final pushRegistration = productionSource.indexOf(
        'registerPushToken: () async {',
      );
      final pushRegistrationEnd = productionSource.indexOf(
        'return push_registration.registerPushToken(',
        pushRegistration,
      );
      final pushRegistrationBody = productionSource.substring(
        pushRegistration,
        pushRegistrationEnd,
      );
      final registrationGroupOwner = pushRegistrationBody.indexOf(
        'groupReactionNotificationProjection?.replaceLocalIdentity(',
      );
      final registrationDirectOwner = pushRegistrationBody.indexOf(
        'directReactionNotificationProjection?.replaceLocalIdentity(',
      );
      expect(
        registrationGroupOwner,
        inInclusiveRange(0, registrationDirectOwner - 1),
      );
      expect(
        pushRegistrationBody,
        contains('groupReactionNotificationProjection?.replaceLocalIdentity('),
      );
      expect(
        pushRegistrationBody,
        contains('directReactionNotificationProjection?.replaceLocalIdentity('),
      );
      expect(pushRegistrationBody, contains('mirrorAllDirectReactionContacts'));
      expect(
        pushRegistrationBody,
        contains('mirrorAllDirectReactionAuthoredTargets'),
      );
      expect(pushRegistrationBody, contains('deviceId: transportPeerId'));
      expect(
        pushRegistrationBody,
        contains('transportPeerId: transportPeerId'),
      );
    },
  );

  test(
    // TC-321-01 (plan 321, C3 hardened) — the fresh-join atomicity headline.
    'fresh accepted join publishes exactly one complete context and never an epoch-less document',
    () async {
      const joiner = '12D3KooWBob';
      const inviter = '12D3KooWAlice';
      const freshGroupId = 'grp-fresh-join-321';
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      // Without ownership every projection write silently no-ops
      // (_ownsContexts) and this test would pass vacuously on HEAD.
      await projection.replaceLocalIdentity(
        accountPeerId: joiner,
        deviceId: 'bob-device',
        transportPeerId: 'bob-transport',
      );
      final persistence = _MemoryGroupPersistence();
      final repo = persistence.repository(projection);
      final bridge = FakeBridge();

      // Publish-precedes-drain observable: at each drain call, snapshot
      // whether the store already holds the COMPLETE (epoch-bearing) context.
      final drainSnapshots = <bool>[];
      setDeferredDistributionDrainSink(({
        required String groupId,
        required String peerId,
      }) async {
        var complete = false;
        final raw = store.values[sharedGroupReactionContextsKey];
        if (raw != null) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          final groups = decoded['groups'] as Map<String, dynamic>? ?? const {};
          final doc = groups[freshGroupId];
          complete = doc is Map<String, dynamic> && doc['keyEpoch'] is int;
        }
        drainSnapshots.add(complete);
      });
      addTearDown(() => setDeferredDistributionDrainSink(null));

      final payload = GroupInvitePayload(
        id: 'invite-321-01',
        groupId: freshGroupId,
        groupKey: 'base64GroupKey==',
        keyEpoch: 1,
        groupConfig: const {
          'name': 'Fresh Join 321',
          'groupType': 'chat',
          'members': [
            {
              'peerId': inviter,
              'username': 'Alice',
              'role': 'admin',
              'publicKey': 'alicePubKey64',
              'mlKemPublicKey': 'aliceMlKem64',
            },
            {
              'peerId': joiner,
              'username': 'Bob',
              'role': 'writer',
              'publicKey': 'bobPubKey64',
              'mlKemPublicKey': 'bobMlKem64',
            },
          ],
          'createdBy': inviter,
          'createdAt': '2026-03-02T00:00:00.000Z',
        },
        senderPeerId: inviter,
        senderUsername: 'Alice',
        timestamp: DateTime.utc(2026, 8, 1).toIso8601String(),
        recipientPeerId: joiner,
        invitePolicy: GroupInvitePolicy(
          expiresAt: DateTime.utc(2099, 3, 9, 12),
          allowedDevices: const [joiner],
          assignedRole: 'writer',
          canInviteOthers: false,
          joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
          keyEpoch: 1,
        ),
      );

      final (
        result,
        materializedGroupId,
      ) = await materializeAcceptedGroupInvitePayload(
        payload: payload,
        groupRepo: repo,
        bridge: bridge,
        ownPeerId: joiner,
      );

      // RED-reason guard: the causal RED must come from the projection
      // invariant below, never from a rejected payload.
      expect(
        result,
        HandleGroupInviteResult.success,
        reason:
            'fixture guard: the fresh join itself must succeed — a red via '
            'invalidPayload means the fixture is wrong, not the window proven',
      );
      expect(materializedGroupId, freshGroupId);

      final groupBearing = store.writeLog
          .where((entry) => entry.$1 == sharedGroupReactionContextsKey)
          .map((entry) => jsonDecode(entry.$2) as Map<String, dynamic>)
          .where((doc) {
            final groups = doc['groups'] as Map<String, dynamic>? ?? const {};
            return groups.containsKey(freshGroupId);
          })
          .toList();

      expect(
        groupBearing,
        isNotEmpty,
        reason: 'the join must project the group',
      );
      for (final doc in groupBearing) {
        final entry =
            (doc['groups'] as Map<String, dynamic>)[freshGroupId]
                as Map<String, dynamic>;
        expect(
          entry['keyEpoch'],
          isA<int>(),
          reason:
              'TC-321-01: no captured contexts document may carry the '
              'group without keyEpoch (HEAD publishes the first doc '
              'epoch-less for the whole roster loop)',
        );
      }
      expect(
        groupBearing.length,
        1,
        reason:
            'TC-321-01: exactly one COMPLETE publish (HEAD writes the '
            'group across N+2 incremental documents)',
      );

      final only =
          (groupBearing.single['groups'] as Map<String, dynamic>)[freshGroupId]
              as Map<String, dynamic>;
      expect(only['name'], 'Fresh Join 321');
      expect(only['type'], 'chat');
      expect(only['muted'], false);
      expect(only['archived'], false);
      expect(only['dissolved'], false);
      expect(only['keyEpoch'], 1);
      final members = only['members'] as Map<String, dynamic>;
      expect(members.keys.toSet(), {inviter, joiner});
      final alice = members[inviter] as Map<String, dynamic>;
      expect(alice['username'], 'Alice');
      expect(alice['role'], 'admin');
      expect(alice['deviceIds'], isA<List<dynamic>>());
      expect(alice['transportPeerIds'], isA<List<dynamic>>());
      expect((members[joiner] as Map<String, dynamic>)['role'], 'writer');

      // Capability-branch tail: the topic join and the drains must survive
      // the suppression scope, and every drain must observe the publish.
      expect(
        bridge.commandLog,
        contains('group:join'),
        reason: 'the capability branch must still join the group topic',
      );
      expect(
        drainSnapshots,
        isNotEmpty,
        reason: 'deferred-distribution drains must still fire',
      );
      expect(
        drainSnapshots.every((sawCompleteDoc) => sawCompleteDoc),
        isTrue,
        reason: 'every drain must run AFTER the complete-context publish',
      );
    },
  );

  GroupInvitePayload freshJoinPayload({
    required String groupId,
    String groupType = 'chat',
  }) => GroupInvitePayload(
    id: 'invite-321-$groupId',
    groupId: groupId,
    groupKey: 'base64GroupKey==',
    keyEpoch: 1,
    groupConfig: {
      'name': 'Fresh Join 321',
      'groupType': groupType,
      'members': const [
        {
          'peerId': '12D3KooWAlice',
          'username': 'Alice',
          'role': 'admin',
          'publicKey': 'alicePubKey64',
          'mlKemPublicKey': 'aliceMlKem64',
        },
        {
          'peerId': '12D3KooWBob',
          'username': 'Bob',
          'role': 'writer',
          'publicKey': 'bobPubKey64',
          'mlKemPublicKey': 'bobMlKem64',
        },
      ],
      'createdBy': '12D3KooWAlice',
      'createdAt': '2026-03-02T00:00:00.000Z',
    },
    senderPeerId: '12D3KooWAlice',
    senderUsername: 'Alice',
    timestamp: DateTime.utc(2026, 8, 1).toIso8601String(),
    recipientPeerId: '12D3KooWBob',
    invitePolicy: GroupInvitePolicy(
      expiresAt: DateTime.utc(2099, 3, 9, 12),
      allowedDevices: const ['12D3KooWBob'],
      assignedRole: 'writer',
      canInviteOthers: false,
      joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
      keyEpoch: 1,
    ),
  );

  List<Map<String, Object?>> groupDocsIn(
    _MemorySecureKeyStore store,
    String groupId,
  ) => store.writeLog
      .where((entry) => entry.$1 == sharedGroupReactionContextsKey)
      .map((entry) => jsonDecode(entry.$2) as Map<String, dynamic>)
      .where((doc) {
        final groups = doc['groups'] as Map<String, dynamic>? ?? const {};
        return groups.containsKey(groupId);
      })
      .map(
        (doc) =>
            ((doc['groups'] as Map<String, dynamic>)[groupId]
                    as Map<String, dynamic>)
                .cast<String, Object?>(),
      )
      .toList(growable: false);

  test(
    // TC-321-02 (plan 321) — KILL-1 guard.
    'mid-join updateGroup neither exposes a partial context nor loses its committed change',
    () async {
      const joiner = '12D3KooWBob';
      const freshGroupId = 'grp-321-tc02';
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: joiner,
        deviceId: 'bob-device',
        transportPeerId: 'bob-transport',
      );
      final persistence = _MemoryGroupPersistence();
      final repo = persistence.repository(projection);
      final bridge = FakeBridge();

      persistence.armMemberInsertBarrier();
      final materializeFuture = materializeAcceptedGroupInvitePayload(
        payload: freshJoinPayload(groupId: freshGroupId),
        groupRepo: repo,
        bridge: bridge,
        ownPeerId: joiner,
      );
      await persistence.memberInsertCaptured.future;
      // Enqueued on the group's mutation tail while the join is paused inside
      // its first saveMember — deterministically lands mid-scope on release.
      final muteFuture = repo.updateGroup(
        GroupModel(
          id: freshGroupId,
          name: 'Fresh Join 321',
          type: GroupType.chat,
          topicName: '/mknoon/groups/$freshGroupId',
          createdAt: DateTime.utc(2026, 3, 2),
          createdBy: '12D3KooWAlice',
          myRole: GroupRole.member,
          isMuted: true,
        ),
      );
      persistence.releaseMemberInsert();
      final (result, _) = await materializeFuture;
      await muteFuture;

      expect(result, HandleGroupInviteResult.success);
      final docs = groupDocsIn(store, freshGroupId);
      expect(
        docs.length,
        1,
        reason:
            'TC-321-02: the mid-join updateGroup must publish NOTHING for '
            'the joining group (HEAD publishes an epoch-less members-less doc)',
      );
      expect(docs.single['keyEpoch'], 1);
      expect(
        docs.single['muted'],
        true,
        reason:
            'the suppressed mirror must not LOSE the mute — the publish '
            'read-back carries the committed row',
      );
    },
  );

  test(
    // TC-321-03 (plan 321) — KILL-2 guard: latest-committed key wins.
    'mid-join key rotation is never downgraded by the fresh-join publish',
    () async {
      const joiner = '12D3KooWBob';
      const freshGroupId = 'grp-321-tc03';
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: joiner,
        deviceId: 'bob-device',
        transportPeerId: 'bob-transport',
      );
      final persistence = _MemoryGroupPersistence();
      final repo = persistence.repository(projection);
      final bridge = FakeBridge();

      persistence.armMemberInsertBarrier();
      final materializeFuture = materializeAcceptedGroupInvitePayload(
        payload: freshJoinPayload(groupId: freshGroupId),
        groupRepo: repo,
        bridge: bridge,
        ownPeerId: joiner,
      );
      await persistence.memberInsertCaptured.future;
      // A concurrent 1:1 rotation lands INSIDE the scope: its mirror is
      // suppressed, so only a latest-read publish can carry generation 2.
      final rotationFuture = repo.saveKey(
        GroupKeyInfo(
          groupId: freshGroupId,
          keyGeneration: 2,
          encryptedKey: 'base64RotatedKey==',
          createdAt: DateTime.utc(2026, 8, 1, 1),
        ),
      );
      persistence.releaseMemberInsert();
      final (result, _) = await materializeFuture;
      await rotationFuture;

      expect(result, HandleGroupInviteResult.success);
      final docs = groupDocsIn(store, freshGroupId);
      expect(docs, isNotEmpty);
      for (final doc in docs) {
        expect(
          doc['keyEpoch'],
          isA<int>(),
          reason: 'no epoch-less intermediate (HEAD exposes one)',
        );
      }
      expect(
        docs.last['keyEpoch'],
        2,
        reason:
            'TC-321-03: the publish must read the LATEST committed '
            'generation — pinning the join generation would downgrade the '
            'mid-scope rotation',
      );
    },
  );

  test(
    // TC-321-03 race case (plan 321) — the _runGroupMutation wrap is
    // test-locked: a deletion racing the publish read-back must win.
    'a group deletion racing the fresh-join publish is never resurrected',
    () async {
      const joiner = '12D3KooWBob';
      const freshGroupId = 'grp-321-tc03-race';
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: joiner,
        deviceId: 'bob-device',
        transportPeerId: 'bob-transport',
      );
      final persistence = _MemoryGroupPersistence();
      final repo = persistence.repository(projection);

      // Committed join state, seeded through the normal writers.
      await repo.saveGroup(
        GroupModel(
          id: freshGroupId,
          name: 'Fresh Join 321',
          type: GroupType.chat,
          topicName: '/mknoon/groups/$freshGroupId',
          createdAt: DateTime.utc(2026, 3, 2),
          createdBy: '12D3KooWAlice',
          myRole: GroupRole.member,
        ),
      );
      await repo.saveMember(
        GroupMember(
          groupId: freshGroupId,
          peerId: joiner,
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'bobPubKey64',
          mlKemPublicKey: 'bobMlKem64',
          joinedAt: DateTime.utc(2026, 3, 2),
        ),
      );
      await repo.saveKey(
        GroupKeyInfo(
          groupId: freshGroupId,
          keyGeneration: 1,
          encryptedKey: 'base64GroupKey==',
          createdAt: DateTime.utc(2026, 8, 1),
        ),
      );

      persistence.armMemberLoadBarrier();
      final publishFuture = (repo as FreshJoinProjectionAtomicity)
          .projectCommittedFreshJoin(freshGroupId);
      await persistence.memberLoadCaptured.future;
      // With the publish inside _runGroupMutation this deletion QUEUES until
      // the publish completes and then removes the doc; an unwrapped publish
      // would let it interleave and then resurrect the group from its stale
      // read-back.
      final deleteFuture = repo.deleteGroup(freshGroupId);
      persistence.releaseMemberLoad();
      await publishFuture;
      await deleteFuture;

      final raw = store.values[sharedGroupReactionContextsKey];
      final groups = raw == null
          ? const <String, dynamic>{}
          : (jsonDecode(raw) as Map<String, dynamic>)['groups']
                    as Map<String, dynamic>? ??
                const <String, dynamic>{};
      expect(
        groups.containsKey(freshGroupId),
        isFalse,
        reason:
            'TC-321-03 race: the deletion must win — a resurrected doc '
            'means the publish ran outside _runGroupMutation',
      );
    },
  );

  test(
    // TC-321-04 (plan 321) — removals pass through the suppression scope.
    'failure-branch and rollback removals pass through the suppression scope',
    () async {
      const joiner = '12D3KooWBob';
      const freshGroupId = 'grp-321-tc04';
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: joiner,
        deviceId: 'bob-device',
        transportPeerId: 'bob-transport',
      );
      // The realistic stale state: a prior attempt left a doc behind. Without
      // this seed, "no doc after failure" is satisfied by a wrong
      // (removal-suppressing) implementation too — nothing was ever written.
      await projection.upsertGroup(
        GroupModel(
          id: freshGroupId,
          name: 'Stale Prior Attempt',
          type: GroupType.chat,
          topicName: '/mknoon/groups/$freshGroupId',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: '12D3KooWAlice',
          myRole: GroupRole.member,
        ),
      );
      final persistence = _MemoryGroupPersistence();
      final repo = persistence.repository(projection);
      final bridge = FakeBridge();

      // Authority flips INSIDE saveKey's own window: the post-insert re-read
      // sees a removed shell and the failure branch must remove the doc even
      // though the suppression scope is active.
      persistence.onGroupKeyInsert = () {
        persistence.groups[freshGroupId]?['self_removed_at'] = DateTime.utc(
          2026,
          8,
          1,
          2,
        ).toIso8601String();
      };

      await expectLater(
        materializeAcceptedGroupInvitePayload(
          payload: freshJoinPayload(groupId: freshGroupId),
          groupRepo: repo,
          bridge: bridge,
          ownPeerId: joiner,
        ),
        throwsStateError,
      );

      final raw = store.values[sharedGroupReactionContextsKey];
      final groups = raw == null
          ? const <String, dynamic>{}
          : (jsonDecode(raw) as Map<String, dynamic>)['groups']
                    as Map<String, dynamic>? ??
                const <String, dynamic>{};
      expect(
        groups.containsKey(freshGroupId),
        isFalse,
        reason:
            'TC-321-04: the authority-flip removal must fire under '
            'suppression — a surviving seeded doc means removals were '
            'suppressed',
      );
    },
  );

  test(
    // TC-321-05 (plan 321) — unsupported type parity + event honesty.
    'unsupported group type join produces no context and no projection error',
    () async {
      const joiner = '12D3KooWBob';
      const freshGroupId = 'grp-321-tc05';
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: joiner,
        deviceId: 'bob-device',
        transportPeerId: 'bob-transport',
      );
      final persistence = _MemoryGroupPersistence();
      final repo = persistence.repository(projection);
      final bridge = FakeBridge();

      final events = await _captureFlowEvents(() async {
        final (result, _) = await materializeAcceptedGroupInvitePayload(
          payload: freshJoinPayload(groupId: freshGroupId, groupType: 'qa'),
          groupRepo: repo,
          bridge: bridge,
          ownPeerId: joiner,
        );
        expect(result, HandleGroupInviteResult.success);
      });

      expect(groupDocsIn(store, freshGroupId), isEmpty);
      expect(
        events.where(
          (e) =>
              e['event'] == 'GROUP_FRESH_JOIN_PROJECTION_PUBLISHED' ||
              e['event'] == 'GROUP_FRESH_JOIN_PROJECTION_DEFERRED',
        ),
        isEmpty,
        reason:
            'TC-321-05: a qa join is a clean no-op — PUBLISHED would be a '
            'false signal and DEFERRED means the ArgumentError fired',
      );
    },
  );

  test(
    // TC-321-05 sibling (plan 321) — announcement is projectable: a chat-only
    // pre-filter would permanently blank announcement joiners.
    'announcement group join publishes a complete context',
    () async {
      const joiner = '12D3KooWBob';
      const freshGroupId = 'grp-321-tc05b';
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: joiner,
        deviceId: 'bob-device',
        transportPeerId: 'bob-transport',
      );
      final persistence = _MemoryGroupPersistence();
      final repo = persistence.repository(projection);
      final bridge = FakeBridge();

      final events = await _captureFlowEvents(() async {
        final (result, _) = await materializeAcceptedGroupInvitePayload(
          payload: freshJoinPayload(
            groupId: freshGroupId,
            groupType: 'announcement',
          ),
          groupRepo: repo,
          bridge: bridge,
          ownPeerId: joiner,
        );
        expect(result, HandleGroupInviteResult.success);
      });

      final docs = groupDocsIn(store, freshGroupId);
      expect(docs.length, 1);
      expect(docs.single['type'], 'announcement');
      expect(docs.single['keyEpoch'], 1);
      expect(
        events.where(
          (e) => e['event'] == 'GROUP_FRESH_JOIN_PROJECTION_PUBLISHED',
        ),
        hasLength(1),
      );
    },
  );

  test(
    // TC-321-06 (plan 321) — publish failure contained + TC-321-11 heal tail.
    'a failed fresh-join publish defers with a flow event and never breaks the join',
    () async {
      const joiner = '12D3KooWBob';
      const freshGroupId = 'grp-321-tc06';
      final store = _MemorySecureKeyStore();
      final projection = GroupReactionNotificationProjection(store: store);
      await projection.replaceLocalIdentity(
        accountPeerId: joiner,
        deviceId: 'bob-device',
        transportPeerId: 'bob-transport',
      );
      final persistence = _MemoryGroupPersistence();
      final repo = persistence.repository(projection);
      final bridge = FakeBridge();

      // The suppressed save scope performs no projection writes, so the next
      // contexts write IS the publish — arm the failure for exactly it.
      store.failNextWriteKeys.add(sharedGroupReactionContextsKey);

      final events = await _captureFlowEvents(() async {
        final (result, _) = await materializeAcceptedGroupInvitePayload(
          payload: freshJoinPayload(groupId: freshGroupId),
          groupRepo: repo,
          bridge: bridge,
          ownPeerId: joiner,
        );
        expect(
          result,
          HandleGroupInviteResult.success,
          reason: 'TC-321-06: the join NEVER fails because of the projection',
        );
      });

      expect(
        events.where(
          (e) => e['event'] == 'GROUP_FRESH_JOIN_PROJECTION_DEFERRED',
        ),
        hasLength(1),
      );
      // Honest posture: the queued failure wiped the store (fail-closed).
      expect(store.values[sharedGroupReactionContextsKey], isNull);

      // TC-321-11 heal tail: the next launch re-establishes identity and the
      // authoritative rebuild restores the group WITH its epoch.
      await projection.replaceLocalIdentity(
        accountPeerId: joiner,
        deviceId: 'bob-device',
        transportPeerId: 'bob-transport',
      );
      await repo.mirrorAllGroupReactionNotificationContexts();
      final healedRaw = store.values[sharedGroupReactionContextsKey];
      expect(healedRaw, isNotNull);
      final healedGroups =
          (jsonDecode(healedRaw!) as Map<String, dynamic>)['groups']
              as Map<String, dynamic>;
      final healedDoc = healedGroups[freshGroupId] as Map<String, dynamic>?;
      expect(healedDoc, isNotNull, reason: 'launch heal must restore the doc');
      expect(
        healedDoc!['keyEpoch'],
        1,
        reason: 'the heal must restore the epoch too',
      );
    },
  );
}

class _MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = <String, String>{};
  final List<String> writeKeys = <String>[];
  bool failWrites = false;
  int failNextWrites = 0;
  final Set<String> failNextWriteKeys = <String>{};
  String? _pauseNextReadKey;
  Completer<void> readCaptured = Completer<void>()..complete();
  Completer<void> _releaseRead = Completer<void>()..complete();

  void armNextReadBarrier(String key) {
    _pauseNextReadKey = key;
    readCaptured = Completer<void>();
    _releaseRead = Completer<void>();
  }

  void releaseRead() {
    if (!_releaseRead.isCompleted) _releaseRead.complete();
  }

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

  @override
  Future<void> delete(String key) async {
    if (failWrites) throw StateError('injected projection failure');
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    final value = values[key];
    if (_pauseNextReadKey == key) {
      _pauseNextReadKey = null;
      if (!readCaptured.isCompleted) readCaptured.complete();
      await _releaseRead.future;
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    writeKeys.add(key);
    if (failWrites || failNextWrites > 0 || failNextWriteKeys.remove(key)) {
      if (failNextWrites > 0) failNextWrites--;
      throw StateError('injected projection failure');
    }
    values[key] = value;
    // Plan 321: committed-write log so per-write document CONTENT can be
    // asserted (writeKeys records keys only).
    writeLog.add((key, value));
  }

  final List<(String, String)> writeLog = <(String, String)>[];
}

class _MemoryGroupPersistence {
  final Map<String, Map<String, Object?>> groups =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> members =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> keys =
      <String, Map<String, Object?>>{};
  bool failNextGroupWrite = false;
  Completer<void> groupLoadCaptured = Completer<void>();
  Completer<void> _releaseGroupLoad = Completer<void>()..complete();

  void armGroupLoadBarrier() {
    groupLoadCaptured = Completer<void>();
    _releaseGroupLoad = Completer<void>();
  }

  void releaseGroupLoad() {
    if (!_releaseGroupLoad.isCompleted) _releaseGroupLoad.complete();
  }

  // Plan 321: in-scope interleave barrier — pauses inside dbInsertGroupMember
  // so a concurrent writer can be enqueued on the group's mutation tail
  // deterministically mid-join (armGroupLoadBarrier gates only
  // dbLoadAllGroups, which the fresh join never calls).
  Completer<void> memberInsertCaptured = Completer<void>();
  Completer<void> _releaseMemberInsert = Completer<void>()..complete();

  void armMemberInsertBarrier() {
    memberInsertCaptured = Completer<void>();
    _releaseMemberInsert = Completer<void>();
  }

  void releaseMemberInsert() {
    if (!_releaseMemberInsert.isCompleted) _releaseMemberInsert.complete();
  }

  // Plan 321: publish read-back barrier — pauses inside dbLoadAllGroupMembers
  // so a concurrent repo mutation can be raced against the atomic publish
  // (test-locks the _runGroupMutation wrap).
  Completer<void> memberLoadCaptured = Completer<void>();
  Completer<void> _releaseMemberLoad = Completer<void>()..complete();

  void armMemberLoadBarrier() {
    memberLoadCaptured = Completer<void>();
    _releaseMemberLoad = Completer<void>();
  }

  void releaseMemberLoad() {
    if (!_releaseMemberLoad.isCompleted) _releaseMemberLoad.complete();
  }

  // Plan 321 (TC-321-04): deterministic authority flip fired synchronously
  // inside dbInsertGroupKey, i.e. inside saveKey's own window.
  void Function()? onGroupKeyInsert;

  GroupRepositoryImpl repository(
    GroupReactionNotificationProjection projection,
  ) => GroupRepositoryImpl(
    dbInsertGroup: (row) async {
      if (failNextGroupWrite) {
        failNextGroupWrite = false;
        throw StateError('injected group commit failure');
      }
      groups[row['id']! as String] = Map<String, Object?>.from(row);
    },
    dbLoadAllGroups: () async {
      final snapshot = groups.values
          .map(Map<String, Object?>.from)
          .toList(growable: false);
      if (!groupLoadCaptured.isCompleted) groupLoadCaptured.complete();
      await _releaseGroupLoad.future;
      return snapshot;
    },
    dbLoadGroup: (id) async => groups[id],
    dbUpdateGroup: (row) async =>
        groups[row['id']! as String] = Map<String, Object?>.from(row),
    dbDeleteGroup: (id) async => groups.remove(id),
    dbLoadActiveGroups: () async => groups.values
        .where((row) => row['is_archived'] != 1)
        .toList(growable: false),
    dbArchiveGroup: (id) async {
      final row = groups[id];
      if (row != null) row['is_archived'] = 1;
    },
    dbUnarchiveGroup: (id) async {
      final row = groups[id];
      if (row != null) row['is_archived'] = 0;
    },
    dbInsertGroupMember: (row) async {
      if (!memberInsertCaptured.isCompleted) memberInsertCaptured.complete();
      await _releaseMemberInsert.future;
      members[_memberKey(
        row['group_id']! as String,
        row['peer_id']! as String,
      )] = Map<String, Object?>.from(
        row,
      );
    },
    dbLoadAllGroupMembers: (groupId) async {
      final snapshot = members.values
          .where((row) => row['group_id'] == groupId)
          .toList(growable: false);
      if (!memberLoadCaptured.isCompleted) memberLoadCaptured.complete();
      await _releaseMemberLoad.future;
      return snapshot;
    },
    dbLoadGroupMember: (groupId, peerId) async =>
        members[_memberKey(groupId, peerId)],
    dbUpdateGroupMemberRole: (groupId, peerId, role) async {
      members[_memberKey(groupId, peerId)]?['role'] = role;
    },
    dbDeleteGroupMember: (groupId, peerId) async =>
        members.remove(_memberKey(groupId, peerId)),
    dbDeleteAllGroupMembers: (groupId) async =>
        members.removeWhere((_, row) => row['group_id'] == groupId),
    dbInsertGroupKey: (row) async {
      keys[_keyKey(row['group_id']! as String, row['key_generation']! as int)] =
          Map<String, Object?>.from(row);
      onGroupKeyInsert?.call();
    },
    dbLoadLatestGroupKey: (groupId) async {
      final rows =
          keys.values
              .where((row) => row['group_id'] == groupId)
              .toList(growable: false)
            ..sort(
              (left, right) => (right['key_generation']! as int).compareTo(
                left['key_generation']! as int,
              ),
            );
      return rows.isEmpty ? null : rows.first;
    },
    dbLoadGroupKeyByGeneration: (groupId, generation) async =>
        keys[_keyKey(groupId, generation)],
    dbDeleteAllGroupKeys: (groupId) async =>
        keys.removeWhere((_, row) => row['group_id'] == groupId),
    // Plan 321: the impl THROWS on a null floor fn and materialize swallows
    // that into invalidPayload BEFORE saveGroup — the fresh-join path needs an
    // explicit absent-floor answer.
    dbLoadSelfRemovedGroupFreshnessFloorFn: (_) async => null,
    groupReactionProjection: projection,
  );

  static String _memberKey(String groupId, String peerId) => '$groupId:$peerId';
  static String _keyKey(String groupId, int generation) =>
      '$groupId:$generation';
}

class _MemoryGroupMessagePersistence {
  final Map<String, Map<String, Object?>> messages =
      <String, Map<String, Object?>>{};
  bool skipNextInsert = false;
  bool failNextTransaction = false;
  Completer<void> authoredLoadCaptured = Completer<void>();
  Completer<void> _releaseAuthoredLoad = Completer<void>()..complete();

  void armAuthoredLoadBarrier() {
    authoredLoadCaptured = Completer<void>();
    _releaseAuthoredLoad = Completer<void>();
  }

  void releaseAuthoredLoad() {
    if (!_releaseAuthoredLoad.isCompleted) _releaseAuthoredLoad.complete();
  }

  GroupMessageRepositoryImpl repository(
    GroupReactionNotificationProjection? projection, {
    bool enableTransactions = false,
  }) => GroupMessageRepositoryImpl(
    dbInsertGroupMessage: (row) async {
      if (skipNextInsert) {
        skipNextInsert = false;
        return false;
      }
      messages[row['id']! as String] = Map<String, Object?>.from(row);
      return true;
    },
    dbLoadGroupMessagesPage: (groupId, {limit = 50, offset = 0}) async =>
        messages.values
            .where((row) => row['group_id'] == groupId)
            .skip(offset)
            .take(limit)
            .toList(growable: false),
    dbLoadGroupMessage: (id) async => messages[id],
    dbLoadLatestGroupMessage: (groupId) async {
      final rows = messages.values
          .where((row) => row['group_id'] == groupId)
          .toList(growable: false);
      return rows.isEmpty ? null : rows.last;
    },
    dbUpdateGroupMessageStatus: (id, status) async {
      messages[id]?['status'] = status;
    },
    dbCountGroupMessages: (groupId) async =>
        messages.values.where((row) => row['group_id'] == groupId).length,
    dbCountUnreadGroupMessages: (groupId) async => messages.values
        .where(
          (row) =>
              row['group_id'] == groupId &&
              row['is_incoming'] == 1 &&
              row['read_at'] == null,
        )
        .length,
    dbCountTotalUnreadGroupMessages: () async => messages.values
        .where((row) => row['is_incoming'] == 1 && row['read_at'] == null)
        .length,
    dbMarkGroupMessagesAsRead: (groupId) async => 0,
    dbDeleteGroupMessage: (id) async => messages.remove(id),
    dbExistsGroupMessageByContent:
        (groupId, senderPeerId, text, timestamp) async => false,
    dbDeleteGroupMessagesForGroup: (groupId) async {
      final before = messages.length;
      messages.removeWhere((_, row) => row['group_id'] == groupId);
      return before - messages.length;
    },
    dbLoadGroupThreadSummaries: (_) async => const <Map<String, Object?>>[],
    dbRunGroupInboxPageTransactionFn: enableTransactions
        ? ({
            required groupId,
            required nextCursor,
            required apply,
            required receipts,
            required markReadMessageIds,
          }) async {
            final staged = _MemoryGroupMessagePersistence();
            staged.messages.addAll(
              messages.map(
                (id, row) => MapEntry(id, Map<String, Object?>.from(row)),
              ),
            );
            await apply(staged.repository(null));
            if (failNextTransaction) {
              failNextTransaction = false;
              throw StateError('injected transaction rollback');
            }
            messages
              ..clear()
              ..addAll(staged.messages);
          }
        : null,
    groupReactionProjection: projection,
    dbLoadAuthoredGroupMessagesForProjectionFn:
        (accountPeerId, {limit = 256}) async {
          final snapshot = messages.values
              .where((row) => row['sender_peer_id'] == accountPeerId)
              .take(limit)
              .map(Map<String, Object?>.from)
              .toList(growable: false);
          if (!authoredLoadCaptured.isCompleted) {
            authoredLoadCaptured.complete();
          }
          await _releaseAuthoredLoad.future;
          return snapshot;
        },
  );
}
