import '../../tool/sims/production_group_dana_add_criteria.dart';
import '../support/production_catalog_dana_add_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.gm003',
  validatorId: 'validateProductionGroupGm003',
  texts: productionGm003Texts,
  validate: validateProductionGroupGm003,
  steps: (s) => productionDanaAddSteps(
    s,
    scenario: 'gm003',
    texts: productionGm003Texts(s.journey.runId),
    offline: true,
    ml: false,
  ),
);
