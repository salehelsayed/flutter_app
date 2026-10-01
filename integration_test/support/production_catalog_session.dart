import 'dart:convert';
import 'dart:io';

import 'production_android_journey.dart';
import 'production_journey_peer.dart';

/// Shared host-side steps for production group-catalog journeys: readiness,
/// UI flows with receipts, read-only waits, quiet-group waits, user-like
/// retries of edits refused by the app's recovery gate, verbatim proof sends,
/// invitation acceptance and verified process death with relaunch.
final class ProductionCatalogSession {
  ProductionCatalogSession(this.journey, this.output, this.proof)
    : actors = {for (final p in journey.actors) p.invocation.role: p} {
    proof['flows'] = flows;
    proof['membershipEditRetries'] = retries;
    proof['imeSwitches'] = imeSwitches;
    proof['kills'] = kills;
  }

  final ProductionAndroidJourney journey;
  final Directory output;
  final Map<String, Object?> proof;
  final Map<String, ProductionJourneyPeer> actors;
  final flows = <String>[];
  final retries = <String, Object?>{};
  final imeSwitches = <Map<String, Object?>>[];
  final kills = <String, Object?>{};
  final peers = <String, String>{};

  /// Host-named texts watched by `catalog_watch_snapshot`.
  Map<String, Object?> watch = const {};

  static const verbatimIme = 'io.appium.settings/.AppiumIME';

  Future<void> persist() => File(
    '${output.path}/observations.json',
  ).writeAsString(jsonEncode(proof));

  void replace(String role, ProductionJourneyPeer peer) {
    actors[role] = peer;
    if (role == 'alice') journey.alice = peer;
    if (role == 'bob') journey.bob = peer;
    if (journey.additionalPeers.containsKey(role)) {
      journey.additionalPeers[role] = peer;
    }
  }

  Future<void> flow(
    String role,
    String name,
    String label, [
    Map<String, String> values = const {},
  ]) async {
    await journey.flow(actors[role]!, name, label, values);
    flows.add(label);
    await persist();
  }

  Future<Map<String, Object?>> wait(
    String role,
    String operation,
    String label,
    bool Function(Map<String, Object?>) predicate, {
    Map<String, Object?> args = const {},
    Duration timeout = const Duration(seconds: 120),
  }) => waitForProductionObservation(label, timeout, () async {
    final s = await actors[role]!.command(operation, args);
    return predicate(s) ? s : null;
  });

  Future<Map<String, Object?>> snap(String role) =>
      actors[role]!.command('catalog_watch_snapshot', {'texts': watch});

  Future<Map<String, Object?>> waitWatch(
    String role,
    String label,
    bool Function(Map<String, Object?>) predicate, {
    Duration timeout = const Duration(seconds: 120),
  }) => wait(
    role,
    'catalog_watch_snapshot',
    label,
    predicate,
    args: {'texts': watch},
    timeout: timeout,
  );

  static int rows(Map<String, Object?> s, String key) =>
      (((s['watched'] as Map?)?[key] as List?) ?? const []).length;

  static List members(Map<String, Object?> s) =>
      (s['memberPeerIds'] as List?) ?? const [];

  /// Prepares, reopens every actor, requires production readiness and an
  /// empty catalog fixture, and records peers and relay addresses.
  Future<void> start() async {
    await journey.prepare();
    for (final role in actors.keys.toList()) {
      replace(role, await journey.reopen(actors[role]!));
    }
    for (final role in actors.keys) {
      final ready = await wait(
        role,
        'catalog_group_snapshot',
        '$role production readiness',
        (s) =>
            s['relayReady'] == true &&
            s['sendReady'] == true &&
            s['inboxReady'] == true &&
            s['groupRecoveryActive'] == false &&
            s['lifecycle'] == 'resumed',
      );
      final invite = await actors[role]!.command('catalog_pending_snapshot');
      if (ready['group'] != null || (invite['pending'] as List).isNotEmpty) {
        throw StateError('catalog fixture is not initially empty');
      }
      peers[role] = ready['peerId']! as String;
    }
    proof['peers'] = peers;
    proof['relayAddresses'] = (await actors['alice']!.command(
      'catalog_group_snapshot',
    ))['relayAddresses'];
    await persist();
  }

  Future<Map<String, Object?>> settled(String role, int count) => wait(
    role,
    'catalog_group_snapshot',
    '$role settled $count-member group',
    (s) =>
        s['group'] is Map &&
        ((s['group'] as Map)['members'] as List).length == count &&
        s['groupRecoveryActive'] == false &&
        s['relayReady'] == true,
  );

  /// Membership edits are refused while group recovery runs, and recovery can
  /// restart when a join is processed: require every invite attempt joined
  /// and recovery inactive for three consecutive seconds.
  Future<void> quiet(String role) async {
    var since = DateTime.now();
    await waitForProductionObservation(
      '$role quiet group',
      const Duration(minutes: 3),
      () async {
        final s = await actors[role]!.command('catalog_group_snapshot');
        final group = s['group'];
        final attempts = group is Map
            ? (group['deliveryAttempts'] as List)
            : const [];
        final calm =
            group is Map &&
            s['groupRecoveryActive'] == false &&
            attempts.every((a) => (a as Map)['status'] == 'joined');
        if (!calm) {
          since = DateTime.now();
          return null;
        }
        return DateTime.now().difference(since) >= const Duration(seconds: 3)
            ? true
            : null;
      },
    );
  }

  /// Retries an edit refused by the recovery gate the way a user would: wait
  /// for a quiet group and tap again from the same screen; at most three tries.
  Future<void> membershipEdit(
    String role,
    String label,
    String name,
    String retryName,
    Map<String, String> values,
    Future<bool> Function() applied,
  ) async {
    await quiet(role);
    for (var attempt = 1; ; attempt++) {
      try {
        await journey.flow(
          actors[role]!,
          attempt == 1 ? name : retryName,
          attempt == 1 ? label : '$label-retry$attempt',
          values,
        );
        break;
      } catch (_) {
        if (attempt >= 3 || await applied()) rethrow;
        retries[label] = attempt;
        await persist();
        await quiet(role);
      }
    }
    flows.add(label);
    await persist();
  }

  /// Keyboards autocorrect original proof texts. For this send only, switch
  /// the device to the installed Appium keyboard (verbatim, no on-screen
  /// keyboard) and restore its own keyboard immediately; without it, use the
  /// device keyboard with the same exact composer check.
  Future<void> verbatimSend(String role, String label, String text) async {
    final peer = actors[role]!;
    final values = {'MESSAGE': text, 'MESSAGE_PATTERN': RegExp.escape(text)};
    final installed = '${(await peer.adb(['shell', 'ime', 'list', '-a', '-s'])).stdout}'
        .contains(verbatimIme);
    if (!installed) {
      imeSwitches.add({'role': role, 'label': label, 'restoreTo': null});
      await flow(role, 'production_direct_send', label, values);
      return;
    }
    final original =
        '${(await peer.adb(['shell', 'settings', 'get', 'secure', 'default_input_method'])).stdout}'
            .trim();
    await peer.adb(['shell', 'ime', 'enable', verbatimIme]);
    await peer.adb(['shell', 'ime', 'set', verbatimIme]);
    imeSwitches.add({'role': role, 'label': label, 'restoreTo': original});
    try {
      await flow(role, 'production_verbatim_send', label, values);
    } finally {
      if (original.isNotEmpty && original != verbatimIme) {
        await peer.adb(['shell', 'ime', 'set', original]);
      }
    }
  }

  Future<void> invitedAndAccept(
    String role,
    String label,
    String groupName,
  ) async {
    await wait(
      role,
      'catalog_pending_snapshot',
      '$role pending invitation',
      (s) => (s['pending'] as List).length == 1,
      timeout: const Duration(minutes: 4),
    );
    await flow(role, 'production_catalog_invite_accept', label, {
      'GROUP_NAME': groupName,
    });
  }

  Future<void> killAndRecover(String role, String kill) async {
    await journey.killOwnedProcess(actors[role]!);
    kills[kill] = File(
      '${output.path}/${actors[role]!.invocation.nonce}-process-death.json',
    ).existsSync();
    replace(role, await journey.reopen(actors[role]!));
    await persist();
  }
}
