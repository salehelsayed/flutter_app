import '../../tool/sims/production_group_ml020_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';
import '../support/production_catalog_session.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.private_admin_role_transfer_delivery',
  validatorId: 'validateProductionGroupMl020',
  texts: productionMl020Texts,
  validate: validateProductionGroupMl020,
  steps: (s) async {
    final texts = productionMl020Texts(s.journey.runId);
    String text(String key) => texts[key]!.text;
    final name = s.catalogName('private_admin_role_transfer_delivery');
    final alice = s.peers['alice']!, bob = s.peers['bob']!;
    final charlie = s.peers['charlie']!;
    String? roleOf(Map<String, Object?> x, String peer) {
      for (final m in (x['memberDetails'] as List?) ?? const []) {
        if ((m as Map)['peerId'] == peer) return m['role'] as String?;
      }
      return null;
    }

    await s.createAndAcceptAll(name);

    // Alice (creator) makes Bob an admin; every roster converges.
    await s.quiet('alice');
    await s
        .flow('alice', 'production_group_info_set_role', 'alice-promotes-bob', {
          'MEMBER_PEER_ID': bob,
          'ROLE_ACTION': 'Make Admin',
          'CONFIRM_TITLE': r'Make Journeybob an admin\?',
        });
    for (final role in ['alice', 'bob', 'charlie']) {
      await s.waitWatch(
        role,
        '$role sees Bob as admin',
        (x) => roleOf(x, bob) == 'admin',
      );
    }
    s.proof['bobPromoted'] = await s.snap('alice');

    // Bob, now admin, removes Alice's admin role.
    await s.quiet('bob');
    await s.flow('bob', 'production_group_info_set_role', 'bob-demotes-alice', {
      'MEMBER_PEER_ID': alice,
      'ROLE_ACTION': 'Remove Admin',
      'CONFIRM_TITLE': r'Remove admin access from Journeyalice\?',
    });
    for (final role in ['alice', 'bob', 'charlie']) {
      await s.waitWatch(
        role,
        '$role sees Alice as writer',
        (x) => roleOf(x, alice) == 'writer',
      );
    }
    s.proof['aliceDemoted'] = await s.snap('bob');

    // Bob removes Charlie through Group Info.
    await s.membershipEdit(
      'bob',
      'remove-charlie',
      'production_catalog_remove_charlie',
      'production_catalog_remove_charlie_retry',
      {'CHARLIE_PEER_ID': charlie},
      () async => !ProductionCatalogSession.members(
        await s.snap('bob'),
      ).contains(charlie),
    );
    s.proof['bobRemovedCharlie'] = await s.snap('bob');
    await s.waitWatch(
      'alice',
      'Alice excludes Charlie',
      (x) => !ProductionCatalogSession.members(x).contains(charlie),
    );
    s.proof['charlieRemoved'] = await s.waitWatch(
      'charlie',
      'Charlie self-removed',
      (x) => x['selfMember'] == false,
    );
    // No rotation wait, as in the original: Bob (admin, not creator) and
    // Alice (creator, demoted) may not rotate, so the rekey stays deferred.
    await s.flow('bob', 'production_back_to_chat', 'bob-back-to-chat');

    await s.sendAndReceive(
      'alice',
      'alice-removed-window',
      'aliceRemovedWindowAfterDemotion',
      text('aliceRemovedWindowAfterDemotion'),
      ['bob'],
    );
    await s.sendAndReceive(
      'bob',
      'bob-removed-window',
      'bobRemovedWindowAfterAliceDemotion',
      text('bobRemovedWindowAfterAliceDemotion'),
      ['alice'],
    );
    // The original counts Charlie's plaintext copies after the window.
    await Future<void>.delayed(const Duration(seconds: 5));
    s.proof['charlieRemovedWindow'] = await s.snap('charlie');
    await s.persist();

    // Bob re-adds Charlie through Add Member; Charlie accepts.
    await s.membershipEdit(
      'bob',
      'readd-charlie',
      'production_group_info_add_member',
      'production_group_info_add_member_retry',
      {'CONTACT_NAME': 'Journeycharlie'},
      () async =>
          ((await s.actors['charlie']!.command(
                    'catalog_pending_snapshot',
                  ))['pending']
                  as List)
              .isNotEmpty,
    );
    await s.acceptReadd(name);

    for (final (role, label, key, receivers) in const [
      (
        'alice',
        'alice-after-readd',
        'aliceAfterCharlieReadd',
        ['bob', 'charlie'],
      ),
      ('bob', 'bob-after-readd', 'bobAfterCharlieReadd', ['alice', 'charlie']),
      (
        'charlie',
        'charlie-after-readd',
        'charlieAfterRoleReadd',
        ['alice', 'bob'],
      ),
    ]) {
      await s.sendAndReceive(role, label, key, text(key), receivers);
    }
  },
);
