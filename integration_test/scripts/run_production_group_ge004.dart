import '../../tool/sims/production_group_ge004_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.ge004',
  validatorId: 'validateProductionGroupGe004',
  texts: productionGe004Texts,
  validate: validateProductionGroupGe004,
  steps: (s) async {
    final texts = productionGe004Texts(s.journey.runId);
    final name = s.catalogName('ge004');
    await s.createAndAcceptAll(name);
    await s.removeCharlie();
    await s.rotatedForRemainingPair();
    await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
    await s.readdCharlie(name);
    for (final (role, key, receivers) in const [
      ('alice', 'aliceGe004PostReadd', ['bob', 'charlie']),
      ('bob', 'bobGe004PostReadd', ['alice', 'charlie']),
      ('charlie', 'charlieGe004PostReadd', ['alice', 'bob']),
    ]) {
      await s.sendAndReceive(
        role,
        '$role-after-readd',
        key,
        texts[key]!.text,
        receivers,
      );
    }
  },
);
