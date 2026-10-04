import '../../tool/sims/production_group_de007_criteria.dart';
import '../support/production_catalog_fallback_steps.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';

const _key = 'aliceZeroPeer';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.de007',
  validatorId: 'validateProductionGroupDe007',
  texts: productionDe007Texts,
  validate: validateProductionGroupDe007,
  steps: (s) async {
    final t = productionDe007Texts(s.journey.runId);
    final name = s.catalogName('de007');
    await s.verbatimFlow(
      'alice',
      'production_catalog_group_create_verbatim',
      'production_catalog_group_create',
      'create',
      {'GROUP_NAME': name},
    );
    // Bob and Charlie hold only the pending invitation when Alice sends.
    for (final r in ['bob', 'charlie']) {
      await s.wait(
        r,
        'catalog_pending_snapshot',
        '$r holds the invitation',
        (x) => ((x['pending'] as List?) ?? const []).isNotEmpty,
      );
      s.proof['${r}BeforeSend'] = {
        ...await s.actors[r]!.command('catalog_pending_snapshot'),
        'group': (await s.actors[r]!.command('catalog_group_snapshot'))['group'],
      };
    }
    await s.verbatimSend('alice', 'alice-zero-peer', t[_key]!.text);
    await s.ownRowSent('alice', _key);
    await s.invitedAndAccept('bob', 'accept-bob', name);
    await s.invitedAndAccept('charlie', 'accept-charlie', name);
    for (final r in ['alice', 'bob', 'charlie']) {
      await s.settled(r, 3);
    }
    for (final r in ['bob', 'charlie']) {
      await s.receivedOnce(r, _key);
    }
  },
);
