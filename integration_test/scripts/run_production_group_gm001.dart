import '../../tool/sims/production_group_send_cases_criteria.dart';
import '../support/production_catalog_send_journey.dart';

Future<void> main(List<String> arguments) => runProductionCatalogSendJourney(
  arguments: arguments,
  capability: 'production.group_catalog.gm001',
  validatorId: 'validateProductionGroupGm001',
  steps: productionGm001Steps,
  validate: validateProductionGroupGm001,
);
