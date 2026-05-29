import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
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

final contactDave = ContactModel(
  peerId: 'peer-dave',
  publicKey: 'pk-dave',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Dave',
  signature: 'sig-dave',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-dave',
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

class _TrackingInviteDeliveryAttemptRepository
    implements GroupInviteDeliveryAttemptRepository {
  final Map<String, GroupInviteDeliveryAttempt> attempts = {};

  String _key(String groupId, String peerId) => '$groupId::$peerId';

  @override
  Future<void> saveAttempt(GroupInviteDeliveryAttempt attempt) async {
    attempts[_key(attempt.groupId, attempt.peerId)] = attempt;
  }

  @override
  Future<GroupInviteDeliveryAttempt?> getAttempt({
    required String groupId,
    required String peerId,
  }) async => attempts[_key(groupId, peerId)];

  @override
  Future<List<GroupInviteDeliveryAttempt>> getAttemptsForGroup(
    String groupId,
  ) async => attempts.values
      .where((attempt) => attempt.groupId == groupId)
      .toList(growable: false);

  @override
  Future<GroupInviteDeliveryStatus> getStatusForMember({
    required String groupId,
    required String peerId,
  }) async =>
      attempts[_key(groupId, peerId)]?.status ??
      GroupInviteDeliveryStatus.unknown;

  @override
  Future<Map<String, GroupInviteDeliveryStatus>> getStatusesForGroupMembers(
    String groupId,
  ) async => {
    for (final attempt in attempts.values.where((a) => a.groupId == groupId))
      attempt.peerId: attempt.status,
  };

  @override
  Future<void> updateStatus({
    required String groupId,
    required String peerId,
    required GroupInviteDeliveryStatus status,
    DateTime? updatedAt,
  }) async {
    final now = (updatedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = attempts[key];
    attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: status,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            status: status,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<void> markJoined({
    required String groupId,
    required String peerId,
    String? username,
    DateTime? joinedAt,
  }) async {
    final now = (joinedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = attempts[key];
    attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            username: username,
            status: GroupInviteDeliveryStatus.joined,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            username: username,
            status: GroupInviteDeliveryStatus.joined,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<int> deleteAttempt({
    required String groupId,
    required String peerId,
  }) async => attempts.remove(_key(groupId, peerId)) == null ? 0 : 1;

  @override
  Future<int> deleteAttemptsForGroup(String groupId) async {
    final keys = attempts.keys
        .where((key) => key.startsWith('$groupId::'))
        .toList(growable: false);
    for (final key in keys) {
      attempts.remove(key);
    }
    return keys.length;
  }
}

class _PeerSelectiveFailureP2PService extends FakeP2PService {
  final Set<String> failedPeerIds;

  _PeerSelectiveFailureP2PService({required this.failedPeerIds})
    : super(initialState: const NodeState(isStarted: true));

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    await super.sendMessage(peerId, message);
    return !failedPeerIds.contains(peerId);
  }

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    await super.storeInInbox(toPeerId, message, timeoutMs: timeoutMs);
    return !failedPeerIds.contains(toPeerId);
  }
}

class _PendingActiveContactsRepository extends InMemoryContactRepository {
  final Completer<List<ContactModel>> activeContactsCompleter;

  _PendingActiveContactsRepository(this.activeContactsCompleter);

  @override
  Future<List<ContactModel>> getActiveContacts() =>
      activeContactsCompleter.future;
}

class _FailOnceActiveContactsRepository extends InMemoryContactRepository {
  var _calls = 0;

  @override
  Future<List<ContactModel>> getActiveContacts() async {
    _calls += 1;
    if (_calls == 1) {
      throw StateError('contacts unavailable');
    }
    return super.getActiveContacts();
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
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  UploadGroupAvatarFn? uploadGroupAvatarFn,
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
        inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
        uploadGroupAvatarFn: uploadGroupAvatarFn ?? uploadGroupAvatar,
      ),
    ),
  );
}

void main() {
  group('ContactPickerWired', () {
    testWidgets(
      'shows loading state instead of empty state while contacts load',
      (tester) async {
        final contactsCompleter = Completer<List<ContactModel>>();
        final contactRepo = _PendingActiveContactsRepository(contactsCompleter);

        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(testGroup);
        await groupRepo.saveMember(memberAdmin);

        await tester.pumpWidget(
          buildDirectWiredTestWidget(
            groupRepo: groupRepo,
            contactRepo: contactRepo,
          ),
        );
        await tester.pump();

        expect(find.text('Loading contacts...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('No contacts available'), findsNothing);

        contactsCompleter.complete([contactAlice]);
        await pumpFrames(tester);

        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('Loading contacts...'), findsNothing);
      },
    );

    testWidgets(
      'contact load failure shows retryable error instead of empty state',
      (tester) async {
        final contactRepo = _FailOnceActiveContactsRepository();
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

        expect(find.text("Couldn't load contacts"), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('No contacts available'), findsNothing);

        await tester.tap(find.text('Retry'));
        await pumpFrames(tester);

        expect(find.text('Alice'), findsOneWidget);
        expect(find.text("Couldn't load contacts"), findsNothing);
      },
    );

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

    testWidgets(
      'batch invite stores and directly sends members_added replay to existing members',
      (tester) async {
        final contactRepo = InMemoryContactRepository();
        contactRepo.addTestContact(contactAlice);

        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(testGroup);
        await groupRepo.saveMember(memberAdmin);
        await groupRepo.saveMember(memberBob);
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
        await tester.tap(find.text('Send Invites'));
        await pumpFrames(tester, count: 30);

        final inboxStoreMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:inboxStore';
        });
        final inboxPayload =
            (jsonDecode(inboxStoreMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(inboxPayload['recipientPeerIds'], ['peer-bob']);
        expect(inboxPayload['preserveRecipientPeerIds'], isTrue);

        final directUpdate = p2pService.sentMessageLog.singleWhere(
          (entry) => entry.peerId == 'peer-bob',
        );
        final directEnvelope =
            jsonDecode(directUpdate.content) as Map<String, dynamic>;
        expect(directEnvelope['type'], 'group_membership_update');
        expect(directEnvelope['groupId'], 'group-1');
        expect(
          (directEnvelope['relayEnvelope'] as Map<String, dynamic>)['message'],
          inboxPayload['message'],
        );

        final invite = p2pService.sentMessageLog.singleWhere(
          (entry) => entry.peerId == 'peer-alice',
        );
        final inviteEnvelope =
            jsonDecode(invite.content) as Map<String, dynamic>;
        expect(inviteEnvelope['type'], 'group_invite');
      },
    );

    testWidgets(
      'batch invite reuploads existing avatar for expanded member ACL before signing invites',
      (tester) async {
        final contactRepo = InMemoryContactRepository();
        contactRepo.addTestContact(contactAlice);

        final avatarDir = Directory.systemTemp.createTempSync(
          'group-avatar-regrant-',
        );
        addTearDown(() {
          if (avatarDir.existsSync()) {
            avatarDir.deleteSync(recursive: true);
          }
        });
        final avatarFile = File('${avatarDir.path}/avatar.jpg');
        avatarFile.writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9]);

        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(
          testGroup.copyWith(
            avatarBlobId: 'blob-old-ab',
            avatarMime: 'image/jpeg',
            avatarPath: avatarFile.path,
          ),
        );
        await groupRepo.saveMember(memberAdmin);
        await groupRepo.saveMember(memberBob);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'test-group-key-base64',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        List<String>? uploadedAllowedPeers;
        String? uploadedPath;
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
            uploadGroupAvatarFn:
                ({
                  required bridge,
                  required localFilePath,
                  required groupId,
                  required allowedPeers,
                  blobId,
                  mime = 'image/jpeg',
                }) async {
                  uploadedPath = localFilePath;
                  uploadedAllowedPeers = allowedPeers;
                  return const GroupAvatarUpload(
                    id: 'blob-regranted-abc',
                    mime: 'image/jpeg',
                    size: 4,
                  );
                },
          ),
        );
        await pumpFrames(tester);

        await tester.tap(find.text('Alice'));
        await tester.pump();
        await tester.tap(find.text('Send Invites'));
        await pumpFrames(tester, count: 30);

        expect(uploadedPath, avatarFile.path);
        expect(uploadedAllowedPeers, ['peer-admin', 'peer-bob', 'peer-alice']);

        final persistedGroup = await groupRepo.getGroup('group-1');
        expect(persistedGroup?.avatarBlobId, 'blob-regranted-abc');

        final updateConfigMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:updateConfig';
        });
        final updateConfigPayload =
            (jsonDecode(updateConfigMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final updateConfig =
            updateConfigPayload['groupConfig'] as Map<String, dynamic>;
        expect(updateConfig['avatarBlobId'], 'blob-regranted-abc');

        final invite = p2pService.sentMessageLog.singleWhere(
          (entry) => entry.peerId == 'peer-alice',
        );
        final inviteEnvelope =
            jsonDecode(invite.content) as Map<String, dynamic>;
        final encrypted = inviteEnvelope['encrypted'] as Map<String, dynamic>;
        final payload = GroupInvitePayload.fromInnerJson(
          encrypted['ciphertext'] as String,
        );
        expect(payload?.groupConfig['avatarBlobId'], 'blob-regranted-abc');
      },
    );

    testWidgets(
      'promoted admin invite from production picker carries latest metadata, avatar, existing-member replay, and full membership snapshot',
      (tester) async {
        final contactRepo = InMemoryContactRepository();
        contactRepo.addTestContact(contactCharlie);

        final avatarDir = Directory.systemTemp.createTempSync(
          'promoted-admin-picker-avatar-',
        );
        addTearDown(() {
          if (avatarDir.existsSync()) {
            avatarDir.deleteSync(recursive: true);
          }
        });
        final avatarFile = File('${avatarDir.path}/avatar.jpg');
        avatarFile.writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9]);

        final promotedAdminIdentity = IdentityModel(
          peerId: contactBob.peerId,
          publicKey: contactBob.publicKey,
          privateKey: 'sk-bob',
          mnemonic12:
              'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
          mlKemPublicKey: contactBob.mlKemPublicKey,
          username: contactBob.username,
          createdAt: DateTime.utc(2026, 5, 28, 12).toIso8601String(),
          updatedAt: DateTime.utc(2026, 5, 28, 12).toIso8601String(),
        );
        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(
          testGroup.copyWith(
            name: 'Bob latest name',
            description: 'Bob latest description',
            createdBy: contactAlice.peerId,
            myRole: GroupRole.admin,
            avatarBlobId: 'blob-bob-latest',
            avatarMime: 'image/jpeg',
            avatarPath: avatarFile.path,
            lastMetadataEventAt: DateTime.utc(2026, 5, 28, 12),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: contactAlice.peerId,
            username: contactAlice.username,
            role: MemberRole.admin,
            publicKey: contactAlice.publicKey,
            mlKemPublicKey: contactAlice.mlKemPublicKey,
            devices: const [
              GroupMemberDeviceIdentity(
                deviceId: 'device-alice',
                transportPeerId: 'peer-alice-device',
                deviceSigningPublicKey: 'pk-alice',
                mlKemPublicKey: 'mlkem-pk-alice',
              ),
            ],
            joinedAt: DateTime.utc(2026, 5, 28, 10),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: contactBob.peerId,
            username: contactBob.username,
            role: MemberRole.admin,
            publicKey: contactBob.publicKey,
            mlKemPublicKey: contactBob.mlKemPublicKey,
            devices: const [
              GroupMemberDeviceIdentity(
                deviceId: 'peer-bob-device',
                transportPeerId: 'peer-bob-device',
                deviceSigningPublicKey: 'pk-bob',
                mlKemPublicKey: 'mlkem-pk-bob',
              ),
            ],
            joinedAt: DateTime.utc(2026, 5, 28, 11),
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 3,
            encryptedKey: 'latest-group-key-base64',
            createdAt: DateTime.utc(2026, 5, 28, 12),
          ),
        );

        List<String>? uploadedAllowedPeers;
        final bridge = PassthroughCryptoBridge();
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            peerId: 'peer-bob-device',
            isStarted: true,
          ),
        );

        await tester.pumpWidget(
          buildDirectWiredTestWidget(
            groupRepo: groupRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            identityRepo: FakeIdentityRepository(
              identity: promotedAdminIdentity,
            ),
            p2pService: p2pService,
            uploadGroupAvatarFn:
                ({
                  required bridge,
                  required localFilePath,
                  required groupId,
                  required allowedPeers,
                  blobId,
                  mime = 'image/jpeg',
                }) async {
                  expect(localFilePath, avatarFile.path);
                  uploadedAllowedPeers = allowedPeers;
                  return const GroupAvatarUpload(
                    id: 'blob-bob-regranted-for-abc',
                    mime: 'image/jpeg',
                    size: 4,
                  );
                },
          ),
        );
        await pumpFrames(tester);

        await tester.tap(find.text('Charlie'));
        await tester.pump();
        await tester.tap(find.text('Send Invites'));
        await pumpFrames(tester, count: 30);

        expect(uploadedAllowedPeers, [
          contactAlice.peerId,
          contactBob.peerId,
          contactCharlie.peerId,
        ]);

        final updateConfigMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:updateConfig';
        });
        final updateConfigPayload =
            (jsonDecode(updateConfigMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final updateConfig =
            updateConfigPayload['groupConfig'] as Map<String, dynamic>;
        expect(updateConfig['name'], 'Bob latest name');
        expect(updateConfig['description'], 'Bob latest description');
        expect(updateConfig['avatarBlobId'], 'blob-bob-regranted-for-abc');
        expect(updateConfig[groupConfigStateHashField], isA<String>());
        final updatedMembers = (updateConfig['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(updatedMembers.map((member) => member['peerId']).toSet(), {
          contactAlice.peerId,
          contactBob.peerId,
          contactCharlie.peerId,
        });
        expect(
          updatedMembers.singleWhere(
            (member) => member['peerId'] == contactBob.peerId,
          )['role'],
          'admin',
        );

        final publishMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(publishPayload['senderPeerId'], contactBob.peerId);
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;
        expect(sysText['__sys'], 'members_added');
        final sysConfig = sysText['groupConfig'] as Map<String, dynamic>;
        expect(sysConfig['name'], 'Bob latest name');
        expect(sysConfig['description'], 'Bob latest description');
        expect(sysConfig['avatarBlobId'], 'blob-bob-regranted-for-abc');
        expect(sysConfig[groupConfigStateHashField], updateConfig['stateHash']);
        expect(
          (sysConfig['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((member) => member['peerId'])
              .toSet(),
          {contactAlice.peerId, contactBob.peerId, contactCharlie.peerId},
        );
        final audit = (sysText[signedGroupTransitionAuditField] as Map)
            .cast<String, dynamic>();
        expect(audit['transitionType'], 'members_added');
        final auditPayload =
            jsonDecode(audit['signedPayload'] as String)
                as Map<String, dynamic>;
        final auditActor = auditPayload['actor'] as Map<String, dynamic>;
        expect(auditActor['peerId'], contactBob.peerId);
        expect(auditActor['signingPublicKey'], contactBob.publicKey);

        final inboxStoreMsg = bridge.sentMessages.firstWhere((message) {
          final parsed = jsonDecode(message) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:inboxStore';
        });
        final inboxPayload =
            (jsonDecode(inboxStoreMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(inboxPayload['recipientPeerIds'], [contactAlice.peerId]);
        expect(inboxPayload['preserveRecipientPeerIds'], isTrue);

        final directMembershipUpdates = p2pService.sentMessageLog
            .where((entry) {
              final envelope =
                  jsonDecode(entry.content) as Map<String, dynamic>;
              return envelope['type'] == 'group_membership_update';
            })
            .toList(growable: false);
        expect(directMembershipUpdates.map((entry) => entry.peerId).toSet(), {
          'peer-alice-device',
        });
        final directEnvelope =
            jsonDecode(directMembershipUpdates.single.content)
                as Map<String, dynamic>;
        final directRelayEnvelope =
            directEnvelope['relayEnvelope'] as Map<String, dynamic>;
        expect(directRelayEnvelope['from'], contactBob.peerId);
        expect(directRelayEnvelope['message'], inboxPayload['message']);

        final invite = p2pService.sentMessageLog.singleWhere(
          (entry) => entry.peerId == contactCharlie.peerId,
        );
        final inviteEnvelope =
            jsonDecode(invite.content) as Map<String, dynamic>;
        expect(inviteEnvelope['type'], 'group_invite');
        final encrypted = inviteEnvelope['encrypted'] as Map<String, dynamic>;
        final invitePayload = GroupInvitePayload.fromInnerJson(
          encrypted['ciphertext'] as String,
        );
        expect(invitePayload, isNotNull);
        expect(invitePayload!.senderPeerId, contactBob.peerId);
        expect(invitePayload.groupConfig['name'], 'Bob latest name');
        expect(
          invitePayload.groupConfig['description'],
          'Bob latest description',
        );
        expect(
          invitePayload.groupConfig['avatarBlobId'],
          'blob-bob-regranted-for-abc',
        );
        expect(
          (invitePayload.groupConfig['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((member) => member['peerId'])
              .toSet(),
          {contactAlice.peerId, contactBob.peerId, contactCharlie.peerId},
        );
        final freshnessProof = invitePayload.membershipFreshnessProof;
        expect(freshnessProof, isNotNull);
        expect(freshnessProof!.inviterPeerId, contactBob.peerId);
        expect(freshnessProof.inviterPublicKey, contactBob.publicKey);
        expect(
          freshnessProof.inviterMemberSnapshot['role'],
          MemberRole.admin.toValue(),
        );
        expect(
          freshnessProof.groupConfigStateHash,
          invitePayload.groupConfig[groupConfigStateHashField],
        );
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

    testWidgets(
      'ML-004 existing-group mixed B/C/D invite failure preserves truthful picker state',
      (tester) async {
        final contactRepo = InMemoryContactRepository();
        contactRepo.addTestContact(contactBob);
        contactRepo.addTestContact(contactCharlie);
        contactRepo.addTestContact(contactDave);

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
        final p2pService = _PeerSelectiveFailureP2PService(
          failedPeerIds: {'peer-dave'},
        );
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
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
                              inviteDeliveryAttemptRepo: inviteStatusRepo,
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

        await tester.tap(find.text('Open Picker'));
        await pumpFrames(tester, count: 20);

        await tester.tap(find.text('Bob'));
        await tester.pump();
        await tester.tap(find.text('Charlie'));
        await tester.pump();
        await tester.tap(find.text('Dave'));
        await tester.pump();
        await tester.tap(find.text('Send Invites'));
        await pumpFrames(tester, count: 20);

        expect(popResult, isNotNull);
        expect(popResult!.membersAdded, 3);
        expect(popResult!.invitesSent, 2);
        expect(popResult!.hasWarnings, isTrue);
        expect(popResult!.inviteBatchResult, isNotNull);
        expect(popResult!.inviteBatchResult!.attempts, hasLength(3));
        expect(popResult!.inviteBatchResult!.successCount, 2);
        expect(popResult!.inviteBatchResult!.failures, hasLength(1));
        expect(
          popResult!.inviteBatchResult!.failures.single.peerId,
          'peer-dave',
        );
        expect(
          popResult!.inviteBatchResult!.failures.single.result,
          SendGroupInviteResult.sendFailed,
        );
        expect(
          popResult!.buildCompletionMessage(),
          contains('Dave (delivery failed)'),
        );

        final members = await groupRepo.getMembers('group-1');
        final memberPeerIds = members.map((m) => m.peerId).toSet();
        expect(
          memberPeerIds,
          equals({'peer-admin', 'peer-bob', 'peer-charlie', 'peer-dave'}),
        );

        final updateConfigMsg = bridge.sentMessages.firstWhere((msg) {
          final parsed = jsonDecode(msg) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:updateConfig';
        });
        final updateConfigPayload =
            (jsonDecode(updateConfigMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final groupConfig =
            updateConfigPayload['groupConfig'] as Map<String, dynamic>;
        final configPeerIds = (groupConfig['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((member) => member['peerId'])
            .toSet();
        expect(configPeerIds, memberPeerIds);

        final publishMsg = bridge.sentMessages.firstWhere((msg) {
          final parsed = jsonDecode(msg) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:publish';
        });
        final publishPayload =
            (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final sysText =
            jsonDecode(publishPayload['text'] as String)
                as Map<String, dynamic>;
        expect(sysText['__sys'], 'members_added');
        final publishedPeerIds = (sysText['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((member) => member['peerId'])
            .toSet();
        expect(publishedPeerIds, {'peer-bob', 'peer-charlie', 'peer-dave'});

        expect(p2pService.sentMessageLog.map((entry) => entry.peerId).toSet(), {
          'peer-bob',
          'peer-charlie',
          'peer-dave',
        });
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.lastStoreInInboxPeerId, 'peer-dave');

        expect(
          await inviteStatusRepo.getStatusForMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
          ),
          GroupInviteDeliveryStatus.sent,
        );
        expect(
          await inviteStatusRepo.getStatusForMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
          ),
          GroupInviteDeliveryStatus.sent,
        );
        expect(
          await inviteStatusRepo.getStatusForMember(
            groupId: 'group-1',
            peerId: 'peer-dave',
          ),
          GroupInviteDeliveryStatus.needsResend,
        );
        final daveAttempt = await inviteStatusRepo.getAttempt(
          groupId: 'group-1',
          peerId: 'peer-dave',
        );
        expect(daveAttempt, isNotNull);
        expect(daveAttempt!.status, isNot(GroupInviteDeliveryStatus.joined));
        expect(daveAttempt.lastError, 'send_failed');
      },
    );

    testWidgets(
      'ML-014 config failure rolls back picker members and creates no invite retry state',
      (tester) async {
        final contactRepo = InMemoryContactRepository();
        contactRepo.addTestContact(contactAlice);
        contactRepo.addTestContact(contactCharlie);

        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(testGroup);
        await groupRepo.saveMember(memberAdmin);
        await groupRepo.saveMember(memberBob);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'test-group-key-base64',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final bridge = PassthroughCryptoBridge();
        bridge.responses['group:updateConfig'] = {
          'ok': false,
          'errorCode': 'CONFIG_SYNC_FAILED',
          'errorMessage': 'bridge rejected config',
        };
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );
        final msgRepo = InMemoryGroupMessageRepository();
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
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
                              msgRepo: msgRepo,
                              inviteDeliveryAttemptRepo: inviteStatusRepo,
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

        await tester.tap(find.text('Open Picker'));
        await pumpFrames(tester, count: 20);

        await tester.tap(find.text('Alice'));
        await tester.pump();
        await tester.tap(find.text('Charlie'));
        await tester.pump();
        await tester.tap(find.text('Send Invites'));
        await pumpFrames(tester, count: 20);

        expect(popResult, isNull);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Failed to invite members'), findsOneWidget);
        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(1),
        );

        final updateConfigMsg = bridge.sentMessages.firstWhere((msg) {
          final parsed = jsonDecode(msg) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:updateConfig';
        });
        final updateConfigPayload =
            (jsonDecode(updateConfigMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final groupConfig =
            updateConfigPayload['groupConfig'] as Map<String, dynamic>;
        expect(
          (groupConfig['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((member) => member['peerId'])
              .toSet(),
          {'peer-admin', 'peer-bob', 'peer-alice', 'peer-charlie'},
        );

        final activeMembers = await groupRepo.getMembers('group-1');
        expect(activeMembers.map((member) => member.peerId).toSet(), {
          'peer-admin',
          'peer-bob',
        });
        expect(await groupRepo.getMember('group-1', 'peer-alice'), isNull);
        expect(await groupRepo.getMember('group-1', 'peer-charlie'), isNull);
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('message.encrypt')));
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(await msgRepo.getMessagesPage('group-1'), isEmpty);
        expect(
          await inviteStatusRepo.getStatusForMember(
            groupId: 'group-1',
            peerId: 'peer-alice',
          ),
          GroupInviteDeliveryStatus.unknown,
        );
        expect(
          await inviteStatusRepo.getStatusForMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
          ),
          GroupInviteDeliveryStatus.unknown,
        );
        expect(await inviteStatusRepo.getAttemptsForGroup('group-1'), isEmpty);
      },
    );

    testWidgets(
      'GM-036 batch invite reports mixed delivery after local re-add',
      (tester) async {
        final contactRepo = InMemoryContactRepository();
        contactRepo.addTestContact(contactCharlie);
        contactRepo.addTestContact(contactDave);

        final groupRepo = InMemoryGroupRepository();
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();
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

        Future<void> seedRemovedMember(ContactModel contact) async {
          await groupRepo.saveMember(
            GroupMember(
              groupId: 'group-1',
              peerId: contact.peerId,
              username: contact.username,
              role: MemberRole.writer,
              publicKey: contact.publicKey,
              mlKemPublicKey: contact.mlKemPublicKey,
              joinedAt: DateTime.utc(2026, 5, 11, 8),
            ),
          );
          await groupRepo.removeMember('group-1', contact.peerId);
        }

        await seedRemovedMember(contactCharlie);
        await seedRemovedMember(contactDave);

        final bridge = PassthroughCryptoBridge();
        final p2pService = _PeerSelectiveFailureP2PService(
          failedPeerIds: {'peer-dave'},
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
                              inviteDeliveryAttemptRepo: inviteStatusRepo,
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

        await tester.tap(find.text('Open Picker'));
        await pumpFrames(tester, count: 20);
        await tester.tap(find.text('Charlie'));
        await tester.pump();
        await tester.tap(find.text('Dave'));
        await tester.pump();
        await tester.tap(find.text('Send Invites'));
        await pumpFrames(tester, count: 20);

        final memberPeerIds = (await groupRepo.getMembers(
          'group-1',
        )).map((member) => member.peerId).toSet();
        expect(
          memberPeerIds,
          containsAll(<String>['peer-charlie', 'peer-dave']),
        );

        expect(popResult, isNotNull);
        expect(popResult!.membersAdded, 2);
        expect(popResult!.invitesSent, 1);
        expect(popResult!.hasWarnings, isTrue);
        final inviteBatch = popResult!.inviteBatchResult;
        expect(inviteBatch, isNotNull);
        expect(
          inviteBatch!.attempts
              .singleWhere((attempt) => attempt.peerId == 'peer-charlie')
              .wasDelivered,
          isTrue,
        );
        final daveAttempt = inviteBatch.attempts.singleWhere(
          (attempt) => attempt.peerId == 'peer-dave',
        );
        expect(daveAttempt.wasDelivered, isFalse);
        expect(daveAttempt.failureLabel, 'delivery failed');

        final completion = popResult!.buildCompletionMessage();
        expect(completion, contains('2 members added'));
        expect(completion, contains('Dave (delivery failed)'));
        expect(completion, isNot(contains('2 members invited')));
        expect(completion, isNot(contains('Charlie (delivery failed)')));

        final charlieDelivery = await inviteStatusRepo.getAttempt(
          groupId: 'group-1',
          peerId: 'peer-charlie',
        );
        final daveDelivery = await inviteStatusRepo.getAttempt(
          groupId: 'group-1',
          peerId: 'peer-dave',
        );
        expect(charlieDelivery, isNotNull);
        expect(charlieDelivery!.status, GroupInviteDeliveryStatus.sent);
        expect(charlieDelivery.lastError, isNull);
        expect(daveDelivery, isNotNull);
        expect(daveDelivery!.status, GroupInviteDeliveryStatus.needsResend);
        expect(daveDelivery.lastError, 'send_failed');

        expect(p2pService.sentMessageLog.map((entry) => entry.peerId).toSet(), {
          'peer-charlie',
          'peer-dave',
        });
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.lastStoreInInboxPeerId, 'peer-dave');
      },
    );

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
