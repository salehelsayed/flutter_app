import 'dart:io';

import 'package:flutter_app/debug/production_journeys/production_group_catalog_controls.dart';
import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/fakes/in_memory_pending_group_invite_repository.dart';

void main() {
  test(
    'an accepted invitation stays observable as consumed across polls',
    () async {
      final directory = await Directory.systemTemp.createTemp('catalog-obs-');
      final invocation = SimsRuntimeInvocation(
        schema: simsRuntimeConfigSchema,
        profileId: 'android.e2e.main',
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
      Map<String, Object?> result(Map<String, Object?> r) => r;

      final now = DateTime.utc(2026, 10, 5);
      await pending.savePendingInvite(
        PendingGroupInvite(
          groupId: 'g1',
          inviteId: 'invite-1',
          payloadJson: '{}',
          groupName: productionCatalogGroupName(controller),
          groupType: GroupType.chat,
          senderPeerId: 'alice',
          senderUsername: 'Alice',
          createdBy: 'alice',
          createdAt: now,
          receivedAt: now,
          expiresAt: now.add(const Duration(days: 7)),
        ),
      );
      final bound = result(await snapshot());
      expect(bound['pending'], hasLength(1));
      expect(bound['consumed'], isNull);

      // Accepting removes the pending row; the consumption may land later.
      await pending.deletePendingInvite('g1');
      expect(result(await snapshot())['consumed'], isNull);
      await pending.saveConsumedInvite(
        GroupInviteConsumption(
          inviteId: 'invite-1',
          groupId: 'g1',
          consumedAt: now,
          expiresAt: now.add(const Duration(days: 7)),
        ),
      );
      for (var poll = 0; poll < 2; poll++) {
        final consumed = result(await snapshot());
        expect(consumed['pending'], isEmpty);
        expect(consumed['consumed'], isA<Map>(), reason: 'poll $poll');
      }
      // A later re-add invitation binds afresh and is not yet consumed.
      await pending.savePendingInvite(
        PendingGroupInvite(
          groupId: 'g1',
          inviteId: 'invite-2',
          payloadJson: '{}',
          groupName: productionCatalogGroupName(controller),
          groupType: GroupType.chat,
          senderPeerId: 'alice',
          senderUsername: 'Alice',
          createdBy: 'alice',
          createdAt: now,
          receivedAt: now,
          expiresAt: now.add(const Duration(days: 7)),
        ),
      );
      final readd = result(await snapshot());
      expect((readd['pending'] as List).single['inviteId'], 'invite-2');
      expect(readd['consumed'], isNull);
    },
  );
}
