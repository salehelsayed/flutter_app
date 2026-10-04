import 'dart:io';

import 'production_catalog_session.dart';

/// Shared UI membership steps for catalog journeys built on
/// [ProductionCatalogSession]: create and accept, Alice removes Charlie
/// through group info, and Alice re-adds Charlie through Add Member.
extension ProductionCatalogMembershipSteps on ProductionCatalogSession {
  /// The run group name the catalog controls observe.
  String catalogName(String scenario) => 'Catalog $scenario ${journey.runId}';

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
      // A re-add that went through despite a slow or failed flow leaves
      // Charlie a pending invitation; a user would not invite him again.
      () async =>
          ((await actors['charlie']!.command(
                    'catalog_pending_snapshot',
                  ))['pending']
                  as List)
              .isNotEmpty,
    );
    proof['aliceReadded'] = await snap('alice');
    if (accept) await acceptReadd(name);
  }

  /// Charlie returns to the home tabs and accepts the re-add invitation, then
  /// all three settle on the 3-member group.
  ///
  /// Only the [online] roles are waited on (an offline role settles later).
  Future<void> acceptReadd(
    String name, {
    List<String> online = const ['alice', 'bob', 'charlie'],
  }) async {
    await flow('charlie', 'production_home_tabs', 'charlie-home');
    await invitedAndAccept('charlie', 'accept-charlie-readd', name);
    for (final role in online) {
      await settled(role, 3);
    }
  }

  /// Alice adds Dana through Add Member (flow label `add-dana`) and records
  /// `aliceAddedDana`. Dana may be offline: the edit counts as applied once
  /// Alice's own roster lists her.
  Future<void> addDana() async {
    await membershipEdit(
      'alice',
      'add-dana',
      'production_group_info_add_member',
      'production_group_info_add_member_retry',
      {'CONTACT_NAME': 'Journeydana'},
      () async => ProductionCatalogSession.members(
        await snap('alice'),
      ).contains(peers['dana']),
    );
    proof['aliceAddedDana'] = await snap('alice');
  }

  /// Dana observes her one pending invitation (`danaPending`) while she has
  /// no group yet (`danaBeforeAccept`), accepts it (flow label
  /// `accept-dana`) and every role in [online] settles on 4 members.
  Future<void> acceptDana(
    String name, {
    List<String> online = const ['alice', 'bob', 'charlie', 'dana'],
  }) async {
    proof['danaPending'] = await wait(
      'dana',
      'catalog_pending_snapshot',
      'dana pending invitation',
      (s) => (s['pending'] as List).length == 1,
    );
    proof['danaBeforeAccept'] = await snap('dana');
    await invitedAndAccept('dana', 'accept-dana', name);
    for (final role in online) {
      await settled(role, 4);
    }
    proof['danaAccepted'] = await snap('dana');
    await persist();
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

  /// Takes [role] offline by a verified owned-process death; records whether
  /// the death was verified under proof key [label].
  Future<void> takeOffline(String role, String label) async {
    await journey.killOwnedProcess(actors[role]!);
    proof[label] = File(
      '${output.path}/${actors[role]!.invocation.nonce}-process-death.json',
    ).existsSync();
    await persist();
  }

  /// Brings [role] back with an ordinary relaunch of the same install.
  Future<void> bringOnline(String role) async {
    replace(role, await journey.reopen(actors[role]!));
    await persist();
  }
}
