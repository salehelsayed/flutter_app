import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../../shared/fixtures/media_bytes.dart';
import '../local_discovery/fake_local_p2p_service.dart';

/// FDC-15 — Dart send leg + the NEW `hasNonCircuitDirectConn` predicate.
///
/// The libp2p-LAN leg streams the SAME ciphertext over a direct conn IN ADDITION
/// to the WS leg, gated by the round-tripped `enableLibp2pLANMedia` flag AND a
/// non-circuit direct conn. The relay-CDN upload stays unconditional at the
/// caller (preserved — the 112-P2.4 guard).

const _directQuicAddr = '/ip4/192.168.1.55/udp/4001/quic-v1';
const _circuitAddr = '/dns4/relay.example/tcp/4001/p2p/relay-peer/p2p-circuit';

class _FakeBridge extends Bridge {
  final Map<String, FutureOr<String> Function(Map<String, dynamic>?)>
  _handlers = {};
  final List<Map<String, dynamic>> lanMediaSends = [];
  final List<String> commandsSent = [];
  bool _initialized = false;

  void whenCommand(
    String cmd,
    FutureOr<String> Function(Map<String, dynamic>?) handler,
  ) {
    _handlers[cmd] = handler;
  }

  @override
  bool get isInitialized => _initialized;
  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final cmd = request['cmd'] as String;
    final payload = request['payload'] as Map<String, dynamic>?;
    commandsSent.add(cmd);
    if (cmd == 'media:lan_send' && payload != null) {
      lanMediaSends.add(payload);
    }
    final handler = _handlers[cmd];
    if (handler != null) {
      return await handler(payload);
    }
    return jsonEncode({
      'ok': false,
      'errorCode': 'UNHANDLED',
      'errorMessage': 'no handler for $cmd',
    });
  }
}

void main() {
  late _FakeBridge bridge;
  late FakeLocalP2PService localP2P;
  late P2PServiceImpl service;

  setUp(() {
    bridge = _FakeBridge();
    localP2P = FakeLocalP2PService()..sendWillSucceed = true;
    bridge.whenCommand(
      'inbox:ack',
      (_) => jsonEncode({'ok': true, 'acked': 1}),
    );
    bridge.whenCommand(
      'media:lan_send',
      (_) => jsonEncode({
        'ok': true,
        'acked': true,
        'sha256Verified': true,
        'transport': 'direct',
      }),
    );
    bridge.whenCommand(
      'media:upload',
      (p) => jsonEncode({'ok': true, 'id': p?['id'] ?? 'blob'}),
    );
    service = P2PServiceImpl(
      bridge: bridge,
      localP2PService: localP2P,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
  });

  tearDown(() => service.dispose());

  Future<void> startNode({required bool flagOn}) async {
    bridge.whenCommand(
      'node:start',
      (_) => jsonEncode({
        'ok': true,
        'peerId': 'self-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
        'featureFlags': {'enableLibp2pLANMedia': flagOn},
      }),
    );
    await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
  }

  void connect(String peerId, List<String> multiaddrs) {
    bridge.onPeerConnected?.call(
      p2p.ConnectionState(
        peerId: peerId,
        multiaddrs: multiaddrs,
        direction: 'outbound',
        status: 'connected',
      ),
    );
  }

  Future<bool> sendCipher(String peerId, {String path = '/tmp/cipher-1.enc'}) {
    return service.sendLocalMedia(
      peerId: peerId,
      filePath: path,
      mime: kOpaqueMediaTransportMime,
      mediaId: 'm1',
      fromPeerId: 'self-peer',
      enc: true,
      encScheme: 'blob-aes-gcm-v1',
    );
  }

  // --- TD1 -----------------------------------------------------------------

  test('TD1: flag ON + non-circuit direct conn ⇒ libp2p-LAN leg invoked with '
      'the ciphertext path', () async {
    await startNode(flagOn: true);
    connect('peer-1', const [_directQuicAddr]);

    final ok = await sendCipher('peer-1', path: '/tmp/cipher-1.enc');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(bridge.lanMediaSends, hasLength(1));
    final p = bridge.lanMediaSends.single;
    expect(p['filePath'], '/tmp/cipher-1.enc');
    expect(p['id'], 'm1');
    expect(p['to'], 'peer-1');
    expect(p['mime'], kOpaqueMediaTransportMime);
    // The WS leg still ran (additive) — sendLocalMedia returns its result.
    expect(ok, isTrue);
  });

  // --- TD2 (relay-CDN stays unconditional — leg cannot gate downstream) -----

  test('TD2: a FAILING libp2p-LAN leg never changes sendLocalMedia outcome '
      '(relay-CDN upload stays unconditional at the caller)', () async {
    await startNode(flagOn: true);
    bridge.whenCommand('media:lan_send', (_) => throw Exception('leg boom'));
    connect('peer-1', const [_directQuicAddr]);

    final ok = await sendCipher('peer-1');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // WS leg result is unaffected by the failed acceleration leg → the caller
    // proceeds to its unconditional uploadMedia exactly as before.
    expect(ok, isTrue);
  });

  // --- TD3 (flag OFF) ------------------------------------------------------

  test('TD3: flag OFF ⇒ no libp2p-LAN leg; WS path unchanged', () async {
    await startNode(flagOn: false);
    connect('peer-1', const [_directQuicAddr]);

    final ok = await sendCipher('peer-1');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(bridge.lanMediaSends, isEmpty);
    expect(ok, isTrue); // WS leg still ran
  });

  // --- TD4 (no direct conn) ------------------------------------------------

  test('TD4: peer only circuit/relay-connected ⇒ no libp2p-LAN leg', () async {
    await startNode(flagOn: true);
    connect('peer-1', const [_circuitAddr]); // circuit only

    await sendCipher('peer-1');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(bridge.lanMediaSends, isEmpty);
  });

  // --- TD5 (ciphertext only) -----------------------------------------------

  test('TD5: the leg streams the ciphertext artifact path + opaque mime, never '
      'a plaintext source', () async {
    await startNode(flagOn: true);
    connect('peer-1', const [_directQuicAddr]);

    await sendCipher('peer-1', path: '/tmp/artifact-ciphertext.enc');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(bridge.lanMediaSends, hasLength(1));
    expect(
      bridge.lanMediaSends.single['filePath'],
      '/tmp/artifact-ciphertext.enc',
    );
    expect(bridge.lanMediaSends.single['mime'], kOpaqueMediaTransportMime);
  });

  test('TD5b: a NON-enc (plaintext) send never fires the libp2p-LAN leg '
      '(fail-closed gate)', () async {
    await startNode(flagOn: true);
    connect('peer-1', const [_directQuicAddr]);

    // enc:false ⇒ filePath would be a plaintext source — the leg must NOT fire.
    await service.sendLocalMedia(
      peerId: 'peer-1',
      filePath: '/tmp/plaintext-source.jpg',
      mime: 'image/jpeg',
      mediaId: 'm-plain',
      fromPeerId: 'self-peer',
      enc: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(bridge.lanMediaSends, isEmpty);
  });

  // --- TD7 (predicate unit) ------------------------------------------------

  test('TD7: hasNonCircuitDirectConn is true iff a non-/p2p-circuit conn exists '
      '(coexisting circuit+direct ⇒ true — the FDC-15 window)', () async {
    await startNode(flagOn: true);

    // (a) only a circuit conn → false.
    connect('a', const [_circuitAddr]);
    expect(service.hasNonCircuitDirectConn('a'), isFalse);

    // (b) only a direct conn → true.
    connect('b', const [_directQuicAddr]);
    expect(service.hasNonCircuitDirectConn('b'), isTrue);

    // (c) a circuit AND a direct addr coexist on the peer → true. This is the
    // representation that traps _inferTransportForPeer (it short-circuits to
    // 'relay' on the first /p2p-circuit addr) — the predicate must NOT reuse it.
    connect('c', const [_circuitAddr, _directQuicAddr]);
    expect(service.hasNonCircuitDirectConn('c'), isTrue);

    // (d) not connected at all → false.
    expect(service.hasNonCircuitDirectConn('d'), isFalse);
  });

  // --- TD6 (group scope lock) ----------------------------------------------

  test('TD6: group media (allowedPeers) is relay-CDN only — never the '
      'libp2p-LAN leg', () async {
    await startNode(flagOn: true);

    final dir = await Directory.systemTemp.createTemp('fdc15-td6-');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/group.jpg');
    await source.writeAsBytes(validJpegFixtureBytes);
    final cipher = File('${dir.path}/group.enc');
    await cipher.writeAsString('opaque-group-ciphertext');
    final artifact = EncryptedMediaArtifact(
      encryptedPath: cipher.path,
      keyBase64: 'key',
      nonce: 'nonce',
      scheme: 'blob-aes-gcm-v1',
      contentHash: 'deadbeef',
      plaintextSize: 23,
    );

    await uploadMedia(
      bridge: bridge,
      localFilePath: '${dir.path}/group.jpg',
      mime: 'image/jpeg',
      recipientPeerId: 'group-rendezvous',
      allowedPeers: const ['member-1', 'member-2'], // GROUP upload
      preparedArtifact: artifact,
      blobId: 'group-blob-0001',
    );

    // The group path issues a relay-CDN upload and NEVER the libp2p-LAN leg.
    expect(bridge.commandsSent, contains('media:upload'));
    expect(bridge.lanMediaSends, isEmpty);
  });
}
