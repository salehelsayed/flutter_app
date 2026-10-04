import '../../tool/sims/production_group_dana_add_criteria.dart';
import '../support/production_catalog_dana_add_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.private_online_add',
  validatorId: 'validateProductionGroupMl002',
  texts: productionMl002Texts,
  validate: validateProductionGroupMl002,
  steps: (s) => productionDanaAddSteps(
    s,
    scenario: 'private_online_add',
    texts: productionMl002Texts(s.journey.runId),
    offline: false,
    ml: true,
  ),
);
