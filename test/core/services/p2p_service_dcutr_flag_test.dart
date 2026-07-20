import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

/// FDC-12 TC-12-10 — the EnableDcutrUpgrade flag plumbs through the feature-flags
/// map handed to the Go bridge `node:start`, defaulting OFF (there is no Dart
/// NodeConfig class — flags travel as a JSON map). The Go half
/// (DefaultFeatureFlags().EnableDcutrUpgrade == false + NodeConfig plumb) lives
/// in dcutr_upgrade_flag_test.go.
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
    'FDC-12 TC-12-10: enableDcutrUpgrade defaults to false in the feature-flags '
    'map handed to the Go bridge node:start',
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
        flags.containsKey('enableDcutrUpgrade'),
        isTrue,
        reason: 'the FDC-12 flag must be plumbed through the feature-flags map',
      );
      expect(
        flags['enableDcutrUpgrade'],
        false,
        reason: 'default-off until the DCUtR device campaign is GREEN',
      );
    },
  );

  test(
    'FDC-12 TC-12-10b: defaultResilienceFeatureFlags includes '
    'enableDcutrUpgrade:false',
    () {
      final flags = defaultResilienceFeatureFlags();
      expect(flags.containsKey('enableDcutrUpgrade'), isTrue);
      expect(flags['enableDcutrUpgrade'], false);
    },
  );
}
