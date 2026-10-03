import 'production_catalog_membership_steps.dart';
import 'production_catalog_session.dart';

/// How long the sender waits after a verified process death before a send
/// that must see the dead member off the live topic. A killed app sends no
/// close; its peers drop the connection once the transport notices.
const productionCatalogMeshSettle = Duration(seconds: 45);

/// Read-only steps for catalog cases where members leave the live topic by
/// verified process death and come back through the offline inbox.
extension ProductionCatalogFallbackSteps on ProductionCatalogSession {
  /// [role] waits until its own row for [key] is persisted as sent.
  Future<void> ownRowSent(String role, String key) => waitWatch(
    role,
    '$role holds $key as sent',
    (x) {
      final rows = ((x['watched'] as Map?)?[key] as List?) ?? const [];
      return rows.length == 1 && (rows.single as Map)['status'] == 'sent';
    },
  );

  /// Relaunches [role] with its own state (`<role>Relaunched`), runs one
  /// production catch-up drain (`<role>Drain`), then waits until [role]
  /// holds [key] once (`got:<key>:<role>`).
  Future<void> relaunchAndRecover(String role, String key) async {
    await bringOnline(role);
    proof['${role}Relaunched'] = await snap(role);
    proof['${role}Drain'] = await actors[role]!.command('catalog_drain_once');
    await receivedOnce(role, key);
  }

  /// Waits until [role] holds [key] once, then records `got:<key>:<role>`
  /// after the original's two-second duplicate-settlement window.
  Future<void> receivedOnce(String role, String key) async {
    await waitWatch(
      role,
      '$role receives $key',
      (x) => ProductionCatalogSession.rows(x, key) == 1,
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    proof['got:$key:$role'] = await snap(role);
  }
}

/// GE-010 / GO-001 steps: Bob and Charlie die, Alice sends with zero topic
/// peers, both relaunch and recover the message from the inbox.
Future<void> productionZeroPeerSteps(
  ProductionCatalogSession s,
  String scenario,
  String key,
  String text,
) async {
  await s.createAndAcceptAll(s.catalogName(scenario));
  for (final r in ['bob', 'charlie']) {
    s.proof['${r}BeforeOffline'] = await s.snap(r);
    await s.takeOffline(r, '${r}Offline');
  }
  await Future<void>.delayed(productionCatalogMeshSettle);
  await s.verbatimSend('alice', 'alice-zero-peer', text);
  await s.ownRowSent('alice', key);
  for (final r in ['bob', 'charlie']) {
    await s.relaunchAndRecover(r, key);
  }
}
