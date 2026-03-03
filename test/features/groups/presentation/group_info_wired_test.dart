import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
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
}) =>
    GroupMember(
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

void main() {
  group('GroupInfoWired', () {
    testWidgets('loads and displays group members on init', (tester) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);

      final m1 = makeMember(
          peerId: 'peer-admin', username: 'Admin', role: MemberRole.admin);
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

    testWidgets('hides Add Member button for non-admin role', (tester) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeMemberGroup();
      await groupRepo.saveGroup(group);

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

    testWidgets('leave group calls bridge and pops to first route',
        (tester) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);

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
                        identityRepo:
                            FakeIdentityRepository(identity: testIdentity),
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
      await tester.tap(find.text('Leave Group'));
      await pumpFrames(tester, count: 20);

      // Verify bridge received group:leave command
      expect(bridge.commandLog, contains('group:leave'));

      // Verify popped back to first route
      expect(find.byType(GroupInfoScreen), findsNothing);
      expect(find.text('Open Info'), findsOneWidget);
    });

    testWidgets('remove member updates config and refreshes member list',
        (tester) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);

      final m1 = makeMember(
          peerId: 'peer-admin', username: 'Admin', role: MemberRole.admin);
      final m2 = makeMember(peerId: 'peer-alice', username: 'Alice');

      await groupRepo.saveMember(m1);
      await groupRepo.saveMember(m2);

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

      // Verify Alice is shown
      expect(find.text('Alice'), findsOneWidget);

      // Tap the remove icon button on Alice's row
      final removeButtons = find.byIcon(Icons.remove_circle_outline);
      expect(removeButtons, findsWidgets);

      await tester.tap(removeButtons.last);
      await pumpFrames(tester, count: 20);

      // Verify bridge received group:updateConfig and group:rotateKey
      expect(bridge.commandLog, contains('group:updateConfig'));
      expect(bridge.commandLog, contains('group:rotateKey'));

      // Alice should disappear after the member list refresh
      expect(find.text('Alice'), findsNothing);
    });

    testWidgets(
        'remove member broadcasts system message and sends key updates via P2P',
        (tester) async {
      final groupRepo = InMemoryGroupRepository();
      final group = makeAdminGroup();
      await groupRepo.saveGroup(group);

      // Create members with publicKey and mlKemPublicKey for key rotation
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

      // PassthroughCryptoBridge handles message.encrypt transparently
      final bridge = PassthroughCryptoBridge();

      // group:rotateKey must return keyEpoch and groupKey
      bridge.responses['group:rotateKey'] = {
        'ok': true,
        'keyEpoch': 2,
        'groupKey': 'newKey==',
      };

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
      // Each GroupMemberRow is a Row; find the one containing 'Alice' text.
      final aliceRow = find.ancestor(
        of: find.text('Alice'),
        matching: find.byType(Row),
      );
      final aliceRemoveButton = find.descendant(
        of: aliceRow,
        matching: find.byIcon(Icons.remove_circle_outline),
      );
      expect(aliceRemoveButton, findsOneWidget);

      await tester.tap(aliceRemoveButton);
      await pumpFrames(tester, count: 30);

      // Verify group:publish was called for the member_removed system message
      expect(bridge.commandLog, contains('group:publish'));

      // Verify at least one P2P sendMessage call was made (key update to Bob)
      expect(p2pService.sendMessageCallCount, greaterThanOrEqualTo(1));

      // Verify the key update was sent specifically to peer-bob
      final bobMessages = p2pService.sentMessageLog
          .where((entry) => entry.peerId == 'peer-bob')
          .toList();
      expect(bobMessages, isNotEmpty,
          reason: 'Key update should be sent to remaining member peer-bob');
    });
  });
}
