import '../../tool/sims/production_group_ge008_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';
import '../support/production_catalog_session.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.ge008',
  validatorId: 'validateProductionGroupGe008',
  texts: productionGe008Texts,
  validate: validateProductionGroupGe008,
  steps: (s) async {
    final t = productionGe008Texts(s.journey.runId);
    final name = s.catalogName('ge008');
    const everyone = ['alice', 'bob', 'charlie'];

    // One phase: every send back to back, then every receipt.
    Future<void> storm(String phase, List<String> senders, List<String> to) async {
      final keys = productionGe008Keys(phase, senders);
      for (final k in keys) {
        await s.verbatimSend(t[k]!.role, 'send-$k', t[k]!.text);
      }
      for (final k in keys) {
        for (final r in to.where((r) => r != t[k]!.role)) {
          await s.waitWatch(
            r,
            '$r receives $k',
            (x) => ProductionCatalogSession.rows(x, k) == 1,
          );
          s.proof['got:$k:$r'] = await s.snap(r);
        }
      }
      // The original receivers' two-second duplicate-settlement window.
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    await s.createAndAcceptAll(name);
    await storm('pre', everyone, everyone);
    await s.removeCharlie();
    await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
    await storm('removed', const ['alice', 'bob'], const ['alice', 'bob']);
    for (final k in ['charlieGe008RemovedStale0', 'charlieGe008RemovedStale1']) {
      s.proof['charlieRejected:$k'] = await s.actors['charlie']!.command(
        'catalog_attempt_removed_send',
        {'key': k, 'text': t[k]!.text},
      );
    }
    // The original's five-second window before counting Charlie's rows.
    await Future<void>.delayed(const Duration(seconds: 5));
    s.proof['charlieRemovedWindow'] = await s.snap('charlie');
    await s.readdCharlie(name);
    await storm('post', everyone, everyone);
  },
);
