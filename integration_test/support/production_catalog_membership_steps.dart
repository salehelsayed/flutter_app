import 'production_catalog_session.dart';

/// Shared UI membership steps for catalog journeys built on
/// [ProductionCatalogSession]: create and accept, Alice removes Charlie
/// through group info, and Alice re-adds Charlie through Add Member.
extension ProductionCatalogMembershipSteps on ProductionCatalogSession {
  /// The run group name the catalog controls observe.
  String catalogName(String scenario) =>
      'Catalog $scenario ${journey.runId}';

  /// UI creation by Alice, then Bob's and Charlie's acceptance, until all
  /// three see the 3-member group; then the original's five-second settle.
  Future<void> createAndAcceptAll(String name) async {
    await verbatimFlow(
      'alice',
      'production_catalog_group_create_verbatim',
      'production_catalog_group_create',
      'create',
      {'GROUP_NAME': name},
    );
    await invitedAndAccept('bob', 'accept-bob', name);
    await invitedAndAccept('charlie', 'accept-charlie', name);
    for (final role in ['alice', 'bob', 'charlie']) {
      await settled(role, 3);
    }
    await Future<void>.delayed(const Duration(seconds: 5));
  }

  /// Alice removes Charlie through group info (flow label `remove-charlie`)
  /// and records her snapshot as `aliceRemoved`. With [waitApplied], waits
  /// until Bob excludes Charlie and Charlie applies his own removal.
  Future<void> removeCharlie({bool waitApplied = true}) async {
    await membershipEdit(
      'alice',
      'remove-charlie',
      'production_catalog_remove_charlie',
      'production_catalog_remove_charlie_retry',
      {'CHARLIE_PEER_ID': peers['charlie']!},
      () async => !ProductionCatalogSession.members(
        await snap('alice'),
      ).contains(peers['charlie']),
    );
    proof['aliceRemoved'] = await snap('alice');
    if (!waitApplied) return;
    proof['bobExcluded'] = await waitWatch(
      'bob',
      'Bob excludes Charlie',
      (x) => !ProductionCatalogSession.members(x).contains(peers['charlie']),
    );
    proof['charlieRemoved'] = await waitWatch(
      'charlie',
      'Charlie self-removed',
      (x) => x['selfMember'] == false,
    );
  }

  /// Waits until Alice rotated past epoch 1 and Bob holds the same epoch.
  Future<void> rotatedForRemainingPair() async {
    final rotated = await waitWatch(
      'alice',
      'Alice rotated epoch',
      (x) => (x['keyEpoch'] as int) >= 2,
    );
    await waitWatch(
      'bob',
      'Bob holds rotated key',
      (x) => x['keyEpoch'] == rotated['keyEpoch'],
    );
  }

  /// Alice re-adds Charlie through Add Member (flow label `readd-charlie`)
  /// and records `aliceReadded`. With [accept], Charlie returns to the home
  /// tabs, accepts the new invitation and all three settle on 3 members.
  Future<void> readdCharlie(String name, {bool accept = true}) async {
    await membershipEdit(
      'alice',
      'readd-charlie',
      'production_group_info_add_member',
      'production_group_info_add_member_retry',
      {'CONTACT_NAME': 'Journeycharlie'},
      () async => false,
    );
    proof['aliceReadded'] = await snap('alice');
    if (accept) await acceptReadd(name);
  }

  /// Charlie returns to the home tabs and accepts the re-add invitation, then
  /// all three settle on the 3-member group.
  Future<void> acceptReadd(String name) async {
    await flow('charlie', 'production_home_tabs', 'charlie-home');
    await invitedAndAccept('charlie', 'accept-charlie-readd', name);
    for (final role in ['alice', 'bob', 'charlie']) {
      await settled(role, 3);
    }
  }

  /// [role] sends [text] verbatim (flow label [label]); every role in
  /// [receivers] must then hold exactly one row for [key], recorded as
  /// `got:<key>:<role>` after the original's two-second settle.
  Future<void> sendAndReceive(
    String role,
    String label,
    String key,
    String text,
    List<String> receivers,
  ) async {
    await verbatimSend(role, label, text);
    for (final receiver in receivers) {
      await waitWatch(
        receiver,
        '$receiver receives $key',
        (x) => ProductionCatalogSession.rows(x, key) == 1,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      proof['got:$key:$receiver'] = await snap(receiver);
    }
  }
}
