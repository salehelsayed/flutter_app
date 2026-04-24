import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

// --- FakeIdentityRepository ---

class FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identity;
  FakeIdentityRepository({this.identity});

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

// --- Test data ---

final testIdentity = IdentityModel(
  peerId: 'peer-admin',
  publicKey: 'pk-admin',
  privateKey: 'sk-admin',
  mnemonic12:
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  mlKemPublicKey: 'mlkem-pk-admin',
  username: 'Admin',
  createdAt: DateTime.now().toUtc().toIso8601String(),
  updatedAt: DateTime.now().toUtc().toIso8601String(),
);

GroupModel makeAdminGroup() => GroupModel(
  id: 'group-1',
  name: 'Test Group',
  type: GroupType.chat,
  topicName: 'topic-1',
  description: 'A test group',
  createdAt: DateTime.now().toUtc(),
  createdBy: 'peer-admin',
  myRole: GroupRole.admin,
);

GroupModel makeMemberGroup() => GroupModel(
  id: 'group-1',
  name: 'Test Group',
  type: GroupType.chat,
  topicName: 'topic-1',
  description: 'A test group',
  createdAt: DateTime.now().toUtc(),
  createdBy: 'peer-admin',
  myRole: GroupRole.member,
);

GroupMember makeMember({
  required String peerId,
  required String username,
  MemberRole role = MemberRole.writer,
}) => GroupMember(
  groupId: 'group-1',
  peerId: peerId,
  username: username,
  role: role,
  joinedAt: DateTime.now().toUtc(),
);

// --- Helpers ---

/// Pump enough frames for async operations to complete.
/// AmbientBackground has an infinite animation, so pumpAndSettle will timeout.
Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> confirmRemoveMemberDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('group-remove-confirm')));
  await pumpFrames(tester, count: 30);
}

Future<void> openRoleActionMenu(WidgetTester tester, String peerId) async {
  final actionButton = find.byKey(ValueKey('group-member-actions-$peerId'));
  await tester.ensureVisible(actionButton);
  await pumpFrames(tester, count: 5);
  await tester.tap(actionButton, warnIfMissed: false);
  await pumpFrames(tester, count: 5);
}

Future<void> confirmRoleChangeDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('group-role-change-confirm')));
  await pumpFrames(tester, count: 30);
}

Future<void> confirmDissolveGroupDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('group-dissolve-confirm')));
  await pumpFrames(tester, count: 30);
}

Future<void> confirmDeleteLocalGroupDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('group-delete-local-confirm')));
  await pumpFrames(tester, count: 30);
}

Future<void> tapLeaveGroupButton(
  WidgetTester tester, {
  int settleFrameCount = 20,
}) async {
  final leaveButton = find.byKey(const ValueKey('group-leave-button'));
  await tester.scrollUntilVisible(
    leaveButton,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(leaveButton);
  await pumpFrames(tester, count: settleFrameCount);
}

Future<void> scrollToDissolveGroupButton(WidgetTester tester) async {
  final dissolveButton = find.byKey(const ValueKey('group-dissolve-button'));
  await tester.scrollUntilVisible(
    dissolveButton,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await pumpFrames(tester, count: 5);
}

Future<void> scrollToDeleteLocalGroupButton(WidgetTester tester) async {
  final deleteButton = find.byKey(const ValueKey('group-delete-local-button'));
  await tester.scrollUntilVisible(
    deleteButton,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await pumpFrames(tester, count: 5);
}

Future<void> _saveGroupReplayKey(
  InMemoryGroupRepository groupRepo, {
  String groupId = 'group-1',
  int generation = 1,
}) async {
  await groupRepo.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: generation,
      encryptedKey: 'test-group-key-$generation',
      createdAt: DateTime.now().toUtc(),
    ),
  );
}

Map<String, dynamic> _storedGroupReplayEnvelope(String message) {
  return jsonDecode(message) as Map<String, dynamic>;
}

Map<String, dynamic> _decodedGroupReplayPayload(String message) {
  final envelope = _storedGroupReplayEnvelope(message);
  final ciphertext = envelope['ciphertext'];
  if (envelope['kind'] == 'group_offline_replay' && ciphertext is String) {
    return jsonDecode(ciphertext) as Map<String, dynamic>;
  }
  return envelope;
}

void main() {
  group('GroupInfoWired', () {
    testWidgets('loads and displays group members on init', (tester) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      final m1 = makeMember(
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
      );
      final m2 = makeMember(peerId: 'peer-alice', username: 'Alice');
      final m3 = makeMember(peerId: 'peer-bob', username: 'Bob');

      await groupRepo.saveMember(m1);
      await groupRepo.saveMember(m2);
      await groupRepo.saveMember(m3);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('You'), findsOneWidget); // self member shows "You"
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('shows Add Member button for admin role', (tester) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Add Member'), findsOneWidget);
    });

    testWidgets(
      'shows the creator username from the real create flow for other members',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final bridge = FakeBridge(
          initialResponses: {
            'group:create': {
              'ok': true,
              'groupId': 'group-created-with-username',
              'topicName': 'topic-group-created-with-username',
              'groupKey': 'group-key-created-with-username',
              'keyEpoch': 0,
            },
          },
        );
        final viewerIdentity = IdentityModel(
          peerId: 'peer-alice',
          publicKey: 'pk-alice',
          privateKey: 'sk-alice',
          mnemonic12:
              'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
          mlKemPublicKey: 'mlkem-pk-alice',
          username: 'Alice',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        );

        final created = await createGroup(
          bridge: bridge,
          groupRepo: groupRepo,
          name: 'Created Group',
          type: GroupType.chat,
          creatorPeerId: testIdentity.peerId,
          creatorPublicKey: testIdentity.publicKey,
          creatorMlKemPublicKey: testIdentity.mlKemPublicKey ?? '',
          creatorUsername: testIdentity.username,
        );
        await groupRepo.saveGroup(created.copyWith(myRole: GroupRole.member));
        await groupRepo.saveMember(
          GroupMember(
            groupId: created.id,
            peerId: viewerIdentity.peerId,
            username: viewerIdentity.username,
            role: MemberRole.writer,
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: GroupInfoWired(
              group: created.copyWith(myRole: GroupRole.member),
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: viewerIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Admin'), findsOneWidget);
        expect(find.text('peer-admin'), findsNothing);
      },
    );

    testWidgets('hides Add Member button for non-admin role', (tester) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeMemberGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Add Member'), findsNothing);
    });

    testWidgets(
      'admin can dissolve a group and the screen switches to read-only state',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-bob', username: 'Bob'),
        );

        final bridge = FakeBridge(
          initialResponses: {
            'group:publish': {'ok': true, 'messageId': 'msg-1'},
            'group:inboxStore': {'ok': true},
            'group:leave': {'ok': true},
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        await scrollToDissolveGroupButton(tester);
        expect(
          find.byKey(const ValueKey('group-dissolve-button')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('group-dissolve-button')));
        await pumpFrames(tester, count: 5);
        expect(
          find.byKey(const ValueKey('group-dissolve-confirm')),
          findsOneWidget,
        );

        await confirmDissolveGroupDialog(tester);

        final updated = await groupRepo.getGroup(group.id);
        expect(updated, isNotNull);
        expect(updated!.isDissolved, isTrue);

        final latest = await msgRepo.getLatestMessage(group.id);
        expect(latest, isNotNull);
        expect(latest!.text, 'Admin dissolved the group');

        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
        expect(bridge.commandLog, contains('group:leave'));

        expect(
          find.text(
            'This conversation is now read-only. Previous messages stay available for reference.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('group-dissolve-button')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('group-leave-button')), findsNothing);
        expect(
          find.byKey(const ValueKey('group-delete-local-button')),
          findsOneWidget,
        );
        expect(find.text('Add Member'), findsNothing);
        expect(
          find.byKey(const ValueKey('group-edit-details-button')),
          findsNothing,
        );
      },
    );

    testWidgets('toggles mute state and persists it to the repository', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('group-mute-switch')))
            .value,
        isFalse,
      );

      await tester.tap(find.byKey(const ValueKey('group-mute-switch')));
      await pumpFrames(tester, count: 20);

      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('group-mute-switch')))
            .value,
        isTrue,
      );
      expect((await groupRepo.getGroup(group.id))?.isMuted, isTrue);
      expect(find.text('Notifications muted for this group'), findsOneWidget);
    });

    testWidgets('hides member remove controls for non-admin role', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeMemberGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
        ),
      );
      await groupRepo.saveMember(
        makeMember(peerId: 'peer-bob', username: 'Bob'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
      expect(
        find.byKey(const ValueKey('group-member-actions-peer-bob')),
        findsNothing,
      );
    });

    testWidgets('uses repo myRole instead of stale navigation role on load', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final persistedGroup = makeAdminGroup();
      await groupRepo.saveGroup(persistedGroup);
      await _saveGroupReplayKey(groupRepo);
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
        ),
      );
      await groupRepo.saveMember(
        makeMember(peerId: 'peer-alice', username: 'Alice'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoWired(
            group: makeMemberGroup(),
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: FakeBridge(),
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Add Member'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('group-member-actions-peer-alice')),
        findsOneWidget,
      );
    });

    testWidgets(
      'admin metadata edit updates repo state, timeline, and bridge payloads',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final bridge = FakeBridge();

        await tester.pumpWidget(
          MaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        await tester.tap(
          find.byKey(const ValueKey('group-edit-details-button')),
        );
        await pumpFrames(tester);

        expect(find.text('Edit Group Details'), findsOneWidget);

        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('group-edit-name-field')),
            matching: find.byType(TextField),
          ),
          'Renamed Group',
        );
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('group-edit-description-field')),
            matching: find.byType(TextField),
          ),
          'Fresh description',
        );

        await tester.tap(find.byKey(const ValueKey('group-edit-save')));
        await pumpFrames(tester, count: 30);

        final updatedGroup = await groupRepo.getGroup('group-1');
        expect(updatedGroup, isNotNull);
        expect(updatedGroup!.name, 'Renamed Group');
        expect(updatedGroup.description, 'Fresh description');
        expect(updatedGroup.lastMetadataEventAt, isNotNull);

        expect(find.text('Renamed Group'), findsWidgets);
        expect(find.text('Fresh description'), findsOneWidget);
        expect(find.text('Group details updated'), findsOneWidget);

        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));

        final publishMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;

        expect(sysText['__sys'], 'group_metadata_updated');
        expect(sysText['groupConfig']['name'], 'Renamed Group');
        expect(sysText['groupConfig']['description'], 'Fresh description');

        final inboxStoreMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:inboxStore';
        });
        final inboxStorePayload =
            (jsonDecode(inboxStoreMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(inboxStorePayload['recipientPeerIds'], ['peer-bob']);

        final latestTimeline = await msgRepo.getLatestMessage('group-1');
        expect(latestTimeline, isNotNull);
        expect(
          latestTimeline!.text,
          buildGroupMetadataUpdatedTimelineText('Admin'),
        );
      },
    );

    testWidgets(
      'promote member shows confirmation, updates badge, and emits member_role_updated payload',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-pk-admin',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-alice',
            username: 'Alice',
            role: MemberRole.writer,
            publicKey: 'pk-alice',
            mlKemPublicKey: 'mlkem-pk-alice',
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final bridge = FakeBridge();

        await tester.pumpWidget(
          MaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        await openRoleActionMenu(tester, 'peer-alice');
        expect(find.text('Make Admin'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('group-member-toggle-admin-peer-alice')),
        );
        await pumpFrames(tester);

        expect(find.text('Make Alice an admin?'), findsOneWidget);
        expect(
          find.text('They will be able to add, remove, and manage members.'),
          findsOneWidget,
        );

        await confirmRoleChangeDialog(tester);

        final aliceRow = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(Row),
        );
        expect(
          find.descendant(of: aliceRow, matching: find.text('admin')),
          findsOneWidget,
        );
        expect(find.text('Alice is now an admin'), findsOneWidget);

        final updatedMember = await groupRepo.getMember(
          'group-1',
          'peer-alice',
        );
        expect(updatedMember?.role, MemberRole.admin);

        expect(bridge.commandLog, contains('group:updateConfig'));
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));

        final publishMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;

        expect(sysText['__sys'], 'member_role_updated');
        expect(sysText['member']['peerId'], 'peer-alice');
        expect(sysText['member']['role'], 'admin');

        final inboxStoreMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:inboxStore';
        });
        final inboxStorePayload =
            (jsonDecode(inboxStoreMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(inboxStorePayload['recipientPeerIds'], ['peer-alice']);

        final latestTimeline = await msgRepo.getLatestMessage('group-1');
        expect(latestTimeline, isNotNull);
        expect(
          latestTimeline!.text,
          buildMemberRoleUpdatedTimelineText(
            'Admin',
            'Alice',
            previousRole: MemberRole.writer,
            newRole: MemberRole.admin,
          ),
        );
      },
    );

    testWidgets(
      'demote admin shows confirmation, updates badge, and emits success feedback',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-pk-admin',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            mlKemPublicKey: 'mlkem-pk-alice',
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final bridge = FakeBridge();

        await tester.pumpWidget(
          MaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        await openRoleActionMenu(tester, 'peer-alice');
        expect(find.text('Remove Admin'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('group-member-toggle-admin-peer-alice')),
        );
        await pumpFrames(tester);

        expect(find.text('Remove admin access from Alice?'), findsOneWidget);
        expect(
          find.text(
            'They will lose admin-only actions after the change syncs.',
          ),
          findsOneWidget,
        );

        await confirmRoleChangeDialog(tester);

        final aliceRow = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(Row),
        );
        expect(
          find.descendant(of: aliceRow, matching: find.text('writer')),
          findsOneWidget,
        );
        expect(find.text('Alice is no longer an admin'), findsOneWidget);

        final updatedMember = await groupRepo.getMember(
          'group-1',
          'peer-alice',
        );
        expect(updatedMember?.role, MemberRole.writer);

        final publishMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;
        expect(sysText['member']['role'], 'writer');
      },
    );

    testWidgets('leave group calls bridge and pops to first route', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      final bridge = FakeBridge();

      // Use a Navigator stack to verify popUntil(isFirst)
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupInfoWired(
                        group: group,
                        groupRepo: groupRepo,
                        contactRepo: InMemoryContactRepository(),
                        bridge: bridge,
                        identityRepo: FakeIdentityRepository(
                          identity: testIdentity,
                        ),
                        p2pService: FakeP2PService(),
                      ),
                    ),
                  );
                },
                child: const Text('Open Info'),
              ),
            ),
          ),
        ),
      );

      // Navigate to group info
      await tester.tap(find.text('Open Info'));
      await pumpFrames(tester, count: 20);

      // Verify info screen is showing
      expect(find.byType(GroupInfoScreen), findsOneWidget);

      // Tap Leave Group
      await tapLeaveGroupButton(tester);

      // Verify bridge received group:leave command
      expect(bridge.commandLog, contains('group:leave'));

      // Verify popped back to first route
      expect(find.byType(GroupInfoScreen), findsNothing);
      expect(find.text('Open Info'), findsOneWidget);
    });

    testWidgets('sole admin leave stays on screen and shows an error', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);
      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
        ),
      );

      final bridge = FakeBridge();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupInfoWired(
                        group: group,
                        groupRepo: groupRepo,
                        contactRepo: InMemoryContactRepository(),
                        bridge: bridge,
                        identityRepo: FakeIdentityRepository(
                          identity: testIdentity,
                        ),
                        p2pService: FakeP2PService(),
                      ),
                    ),
                  );
                },
                child: const Text('Open Info'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Info'));
      await pumpFrames(tester, count: 20);

      expect(find.byType(GroupInfoScreen), findsOneWidget);

      await tapLeaveGroupButton(tester);

      expect(bridge.commandLog, isNot(contains('group:leave')));
      expect(find.byType(GroupInfoScreen), findsOneWidget);
      expect(find.text('Open Info'), findsNothing);
      expect(find.text(lastAdminLeaveBlockedMessage), findsOneWidget);
      expect(await groupRepo.getGroup(group.id), isNotNull);
    });

    testWidgets(
      'dissolved local delete clears local state without publishing group leave and pops to the first route',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup().copyWith(
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
          dissolvedBy: 'peer-admin',
        );
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-dissolved-1',
            groupId: group.id,
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Admin dissolved the group',
            timestamp: DateTime.utc(2026, 4, 5, 12, 0, 0),
            createdAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
            isIncoming: false,
            status: 'sent',
          ),
        );

        final bridge = FakeBridge();

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: group,
                          groupRepo: groupRepo,
                          msgRepo: msgRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bridge,
                          identityRepo: FakeIdentityRepository(
                            identity: testIdentity,
                          ),
                          p2pService: FakeP2PService(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Info'));
        await pumpFrames(tester, count: 20);

        await scrollToDeleteLocalGroupButton(tester);
        expect(
          find.byKey(const ValueKey('group-delete-local-button')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('group-delete-local-button')),
        );
        await pumpFrames(tester, count: 5);

        expect(
          find.byKey(const ValueKey('group-delete-local-confirm')),
          findsOneWidget,
        );

        await confirmDeleteLocalGroupDialog(tester);

        expect(await groupRepo.getGroup(group.id), isNull);
        expect(await groupRepo.getLatestKey(group.id), isNull);
        expect(await groupRepo.getMembers(group.id), isEmpty);
        expect(await msgRepo.getMessageCount(group.id), 0);
        expect(bridge.commandLog, isNot(contains('group:leave')));
        expect(find.byType(GroupInfoScreen), findsNothing);
        expect(find.text('Open Info'), findsOneWidget);
      },
    );

    testWidgets(
      'canceling dissolved local delete keeps the group state and route intact',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup().copyWith(
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
          dissolvedBy: 'peer-admin',
        );
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);
        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-dissolved-2',
            groupId: group.id,
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Admin dissolved the group',
            timestamp: DateTime.utc(2026, 4, 5, 12, 0, 0),
            createdAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
            isIncoming: false,
            status: 'sent',
          ),
        );

        final bridge = FakeBridge();

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: group,
                          groupRepo: groupRepo,
                          msgRepo: msgRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bridge,
                          identityRepo: FakeIdentityRepository(
                            identity: testIdentity,
                          ),
                          p2pService: FakeP2PService(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Info'));
        await pumpFrames(tester, count: 20);

        await scrollToDeleteLocalGroupButton(tester);
        await tester.tap(
          find.byKey(const ValueKey('group-delete-local-button')),
        );
        await pumpFrames(tester, count: 5);

        expect(
          find.byKey(const ValueKey('group-delete-local-cancel')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('group-delete-local-cancel')),
        );
        await pumpFrames(tester, count: 20);

        expect(await groupRepo.getGroup(group.id), isNotNull);
        expect(await groupRepo.getLatestKey(group.id), isNotNull);
        expect(await msgRepo.getMessageCount(group.id), 1);
        expect(bridge.commandLog, isNot(contains('group:leave')));
        expect(find.byType(GroupInfoScreen), findsOneWidget);
        expect(find.text('Open Info'), findsNothing);
      },
    );

    testWidgets(
      'multi-admin leave broadcasts self-removal, rotates key, and pops to first route',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-pk-admin',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.admin,
            publicKey: 'pk-bob',
            mlKemPublicKey: 'mlkem-pk-bob',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            mlKemPublicKey: 'mlkem-pk-charlie',
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final bridge = PassthroughCryptoBridge();
        bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'fake-rotated-key',
          'keyEpoch': 2,
        };
        bridge.responses['group:publish'] = {'ok': true, 'messageId': 'msg-1'};
        final p2pService = FakeP2PService();

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: group,
                          groupRepo: groupRepo,
                          msgRepo: msgRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bridge,
                          identityRepo: FakeIdentityRepository(
                            identity: testIdentity,
                          ),
                          p2pService: p2pService,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Info'));
        await pumpFrames(tester, count: 30);

        expect(find.byType(GroupInfoScreen), findsOneWidget);

        await tapLeaveGroupButton(tester, settleFrameCount: 30);

        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
        expect(bridge.commandLog, contains('group:generateNextKey'));
        expect(bridge.commandLog, contains('group:leave'));
        expect(
          bridge.commandLog.indexOf('group:leave'),
          greaterThan(bridge.commandLog.indexOf('group:generateNextKey')),
        );
        expect(p2pService.sentMessageLog.length, 2);

        final publishMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish' &&
              ((parsed['payload'] as Map<String, dynamic>)['text'] as String)
                  .contains('"__sys":"member_removed"');
        });
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;
        expect(sysText['member']['peerId'], 'peer-admin');
        expect(sysText['member']['username'], 'Admin');

        final latestTimeline = await msgRepo.getLatestMessage('group-1');
        expect(latestTimeline, isNotNull);
        expect(
          latestTimeline!.text,
          buildMemberRemovedTimelineText('Admin', 'Admin'),
        );

        expect(await groupRepo.getGroup('group-1'), isNull);
        expect(find.byType(GroupInfoScreen), findsNothing);
        expect(find.text('Open Info'), findsOneWidget);
      },
    );

    testWidgets(
      'writer leave broadcasts a durable left-the-group event before local cleanup',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeMemberGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-pk-admin',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            mlKemPublicKey: 'mlkem-pk-bob',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            mlKemPublicKey: 'mlkem-pk-charlie',
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final leavingIdentity = IdentityModel(
          peerId: 'peer-bob',
          publicKey: 'pk-bob',
          privateKey: 'sk-bob',
          mnemonic12:
              'one two three four five six seven eight nine ten eleven twelve',
          mlKemPublicKey: 'mlkem-pk-bob',
          username: 'Bob',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        );

        final bridge = PassthroughCryptoBridge();
        bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'writer-rotated-key',
          'keyEpoch': 2,
        };
        final p2pService = FakeP2PService();

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupInfoWired(
                          group: group,
                          groupRepo: groupRepo,
                          msgRepo: msgRepo,
                          contactRepo: InMemoryContactRepository(),
                          bridge: bridge,
                          identityRepo: FakeIdentityRepository(
                            identity: leavingIdentity,
                          ),
                          p2pService: p2pService,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Info'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Info'));
        await pumpFrames(tester, count: 30);

        expect(find.byType(GroupInfoScreen), findsOneWidget);

        await tapLeaveGroupButton(tester, settleFrameCount: 30);

        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
        expect(bridge.commandLog, contains('group:generateNextKey'));
        expect(bridge.commandLog, contains('group:leave'));
        expect(p2pService.sentMessageLog.length, 2);

        final latestTimeline = await msgRepo.getLatestMessage('group-1');
        expect(latestTimeline, isNotNull);
        expect(
          latestTimeline!.text,
          buildMemberRemovedTimelineText('Bob', 'Bob'),
        );

        expect(await groupRepo.getGroup('group-1'), isNull);
        expect(find.byType(GroupInfoScreen), findsNothing);
      },
    );

    testWidgets('remove member updates config and refreshes member list', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      final m1 = makeMember(
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
      );
      final m2 = makeMember(peerId: 'peer-alice', username: 'Alice');

      await groupRepo.saveMember(m1);
      await groupRepo.saveMember(m2);

      final bridge = FakeBridge(
        initialResponses: {
          'group:generateNextKey': {
            'ok': true,
            'groupKey': 'fake-rotated-key',
            'keyEpoch': 2,
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: bridge,
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      // Verify Alice is shown
      expect(find.text('Alice'), findsOneWidget);

      // Tap the remove icon button on Alice's row
      final removeButtons = find.byIcon(Icons.remove_circle_outline);
      expect(removeButtons, findsWidgets);

      await tester.ensureVisible(removeButtons.last);
      await pumpFrames(tester, count: 5);
      await tester.tap(removeButtons.last, warnIfMissed: false);
      await pumpFrames(tester);

      expect(find.text('Remove Alice from the group?'), findsOneWidget);
      expect(
        find.text('They will stop receiving new messages from this group.'),
        findsOneWidget,
      );

      await confirmRemoveMemberDialog(tester);

      // Verify bridge received group:updateConfig AND group:generateNextKey
      expect(bridge.commandLog, contains('group:updateConfig'));
      expect(bridge.commandLog, contains('group:inboxStore'));
      expect(bridge.commandLog, contains('group:generateNextKey'));

      // Alice should disappear after the member list refresh
      expect(find.text('Alice'), findsNothing);
    });

    testWidgets('remove member broadcasts system message and rotates key', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      final admin = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        publicKey: 'pk-admin',
        mlKemPublicKey: 'mlkem-pk-admin',
        joinedAt: DateTime.now().toUtc(),
      );
      final alice = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-alice',
        username: 'Alice',
        role: MemberRole.writer,
        publicKey: 'pk-alice',
        mlKemPublicKey: 'mlkem-pk-alice',
        joinedAt: DateTime.now().toUtc(),
      );
      final bob = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-bob',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'pk-bob',
        mlKemPublicKey: 'mlkem-pk-bob',
        joinedAt: DateTime.now().toUtc(),
      );

      await groupRepo.saveMember(admin);
      await groupRepo.saveMember(alice);
      await groupRepo.saveMember(bob);

      final bridge = FakeBridge(
        initialResponses: {
          'group:generateNextKey': {
            'ok': true,
            'groupKey': 'fake-rotated-key',
            'keyEpoch': 2,
          },
        },
      );
      final p2pService = FakeP2PService();

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: bridge,
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: p2pService,
          ),
        ),
      );
      await pumpFrames(tester);

      // Verify all members are shown
      expect(find.text('You'), findsOneWidget); // admin shows as "You"
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Find the remove button specifically on Alice's row.
      final aliceRow = find.ancestor(
        of: find.text('Alice'),
        matching: find.byType(Row),
      );
      final aliceRemoveButton = find.descendant(
        of: aliceRow,
        matching: find.byIcon(Icons.remove_circle_outline),
      );
      expect(aliceRemoveButton, findsOneWidget);

      await tester.ensureVisible(aliceRemoveButton);
      await pumpFrames(tester, count: 5);
      await tester.tap(aliceRemoveButton, warnIfMissed: false);
      await pumpFrames(tester);
      await confirmRemoveMemberDialog(tester);

      // Verify the live broadcast and replay artifact both ran.
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('group:inboxStore'));

      // Key generation starts after broadcast to preserve the current flow shape
      expect(bridge.commandLog, contains('group:generateNextKey'));
    });

    testWidgets(
      'remove member calls bridge in correct order: updateConfig → publish → inboxStore → generateNextKey',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        final admin = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          mlKemPublicKey: 'mlkem-pk-admin',
          joinedAt: DateTime.now().toUtc(),
        );
        final alice = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-alice',
          username: 'Alice',
          role: MemberRole.writer,
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-pk-alice',
          joinedAt: DateTime.now().toUtc(),
        );

        await groupRepo.saveMember(admin);
        await groupRepo.saveMember(alice);

        final bridge = FakeBridge(
          initialResponses: {
            'group:generateNextKey': {
              'ok': true,
              'groupKey': 'fake-rotated-key',
              'keyEpoch': 2,
            },
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        final aliceRow = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(Row),
        );
        final aliceRemoveButton = find.descendant(
          of: aliceRow,
          matching: find.byIcon(Icons.remove_circle_outline),
        );
        await tester.ensureVisible(aliceRemoveButton);
        await pumpFrames(tester, count: 5);
        await tester.tap(aliceRemoveButton, warnIfMissed: false);
        await pumpFrames(tester);
        await confirmRemoveMemberDialog(tester);

        // Verify the durable removal replay is encrypted before inbox store,
        // and that key rotation starts only after the replay is persisted.
        final distinctCommands = <String>[];
        for (final cmd in bridge.commandLog) {
          if (!distinctCommands.contains(cmd)) {
            distinctCommands.add(cmd);
          }
          if (distinctCommands.length == 5) break;
        }
        expect(distinctCommands, [
          'group:updateConfig',
          'group:publish',
          'group.encrypt',
          'group:inboxStore',
          'group:generateNextKey',
        ]);
      },
    );

    testWidgets(
      'remove member distributes rotated key to remaining members via P2P',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        final admin = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          mlKemPublicKey: 'mlkem-pk-admin',
          joinedAt: DateTime.now().toUtc(),
        );
        final alice = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-alice',
          username: 'Alice',
          role: MemberRole.writer,
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-pk-alice',
          joinedAt: DateTime.now().toUtc(),
        );
        final bob = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob',
          mlKemPublicKey: 'mlkem-pk-bob',
          joinedAt: DateTime.now().toUtc(),
        );

        await groupRepo.saveMember(admin);
        await groupRepo.saveMember(alice);
        await groupRepo.saveMember(bob);

        final bridge = PassthroughCryptoBridge();
        bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'fake-rotated-key',
          'keyEpoch': 2,
        };
        bridge.responses['group:publish'] = {'ok': true, 'messageId': 'msg-1'};
        final p2pService = FakeP2PService();

        await tester.pumpWidget(
          MaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: p2pService,
            ),
          ),
        );
        await pumpFrames(tester);

        // Remove Alice — Bob should remain and receive key distribution
        final aliceRow = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(Row),
        );
        final aliceRemoveButton = find.descendant(
          of: aliceRow,
          matching: find.byIcon(Icons.remove_circle_outline),
        );
        await tester.ensureVisible(aliceRemoveButton);
        await pumpFrames(tester, count: 5);
        await tester.tap(aliceRemoveButton, warnIfMissed: false);
        await pumpFrames(tester);
        await confirmRemoveMemberDialog(tester);

        // Only Bob should receive the key update (not Alice, not self)
        expect(p2pService.sentMessageLog.length, 1);
        expect(p2pService.sentMessageLog.first.peerId, 'peer-bob');

        // Verify it's a group_key_update v2 envelope
        final envelope =
            jsonDecode(p2pService.sentMessageLog.first.content)
                as Map<String, dynamic>;
        expect(envelope['type'], 'group_key_update');
        expect(envelope['version'], '2');
        expect(envelope['encrypted'], isNotNull);
      },
    );

    testWidgets(
      'remove member broadcast and replay artifact contain correct member_removed payload',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final msgRepo = InMemoryGroupMessageRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        final admin = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
          publicKey: 'pk-admin',
          mlKemPublicKey: 'mlkem-pk-admin',
          joinedAt: DateTime.now().toUtc(),
        );
        final alice = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-alice',
          username: 'Alice',
          role: MemberRole.writer,
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-pk-alice',
          joinedAt: DateTime.now().toUtc(),
        );
        final bob = GroupMember(
          groupId: 'group-1',
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob',
          mlKemPublicKey: 'mlkem-pk-bob',
          joinedAt: DateTime.now().toUtc(),
        );

        await groupRepo.saveMember(admin);
        await groupRepo.saveMember(alice);
        await groupRepo.saveMember(bob);

        final bridge = FakeBridge(
          initialResponses: {
            'group:generateNextKey': {
              'ok': true,
              'groupKey': 'fake-rotated-key',
              'keyEpoch': 2,
            },
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        // Remove Alice
        final aliceRow = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(Row),
        );
        final aliceRemoveButton = find.descendant(
          of: aliceRow,
          matching: find.byIcon(Icons.remove_circle_outline),
        );
        await tester.ensureVisible(aliceRemoveButton);
        await pumpFrames(tester, count: 5);
        await tester.tap(aliceRemoveButton, warnIfMissed: false);
        await pumpFrames(tester);
        await confirmRemoveMemberDialog(tester);

        // Find the group:publish command in sentMessages
        final publishMsg = bridge.sentMessages.firstWhere((m) {
          final parsed = jsonDecode(m) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;

        // Verify system message type and removed member info
        expect(sysText['__sys'], 'member_removed');
        expect(sysText['member']['peerId'], 'peer-alice');
        expect(sysText['member']['username'], 'Alice');
        expect(sysText['removedAt'], isA<String>());

        // Verify groupConfig.members excludes the removed member (Alice)
        final groupConfig = sysText['groupConfig'] as Map<String, dynamic>;
        final memberPeerIds = (groupConfig['members'] as List)
            .map((m) => (m as Map<String, dynamic>)['peerId'] as String)
            .toList();
        expect(memberPeerIds, contains('peer-admin'));
        expect(memberPeerIds, contains('peer-bob'));
        expect(memberPeerIds, isNot(contains('peer-alice')));

        final removedAt = DateTime.parse(sysText['removedAt'] as String);
        final timelineMessage = buildMemberRemovedTimelineMessage(
          groupId: 'group-1',
          removedPeerId: 'peer-alice',
          removedUsername: 'Alice',
          senderId: 'peer-admin',
          senderUsername: 'Admin',
          eventAt: removedAt,
        );

        final inboxStoreMsg = bridge.sentMessages.firstWhere((m) {
          final parsed = jsonDecode(m) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:inboxStore';
        });
        final inboxStorePayload =
            (jsonDecode(inboxStoreMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(inboxStorePayload['recipientPeerIds'], ['peer-alice']);

        final replayEnvelope = _storedGroupReplayEnvelope(
          inboxStorePayload['message'] as String,
        );
        expect(replayEnvelope['kind'], 'group_offline_replay');
        expect(replayEnvelope['payloadType'], 'group_message');
        expect(replayEnvelope['keyEpoch'], 1);
        expect(replayEnvelope['messageId'], timelineMessage.id);

        final inboxEnvelope = _decodedGroupReplayPayload(
          inboxStorePayload['message'] as String,
        );
        expect(inboxEnvelope['groupId'], 'group-1');
        expect(inboxEnvelope['senderId'], 'peer-admin');
        expect(inboxEnvelope['senderUsername'], 'Admin');
        expect(inboxEnvelope['text'], publishPayload['text']);
        expect(inboxEnvelope['timestamp'], sysText['removedAt']);

        final persistedTimeline = await msgRepo.getMessage(timelineMessage.id);
        expect(persistedTimeline, isNotNull);
        expect(
          persistedTimeline!.text,
          buildMemberRemovedTimelineText('Admin', 'Alice'),
        );
        expect(
          persistedTimeline.timestamp.toUtc().toIso8601String(),
          removedAt.toUtc().toIso8601String(),
        );
      },
    );

    testWidgets(
      'stale non-member removal shows error and emits no removal side effects',
      (tester) async {
        final groupRepo = InMemoryGroupRepository();
        final group = makeAdminGroup();
        await groupRepo.saveGroup(group);
        await _saveGroupReplayKey(groupRepo);

        await groupRepo.saveMember(
          makeMember(
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
          ),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-alice', username: 'Alice'),
        );
        await groupRepo.saveMember(
          makeMember(peerId: 'peer-bob', username: 'Bob'),
        );

        final bridge = FakeBridge();

        await tester.pumpWidget(
          MaterialApp(
            home: GroupInfoWired(
              group: group,
              groupRepo: groupRepo,
              contactRepo: InMemoryContactRepository(),
              bridge: bridge,
              identityRepo: FakeIdentityRepository(identity: testIdentity),
              p2pService: FakeP2PService(),
            ),
          ),
        );
        await pumpFrames(tester);

        final aliceRow = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(Row),
        );
        final aliceRemoveButton = find.descendant(
          of: aliceRow,
          matching: find.byIcon(Icons.remove_circle_outline),
        );

        await groupRepo.removeMember('group-1', 'peer-alice');

        await tester.ensureVisible(aliceRemoveButton);
        await pumpFrames(tester, count: 5);
        await tester.tap(aliceRemoveButton, warnIfMissed: false);
        await pumpFrames(tester);
        await confirmRemoveMemberDialog(tester);

        expect(find.text('Member not found'), findsOneWidget);
        expect(find.text('Alice'), findsNothing);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:publish'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:inboxStore'),
          isEmpty,
        );

        final members = await groupRepo.getMembers('group-1');
        expect(members.map((member) => member.peerId).toSet(), {
          'peer-admin',
          'peer-bob',
        });
      },
    );

    testWidgets('canceling remove member keeps membership unchanged', (
      tester,
    ) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);
      await _saveGroupReplayKey(groupRepo);

      await groupRepo.saveMember(
        makeMember(
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.admin,
        ),
      );
      await groupRepo.saveMember(
        makeMember(peerId: 'peer-alice', username: 'Alice'),
      );

      final bridge = FakeBridge();

      await tester.pumpWidget(
        MaterialApp(
          home: GroupInfoWired(
            group: group,
            groupRepo: groupRepo,
            contactRepo: InMemoryContactRepository(),
            bridge: bridge,
            identityRepo: FakeIdentityRepository(identity: testIdentity),
            p2pService: FakeP2PService(),
          ),
        ),
      );
      await pumpFrames(tester);

      final aliceRow = find.ancestor(
        of: find.text('Alice'),
        matching: find.byType(Row),
      );
      final aliceRemoveButton = find.descendant(
        of: aliceRow,
        matching: find.byIcon(Icons.remove_circle_outline),
      );

      await tester.ensureVisible(aliceRemoveButton);
      await pumpFrames(tester, count: 5);
      await tester.tap(aliceRemoveButton, warnIfMissed: false);
      await pumpFrames(tester);

      expect(find.text('Remove Alice from the group?'), findsOneWidget);
      expect(
        find.text('They will stop receiving new messages from this group.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('group-remove-cancel')));
      await pumpFrames(tester, count: 20);

      expect(find.text('Alice'), findsOneWidget);
      expect(bridge.commandLog, isEmpty);
    });
  });
}
