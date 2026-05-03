import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/contact_picker_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/contact_picker_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
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
  publicKey: 'pk-bob',
  mlKemPublicKey: 'mlkem-pk-bob',
  joinedAt: DateTime.now().toUtc(),
);

final memberAdmin = GroupMember(
  groupId: 'group-1',
  peerId: 'peer-admin',
  username: 'Admin',
  role: MemberRole.admin,
  publicKey: 'pk-admin',
  mlKemPublicKey: 'mlkem-pk-admin',
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

Future<void> seedGroupMembers(
  InMemoryGroupRepository groupRepo, {
  required int totalMembers,
}) async {
  for (var index = 0; index < totalMembers; index++) {
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: index == 0 ? 'peer-admin' : 'peer-seed-$index',
        username: index == 0 ? 'Admin' : 'Seed $index',
        role: index == 0 ? MemberRole.admin : MemberRole.writer,
        joinedAt: DateTime.now().toUtc(),
      ),
    );
  }
}

/// Simpler builder that puts the wired widget directly as the home.
Widget buildDirectWiredTestWidget({
  required InMemoryGroupRepository groupRepo,
  required InMemoryContactRepository contactRepo,
  FakeBridge? bridge,
  FakeIdentityRepository? identityRepo,
  FakeP2PService? p2pService,
  InMemoryGroupMessageRepository? msgRepo,
  String groupId = 'group-1',
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ContactPickerWired(
        groupId: groupId,
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge ?? FakeBridge(),
        identityRepo:
            identityRepo ?? FakeIdentityRepository(identity: testIdentity),
        p2pService: p2pService ?? FakeP2PService(),
        msgRepo: msgRepo,
      ),
    ),
  );
}

void main() {
  group('ContactPickerWired', () {
    testWidgets('shows contacts excluding existing group members', (
      tester,
    ) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);
      contactRepo.addTestContact(contactBob);
      contactRepo.addTestContact(contactCharlie);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'test-group-key-base64',
          createdAt: DateTime.now().toUtc(),
        ),
      );
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

    testWidgets(
      'stale duplicate selection fails without config sync or members_added publish',
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

        await tester.tap(find.text('Alice'));
        await tester.pump();
        expect(find.text('Send Invites'), findsOneWidget);

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

        await tester.tap(find.text('Send Invites'));
        await pumpFrames(tester, count: 20);

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Failed to invite members'), findsOneWidget);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:publish'),
          isEmpty,
        );

        final members = await groupRepo.getMembers('group-1');
        final aliceRows = members.where(
          (member) => member.peerId == 'peer-alice',
        );
        expect(aliceRows, hasLength(1));
        expect(aliceRows.single.username, 'Alice');
        expect(aliceRows.single.role, MemberRole.writer);
      },
    );

    testWidgets(
      'over-limit batch selection fails without partial members or config sync',
      (tester) async {
        final contactRepo = InMemoryContactRepository();
        contactRepo.addTestContact(contactAlice);
        contactRepo.addTestContact(contactCharlie);

        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(testGroup);
        await seedGroupMembers(
          groupRepo,
          totalMembers: groupMembershipLimit - 1,
        );

        final bridge = FakeBridge();

        await tester.pumpWidget(
          buildDirectWiredTestWidget(
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            bridge: bridge,
          ),
        );
        await pumpFrames(tester);

        await tester.tap(find.text('Alice'));
        await tester.pump();
        await tester.tap(find.text('Charlie'));
        await tester.pump();
        await tester.tap(find.text('Send Invites'));
        await pumpFrames(tester, count: 20);

        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text(
            'Groups can have up to 50 members. Reduce your selection by 1 and try again.',
          ),
          findsOneWidget,
        );
        final members = await groupRepo.getMembers('group-1');
        expect(members.length, groupMembershipLimit - 1);
        expect(
          members.where((member) => member.peerId == 'peer-alice'),
          isEmpty,
        );
        expect(
          members.where((member) => member.peerId == 'peer-charlie'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:publish'),
          isEmpty,
        );
      },
    );

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

    testWidgets('tapping contact toggles selection state', (tester) async {
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

      // Initially unselected
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);

      // Tap Alice → selected
      await tester.tap(find.text('Alice'));
      await tester.pump();

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);

      // Tap Alice again → deselected
      await tester.tap(find.text('Alice'));
      await tester.pump();

      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('confirm button appears after selecting one contact', (
      tester,
    ) async {
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

      // Initially no confirm button
      expect(find.text('Send Invites'), findsNothing);

      // Tap Alice
      await tester.tap(find.text('Alice'));
      await tester.pump();

      // Confirm button appears
      expect(find.text('Send Invites'), findsOneWidget);
    });

    testWidgets('header shows selected count', (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);
      contactRepo.addTestContact(contactCharlie);

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

      // Initially "Add Member"
      expect(find.text('Add Member'), findsOneWidget);

      // Tap Alice
      await tester.tap(find.text('Alice'));
      await tester.pump();
      expect(find.text('Add Members (1)'), findsOneWidget);

      // Tap Charlie
      await tester.tap(find.text('Charlie'));
      await tester.pump();
      expect(find.text('Add Members (2)'), findsOneWidget);
    });

    testWidgets('batch invite adds all selected members to DB', (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);
      contactRepo.addTestContact(contactCharlie);

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

      // Select Alice + Charlie
      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.text('Charlie'));
      await tester.pump();

      // Tap Send Invites
      await tester.tap(find.text('Send Invites'));
      await pumpFrames(tester, count: 20);

      // Both should be in group members
      final members = await groupRepo.getMembers('group-1');
      final peerIds = members.map((m) => m.peerId).toSet();
      expect(peerIds, contains('peer-alice'));
      expect(peerIds, contains('peer-charlie'));
    });

    testWidgets(
      'batch invite calls callGroupUpdateConfig once with all new members',
      (tester) async {
        final contactRepo = InMemoryContactRepository();
        contactRepo.addTestContact(contactAlice);
        contactRepo.addTestContact(contactCharlie);

        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(testGroup);
        await groupRepo.saveMember(memberAdmin);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'test-group-key-base64',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final bridge = PassthroughCryptoBridge();

        await tester.pumpWidget(
          buildDirectWiredTestWidget(
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            p2pService: FakeP2PService(
              initialState: const NodeState(isStarted: true),
            ),
          ),
        );
        await pumpFrames(tester);

        // Select Alice + Charlie, tap Send Invites
        await tester.tap(find.text('Alice'));
        await tester.pump();
        await tester.tap(find.text('Charlie'));
        await tester.pump();
        await tester.tap(find.text('Send Invites'));
        await pumpFrames(tester, count: 20);

        // Exactly 1 group:updateConfig call
        final updateConfigCalls = bridge.commandLog
            .where((c) => c == 'group:updateConfig')
            .length;
        expect(updateConfigCalls, equals(1));

        // Config members list includes both new members
        final updateConfigMsg = bridge.sentMessages.firstWhere((msg) {
          final parsed = jsonDecode(msg) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:updateConfig';
        });
        final parsed = jsonDecode(updateConfigMsg) as Map<String, dynamic>;
        final payload = parsed['payload'] as Map<String, dynamic>;
        final groupConfig = payload['groupConfig'] as Map<String, dynamic>;
        final members = groupConfig['members'] as List<dynamic>;
        final peerIds = members
            .map((m) => (m as Map<String, dynamic>)['peerId'])
            .toSet();
        expect(peerIds, contains('peer-admin'));
        expect(peerIds, contains('peer-alice'));
        expect(peerIds, contains('peer-charlie'));
      },
    );

    testWidgets(
      'PREREQ-SIGNED-COMMIT-AUDIT batch invite broadcasts one signed members_added system message',
      (tester) async {
        final contactRepo = InMemoryContactRepository();
        contactRepo.addTestContact(contactAlice);
        contactRepo.addTestContact(contactCharlie);

        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(testGroup);
        await groupRepo.saveMember(memberAdmin);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'test-group-key-base64',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final bridge = PassthroughCryptoBridge();

        await tester.pumpWidget(
          buildDirectWiredTestWidget(
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            p2pService: FakeP2PService(
              initialState: const NodeState(isStarted: true),
            ),
          ),
        );
        await pumpFrames(tester);

        // Select Alice + Charlie, tap Send Invites
        await tester.tap(find.text('Alice'));
        await tester.pump();
        await tester.tap(find.text('Charlie'));
        await tester.pump();
        await tester.tap(find.text('Send Invites'));
        await pumpFrames(tester, count: 20);

        // Exactly 1 group:publish call
        final publishCalls = bridge.commandLog
            .where((c) => c == 'group:publish')
            .length;
        expect(publishCalls, equals(1));

        // Published text has __sys: 'members_added' with 2 members
        final publishMsg = bridge.sentMessages.firstWhere((msg) {
          final parsed = jsonDecode(msg) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final parsed = jsonDecode(publishMsg) as Map<String, dynamic>;
        final payload = parsed['payload'] as Map<String, dynamic>;
        final sysText =
            jsonDecode(payload['text'] as String) as Map<String, dynamic>;
        expect(sysText['__sys'], equals('members_added'));
        final sysMembers = sysText['members'] as List<dynamic>;
        expect(sysMembers.length, equals(2));
        expect(sysText[signedGroupTransitionAuditField], isA<Map>());
        final audit = (sysText[signedGroupTransitionAuditField] as Map)
            .cast<String, dynamic>();
        expect(audit['transitionType'], 'members_added');
        expect(audit['groupId'], 'group-1');
        expect(audit['sourceEventId'], payload['messageId']);
        expect(audit['signatureAlgorithm'], 'ed25519');
        expect(audit['signedPayload'], isA<String>());
        expect(audit['signature'], isA<String>());

        final auditPayload =
            jsonDecode(audit['signedPayload'] as String)
                as Map<String, dynamic>;
        expect(auditPayload['sourceEventId'], payload['messageId']);
        expect(auditPayload['transitionType'], 'members_added');
        expect(auditPayload['transitionOutputHash'], isA<String>());
        expect(auditPayload['preTransitionStateHash'], isA<String>());
        expect(
          (auditPayload['actor'] as Map)['signingPublicKey'],
          contactSelf.publicKey,
        );

        final signIndex = bridge.commandLog.indexOf('payload.sign');
        final publishIndex = bridge.commandLog.indexOf('group:publish');
        expect(signIndex, isNonNegative);
        expect(signIndex, lessThan(publishIndex));
      },
    );

    testWidgets('batch invite sends individual P2P invites to each contact', (
      tester,
    ) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);
      contactRepo.addTestContact(contactCharlie);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'test-group-key-base64',
          createdAt: DateTime.now().toUtc(),
        ),
      );

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

      // Select Alice + Charlie, tap Send Invites
      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.text('Charlie'));
      await tester.pump();
      await tester.tap(find.text('Send Invites'));
      await pumpFrames(tester, count: 20);

      // 2 entries in sentMessageLog (one per contact)
      expect(p2pService.sentMessageLog.length, equals(2));

      // Each is a v2 group_invite envelope
      final peerIds = p2pService.sentMessageLog.map((e) => e.peerId).toSet();
      expect(peerIds, contains('peer-alice'));
      expect(peerIds, contains('peer-charlie'));

      for (final entry in p2pService.sentMessageLog) {
        final envelope = jsonDecode(entry.content) as Map<String, dynamic>;
        expect(envelope['type'], equals('group_invite'));
        expect(envelope['version'], equals('2'));
        expect(envelope['encrypted'], isNotNull);
      }
    });

    testWidgets(
      'PREREQ-INVITER-FRESHNESS batch invite sends proof-bound invite payloads',
      (tester) async {
        final contactRepo = InMemoryContactRepository();
        contactRepo.addTestContact(contactAlice);
        contactRepo.addTestContact(contactCharlie);

        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(testGroup);
        await groupRepo.saveMember(memberAdmin);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'test-group-key-base64',
            createdAt: DateTime.now().toUtc(),
          ),
        );

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

        await tester.tap(find.text('Alice'));
        await tester.pump();
        await tester.tap(find.text('Charlie'));
        await tester.pump();
        await tester.tap(find.text('Send Invites'));
        await pumpFrames(tester, count: 20);

        expect(p2pService.sentMessageLog.length, equals(2));
        for (final entry in p2pService.sentMessageLog) {
          final envelope = jsonDecode(entry.content) as Map<String, dynamic>;
          final encrypted = envelope['encrypted'] as Map<String, dynamic>;
          final payload = GroupInvitePayload.fromInnerJson(
            encrypted['ciphertext'] as String,
          );
          expect(payload, isNotNull);
          expect(payload!.membershipFreshnessProof, isNotNull);
          expect(
            payload.inviteSignature!.signedPayload,
            contains(groupInviteMembershipFreshnessProofField),
          );
          expect(
            payload.membershipFreshnessProof!.groupConfigStateHash,
            payload.groupConfig['stateHash'],
          );
        }
      },
    );

    testWidgets('batch invite saves a durable members-added timeline locally', (
      tester,
    ) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);
      contactRepo.addTestContact(contactCharlie);

      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'test-group-key-base64',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      await tester.pumpWidget(
        buildDirectWiredTestWidget(
          groupRepo: groupRepo,
          contactRepo: contactRepo,
          bridge: PassthroughCryptoBridge(),
          p2pService: FakeP2PService(
            initialState: const NodeState(isStarted: true),
          ),
          msgRepo: msgRepo,
        ),
      );
      await pumpFrames(tester);

      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.text('Charlie'));
      await tester.pump();
      await tester.tap(find.text('Send Invites'));
      await pumpFrames(tester, count: 20);

      expect(msgRepo.count, equals(1));
      final latestMessage = await msgRepo.getLatestMessage('group-1');
      expect(latestMessage, isNotNull);
      expect(latestMessage!.text, equals('Admin added Alice and Charlie'));
    });

    testWidgets('batch invite pops with count of invited members', (
      tester,
    ) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);
      contactRepo.addTestContact(contactCharlie);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'test-group-key-base64',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      ContactPickerInviteResult? popResult;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.of(context)
                      .push<ContactPickerInviteResult>(
                        MaterialPageRoute(
                          builder: (_) => ContactPickerWired(
                            groupId: 'group-1',
                            groupRepo: groupRepo,
                            contactRepo: contactRepo,
                            bridge: PassthroughCryptoBridge(),
                            identityRepo: FakeIdentityRepository(
                              identity: testIdentity,
                            ),
                            p2pService: FakeP2PService(
                              initialState: const NodeState(isStarted: true),
                            ),
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
      expect(find.byType(ContactPickerScreen), findsOneWidget);

      // Select Alice + Charlie
      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.text('Charlie'));
      await tester.pump();

      // Tap Send Invites
      await tester.tap(find.text('Send Invites'));
      await pumpFrames(tester, count: 20);

      expect(popResult, isNotNull);
      expect(popResult!.membersAdded, equals(2));
      expect(popResult!.hasWarnings, isFalse);
    });

    testWidgets('back button pops with 0', (tester) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);

      ContactPickerInviteResult? popResult;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.of(context)
                      .push<ContactPickerInviteResult>(
                        MaterialPageRoute(
                          builder: (_) => ContactPickerWired(
                            groupId: 'group-1',
                            groupRepo: groupRepo,
                            contactRepo: contactRepo,
                            bridge: FakeBridge(),
                            identityRepo: FakeIdentityRepository(
                              identity: testIdentity,
                            ),
                            p2pService: FakeP2PService(),
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
      expect(find.byType(ContactPickerScreen), findsOneWidget);

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await pumpFrames(tester, count: 20);

      // Picker should be popped with a cancelled result
      expect(find.byType(ContactPickerScreen), findsNothing);
      expect(popResult, isNotNull);
      expect(popResult!.membersAdded, equals(0));
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
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-admin',
          username: 'Admin',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      await tester.pumpWidget(
        buildDirectWiredTestWidget(
          groupRepo: groupRepo,
          contactRepo: contactRepo,
        ),
      );
      await pumpFrames(tester);

      // Tap Alice to select
      await tester.tap(find.text('Alice'));
      await tester.pump();

      // Tap Send Invites
      await tester.tap(find.text('Send Invites'));
      await pumpFrames(tester);

      // Error snackbar should appear
      expect(find.text('Failed to invite members'), findsOneWidget);
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
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 42,
            encryptedKey: 'specific-key-material-gen42',
            createdAt: DateTime.now().toUtc(),
          ),
        );

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

        // Select Alice, tap Send Invites
        await tester.tap(find.text('Alice'));
        await tester.pump();
        await tester.tap(find.text('Send Invites'));
        await pumpFrames(tester, count: 20);

        // PassthroughCryptoBridge passes plaintext through as ciphertext
        final sentContent = p2pService.lastSendMessageContent!;
        final envelope = jsonDecode(sentContent) as Map<String, dynamic>;
        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        final innerJson = encrypted['ciphertext'] as String;
        final innerPayload = jsonDecode(innerJson) as Map<String, dynamic>;

        expect(innerPayload['groupKey'], equals('specific-key-material-gen42'));
        expect(innerPayload['keyEpoch'], equals(42));
        expect(innerPayload['groupId'], equals('group-1'));
      },
    );

    testWidgets(
      'invite succeeds even when sendGroupInvite fails (members still added locally)',
      (tester) async {
        final contactRepo = InMemoryContactRepository();
        contactRepo.addTestContact(contactAlice);

        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(testGroup);
        await groupRepo.saveMember(memberAdmin);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'test-group-key-base64',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final bridge = PassthroughCryptoBridge();
        // P2P node started but both sendMessage and storeInInbox fail
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
          sendMessageResult: false,
          storeInInboxResult: false,
        );

        // Use Navigator pattern to verify pop with count
        ContactPickerInviteResult? popResult;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    final result = await Navigator.of(context)
                        .push<ContactPickerInviteResult>(
                          MaterialPageRoute(
                            builder: (_) => ContactPickerWired(
                              groupId: 'group-1',
                              groupRepo: groupRepo,
                              contactRepo: contactRepo,
                              bridge: bridge,
                              identityRepo: FakeIdentityRepository(
                                identity: testIdentity,
                              ),
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

        // Select Alice, tap Send Invites
        await tester.tap(find.text('Alice'));
        await tester.pump();
        await tester.tap(find.text('Send Invites'));
        await pumpFrames(tester, count: 20);

        // Member should be saved locally despite P2P failure
        final members = await groupRepo.getMembers('group-1');
        final memberPeerIds = members.map((m) => m.peerId).toSet();
        expect(memberPeerIds, contains('peer-alice'));

        expect(popResult, isNotNull);
        expect(popResult!.membersAdded, equals(1));
        expect(popResult!.hasWarnings, isTrue);
        expect(popResult!.invitesSent, equals(0));
        expect(
          popResult!.buildCompletionMessage(),
          contains('invite issues: Alice (delivery failed)'),
        );

        // Verify P2P was attempted
        expect(p2pService.sendMessageCallCount, greaterThan(0));
        // storeInInbox was also attempted as fallback
        expect(p2pService.storeInInboxCallCount, greaterThan(0));
      },
    );

    testWidgets('invite skips sendGroupInvite when no group key exists', (
      tester,
    ) async {
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

      // Select Alice, tap Send Invites
      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.text('Send Invites'));
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

    testWidgets('batch invite with no group key still adds members locally', (
      tester,
    ) async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(contactAlice);
      contactRepo.addTestContact(contactCharlie);

      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(testGroup);
      await groupRepo.saveMember(memberAdmin);
      // No GroupKeyInfo saved

      final bridge = FakeBridge();
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
      );

      ContactPickerInviteResult? popResult;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.of(context)
                      .push<ContactPickerInviteResult>(
                        MaterialPageRoute(
                          builder: (_) => ContactPickerWired(
                            groupId: 'group-1',
                            groupRepo: groupRepo,
                            contactRepo: contactRepo,
                            bridge: bridge,
                            identityRepo: FakeIdentityRepository(
                              identity: testIdentity,
                            ),
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

      // Select Alice + Charlie, tap Send Invites
      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.text('Charlie'));
      await tester.pump();
      await tester.tap(find.text('Send Invites'));
      await pumpFrames(tester, count: 20);

      // Members should be saved locally
      final members = await groupRepo.getMembers('group-1');
      final peerIds = members.map((m) => m.peerId).toSet();
      expect(peerIds, contains('peer-alice'));
      expect(peerIds, contains('peer-charlie'));

      // Config updated
      expect(bridge.commandLog, contains('group:updateConfig'));

      // No P2P sends (no key)
      expect(p2pService.sendMessageCallCount, equals(0));

      expect(popResult, isNotNull);
      expect(popResult!.membersAdded, equals(2));
      expect(popResult!.hasWarnings, isTrue);
      expect(popResult!.inviteDeliverySkippedMissingKey, isTrue);
      expect(
        popResult!.buildCompletionMessage(),
        contains('missing its latest key'),
      );
    });
  });
}
