import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

// 183 (TC-183-20 / TC-183-09 impl leg) — the PeerLivenessProbe capability and
// its move-gated P2PServiceImpl implementation.
//
// INV-3 (interface purity): pingPeer lives on the opt-in PeerLivenessProbe
// capability, NEVER on the base P2PService — exactly like RelayPresenceSet (181)
// — so the ~31 hand-written `implements P2PService` fakes do not all have to grow
// it. Locked structurally (source-assertion) AND by a clean feature-host-all
// (TC-183-22). INV-4 (non-load-bearing): a move-gated probe returns false (never
// throws), so a migrating device never pings while ceding the account.

class _MockBridge extends Bridge {
  Map<String, dynamic> nextResponse = {'ok': true};
  final List<String> sentCmds = [];

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final cmd = (jsonDecode(message) as Map<String, dynamic>)['cmd'] as String?;
    if (cmd != null) sentCmds.add(cmd);
    return jsonEncode(nextResponse);
  }
}

/// Slice a top-level class/interface block out of [src] (decl → next top-level).
String _classBlock(String src, String startSig) {
  final start = src.indexOf(startSig);
  expect(start, isNonNegative, reason: 'expected to find: $startSig');
  final after = start + startSig.length;
  final next = RegExp(r'\n(?:abstract |enum |class |mixin )')
      .firstMatch(src.substring(after));
  final end = next == null ? src.length : after + next.start;
  return src.substring(start, end);
}

void main() {
  late _MockBridge bridge;
  late InMemoryInboxStagingRepository staging;

  setUp(() {
    flowEventLoggingEnabled = false;
    bridge = _MockBridge();
    staging = InMemoryInboxStagingRepository();
  });

  P2PServiceImpl buildService({required bool allowSideEffects}) => P2PServiceImpl(
    bridge: bridge,
    inboxStagingRepository: staging,
    accountMigrationNetworkGate: ({peerId, required operation}) async =>
        allowSideEffects,
  );

  // TC-183-20 — pingPeer is on the PeerLivenessProbe capability, NOT base
  // P2PService. Mutation: move pingPeer onto base P2PService → this fails AND the
  // ~31 fakes stop compiling (TC-183-22 / feature-host-all).
  test('TC-183-20: pingPeer is on PeerLivenessProbe, not base P2PService', () async {
    final src = await File('lib/core/services/p2p_service.dart').readAsString();

    final probeIface =
        _classBlock(src, 'abstract interface class PeerLivenessProbe {');
    expect(
      probeIface,
      contains('pingPeer'),
      reason: 'pingPeer must live on the PeerLivenessProbe capability',
    );

    final baseP2P = _classBlock(src, 'abstract class P2PService {');
    expect(
      baseP2P.contains('pingPeer'),
      isFalse,
      reason: 'hoisting pingPeer to the base P2PService interface breaks ~31 fakes',
    );
  });

  // The concrete impl opts into the capability.
  test('P2PServiceImpl implements PeerLivenessProbe', () {
    final service = buildService(allowSideEffects: true);
    addTearDown(service.dispose);
    expect(service, isA<PeerLivenessProbe>());
  });

  // TC-183-09 (impl leg) — a move-gated probe returns false (no throw, no bridge
  // call). Mutation: drop the gate → the bridge `peer:ping` would be issued.
  test('TC-183-09: pingPeer is move-gated → returns false without pinging', () async {
    final service = buildService(allowSideEffects: false);
    addTearDown(service.dispose);

    final alive = await service.pingPeer('peer-abc', timeoutMs: 4000);

    expect(alive, isFalse);
    expect(bridge.sentCmds, isNot(contains('peer:ping')),
        reason: 'a gated/migrating device must not ping');
  });

  // The ungated happy path issues `peer:ping` and reports the peer alive on ok.
  test('pingPeer issues peer:ping and returns true on ok', () async {
    bridge.nextResponse = {'ok': true, 'rttMs': 12};
    final service = buildService(allowSideEffects: true);
    addTearDown(service.dispose);

    final alive = await service.pingPeer('peer-abc', timeoutMs: 4000);

    expect(alive, isTrue);
    expect(bridge.sentCmds, contains('peer:ping'));
  });

  // A failed/unknown ping never throws — it degrades to false (a miss).
  test('pingPeer degrades a failure to false (never throws)', () async {
    bridge.nextResponse = {'ok': false, 'error': 'no route'};
    final service = buildService(allowSideEffects: true);
    addTearDown(service.dispose);

    final alive = await service.pingPeer('peer-gone', timeoutMs: 4000);
    expect(alive, isFalse);
  });
}
