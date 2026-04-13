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
import 'package:flutter_app/l10n/app_localizations.dart';

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

Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('multi-select integration: full batch invite flow', (
    tester,
  ) async {
    // Set up repos
    final contactRepo = InMemoryContactRepository();
    contactRepo.addTestContact(contactAlice);
    contactRepo.addTestContact(contactBob);
    contactRepo.addTestContact(contactCharlie);

    final groupRepo = InMemoryGroupRepository();
    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    // Bob is already a member
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-bob',
        username: 'Bob',
        role: MemberRole.writer,
        joinedAt: DateTime.now().toUtc(),
      ),
    );
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

    // Open the picker via Navigator
    await tester.tap(find.text('Open Picker'));
    await pumpFrames(tester, count: 20);
    expect(find.byType(ContactPickerScreen), findsOneWidget);

    // Bob should NOT appear (already a member)
    expect(find.text('Bob'), findsNothing);

    // Alice and Charlie should appear
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);

    // Tap Alice → selected
    await tester.tap(find.text('Alice'));
    await tester.pump();
    expect(find.text('Add Members (1)'), findsOneWidget);

    // Tap Charlie → selected
    await tester.tap(find.text('Charlie'));
    await tester.pump();
    expect(find.text('Add Members (2)'), findsOneWidget);

    // Send Invites button should appear
    expect(find.text('Send Invites'), findsOneWidget);

    // Tap Send Invites
    await tester.tap(find.text('Send Invites'));
    await pumpFrames(tester, count: 20);

    // --- Verify results ---

    // 1. Both in groupRepo members
    final members = await groupRepo.getMembers('group-1');
    final peerIds = members.map((m) => m.peerId).toSet();
    expect(peerIds, contains('peer-alice'));
    expect(peerIds, contains('peer-charlie'));
    expect(peerIds, contains('peer-bob')); // still there
    expect(peerIds, contains('peer-admin')); // still there

    // 2. Exactly 1 group:updateConfig call
    final updateConfigCalls = bridge.commandLog
        .where((c) => c == 'group:updateConfig')
        .length;
    expect(updateConfigCalls, equals(1));

    // 3. Exactly 1 group:publish call with members_added
    final publishCalls = bridge.commandLog
        .where((c) => c == 'group:publish')
        .length;
    expect(publishCalls, equals(1));

    final publishMsg = bridge.sentMessages.firstWhere((msg) {
      final parsed = jsonDecode(msg) as Map<String, dynamic>;
      return parsed['cmd'] == 'group:publish';
    });
    final parsedPublish = jsonDecode(publishMsg) as Map<String, dynamic>;
    final publishPayload = parsedPublish['payload'] as Map<String, dynamic>;
    final sysText =
        jsonDecode(publishPayload['text'] as String) as Map<String, dynamic>;
    expect(sysText['__sys'], equals('members_added'));
    final sysMembers = sysText['members'] as List<dynamic>;
    expect(sysMembers.length, equals(2));

    // 4. 2 entries in p2pService.sentMessageLog
    expect(p2pService.sentMessageLog.length, equals(2));
    final sentPeerIds = p2pService.sentMessageLog.map((e) => e.peerId).toSet();
    expect(sentPeerIds, contains('peer-alice'));
    expect(sentPeerIds, contains('peer-charlie'));

    // Each is a v2 group_invite envelope
    for (final entry in p2pService.sentMessageLog) {
      final envelope = jsonDecode(entry.content) as Map<String, dynamic>;
      expect(envelope['type'], equals('group_invite'));
      expect(envelope['version'], equals('2'));
    }

    expect(popResult, isNotNull);
    expect(popResult!.membersAdded, equals(2));
    expect(popResult!.hasWarnings, isFalse);
  });
}
