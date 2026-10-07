import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/debug/production_journeys/production_group_catalog_controls.dart';
import 'package:flutter_app/debug/production_journeys/production_group_fixture_controls.dart';
import 'package:flutter_app/debug/production_journeys/production_group_invite_controls.dart';
import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import '../core/bridge/fake_bridge.dart';
import '../core/services/fake_p2p_service.dart';
import '../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../features/identity/domain/repositories/fake_identity_repository.dart';
import '../shared/fakes/in_memory_group_repository.dart';
import '../shared/fakes/in_memory_group_message_repository.dart';
import '../shared/fakes/in_memory_pending_group_invite_repository.dart';

class _Delivery extends Fake implements GroupInviteDeliveryAttemptRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('config field digests isolate changed values without key material', () {
    final before = productionCatalogConfigFieldDigests({
      'createdAt': '2026-09-27T00:00:00Z',
      'members': [
        {'peerId': 'alice', 'publicKey': 'public-key-value', 'role': 'admin'},
        {'peerId': 'bob', 'publicKey': 'bob-key-value', 'role': 'writer'},
      ],
    });
    final after = productionCatalogConfigFieldDigests({
      'createdAt': '2026-09-27T00:00:00Z',
      'members': [
        {'peerId': 'bob', 'publicKey': 'bob-key-value', 'role': 'writer'},
        {'peerId': 'alice', 'publicKey': 'changed-key-value', 'role': 'admin'},
      ],
    });
    expect(before.keys.where((key) => before[key] != after[key]), [
      'config/members/alice/publicKey',
    ]);
    expect(
      before.values.every((v) => RegExp(r'^[0-9a-f]{64}$').hasMatch(v)),
      isTrue,
    );
    expect(before.toString(), isNot(contains('public-key-value')));
  });
  test('config diagnostics distinguish null, absent and empty collections', () {
    final fields = productionCatalogConfigFieldDigests({
      'null': null,
      'list': <Object?>[],
      'map': <String, Object?>{},
    });
    expect(fields.length, 3);
    expect(fields.values.toSet().length, 3);
    expect(fields.containsKey('config/absent'), isFalse);
  });
  test('ambiguous member identity cannot overwrite a diagnostic field', () {
    expect(
      () => productionCatalogConfigFieldDigests({
        'members': [
          {'peerId': 'alice', 'role': 'admin'},
          {'peerId': 'alice', 'role': 'writer'},
        ],
      }),
      throwsStateError,
    );
  });
  for (final scenario in productionGroupCatalogJourneys) {
    test(
      '$scenario binds observations while refusing fixture or protocol mutation shortcuts',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'catalog-controls-',
        );
        final invocation = SimsRuntimeInvocation(
          schema: simsRuntimeConfigSchema,
          profileId: 'android.e2e.production',
          scenarioId: scenario,
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
        final identity = FakeIdentityRepository()
          ..seed(FakeIdentityRepository.makeIdentity(peerId: 'alice'));
        final bridge = FakeBridge();
        final p2p = FakeP2PService();
        final contacts = FakeContactRepository();
        final groups = InMemoryGroupRepository();
        final delivery = _Delivery();
        bindProductionGroupFixtureControls(
          controller: controller,
          bridge: bridge,
          p2pService: p2p,
          identityRepository: identity,
          contactRepository: contacts,
          groupRepository: groups,
          groupMessageRepository: InMemoryGroupMessageRepository(),
          inviteDeliveryRepository: delivery,
        );
        bindProductionGroupInviteControls(
          controller: controller,
          bridge: bridge,
          p2pService: p2p,
          identityRepository: identity,
          contactRepository: contacts,
          groupRepository: groups,
          pendingInviteRepository: InMemoryPendingGroupInviteRepository(),
          deliveryRepository: delivery,
        );
        controller.foregroundPush.bind((_) async {});
        controller.markRuntimeReady();
        await controller.start();
        var sequence = 0;
        Future<Map<String, Object?>> command(String name) =>
            controller.execute({
              'invocation': invocation.toJson(),
              'sequence': ++sequence,
              'operation': name,
              'arguments': <String, Object?>{},
            });
        final empty = await command('catalog_group_snapshot');
        expect(empty['group'], isNull);
        expect(empty['peerId'], 'alice');
        expect((await command('catalog_pending_snapshot'))['pending'], isEmpty);
        for (final operation in [
          'prepare_group',
          'import_group',
          'mark_fixture_joined',
          'leave_topic',
          'foreground_push',
          'resend_declined_invite',
          'prepare_invite_fresh_metadata',
        ]) {
          await expectLater(
            command(operation),
            throwsStateError,
            reason: operation,
          );
        }
        expect(await groups.getAllGroups(), isEmpty);
      },
    );
  }

  test(
    'catalog pending snapshot keeps reporting the consumed invitation after it leaves the pending list',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'catalog-consumed-',
      );
      final invocation = SimsRuntimeInvocation(
        schema: simsRuntimeConfigSchema,
        profileId: 'android.e2e.production',
        scenarioId: 'production.group_catalog.private_abc_create',
        role: 'bob',
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
      final pending = InMemoryPendingGroupInviteRepository();
      bindProductionGroupCatalogInviteObservations(
        controller: controller,
        pendingRepository: pending,
      );
      controller.foregroundPush.bind((_) async {});
      controller.markRuntimeReady();
      await controller.start();
      var sequence = 0;
      Future<Map<String, Object?>> snapshot() => controller.execute({
        'invocation': invocation.toJson(),
        'sequence': ++sequence,
        'operation': 'catalog_pending_snapshot',
        'arguments': <String, Object?>{},
      });
      final now = DateTime.utc(2026, 10, 6);
      PendingGroupInvite invite(String id, String group) => PendingGroupInvite(
        groupId: group,
        inviteId: id,
        payloadJson: '{}',
        groupName: productionCatalogGroupName(controller),
        groupType: GroupType.values.first,
        senderPeerId: 'alice',
        senderUsername: 'Alice',
        createdBy: 'alice',
        createdAt: now,
        receivedAt: now,
        expiresAt: now.add(const Duration(days: 1)),
      );
      Future<void> consume(String id, String group) async {
        await pending.deletePendingInvite(group);
        await pending.saveConsumedInvite(
          GroupInviteConsumption(
            inviteId: id,
            groupId: group,
            consumedAt: now,
            expiresAt: now.add(const Duration(days: 1)),
          ),
        );
      }

      await pending.savePendingInvite(invite('invite-1', 'group-1'));
      final before = await snapshot();
      expect(before['pending'], hasLength(1));
      expect(before['consumed'], isNull);

      await consume('invite-1', 'group-1');
      for (var i = 0; i < 2; i++) {
        final after = await snapshot();
        expect(after['pending'], isEmpty);
        expect(after['consumed'], isA<Map>(), reason: 'poll $i');
        expect((after['consumed']! as Map)['invite_id'], 'invite-1');
      }

      // A re-add invitation binds afresh and replaces the reported record.
      await pending.savePendingInvite(invite('invite-2', 'group-1'));
      final readd = await snapshot();
      expect(readd['pending'], hasLength(1));
      expect(readd['consumed'], isNull);
      await consume('invite-2', 'group-1');
      expect(((await snapshot())['consumed']! as Map)['invite_id'], 'invite-2');
    },
  );
}
