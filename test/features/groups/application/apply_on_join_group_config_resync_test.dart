import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/groups/application/apply_on_join_group_config_resync.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late InMemoryGroupRepository groupRepo;
  late FakeBridge bridge;

  const groupId = 'grp-abc123';
  const adminPeerId = '12D3KooWAlice';
  const adminPublicKey = 'alicePubKey64';

  setUp(() {
    groupRepo = InMemoryGroupRepository();
    bridge = FakeBridge();
  });

  GroupModel localGroup({
    required String name,
    DateTime? lastMetadataEventAt,
  }) {
    return GroupModel(
      id: groupId,
      name: name,
      type: GroupType.chat,
      topicName: '/mknoon/group/$groupId',
      createdAt: DateTime.utc(2026, 1, 1),
      createdBy: adminPeerId,
      myRole: GroupRole.member,
      lastMetadataEventAt: lastMetadataEventAt,
    );
  }

  GroupMember member(String peerId, MemberRole role, String publicKey) {
    return GroupMember(
      groupId: groupId,
      peerId: peerId,
      username: peerId,
      role: role,
      publicKey: publicKey,
      mlKemPublicKey: '$peerId-mlkem',
      joinedAt: DateTime.utc(2026, 1, 1),
    );
  }

  /// Builds a `config:response` system payload advertising [name]/[avatarBlobId]
  /// signed by [actorPeerId]/[actorPublicKey] with metadata stamp [updatedAt].
  Future<Map<String, dynamic>> buildSystemPayload({
    required String name,
    String? avatarBlobId,
    String? avatarMime,
    required String actorPeerId,
    required String actorPublicKey,
    required DateTime updatedAt,
  }) async {
    final responderGroup = GroupModel(
      id: groupId,
      name: name,
      type: GroupType.chat,
      topicName: '/mknoon/group/$groupId',
      avatarBlobId: avatarBlobId,
      avatarMime: avatarMime,
      createdAt: DateTime.utc(2026, 1, 1),
      createdBy: adminPeerId,
      myRole: GroupRole.admin,
      lastMetadataEventAt: updatedAt,
    );
    final members = [member(actorPeerId, MemberRole.admin, actorPublicKey)];
    final groupConfig = buildGroupConfigPayload(responderGroup, members);
    final actorPayload = buildGroupMetadataActorEventPayload(
      groupId: groupId,
      updatedAt: updatedAt,
      actorPeerId: actorPeerId,
      actorUsername: actorPeerId,
      actorPublicKey: actorPublicKey,
      groupConfig: groupConfig,
    );
    final canonical = canonicalizeGroupMetadataActorEventPayload(actorPayload);
    final signResponse = await callSignPayload(
      bridge: bridge,
      dataToSign: canonical,
      privateKey: 'priv',
    );
    return {
      '__sys': groupMetadataUpdatedEventType,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'groupConfig': groupConfig,
      groupMetadataActorEventEnvelopeField:
          buildSignedGroupMetadataActorEventEnvelope(
            signedPayload: canonical,
            signature: signResponse['signature'] as String,
          ),
    };
  }

  test(
    'applies strictly-newer admin-signed metadata (name + avatar + watermark) and fetches the avatar',
    () async {
      final t1 = DateTime.utc(2026, 6, 1);
      final t2 = DateTime.utc(2026, 6, 10);
      await groupRepo.saveGroup(
        localGroup(name: 'Old Name', lastMetadataEventAt: t1),
      );
      await groupRepo.saveMember(
        member(adminPeerId, MemberRole.admin, adminPublicKey),
      );

      final systemPayload = await buildSystemPayload(
        name: 'New Name',
        avatarBlobId: 'blob-new',
        avatarMime: 'image/jpeg',
        actorPeerId: adminPeerId,
        actorPublicKey: adminPublicKey,
        updatedAt: t2,
      );

      final downloadedBlobs = <String>[];
      final result = await applyOnJoinGroupConfigResponse(
        systemPayload: systemPayload,
        groupId: groupId,
        groupRepo: groupRepo,
        bridge: bridge,
        downloadGroupAvatarFn:
            ({required bridge, required groupId, required blobId}) async {
              downloadedBlobs.add(blobId);
              return '/tmp/$blobId.jpg';
            },
        now: DateTime.utc(2026, 6, 11),
      );

      expect(result, ApplyGroupConfigResponseResult.applied);
      final updated = await groupRepo.getGroup(groupId);
      expect(updated!.name, 'New Name');
      expect(updated.avatarBlobId, 'blob-new');
      expect(updated.lastMetadataEventAt, t2);
      expect(updated.avatarPath, '/tmp/blob-new.jpg');
      expect(downloadedBlobs, ['blob-new']);
    },
  );

  test('does not apply non-strictly-newer metadata (idempotent watermark)',
      () async {
    final t2 = DateTime.utc(2026, 6, 10);
    final t1 = DateTime.utc(2026, 6, 1);
    await groupRepo.saveGroup(
      localGroup(name: 'Current', lastMetadataEventAt: t2),
    );
    await groupRepo.saveMember(
      member(adminPeerId, MemberRole.admin, adminPublicKey),
    );

    final systemPayload = await buildSystemPayload(
      name: 'Stale Echo',
      actorPeerId: adminPeerId,
      actorPublicKey: adminPublicKey,
      updatedAt: t1,
    );

    var downloadCalls = 0;
    final result = await applyOnJoinGroupConfigResponse(
      systemPayload: systemPayload,
      groupId: groupId,
      groupRepo: groupRepo,
      bridge: bridge,
      downloadGroupAvatarFn:
          ({required bridge, required groupId, required blobId}) async {
            downloadCalls++;
            return null;
          },
    );

    expect(result, ApplyGroupConfigResponseResult.notNewer);
    expect((await groupRepo.getGroup(groupId))!.name, 'Current');
    expect(downloadCalls, 0);
  });

  test('rejects a response signed by a non-admin member (authenticity gate)',
      () async {
    final t1 = DateTime.utc(2026, 6, 1);
    await groupRepo.saveGroup(
      localGroup(name: 'Old Name', lastMetadataEventAt: t1),
    );
    // Charlie is only a writer locally.
    await groupRepo.saveMember(
      member('12D3KooWCharlie', MemberRole.writer, 'charliePub'),
    );

    final systemPayload = await buildSystemPayload(
      name: 'Forged Name',
      actorPeerId: '12D3KooWCharlie',
      actorPublicKey: 'charliePub',
      updatedAt: DateTime.utc(2026, 6, 10),
    );

    final result = await applyOnJoinGroupConfigResponse(
      systemPayload: systemPayload,
      groupId: groupId,
      groupRepo: groupRepo,
      bridge: bridge,
    );

    expect(result, ApplyGroupConfigResponseResult.notMember);
    expect((await groupRepo.getGroup(groupId))!.name, 'Old Name');
  });

  test('rejects a response whose admin-signature does not verify', () async {
    final t1 = DateTime.utc(2026, 6, 1);
    await groupRepo.saveGroup(
      localGroup(name: 'Old Name', lastMetadataEventAt: t1),
    );
    await groupRepo.saveMember(
      member(adminPeerId, MemberRole.admin, adminPublicKey),
    );

    final systemPayload = await buildSystemPayload(
      name: 'New Name',
      actorPeerId: adminPeerId,
      actorPublicKey: adminPublicKey,
      updatedAt: DateTime.utc(2026, 6, 10),
    );
    // Force the cryptographic verification to fail.
    bridge.responses['payload.verify'] = {'ok': true, 'valid': false};

    final result = await applyOnJoinGroupConfigResponse(
      systemPayload: systemPayload,
      groupId: groupId,
      groupRepo: groupRepo,
      bridge: bridge,
    );

    expect(result, ApplyGroupConfigResponseResult.unauthenticated);
    expect((await groupRepo.getGroup(groupId))!.name, 'Old Name');
  });
}
