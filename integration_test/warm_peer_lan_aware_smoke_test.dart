// FDC-04 — LAN-aware eager warm: warm-then-send transport smoke (TC-04-15).
//
// HOST-FAKE smoke (no device): proves the warm→send authority wiring — a
// same-WiFi peer with a warmed authenticated DIRECT connection reuses that
// stream instead of letting an unauthenticated LAN write settle delivery.
// Registered in TRANSPORT_TESTS +
// the reliability discovery classifier.
//
//   flutter test integration_test/warm_peer_lan_aware_smoke_test.dart

@Tags(['smoke'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;

import '../test/core/bridge/fake_bridge.dart';
import '../test/shared/fakes/fake_p2p_network.dart';
import '../test/shared/fakes/fake_p2p_service_integration.dart';
import '../test/shared/fakes/in_memory_message_repository.dart';

void main() {
  group('FDC-04 warm-then-LAN-send smoke (TC-04-15, host-fake)', () {
    test('TC-04-15: warm then LAN-visible send reuses the authenticated direct '
        'connection', () async {
      final network = FakeP2PNetwork();
      // The target is registered on the network (so the LAN leg actually
      // delivers) AND seeded as same-WiFi on the sender AND already has a
      // warmed DIRECT connection. Authenticated reuse is authoritative and
      // completes before the LAN race is constructed.
      FakeP2PService(peerId: 'target-peer', network: network);
      final sender = FakeP2PService(peerId: 'sender-peer', network: network)
        ..localPeers.add('target-peer') // same-WiFi (LAN-visible)
        ..testConnections.add(
          const p2p.ConnectionState(
            peerId: 'target-peer',
            multiaddrs: ['/ip4/192.168.1.20/tcp/4001'], // a warmed DIRECT conn
            direction: 'outbound',
            status: 'connected',
          ),
        );
      final messageRepo = InMemoryMessageRepository();

      // Eager warm overlaps connection setup with reading/typing.
      await sender.warmPeer('target-peer');

      final (result, message) = await sendChatMessage(
        p2pService: sender,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'warm then lan',
        senderPeerId: 'sender-peer',
        senderUsername: 'Sender',
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: 'recipient-mlkem-public-key',
      );

      expect(result, SendChatMessageResult.success);
      expect(message, isNotNull);
      expect(message!.transport, 'direct');
      expect(sender.localSendCallCount, 0);
    });
  });
}
