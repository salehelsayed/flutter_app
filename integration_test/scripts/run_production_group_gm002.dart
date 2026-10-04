import '../../tool/sims/production_group_dana_add_criteria.dart';
import '../support/production_catalog_dana_add_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.gm002',
  validatorId: 'validateProductionGroupGm002',
  texts: productionGm002Texts,
  validate: validateProductionGroupGm002,
  steps: (s) => productionDanaAddSteps(
    s,
    scenario: 'gm002',
    texts: productionGm002Texts(s.journey.runId),
    offline: false,
    ml: false,
  ),
);
