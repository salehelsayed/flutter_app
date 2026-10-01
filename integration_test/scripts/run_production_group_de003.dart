import '../../tool/sims/production_group_send_cases_criteria.dart';
import '../support/production_catalog_send_journey.dart';

Future<void> main(List<String> arguments) => runProductionCatalogSendJourney(
  arguments: arguments,
  capability: 'production.group_catalog.de003',
  validatorId: 'validateProductionGroupDe003',
  steps: productionDe003Steps,
  validate: validateProductionGroupDe003,
  // The original receivers run one explicit catch-up drain after receipt;
  // the final snapshot then counts the rows for the same message id.
  after: (s) async {
    for (final role in ['bob', 'charlie']) {
      s.proof['deReplay:$role'] = await s.actors[role]!.command(
        'catalog_drain_once',
      );
    }
  },
);
