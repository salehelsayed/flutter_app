import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/services/fake_p2p_service.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_group_message_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';

const configuredSharedDir = String.fromEnvironment(
  'E2E_SHARED_DIR',
  defaultValue: '',
);
const configuredRole = String.fromEnvironment(
  'INVITE_STATUS_MATRIX_ROLE',
  defaultValue: 'creator',
);
const configuredRunId = String.fromEnvironment(
  'INVITE_STATUS_MATRIX_RUN_ID',
  defaultValue: 'adhoc',
);

class _MatrixIdentityRepository implements IdentityRepository {
  IdentityModel? identity;

  _MatrixIdentityRepository(this.identity);

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

class _MatrixInviteDeliveryAttemptRepository
    implements GroupInviteDeliveryAttemptRepository {
  final Map<String, GroupInviteDeliveryAttempt> _attempts = {};

  String _key(String groupId, String peerId) => '$groupId::$peerId';

  @override
  Future<void> saveAttempt(GroupInviteDeliveryAttempt attempt) async {
    _attempts[_key(attempt.groupId, attempt.peerId)] = attempt;
  }

  @override
  Future<GroupInviteDeliveryAttempt?> getAttempt({
    required String groupId,
    required String peerId,
  }) async => _attempts[_key(groupId, peerId)];

  @override
  Future<List<GroupInviteDeliveryAttempt>> getAttemptsForGroup(
    String groupId,
  ) async => _attempts.values
      .where((attempt) => attempt.groupId == groupId)
      .toList(growable: false);

  @override
  Future<GroupInviteDeliveryStatus> getStatusForMember({
    required String groupId,
    required String peerId,
  }) async =>
      _attempts[_key(groupId, peerId)]?.status ??
      GroupInviteDeliveryStatus.unknown;

  @override
  Future<Map<String, GroupInviteDeliveryStatus>> getStatusesForGroupMembers(
    String groupId,
  ) async => {
    for (final attempt in _attempts.values.where(
      (attempt) => attempt.groupId == groupId,
    ))
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
    final existing = _attempts[key];
    _attempts[key] = existing == null
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
    await updateStatus(
      groupId: groupId,
      peerId: peerId,
      status: GroupInviteDeliveryStatus.joined,
      updatedAt: joinedAt,
    );
  }

  @override
  Future<int> deleteAttempt({
    required String groupId,
    required String peerId,
  }) async {
    return _attempts.remove(_key(groupId, peerId)) == null ? 0 : 1;
  }

  @override
  Future<int> deleteAttemptsForGroup(String groupId) async {
    final keys = _attempts.entries
        .where((entry) => entry.value.groupId == groupId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in keys) {
      _attempts.remove(key);
    }
    return keys.length;
  }
}

IdentityModel _identity({required String peerId, required String username}) {
  final now = DateTime.utc(2026, 5, 9).toIso8601String();
  return IdentityModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    privateKey: 'sk-$peerId',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    mlKemPublicKey: 'mlkem-pk-$peerId',
    username: username,
    createdAt: now,
    updatedAt: now,
  );
}

IdentityModel _identityForRole(String role) {
  switch (role) {
    case 'accepted_one':
      return _identity(peerId: 'peer-accepted-one', username: 'Accepted One');
    case 'accepted_two':
      return _identity(peerId: 'peer-accepted-two', username: 'Accepted Two');
    case 'pending_unaccepted':
      return _identity(peerId: 'peer-sent', username: 'Sent Member');
    case 'creator':
    default:
      return _identity(peerId: 'peer-admin', username: 'Admin');
  }
}

GroupModel _groupForRole(String role) {
  return GroupModel(
    id: 'group-invite-status-matrix',
    name: 'Invite Status Matrix',
    type: GroupType.chat,
    topicName: 'topic-invite-status-matrix',
    description: 'Creator-side invite status matrix proof',
    createdAt: DateTime.utc(2026, 5, 9),
    createdBy: 'peer-admin',
    myRole: role == 'creator' ? GroupRole.admin : GroupRole.member,
  );
}

GroupMember _member({
  required String peerId,
  required String username,
  MemberRole role = MemberRole.writer,
  int joinedMinute = 0,
}) {
  return GroupMember(
    groupId: 'group-invite-status-matrix',
    peerId: peerId,
    username: username,
    role: role,
    publicKey: 'pk-$peerId',
    mlKemPublicKey: 'mlkem-pk-$peerId',
    joinedAt: DateTime.utc(2026, 5, 9, 12, joinedMinute),
  );
}

Future<_MatrixFixture> _buildFixture(String role) async {
  final groupRepo = InMemoryGroupRepository();
  final msgRepo = InMemoryGroupMessageRepository();
  final inviteRepo = _MatrixInviteDeliveryAttemptRepository();
  final group = _groupForRole(role);

  await groupRepo.saveGroup(group);
  await groupRepo.saveKey(
    GroupKeyInfo(
      groupId: group.id,
      keyGeneration: 1,
      encryptedKey: 'matrix-group-key',
      createdAt: DateTime.utc(2026, 5, 9, 12),
    ),
  );

  final members = [
    _member(
      peerId: 'peer-admin',
      username: 'Admin',
      role: MemberRole.admin,
      joinedMinute: 0,
    ),
    _member(
      peerId: 'peer-accepted-one',
      username: 'Accepted One',
      joinedMinute: 1,
    ),
    _member(
      peerId: 'peer-accepted-two',
      username: 'Accepted Two',
      joinedMinute: 2,
    ),
    _member(peerId: 'peer-sent', username: 'Sent Member', joinedMinute: 3),
    _member(peerId: 'peer-queued', username: 'Queued Member', joinedMinute: 4),
    _member(peerId: 'peer-resend', username: 'Resend Member', joinedMinute: 5),
    _member(peerId: 'peer-cannot', username: 'Cannot Member', joinedMinute: 6),
    _member(
      peerId: 'peer-unknown',
      username: 'Unknown Member',
      joinedMinute: 7,
    ),
  ];
  for (final member in members) {
    await groupRepo.saveMember(member);
  }

  await msgRepo.saveMessage(
    buildMemberJoinedTimelineMessage(
      groupId: group.id,
      joinedPeerId: 'peer-accepted-one',
      joinedUsername: 'Accepted One',
      eventAt: DateTime.utc(2026, 5, 9, 12, 10),
    ),
  );
  await msgRepo.saveMessage(
    buildMemberJoinedTimelineMessage(
      groupId: group.id,
      joinedPeerId: 'peer-accepted-two',
      joinedUsername: 'Accepted Two',
      eventAt: DateTime.utc(2026, 5, 9, 12, 11),
    ),
  );

  await _saveAttempt(
    inviteRepo,
    peerId: 'peer-accepted-two',
    username: 'Accepted Two',
    status: GroupInviteDeliveryStatus.sent,
    minute: 8,
  );
  await _saveAttempt(
    inviteRepo,
    peerId: 'peer-sent',
    username: 'Sent Member',
    status: GroupInviteDeliveryStatus.sent,
    minute: 12,
  );
  await _saveAttempt(
    inviteRepo,
    peerId: 'peer-queued',
    username: 'Queued Member',
    status: GroupInviteDeliveryStatus.queued,
    minute: 13,
  );
  await _saveAttempt(
    inviteRepo,
    peerId: 'peer-resend',
    username: 'Resend Member',
    status: GroupInviteDeliveryStatus.needsResend,
    minute: 14,
  );
  await _saveAttempt(
    inviteRepo,
    peerId: 'peer-cannot',
    username: 'Cannot Member',
    status: GroupInviteDeliveryStatus.cannotSend,
    minute: 15,
    lastError: 'missing_secure_key',
  );

  return _MatrixFixture(
    group: group,
    groupRepo: groupRepo,
    msgRepo: msgRepo,
    contactRepo: InMemoryContactRepository(),
    bridge: FakeBridge(),
    identityRepo: _MatrixIdentityRepository(_identityForRole(role)),
    p2pService: FakeP2PService(),
    inviteRepo: inviteRepo,
  );
}

Future<void> _saveAttempt(
  _MatrixInviteDeliveryAttemptRepository repo, {
  required String peerId,
  required String username,
  required GroupInviteDeliveryStatus status,
  required int minute,
  String? lastError,
}) async {
  final timestamp = DateTime.utc(2026, 5, 9, 12, minute);
  await repo.saveAttempt(
    GroupInviteDeliveryAttempt(
      groupId: 'group-invite-status-matrix',
      peerId: peerId,
      username: username,
      status: status,
      attemptedAt: timestamp,
      updatedAt: timestamp,
      lastError: lastError,
    ),
  );
}

class _MatrixFixture {
  final GroupModel group;
  final InMemoryGroupRepository groupRepo;
  final InMemoryGroupMessageRepository msgRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final IdentityRepository identityRepo;
  final P2PService p2pService;
  final GroupInviteDeliveryAttemptRepository inviteRepo;

  const _MatrixFixture({
    required this.group,
    required this.groupRepo,
    required this.msgRepo,
    required this.contactRepo,
    required this.bridge,
    required this.identityRepo,
    required this.p2pService,
    required this.inviteRepo,
  });
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 12}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _writeVerdict(Map<String, Object?> verdict) {
  if (configuredSharedDir.isEmpty) {
    stdout.writeln(jsonEncode(verdict));
    return;
  }
  Directory(configuredSharedDir).createSync(recursive: true);
  final file = File(
    '$configuredSharedDir/invite_status_${configuredRunId}_'
    '${configuredRole}_verdict.json',
  );
  final tempFile = File('${file.path}.tmp');
  tempFile.writeAsStringSync(jsonEncode(verdict), flush: true);
  tempFile.renameSync(file.path);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('group invite status matrix role $configuredRole', (
    tester,
  ) async {
    final fixture = await _buildFixture(configuredRole);

    await tester.pumpWidget(
      MaterialApp(
        home: GroupInfoWired(
          group: fixture.group,
          groupRepo: fixture.groupRepo,
          msgRepo: fixture.msgRepo,
          contactRepo: fixture.contactRepo,
          bridge: fixture.bridge,
          identityRepo: fixture.identityRepo,
          p2pService: fixture.p2pService,
          inviteDeliveryAttemptRepo: fixture.inviteRepo,
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.text('Group Info'), findsOneWidget);
    expect(find.text('Invite Status Matrix'), findsOneWidget);

    final verdict = <String, Object?>{
      'role': configuredRole,
      'runId': configuredRunId,
      'displayProof': 'seeded_group_info_wired',
      'relayLifecycleProof': false,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    if (configuredRole == 'creator') {
      expect(find.text('Invite sent'), findsOneWidget);
      expect(find.text('In their inbox'), findsOneWidget);
      expect(find.text('Resend needed'), findsOneWidget);
      expect(find.text('Cannot send'), findsOneWidget);
      expect(
        find.text(
          "We don't have the secure info needed to invite this friend. Ask them to open or reinstall the app, then try again.",
        ),
        findsOneWidget,
      );
      expect(find.text('Joined'), findsNWidgets(2));
      expect(find.text('Invite unknown'), findsOneWidget);
      verdict['creatorMatrixPass'] = true;
      verdict['labels'] = const [
        'Invite sent',
        'In their inbox',
        'Resend needed',
        'Cannot send',
        'Joined',
        'Invite unknown',
      ];
    } else {
      expect(find.text('You'), findsOneWidget);
      verdict['roleAttachPass'] = true;
    }

    _writeVerdict(verdict);
  });
}
