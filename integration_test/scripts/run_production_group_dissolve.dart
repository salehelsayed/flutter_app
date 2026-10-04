import '../../tool/sims/production_group_dissolve_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.private_online_dissolve_convergence',
  validatorId: 'validateProductionGroupDissolve',
  texts: productionDissolveTexts,
  validate: validateProductionGroupDissolve,
  steps: (s) async {
    await s.createAndAcceptAll(
      s.catalogName('private_online_dissolve_convergence'),
    );
    // The original resolves the binding the dissolve will sign beforehand.
    s.proof['aliceBinding'] = await s.actors['alice']!.command(
      'catalog_sender_binding',
    );
    await s.flow('alice', 'production_group_info_dissolve', 'alice-dissolve');
    for (final r in ['alice', 'bob', 'charlie']) {
      await s.waitWatch(
        r,
        '$r sees the group dissolved',
        (x) =>
            x['isDissolved'] == true &&
            (r == 'alice' ||
                ((x['dissolveTimelineTexts'] as List?) ?? const []).isNotEmpty),
      );
    }
  },
);
