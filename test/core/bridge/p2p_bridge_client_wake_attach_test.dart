import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';

import 'fake_bridge.dart';

// FDC-09 §12 / CV-14 (217 §A3 / A06) — callP2PInboxStore attaches the
// recipient-issued wake-token when present, and omits the key entirely (byte-
// identical to the pre-FDC-09 frame, NET-REL-07) when absent/empty.
void main() {
  Map<String, dynamic> storePayload(FakeBridge bridge) {
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

    final payload = storePayload(bridge);
    expect(payload['wakeToken'], 'tok-for-B');
  });

  test(
    'omits wakeToken key entirely when null (NET-REL-07 byte-identity)',
    () async {
      final bridge = FakeBridge();
      bridge.responses['inbox:store'] = {'ok': true, 'stored': true};

      await callP2PInboxStore(bridge, toPeerId: 'peerB', message: 'hello');

      final payload = storePayload(bridge);
      expect(payload.containsKey('wakeToken'), isFalse);
      // The raw frame must not contain the key at all.
      expect(bridge.sentMessages.single.contains('wakeToken'), isFalse);
    },
  );

  test('omits wakeToken key entirely when empty string', () async {
    final bridge = FakeBridge();
    bridge.responses['inbox:store'] = {'ok': true, 'stored': true};

    await callP2PInboxStore(
      bridge,
      toPeerId: 'peerB',
      message: 'hello',
      wakeToken: '',
    );

    final payload = storePayload(bridge);
    expect(payload.containsKey('wakeToken'), isFalse);
  });

  test(
    'notification suppression preserves exact STORE bytes and custody fields',
    () async {
      final bridge = FakeBridge();
      bridge.responses['inbox:store'] = {'ok': true, 'stored': true};
      const envelope =
          ' { "messageId": "historic-message", '
          '"ciphertext": "AQIDBA==" }\n';

      await callP2PInboxStore(
        bridge,
        toPeerId: 'peerB',
        message: envelope,
        timeoutMs: 5000,
        wakeToken: 'tok-for-B',
        suppressNotification: true,
        custodyContract: 'ack_or_expiry_v1',
        custodyKind: 'direct_text_v108',
        custodyExpiresAtOrBeforeMs: 2000000123456,
      );

      expect(storePayload(bridge), <String, dynamic>{
        'toPeerId': 'peerB',
        'message': envelope,
        'timeoutMs': 5000,
        'wakeToken': 'tok-for-B',
        'suppressNotification': true,
        'custodyContract': 'ack_or_expiry_v1',
        'custodyKind': 'direct_text_v108',
        'custodyExpiresAtOrBeforeMs': 2000000123456,
      });
    },
  );

  test(
    'false and absent suppression preserve the legacy STORE frame',
    () async {
      final absent = FakeBridge();
      final explicitFalse = FakeBridge();
      absent.responses['inbox:store'] = {'ok': true, 'stored': true};
      explicitFalse.responses['inbox:store'] = {'ok': true, 'stored': true};

      await callP2PInboxStore(absent, toPeerId: 'peerB', message: 'hello');
      await callP2PInboxStore(
        explicitFalse,
        toPeerId: 'peerB',
        message: 'hello',
        suppressNotification: false,
      );

      expect(explicitFalse.sentMessages.single, absent.sentMessages.single);
      expect(
        storePayload(explicitFalse).containsKey('suppressNotification'),
        isFalse,
      );
    },
  );
}
