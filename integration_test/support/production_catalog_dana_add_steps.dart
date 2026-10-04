import '../../tool/sims/production_catalog_case.dart';
import 'production_catalog_fallback_steps.dart';
import 'production_catalog_membership_steps.dart';
import 'production_catalog_session.dart';

/// The four-person add cases (gm002, ML-002, gm003, ML-003): Alice creates
/// the group with Bob and Charlie through the UI, then adds Dana through Add
/// Member. Online cases add Dana while her app runs; offline cases add her
/// after a verified process death and relaunch her once the post-add sends
/// are done, as the original's late launch does. Milestones are recorded in
/// order under `order` for the adapters.
Future<void> productionDanaAddSteps(
  ProductionCatalogSession s, {
  required String scenario,
  required Map<String, ProductionCatalogText> texts,
  required bool offline,
  required bool ml,
}) async {
  final order = <String>[];
  s.proof['order'] = order;
  Future<void> mark(String milestone) async {
    order.add(milestone);
    await s.persist();
  }

  String text(String key) => texts[key]!.text;
  final name = s.catalogName(scenario);
  await s.createAndAcceptAll(name);

  if (!offline) {
    s.proof['aliceBeforeAdd'] = await s.snap('alice');
    await s.addDana();
    await mark('add-dana');
    await s.acceptDana(name);
    await mark('accept-dana');
    // Dana's topic mesh forms before the post-join sends, so live receipt
    // (ML-002 `liveOnly`) is observable rather than an inbox catch-up.
    await Future<void>.delayed(productionCatalogMeshSettle);
    await s.sendAndReceive(
      'alice',
      'alice-after-add',
      'aliceAfterDanaAdd',
      text('aliceAfterDanaAdd'),
      ['bob', 'charlie', 'dana'],
    );
    if (ml) {
      await s.sendAndReceive(
        'bob',
        'bob-after-add',
        'bobAfterDanaAdd',
        text('bobAfterDanaAdd'),
        ['alice', 'charlie', 'dana'],
      );
    }
    await s.sendAndReceive(
      'dana',
      'dana-after-join',
      'danaAfterJoin',
      text('danaAfterJoin'),
      ['alice', 'bob', 'charlie'],
    );
    return;
  }

  await s.sendAndReceive(
    'alice',
    'alice-before-add',
    'aliceBeforeDanaAdd',
    text('aliceBeforeDanaAdd'),
    ['bob', 'charlie'],
  );
  await s.takeOffline('dana', 'dana-offline');
  await mark('dana-offline');
  await s.addDana();
  await mark('add-dana');
  if (ml) {
    s.proof['bobBeforeSend'] = await s.waitWatch(
      'bob',
      'Bob sees Dana in the group',
      (x) => ProductionCatalogSession.members(x).contains(s.peers['dana']),
    );
  }
  await s.sendAndReceive(
    'alice',
    'alice-after-add',
    'aliceAfterDanaOfflineAdd',
    text('aliceAfterDanaOfflineAdd'),
    ['bob', 'charlie'],
  );
  await mark('alice-after-add');
  if (ml) {
    await s.sendAndReceive(
      'bob',
      'bob-after-add',
      'bobAfterDanaOfflineAdd',
      text('bobAfterDanaOfflineAdd'),
      ['alice', 'charlie'],
    );
    await mark('bob-after-add');
  }
  await s.bringOnline('dana');
  await mark('dana-online');
  await s.acceptDana(name, online: const ['alice', 'bob', 'charlie', 'dana']);
  await mark('accept-dana');
  for (final key in [
    'aliceAfterDanaOfflineAdd',
    if (ml) 'bobAfterDanaOfflineAdd',
  ]) {
    await s.waitWatch(
      'dana',
      'dana catches up on $key',
      (x) => ProductionCatalogSession.rows(x, key) == 1,
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    s.proof['got:$key:dana'] = await s.snap('dana');
  }
  await mark('dana-caught-up');
  if (ml) {
    await Future<void>.delayed(productionCatalogMeshSettle);
    await s.sendAndReceive(
      'alice',
      'alice-live-after-drain',
      'aliceLiveAfterDanaDrain',
      text('aliceLiveAfterDanaDrain'),
      ['dana'],
    );
    await mark('alice-live-after-drain');
    return;
  }
  await s.sendAndReceive(
    'dana',
    'dana-after-join',
    'danaAfterOfflineJoin',
    text('danaAfterOfflineJoin'),
    ['alice', 'bob', 'charlie'],
  );
}
