import '../../tool/sims/production_group_voluntary_leave_criteria.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_runner.dart';
import '../support/production_catalog_session.dart';
import '../support/production_journey_peer.dart';

Future<void> main(List<String> arguments) => runProductionCatalogJourney(
  arguments: arguments,
  capability: 'production.group_catalog.private_voluntary_leave_convergence',
  validatorId: 'validateProductionGroupVoluntaryLeave',
  texts: productionVoluntaryLeaveTexts,
  validate: validateProductionGroupVoluntaryLeave,
  steps: (s) async {
    await s.createAndAcceptAll(
      s.catalogName('private_voluntary_leave_convergence'),
    );
    for (final r in ['alice', 'bob', 'charlie']) {
      s.proof['${r}Before'] = await s.snap(r);
    }
    final groupId = (s.proof['charlieBefore']! as Map)['groupId'] as String;
    Future<Map<String, Object?>> exitState() => s.actors['charlie']!.command(
      'catalog_exit_snapshot',
      {'groupId': groupId},
    );
    s.proof['charlieExitBefore'] = await exitState();
    // An ordinary reopen lands Charlie on Orbit's Inner Circle view, where
    // the group row and his two friends (Alice and Bob) are listed.
    s.replace('charlie', await s.journey.reopen(s.actors['charlie']!));
    await s.flow('charlie', 'production_orbit_group_leave_delete', 'charlie-leave-delete', {
      'GROUP_ID': groupId,
      'ALICE_PEER_ID': s.peers['alice']!,
      'CHARLIE_PEER_ID': s.peers['bob']!,
    });
    await s.waitWatch(
      'charlie',
      'Charlie deleted the group',
      (x) => x['groupPresent'] == false,
    );
    s.proof['charlieExitAfter'] = await waitForProductionObservation(
      'Charlie exit cleanup',
      const Duration(minutes: 2),
      () async {
        final x = await exitState();
        return x['intentPresent'] == false &&
                (x['pendingBroadcastIds'] as List).isEmpty
            ? x
            : null;
      },
    );
    final aliceEpoch = (s.proof['aliceBefore']! as Map)['keyEpoch'] as int;
    final rotated = await s.waitWatch(
      'alice',
      'Alice re-keyed without Charlie',
      (x) =>
          !ProductionCatalogSession.members(x).contains(s.peers['charlie']) &&
          (x['keyEpoch'] as int) > aliceEpoch,
    );
    await s.waitWatch(
      'bob',
      'Bob converged without Charlie',
      (x) =>
          !ProductionCatalogSession.members(x).contains(s.peers['charlie']) &&
          x['keyEpoch'] == rotated['keyEpoch'],
    );
    // The original receivers' settle before their final observation.
    await Future<void>.delayed(const Duration(seconds: 5));
  },
);
