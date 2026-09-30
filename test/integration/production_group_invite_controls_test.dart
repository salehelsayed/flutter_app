import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/debug/production_journeys/production_group_invite_controls.dart';
import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';

import '../core/bridge/fake_bridge.dart';
import '../core/services/fake_p2p_service.dart';
import '../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../features/identity/domain/repositories/fake_identity_repository.dart';
import '../shared/fakes/in_memory_group_repository.dart';
import '../shared/fakes/in_memory_pending_group_invite_repository.dart';

class _Delivery extends Fake implements GroupInviteDeliveryAttemptRepository {
  @override
  Future<GroupInviteDeliveryAttempt?> getAttempt({
    required String groupId,
    required String peerId,
  }) async => GroupInviteDeliveryAttempt(
    groupId: groupId,
    peerId: peerId,
    status: GroupInviteDeliveryStatus.sent,
    attemptedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    inviteId: 'invite-1',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'serializes real group member enum roles after UI group creation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'invite-controls-',
      );
      const invocation = SimsRuntimeInvocation(
        schema: simsRuntimeConfigSchema,
        profileId: 'android.e2e.main',
        scenarioId: groupInviteJourney,
        role: 'alice',
        runId: 'run',
        nonce: 'nonce',
        values: {},
      );
      final controller = ProductionJourneyController(
        directory: directory,
        profileId: invocation.profileId,
        invocation: invocation,
      );
      addTearDown(() async {
        controller.dispose();
        await directory.delete(recursive: true);
      });
      final contacts = FakeContactRepository()
        ..seed([
          ContactModel(
            peerId: 'bob',
            publicKey: 'key',
            rendezvous: '/mknoon/production-journey/run',
            username: 'Bob',
            signature: 'fixture',
            scannedAt: DateTime.utc(2026).toIso8601String(),
          ),
        ]);
      final groups = InMemoryGroupRepository();
      await groups.saveGroup(
        GroupModel(
          id: 'group',
          name: 'Invite Reliability run',
          type: GroupType.chat,
          topicName: 'fixture-topic',
          createdAt: DateTime.utc(2026),
          createdBy: 'alice',
          myRole: GroupRole.admin,
        ),
      );
      for (final entry in {
        'alice': MemberRole.admin,
        'bob': MemberRole.writer,
      }.entries) {
        await groups.saveMember(
          GroupMember(
            groupId: 'group',
            peerId: entry.key,
            role: entry.value,
            joinedAt: DateTime.utc(2026),
          ),
        );
      }
      await groups.saveKey(
        GroupKeyInfo(
          groupId: 'group',
          keyGeneration: 1,
          encryptedKey: 'private-fixture',
          createdAt: DateTime.utc(2026),
        ),
      );
      bindProductionGroupInviteControls(
        controller: controller,
        bridge: FakeBridge(),
        p2pService: FakeP2PService(),
        identityRepository: FakeIdentityRepository(),
        contactRepository: contacts,
        groupRepository: groups,
        pendingInviteRepository: InMemoryPendingGroupInviteRepository(),
        deliveryRepository: _Delivery(),
      );
      controller.foregroundPush.bind((_) async {});
      controller.markRuntimeReady();
      await controller.start();
      final result = await controller.execute({
        'invocation': invocation.toJson(),
        'sequence': 1,
        'operation': 'invite_snapshot',
        'arguments': {'peerId': 'bob'},
      });
      expect(result['members'], [
        {'peerId': 'alice', 'role': 'admin'},
        {'peerId': 'bob', 'role': 'writer'},
      ]);
      expect((result['attempt'] as Map)['invite_id'], 'invite-1');
      expect(result['keyGeneration'], 1);
      expect(result.toString(), isNot(contains('private-fixture')));
    },
  );
}
