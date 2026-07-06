import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';

import 'fake_bridge.dart';

// FDC-09 §12 / CV-14 (217 §A3 / A06) — callP2PInboxStore attaches the
// recipient-issued wake-token when present, and omits the key entirely (byte-
// identical to the pre-FDC-09 frame, NET-REL-07) when absent/empty.
void main() {
  Map<String, dynamic> _storePayload(FakeBridge bridge) {
    final sent = bridge.sentMessages
        .map((m) => jsonDecode(m) as Map<String, dynamic>)
        .firstWhere((m) => m['cmd'] == 'inbox:store');
    return sent['payload'] as Map<String, dynamic>;
  }

  test('attaches wakeToken when present', () async {
    final bridge = FakeBridge();
    bridge.responses['inbox:store'] = {'ok': true, 'stored': true};

    await callP2PInboxStore(
      bridge,
      toPeerId: 'peerB',
      message: 'hello',
      wakeToken: 'tok-for-B',
    );

    final payload = _storePayload(bridge);
    expect(payload['wakeToken'], 'tok-for-B');
  });

  test('omits wakeToken key entirely when null (NET-REL-07 byte-identity)',
      () async {
    final bridge = FakeBridge();
    bridge.responses['inbox:store'] = {'ok': true, 'stored': true};

    await callP2PInboxStore(bridge, toPeerId: 'peerB', message: 'hello');

    final payload = _storePayload(bridge);
    expect(payload.containsKey('wakeToken'), isFalse);
    // The raw frame must not contain the key at all.
    expect(bridge.sentMessages.single.contains('wakeToken'), isFalse);
  });

  test('omits wakeToken key entirely when empty string', () async {
    final bridge = FakeBridge();
    bridge.responses['inbox:store'] = {'ok': true, 'stored': true};

    await callP2PInboxStore(
      bridge,
      toPeerId: 'peerB',
      message: 'hello',
      wakeToken: '',
    );

    final payload = _storePayload(bridge);
    expect(payload.containsKey('wakeToken'), isFalse);
  });
}
