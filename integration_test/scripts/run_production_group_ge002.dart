import '../../tool/sims/production_group_removal_pair_criteria.dart';
import '../support/production_catalog_removal_pair_journey.dart';

Future<void> main(List<String> arguments) => runProductionRemovalPairJourney(
  arguments: arguments,
  removalCase: productionGe002Case,
  validatorId: 'validateProductionGroupGe002',
);
