import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/contact_picker_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/contact_picker_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

// --- Test data ---

final contactAlice = ContactModel(
  peerId: 'peer-alice',
  publicKey: 'pk-alice',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Alice',
  signature: 'sig-alice',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-alice',
);

final contactBob = ContactModel(
  peerId: 'peer-bob',
  publicKey: 'pk-bob',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Bob',
  signature: 'sig-bob',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-bob',
);

final contactCharlie = ContactModel(
  peerId: 'peer-charlie',
  publicKey: 'pk-charlie',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Charlie',
  signature: 'sig-charlie',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-charlie',
);

final contactSelf = ContactModel(
  peerId: 'peer-admin',
  publicKey: 'pk-admin',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Admin',
  signature: 'sig-admin',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-admin',
);

final testGroup = GroupModel(
  id: 'group-1',
  name: 'Test Group',
  type: GroupType.chat,
  topicName: 'topic-1',
  description: 'A test group',
  createdAt: DateTime.now().toUtc(),
  createdBy: 'peer-admin',
  myRole: GroupRole.admin,
);

final memberBob = GroupMember(
  groupId: 'group-1',
  peerId: 'peer-bob',
  username: 'Bob',
  role: MemberRole.writer,
  joinedAt: DateTime.now().toUtc(),
);

final memberAdmin = GroupMember(
  groupId: 'group-1',
  peerId: 'peer-admin',
  username: 'Admin',
  role: MemberRole.admin,
  joinedAt: DateTime.now().toUtc(),
);

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

// --- Test helpers ---

/// Pump enough frames for async operations to complete.
/// AmbientBackground has an infinite animation, so pumpAndSettle will timeout.
/// Instead, pump several frames with small durations.
Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Simpler builder that puts the wired widget directly as the home.
Widget buildDirectWiredTestWidget({
  required InMemoryGroupRepository groupRepo,
  required InMemoryContactRepository contactRepo,
  FakeBridge? bridge,
  FakeIdentityRepository? identityRepo,
  FakeP2PService? p2pService,
  String groupId = 'group-1',
}) {
  return MaterialApp(
    home: Scaffold(
      body: ContactPickerWired(
        groupId: groupId,
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge ?? FakeBridge(),
        identityRepo: identityRepo ??
            FakeIdentityRepository(identity: testIdentity),
        p2pService: p2pService ?? FakeP2PService(),
      ),
    ),
  );
}

void main() {
  group('ContactPickerWired', () {
    testWidgets('shows contacts excluding existing group members',
        (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);
      contactRepo.addTestContact(contactBob);
      contactRepo.addTestContact(contactCharlie);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);
      await groupRepo.saveMember(memberBob); // Bob is already a member

      await tester.pumpWidget(
        buildDirectWiredTestWidget(
          groupRepo: groupRepo,
          contactRepo: contactRepo,
        ),
      );
      await pumpFrames(tester);

      // Alice and Charlie should appear
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
      // Bob is a member -- should NOT appear
      expect(find.text('Bob'), findsNothing);
    });

    testWidgets('excludes self from contact list', (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);
      contactRepo.addTestContact(contactSelf); // same peerId as identity

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);

      await tester.pumpWidget(
        buildDirectWiredTestWidget(
          groupRepo: groupRepo,
          contactRepo: contactRepo,
        ),
      );
      await pumpFrames(tester);

      // Alice appears
      expect(find.text('Alice'), findsOneWidget);
      // Self should NOT appear (even though "Admin" is a contact)
      expect(find.text('Admin'), findsNothing);
    });

    testWidgets('shows confirmation dialog on contact selection',
        (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);

      await tester.pumpWidget(
        buildDirectWiredTestWidget(
          groupRepo: groupRepo,
          contactRepo: contactRepo,
        ),
      );
      await pumpFrames(tester);

      // Tap Alice
      await tester.tap(find.text('Alice'));
      await pumpFrames(tester);

      // Confirmation dialog should appear
      expect(find.text('Invite Alice?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Invite'), findsOneWidget);
    });

    testWidgets('cancelling confirmation does not invoke use case',
        (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);

      final bridge = FakeBridge();

      await tester.pumpWidget(
        buildDirectWiredTestWidget(
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
        ),
      );
      await pumpFrames(tester);

      // Tap Alice
      await tester.tap(find.text('Alice'));
      await pumpFrames(tester);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester);

      // No bridge calls should have been made
      expect(bridge.sendCallCount, equals(0));

      // Alice's peerId should NOT be in group members
      final members = await groupRepo.getMembers('group-1');
      final memberPeerIds = members.map((m) => m.peerId).toSet();
      expect(memberPeerIds.contains('peer-alice'), isFalse);
    });

    testWidgets('confirming invite adds member and pops screen',
        (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);

      // Build with a Navigator to verify pop
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ContactPickerWired(
                        groupId: 'group-1',
                        groupRepo: groupRepo,
                        contactRepo: contactRepo,
                        bridge: FakeBridge(),
                        identityRepo:
                            FakeIdentityRepository(identity: testIdentity),
                        p2pService: FakeP2PService(),
                      ),
                    ),
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      );

      // Open the picker
      await tester.tap(find.text('Open Picker'));
      await pumpFrames(tester, count: 20);

      // Verify picker screen is showing
      expect(find.byType(ContactPickerScreen), findsOneWidget);

      // Tap Alice
      await tester.tap(find.text('Alice'));
      await pumpFrames(tester);

      // Confirm invite
      await tester.tap(find.text('Invite'));
      await pumpFrames(tester, count: 20);

      // Picker should be popped
      expect(find.byType(ContactPickerScreen), findsNothing);
      expect(find.text('Open Picker'), findsOneWidget);

      // Alice should be a member now
      final members = await groupRepo.getMembers('group-1');
      final memberPeerIds = members.map((m) => m.peerId).toSet();
      expect(memberPeerIds.contains('peer-alice'), isTrue);
    });

    testWidgets('shows error snackbar when invite fails', (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);

      // Use a group where the user is NOT admin -- addGroupMember will throw
      final nonAdminGroup = GroupModel(
        id: 'group-1',
        name: 'Test Group',
        type: GroupType.chat,
        topicName: 'topic-1',
        description: 'A test group',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member, // NOT admin
      );

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(nonAdminGroup);
      // Still need identity to match admin for the filter
      await groupRepo.saveMember(memberAdmin);

      await tester.pumpWidget(
        buildDirectWiredTestWidget(
          groupRepo: groupRepo,
          contactRepo: contactRepo,
        ),
      );
      await pumpFrames(tester);

      // Tap Alice
      await tester.tap(find.text('Alice'));
      await pumpFrames(tester);

      // Confirm invite
      await tester.tap(find.text('Invite'));
      await pumpFrames(tester);

      // Error snackbar should appear
      expect(find.text('Failed to invite member'), findsOneWidget);
    });

    testWidgets('back button pops the screen', (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ContactPickerWired(
                        groupId: 'group-1',
                        groupRepo: groupRepo,
                        contactRepo: contactRepo,
                        bridge: FakeBridge(),
                        identityRepo:
                            FakeIdentityRepository(identity: testIdentity),
                        p2pService: FakeP2PService(),
                      ),
                    ),
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      );

      // Open the picker
      await tester.tap(find.text('Open Picker'));
      await pumpFrames(tester, count: 20);

      // Verify picker is showing
      expect(find.byType(ContactPickerScreen), findsOneWidget);

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await pumpFrames(tester, count: 20);

      // Picker should be popped
      expect(find.byType(ContactPickerScreen), findsNothing);
      expect(find.text('Open Picker'), findsOneWidget);
    });

    testWidgets(
        'confirming invite calls callGroupUpdateConfig with full GroupConfig including new member',
        (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);
      await groupRepo.saveKey(GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 1,
        encryptedKey: 'test-group-key-base64',
        createdAt: DateTime.now().toUtc(),
      ));

      final bridge = PassthroughCryptoBridge();
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
      );

      await tester.pumpWidget(
        buildDirectWiredTestWidget(
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          p2pService: p2pService,
        ),
      );
      await pumpFrames(tester);

      // Tap Alice
      await tester.tap(find.text('Alice'));
      await pumpFrames(tester);

      // Confirm invite
      await tester.tap(find.text('Invite'));
      await pumpFrames(tester, count: 20);

      // Find the group:updateConfig command in sentMessages
      expect(bridge.commandLog, contains('group:updateConfig'));

      final updateConfigMsg = bridge.sentMessages.firstWhere((msg) {
        final parsed = jsonDecode(msg) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:updateConfig';
      });
      final parsed = jsonDecode(updateConfigMsg) as Map<String, dynamic>;
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupConfig = payload['groupConfig'] as Map<String, dynamic>;
      final members = groupConfig['members'] as List<dynamic>;

      // Should contain both Admin and Alice
      final peerIds = members.map((m) => (m as Map<String, dynamic>)['peerId']).toSet();
      expect(peerIds, contains('peer-admin'));
      expect(peerIds, contains('peer-alice'));
      expect(members.length, equals(2));

      // Verify groupConfig fields
      expect(groupConfig['name'], equals('Test Group'));
      expect(groupConfig['groupType'], equals('chat'));
      expect(groupConfig['createdBy'], equals('peer-admin'));
    });

    testWidgets('confirming invite calls sendGroupInvite via P2P',
        (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);
      await groupRepo.saveKey(GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 1,
        encryptedKey: 'test-group-key-base64',
        createdAt: DateTime.now().toUtc(),
      ));

      final bridge = PassthroughCryptoBridge();
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
      );

      await tester.pumpWidget(
        buildDirectWiredTestWidget(
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          p2pService: p2pService,
        ),
      );
      await pumpFrames(tester);

      // Tap Alice
      await tester.tap(find.text('Alice'));
      await pumpFrames(tester);

      // Confirm invite
      await tester.tap(find.text('Invite'));
      await pumpFrames(tester, count: 20);

      // Verify P2P sendMessage was called to Alice
      expect(p2pService.sendMessageCallCount, equals(1));
      expect(p2pService.lastSendMessagePeerId, equals('peer-alice'));

      // Verify the sent message is a v2 group_invite envelope
      final sentContent = p2pService.lastSendMessageContent!;
      final envelope = jsonDecode(sentContent) as Map<String, dynamic>;
      expect(envelope['type'], equals('group_invite'));
      expect(envelope['version'], equals('2'));
      expect(envelope['encrypted'], isNotNull);

      final encrypted = envelope['encrypted'] as Map<String, dynamic>;
      expect(encrypted['kem'], isNotNull);
      expect(encrypted['ciphertext'], isNotNull);
      expect(encrypted['nonce'], isNotNull);
    });

    testWidgets(
        'confirming invite sends groupKey and keyEpoch from latest key',
        (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);

      // Save a key with specific generation and key material
      await groupRepo.saveKey(GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 42,
        encryptedKey: 'specific-key-material-gen42',
        createdAt: DateTime.now().toUtc(),
      ));

      final bridge = PassthroughCryptoBridge();
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
      );

      await tester.pumpWidget(
        buildDirectWiredTestWidget(
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          p2pService: p2pService,
        ),
      );
      await pumpFrames(tester);

      // Tap Alice
      await tester.tap(find.text('Alice'));
      await pumpFrames(tester);

      // Confirm invite
      await tester.tap(find.text('Invite'));
      await pumpFrames(tester, count: 20);

      // PassthroughCryptoBridge passes plaintext through as ciphertext,
      // so we can decode the v2 envelope's ciphertext to read the inner payload.
      final sentContent = p2pService.lastSendMessageContent!;
      final envelope = jsonDecode(sentContent) as Map<String, dynamic>;
      final encrypted = envelope['encrypted'] as Map<String, dynamic>;
      // ciphertext IS the plaintext because PassthroughCryptoBridge echoes it
      final innerJson = encrypted['ciphertext'] as String;
      final innerPayload = jsonDecode(innerJson) as Map<String, dynamic>;

      expect(innerPayload['groupKey'], equals('specific-key-material-gen42'));
      expect(innerPayload['keyEpoch'], equals(42));
      expect(innerPayload['groupId'], equals('group-1'));
    });

    testWidgets(
        'invite succeeds even when sendGroupInvite fails (member still added locally)',
        (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);
      await groupRepo.saveKey(GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 1,
        encryptedKey: 'test-group-key-base64',
        createdAt: DateTime.now().toUtc(),
      ));

      final bridge = PassthroughCryptoBridge();
      // P2P node started but both sendMessage and storeInInbox fail
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
        sendMessageResult: false,
        storeInInboxResult: false,
      );

      // Use Navigator pattern to verify pop with true
      bool? popResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ContactPickerWired(
                        groupId: 'group-1',
                        groupRepo: groupRepo,
                        contactRepo: contactRepo,
                        bridge: bridge,
                        identityRepo:
                            FakeIdentityRepository(identity: testIdentity),
                        p2pService: p2pService,
                      ),
                    ),
                  );
                  popResult = result;
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      );

      // Open the picker
      await tester.tap(find.text('Open Picker'));
      await pumpFrames(tester, count: 20);

      // Tap Alice
      await tester.tap(find.text('Alice'));
      await pumpFrames(tester);

      // Confirm invite
      await tester.tap(find.text('Invite'));
      await pumpFrames(tester, count: 20);

      // Member should be saved locally despite P2P failure
      final members = await groupRepo.getMembers('group-1');
      final memberPeerIds = members.map((m) => m.peerId).toSet();
      expect(memberPeerIds, contains('peer-alice'));

      // Screen should have popped with true (success)
      expect(popResult, isTrue);

      // Verify P2P was attempted (sendMessage was called)
      expect(p2pService.sendMessageCallCount, greaterThan(0));
      // storeInInbox was also attempted as fallback
      expect(p2pService.storeInInboxCallCount, greaterThan(0));
    });

    testWidgets('invite skips sendGroupInvite when no group key exists',
        (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);
      // No GroupKeyInfo saved -- getLatestKey will return null

      final bridge = PassthroughCryptoBridge();
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
      );

      await tester.pumpWidget(
        buildDirectWiredTestWidget(
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          p2pService: p2pService,
        ),
      );
      await pumpFrames(tester);

      // Tap Alice
      await tester.tap(find.text('Alice'));
      await pumpFrames(tester);

      // Confirm invite
      await tester.tap(find.text('Invite'));
      await pumpFrames(tester, count: 20);

      // Member should be saved locally
      final members = await groupRepo.getMembers('group-1');
      final memberPeerIds = members.map((m) => m.peerId).toSet();
      expect(memberPeerIds, contains('peer-alice'));

      // callGroupUpdateConfig should have been called
      expect(bridge.commandLog, contains('group:updateConfig'));

      // No P2P send should have been attempted (no key = no invite send)
      expect(p2pService.sendMessageCallCount, equals(0));
      expect(p2pService.storeInInboxCallCount, equals(0));

      // No message.encrypt call should have been made either
      expect(bridge.commandLog, isNot(contains('message.encrypt')));
    });
  });
}
