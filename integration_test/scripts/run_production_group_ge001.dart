import '../../tool/sims/production_group_send_cases_criteria.dart';
import '../support/production_catalog_send_journey.dart';

Future<void> main(List<String> arguments) => runProductionCatalogSendJourney(
  arguments: arguments,
  capability: 'production.group_catalog.ge001',
  validatorId: 'validateProductionGroupGe001',
  steps: productionGe001Steps,
  validate: validateProductionGroupGe001,
);
