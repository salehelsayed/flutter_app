import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

/// CV-09 TC-09-02/03 — the EnableLibp2pLANDial flag (FDC-11) graduates from dark
/// to default-ON now that its D1 two-phone device-proof closed (CV-08, commit
/// 121f0551: Pixel 6 <-> iPhone 11 reached MSG_RECEIVED_TRANSPORT:"direct" both
/// directions). There is no Dart NodeConfig class — flags travel as a JSON map in
/// the `node:start` payload — so the LOAD-BEARING runtime default is the Dart
/// `defaultValue` at p2p_bridge_client.dart, NOT the Go fallback. Go applies the
/// always-sent map wholesale (config.go EffectiveFlags returns *c.FeatureFlags in
/// its entirety when non-nil), so flipping ONLY the Go default
/// (feature_flags.go DefaultFeatureFlags) is a production no-op. TC-09-02 pins the
/// value actually SERIALIZED to node:start (the anti-trap test); the matching Go
/// guard (DefaultFeatureFlags().EnableLibp2pLANDial == true) lives in
/// feature_flags_runtime_test.go. Mirrors p2p_service_dcutr_flag_test.dart.
class _PayloadCapturingBridge extends Bridge {
  Map<String, dynamic>? lastNodeStartPayload;
  bool _initialized = false;

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
    if (cmd == 'node:start') {
      lastNodeStartPayload = payload;
      return jsonEncode({
        'ok': true,
        'peerId': 'self-peer',
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      });
    }
    if (cmd == 'inbox:ack') {
      return jsonEncode({'ok': true, 'acked': 1});
    }
    return jsonEncode({
      'ok': false,
      'errorCode': 'UNHANDLED',
      'errorMessage': 'no handler for $cmd',
    });
  }
}

void main() {
  test(
    'CV-09 TC-09-02: enableLibp2pLANDial defaults to true in the feature-flags '
    'map handed to the Go bridge node:start (the value SENT, not just the Go '
    'fallback — catches the flip-only-Go trap)',
    () async {
      final bridge = _PayloadCapturingBridge();
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );
      addTearDown(service.dispose);

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

      final payload = bridge.lastNodeStartPayload;
      expect(payload, isNotNull, reason: 'node:start must be sent');
      final flags = payload!['featureFlags'] as Map<String, dynamic>;
      expect(
        flags.containsKey('enableLibp2pLANDial'),
        isTrue,
        reason: 'the FDC-11 flag must be plumbed through the feature-flags map',
      );
      expect(
        flags['enableLibp2pLANDial'],
        true,
        reason: 'default-ON after CV-08 D1 two-phone proof closed (CV-09); a '
            'profile/release build with NO --dart-define must serialize true so '
            'the Go node dials LAN-direct by default',
      );
    },
  );

  test(
    'CV-09 TC-09-03: defaultResilienceFeatureFlags includes '
    'enableLibp2pLANDial:true',
    () {
      final flags = defaultResilienceFeatureFlags();
      expect(flags.containsKey('enableLibp2pLANDial'), isTrue);
      expect(flags['enableLibp2pLANDial'], true);
    },
  );
}
