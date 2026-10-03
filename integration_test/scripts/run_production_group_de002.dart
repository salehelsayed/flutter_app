import '../../tool/sims/production_group_de002_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';
import '../support/production_catalog_session.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.de002',
  validatorId: 'validateProductionGroupDe002',
  texts: productionDe002Texts,
  validate: validateProductionGroupDe002,
  steps: (s) async {
    final t = productionDe002Texts(s.journey.runId);
    await s.createAndAcceptAll(s.catalogName('de002'));
    for (var i = 0; i < 100; i++) {
      await s.verbatimSend(
        'alice',
        'alice-seq-${i + 1}',
        t[productionDe002Key(i)]!.text,
      );
    }
    for (final r in ['bob', 'charlie']) {
      await s.waitWatch(
        r,
        '$r holds all 100',
        (x) => [
          for (var i = 0; i < 100; i++)
            ProductionCatalogSession.rows(x, productionDe002Key(i)),
        ].every((n) => n == 1),
        timeout: const Duration(minutes: 10),
      );
    }
  },
);
