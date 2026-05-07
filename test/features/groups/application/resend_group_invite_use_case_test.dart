import 'package:flutter_app/features/groups/application/resend_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

class _InMemoryInviteDeliveryAttemptRepository
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
  }) async {
    return attempts[_key(groupId, peerId)];
  }

  @override
  Future<List<GroupInviteDeliveryAttempt>> getAttemptsForGroup(
    String groupId,
  ) async {
    return attempts.values
        .where((attempt) => attempt.groupId == groupId)
        .toList(growable: false);
  }

  @override
  Future<GroupInviteDeliveryStatus> getStatusForMember({
    required String groupId,
    required String peerId,
  }) async {
    return attempts[_key(groupId, peerId)]?.status ??
        GroupInviteDeliveryStatus.unknown;
  }

  @override
  Future<Map<String, GroupInviteDeliveryStatus>> getStatusesForGroupMembers(
    String groupId,
  ) async {
    return {
      for (final attempt in attempts.values.where((a) => a.groupId == groupId))
        attempt.peerId: attempt.status,
    };
  }

  @override
  Future<void> updateStatus({
    required String groupId,
    required String peerId,
    required GroupInviteDeliveryStatus status,
    DateTime? updatedAt,
  }) async {
    final existing = attempts[_key(groupId, peerId)];
    final now = updatedAt ?? DateTime.now().toUtc();
    attempts[_key(groupId, peerId)] =
        existing?.copyWith(
          status: status,
          updatedAt: now,
          clearLastError: true,
        ) ??
        GroupInviteDeliveryAttempt(
          groupId: groupId,
          peerId: peerId,
          status: status,
          attemptedAt: now,
          updatedAt: now,
        );
  }

  @override
  Future<void> markJoined({
    required String groupId,
    required String peerId,
    String? username,
    DateTime? joinedAt,
  }) async {
    final now = joinedAt ?? DateTime.now().toUtc();
    final existing = attempts[_key(groupId, peerId)];
    attempts[_key(groupId, peerId)] =
        existing?.copyWith(
          username: username,
          status: GroupInviteDeliveryStatus.joined,
          updatedAt: now,
          clearLastError: true,
        ) ??
        GroupInviteDeliveryAttempt(
          groupId: groupId,
          peerId: peerId,
          username: username,
          status: GroupInviteDeliveryStatus.joined,
          attemptedAt: now,
          updatedAt: now,
        );
  }

  @override
  Future<int> deleteAttempt({
    required String groupId,
    required String peerId,
  }) async {
    return attempts.remove(_key(groupId, peerId)) == null ? 0 : 1;
  }

  @override
  Future<int> deleteAttemptsForGroup(String groupId) async {
    final before = attempts.length;
    attempts.removeWhere((_, attempt) => attempt.groupId == groupId);
    return before - attempts.length;
  }
}

void main() {
  final identity = IdentityModel(
    peerId: 'peer-admin',
    publicKey: 'pk-admin',
    privateKey: 'sk-admin',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    mlKemPublicKey: 'mlkem-pk-admin',
    username: 'Admin',
    createdAt: DateTime.utc(2026, 5, 7).toIso8601String(),
    updatedAt: DateTime.utc(2026, 5, 7).toIso8601String(),
  );

  Future<InMemoryGroupRepository> seededGroupRepo() async {
    final repo = InMemoryGroupRepository();
    final createdAt = DateTime.utc(2026, 5, 7);
    await repo.saveGroup(
      GroupModel(
        id: 'group-1',
        name: 'Status Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/group-1',
        createdAt: createdAt,
        createdBy: identity.peerId,
        myRole: GroupRole.admin,
      ),
    );
    await repo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        publicKey: 'pk-admin',
        mlKemPublicKey: 'mlkem-pk-admin',
        joinedAt: createdAt,
      ),
    );
    await repo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-alice',
        username: 'Alice',
        role: MemberRole.writer,
        publicKey: 'pk-alice',
        mlKemPublicKey: 'mlkem-pk-alice',
        joinedAt: createdAt,
      ),
    );
    await repo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 1,
        encryptedKey: 'group-key',
        createdAt: createdAt,
      ),
    );
    return repo;
  }

  test('resend sends only the invite and updates status to sent', () async {
    final groupRepo = await seededGroupRepo();
    final inviteStatusRepo = _InMemoryInviteDeliveryAttemptRepository();
    final p2pService = FakeP2PService(
      initialState: const NodeState(isStarted: true),
    );
    final bridge = PassthroughCryptoBridge();

    final result = await resendGroupInvite(
      p2pService: p2pService,
      bridge: bridge,
      groupRepo: groupRepo,
      inviteDeliveryAttemptRepo: inviteStatusRepo,
      identity: identity,
      groupId: 'group-1',
      memberPeerId: 'peer-alice',
    );

    expect(result.status, GroupInviteDeliveryStatus.sent);
    expect(p2pService.sendMessageCallCount, 1);
    expect(
      bridge.commandLog.where((command) => command == 'group:publish'),
      isEmpty,
    );
    expect(await groupRepo.getMembers('group-1'), hasLength(2));
    expect(
      await inviteStatusRepo.getStatusForMember(
        groupId: 'group-1',
        peerId: 'peer-alice',
      ),
      GroupInviteDeliveryStatus.sent,
    );
  });

  test(
    'resend records needs_resend when direct and inbox delivery fail',
    () async {
      final groupRepo = await seededGroupRepo();
      final inviteStatusRepo = _InMemoryInviteDeliveryAttemptRepository();
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true),
        sendMessageResult: false,
        storeInInboxResult: false,
      );

      final result = await resendGroupInvite(
        p2pService: p2pService,
        bridge: PassthroughCryptoBridge(),
        groupRepo: groupRepo,
        inviteDeliveryAttemptRepo: inviteStatusRepo,
        identity: identity,
        groupId: 'group-1',
        memberPeerId: 'peer-alice',
      );

      expect(result.status, GroupInviteDeliveryStatus.needsResend);
      expect(p2pService.storeInInboxCallCount, 1);
      expect(
        await inviteStatusRepo.getStatusForMember(
          groupId: 'group-1',
          peerId: 'peer-alice',
        ),
        GroupInviteDeliveryStatus.needsResend,
      );
    },
  );

  test('resend does not add missing members', () async {
    final groupRepo = await seededGroupRepo();
    final inviteStatusRepo = _InMemoryInviteDeliveryAttemptRepository();
    final p2pService = FakeP2PService(
      initialState: const NodeState(isStarted: true),
    );

    final result = await resendGroupInvite(
      p2pService: p2pService,
      bridge: PassthroughCryptoBridge(),
      groupRepo: groupRepo,
      inviteDeliveryAttemptRepo: inviteStatusRepo,
      identity: identity,
      groupId: 'group-1',
      memberPeerId: 'peer-missing',
    );

    expect(result.status, GroupInviteDeliveryStatus.unknown);
    expect(result.reason, ResendGroupInviteReason.memberNotFound);
    expect(p2pService.sendMessageCallCount, 0);
    expect(await groupRepo.getMembers('group-1'), hasLength(2));
  });
}
