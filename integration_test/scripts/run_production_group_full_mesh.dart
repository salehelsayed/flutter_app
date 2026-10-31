import 'dart:convert';
import 'dart:io';

import '../../tool/sims/production_group_full_mesh_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--eight-actor-scope')) {
    stdout.writeln(
      jsonEncode({
        'journeyId': 'GX-001',
        'scope': 'eight-actor every-sender/every-recipient',
        'status': 'N/A',
        'executionStatus': 'SKIP',
        'reason':
            'owner-declared eight-target topology unavailable by project policy',
        'supportedDefaultActorCount': 3,
        'discoveryPerformedByThisCommand': false,
        'nativeExecutedByThisCommand': false,
      }),
    );
    return;
  }
  await runProductionCatalogJourney(
    arguments: arguments,
    capability: 'production.group_catalog.private_full_mesh_online',
    validatorId: 'validateProductionGroupFullMesh',
    texts: productionFullMeshTexts,
    validate: validateProductionGroupFullMesh,
    steps: (s) async {
      final t = productionFullMeshTexts(s.journey.runId);
      await s.createAndAcceptAll(s.catalogName('private_full_mesh_online'));
      for (final r in ['alice', 'bob', 'charlie']) {
        await s.sendAndReceive(
          r,
          '$r-full-mesh',
          '${r}FullMesh',
          t['${r}FullMesh']!.text,
          [
            for (final o in ['alice', 'bob', 'charlie'])
              if (o != r) o,
          ],
        );
      }
    },
  );
}
