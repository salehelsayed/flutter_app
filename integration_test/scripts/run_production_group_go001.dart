import '../../tool/sims/production_group_ge010_criteria.dart';
import '../support/production_catalog_fallback_steps.dart';
import '../support/production_catalog_runner.dart';

const _key = 'aliceGe010ZeroPeerFallback';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.go001',
  validatorId: 'validateProductionGroupGo001',
  texts: productionGe010Texts,
  validate: validateProductionGroupGo001,
  steps: (s) => productionZeroPeerSteps(
    s,
    'go001',
    _key,
    productionGe010Texts(s.journey.runId)[_key]!.text,
  ),
);
