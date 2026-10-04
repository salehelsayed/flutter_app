import '../../tool/sims/production_group_dana_add_criteria.dart';
import '../support/production_catalog_dana_add_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.private_offline_add',
  validatorId: 'validateProductionGroupMl003',
  texts: productionMl003Texts,
  validate: validateProductionGroupMl003,
  steps: (s) => productionDanaAddSteps(
    s,
    scenario: 'private_offline_add',
    texts: productionMl003Texts(s.journey.runId),
    offline: true,
    ml: true,
  ),
);
