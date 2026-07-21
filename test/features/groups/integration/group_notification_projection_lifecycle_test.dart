import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/group_reaction_notification_projection.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final source = await File('lib/main.dart').readAsString();
      final identitySource = await File(
        'lib/features/identity/domain/repositories/identity_repository_impl.dart',
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
        'await _secureKeyStore.write(_kPrivateKey',
        saveStart,
      );
      final saveDatabase = identitySource.indexOf(
        'await _dbUpsertIdentityRow(row);',
        saveStart,
      );
      expect(saveGroupOwner, inInclusiveRange(saveStart, saveDirectOwner - 1));
      expect(saveDirectOwner, inInclusiveRange(saveGroupOwner, saveSecret - 1));
      expect(saveSecret, inInclusiveRange(saveDirectOwner, saveDatabase - 1));

      final identityOwner = source.indexOf(
        'groupReactionProjectionIdentityReady = repository.loadIdentity();',
      );
      final contextKickoff = source.indexOf(
        'keychainMirrorBackfill = () async {',
      );
      expect(identityOwner, inInclusiveRange(0, contextKickoff - 1));
      final directContactBackfill = source.indexOf(
        'contactRepository.mirrorAllDirectReactionContacts()',
      );
      final directIdentityAwait = source.lastIndexOf(
        'await groupReactionProjectionIdentityReady;',
        directContactBackfill,
      );
      expect(
        directIdentityAwait,
        inInclusiveRange(identityOwner, directContactBackfill - 1),
      );

      final start = source.indexOf('Future<void> startLiveServices() async {');
      final firebase = source.indexOf('await ensureFirebaseReady();', start);
      final contextAwait = source.indexOf('await groupContextBackfill;', start);
      final comparandsAwait = source.indexOf(
        'await groupReactionComparandBackfill;',
        start,
      );
      expect(contextAwait, inInclusiveRange(start, firebase - 1));
      expect(comparandsAwait, inInclusiveRange(contextAwait, firebase - 1));

      final migration = source.indexOf(
        'Future<void> _handleAccountMigrationReceiverActivated() async {',
      );
      final migrationEnd = source.indexOf('\n  }', migration);
      final migrationBody = source.substring(migration, migrationEnd);
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

      final pushRegistration = source.indexOf('registerPushToken: () async {');
      final pushRegistrationEnd = source.indexOf(
        'return push_registration.registerPushToken(',
        pushRegistration,
      );
      final pushRegistrationBody = source.substring(
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
}

class _MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = <String, String>{};
  final List<String> writeKeys = <String>[];
  bool failWrites = false;
  int failNextWrites = 0;
  final Set<String> failNextWriteKeys = <String>{};

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

  @override
  Future<void> delete(String key) async {
    if (failWrites) throw StateError('injected projection failure');
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writeKeys.add(key);
    if (failWrites || failNextWrites > 0 || failNextWriteKeys.remove(key)) {
      if (failNextWrites > 0) failNextWrites--;
      throw StateError('injected projection failure');
    }
    values[key] = value;
  }
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
    dbInsertGroupMember: (row) async =>
        members[_memberKey(
          row['group_id']! as String,
          row['peer_id']! as String,
        )] = Map<String, Object?>.from(
          row,
        ),
    dbLoadAllGroupMembers: (groupId) async => members.values
        .where((row) => row['group_id'] == groupId)
        .toList(growable: false),
    dbLoadGroupMember: (groupId, peerId) async =>
        members[_memberKey(groupId, peerId)],
    dbUpdateGroupMemberRole: (groupId, peerId, role) async {
      members[_memberKey(groupId, peerId)]?['role'] = role;
    },
    dbDeleteGroupMember: (groupId, peerId) async =>
        members.remove(_memberKey(groupId, peerId)),
    dbDeleteAllGroupMembers: (groupId) async =>
        members.removeWhere((_, row) => row['group_id'] == groupId),
    dbInsertGroupKey: (row) async =>
        keys[_keyKey(
          row['group_id']! as String,
          row['key_generation']! as int,
        )] = Map<String, Object?>.from(
          row,
        ),
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
