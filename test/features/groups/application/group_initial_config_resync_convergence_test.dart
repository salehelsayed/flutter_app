import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/application/apply_on_join_group_config_resync.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/on_join_group_config_resync_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 28, 0, 26, 30, 279, 311);
  final membershipAt = createdAt.add(const Duration(milliseconds: 582));
  late InMemoryGroupRepository creator, recipient;
  late FakeBridge bridge;
  late FakeP2PService creatorTransport, recipientTransport;
  final identity = IdentityModel(
    peerId: 'alice',
    publicKey: 'alice-public',
    privateKey: 'alice-private',
    mnemonic12: 'fixture',
    username: 'Alice',
    createdAt: createdAt.toIso8601String(),
    updatedAt: createdAt.toIso8601String(),
  );

  Future<String> hash(InMemoryGroupRepository repo) async =>
      buildGroupConfigPayload(
            (await repo.getGroup('group'))!,
            await repo.getMembers('group'),
          )[groupConfigStateHashField]
          as String;

  Future<ApplyGroupConfigResponseResult> roundtrip() async {
    expect(
      await sendOnJoinGroupConfigRequest(
        p2pService: recipientTransport,
        bridge: bridge,
        groupId: 'group',
        requesterPeerId: 'bob',
        inviterPeerId: 'alice',
        inviterMlKemPublicKey: 'alice-mlkem',
      ),
      SendGroupConfigResyncResult.success,
    );
    await handleIncomingGroupConfigRequest(
      message: ChatMessage(
        from: 'bob',
        to: 'alice',
        content: recipientTransport.lastSendMessageContent!,
        timestamp: createdAt.toIso8601String(),
        isIncoming: true,
      ),
      groupRepo: creator,
      p2pService: creatorTransport,
      bridge: bridge,
      ownIdentity: identity,
      ownMlKemSecretKey: 'alice-secret',
    );
    expect(creatorTransport.lastSendMessageContent, isNotNull);
    return handleIncomingGroupConfigResponse(
      message: ChatMessage(
        from: 'alice',
        to: 'bob',
        content: creatorTransport.lastSendMessageContent!,
        timestamp: createdAt.toIso8601String(),
        isIncoming: true,
      ),
      groupRepo: recipient,
      bridge: bridge,
      ownMlKemSecretKey: 'bob-secret',
    );
  }

  setUp(() async {
    creator = InMemoryGroupRepository();
    recipient = InMemoryGroupRepository();
    bridge = FakeBridge();
    creatorTransport = FakeP2PService(
      initialState: const NodeState(isStarted: true),
    );
    recipientTransport = FakeP2PService(
      initialState: const NodeState(isStarted: true),
    );
    for (final repo in [creator, recipient]) {
      await repo.saveGroup(
        GroupModel(
          id: 'group',
          name: 'Initial group',
          type: GroupType.chat,
          topicName: '/mknoon/group/group',
          createdAt: createdAt,
          createdBy: 'alice',
          myRole: identical(repo, creator) ? GroupRole.admin : GroupRole.member,
          lastMembershipEventAt: membershipAt,
        ),
      );
      for (final peer in ['alice', 'bob']) {
        await repo.saveMember(
          GroupMember(
            groupId: 'group',
            peerId: peer,
            username: peer == 'alice' ? 'Alice' : 'Bob',
            role: peer == 'alice' ? MemberRole.admin : MemberRole.writer,
            publicKey: '$peer-public',
            mlKemPublicKey: '$peer-mlkem',
            joinedAt: createdAt,
          ),
        );
      }
    }
  });

  test(
    'initial signed resync preserves null metadata watermark and exact config hash',
    () async {
      final before = await hash(recipient);
      expect(before, await hash(creator));
      expect(await roundtrip(), ApplyGroupConfigResponseResult.notNewer);
      expect((await recipient.getGroup('group'))!.lastMetadataEventAt, isNull);
      expect(await hash(recipient), before);
      expect(await hash(recipient), await hash(creator));
    },
  );

  test(
    'actual newer metadata still applies and converges after the initial echo',
    () async {
      await roundtrip();
      final editedAt = createdAt.add(const Duration(seconds: 5));
      await creator.updateGroup(
        (await creator.getGroup(
          'group',
        ))!.copyWith(name: 'Edited', lastMetadataEventAt: editedAt),
      );
      expect(await roundtrip(), ApplyGroupConfigResponseResult.applied);
      final updated = (await recipient.getGroup('group'))!;
      expect(updated.name, 'Edited');
      expect(updated.lastMetadataEventAt, editedAt);
      expect(await hash(recipient), await hash(creator));
      expect(await roundtrip(), ApplyGroupConfigResponseResult.notNewer);
    },
  );

  test(
    'initial echo remains authenticated before the no-op decision',
    () async {
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};
      expect(await roundtrip(), ApplyGroupConfigResponseResult.unauthenticated);
      expect((await recipient.getGroup('group'))!.lastMetadataEventAt, isNull);
      expect(await hash(recipient), await hash(creator));
    },
  );
}
