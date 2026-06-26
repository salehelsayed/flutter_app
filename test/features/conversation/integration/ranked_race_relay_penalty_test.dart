// FDC-02 Tier-2 integration: staggered relay-penalty ranked race, end-to-end
// across a SENDER and a RECEIVER (two fakes).
//
// The host fake cannot prove "the LAN/direct leg actually won on the wire"
// (FDC-00 closure caveat: a ranked-race test can pass via the parallel
// inbox/dedup copy even when the live leg never fired). So the LOAD-BEARING
// discriminator here is the SENDER's relayLiveSendCount — the thing receiver
// messageId dedup masks. The receiver is modeled as a messageId-deduping store:
// no matter how many times a message is transmitted (LAN win + an un-cancellable
// in-flight relay-live loser), the receiver holds exactly ONE row; only
// relayLiveSendCount reveals whether the staggered relay-live leg actually fired.
//
// Real-wire "live-wins" proof is deferred to /sims + a two-device smoke
// (Device/Relay Proof Profile).

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
// The local sendChatMessage wrapper (with test defaults) comes from the unit
// suite import below; hide the production entrypoints to avoid the name clash.
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart'
    hide sendChatMessage, editChatMessage;
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

// Reuse the host fakes + the sendChatMessage wrapper from the unit suite (DRY).
import '../application/send_chat_message_use_case_test.dart'
    show
        FakeP2PService,
        DurableLanFakeP2PService,
        FakeMessageRepository,
        sendChatMessage;
import '../domain/repositories/fake_media_attachment_repository.dart';

void main() {
  const circuitMultiaddr =
      '/ip4/10.0.0.8/tcp/4001/p2p/12D3KooWRelay/p2p-circuit';
  const receiverPeerId = '12D3KooWReceiverPeerId00000001';

  NodeState circuitOnlyState() => const NodeState(
    isStarted: true,
    connections: [
      p2p.ConnectionState(
        peerId: receiverPeerId,
        multiaddrs: [circuitMultiaddr],
        direction: 'outbound',
        status: 'connected',
      ),
    ],
  );

  // A receiver that applies messageId dedup on inbound delivery (production's
  // only correctness backstop for an un-cancellable in-flight loser). Returns
  // the count of distinct rows held.
  late List<String> receiverRows;
  void deliverToReceiver(String messageId) {
    if (receiverRows.contains(messageId)) return; // dedup by messageId
    receiverRows.add(messageId);
  }

  late FakeMessageRepository senderRepo;
  setUp(() {
    receiverRows = <String>[];
    senderRepo = FakeMessageRepository();
  });

  group('FDC-02 e2e — staggered relay-penalty ranked race', () {
    // TC-02-11 — sender LAN-wins; the staggered relay-live leg never fires; the
    // receiver persists exactly one decrypted row (dedup masks the transmission
    // count — relayLiveSendCount is the discriminator that does not).
    test(
      'FDC-02 e2e: sender LAN-wins, relay-live leg never fires, receiver '
      'persists one row',
      () async {
        final sender = DurableLanFakeP2PService(currentState: circuitOnlyState())
          ..localPeers.add(receiverPeerId)
          ..localSendDelay = const Duration(milliseconds: 40);
        const fixedId = 'msg-fdc02-e2e-lan-001';

        final (result, message) = await sendChatMessage(
          p2pService: sender,
          messageRepo: senderRepo,
          targetPeerId: receiverPeerId,
          text: 'LAN beats the warmed relay, e2e',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: fixedId,
        );

        // Sender side: LAN carried it; the relay-live leg was suppressed.
        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'local');
        // Wait out the full stagger window — the relay-live leg reaches its
        // delay, sees `best` committed, and never sends.
        await Future<void>.delayed(const Duration(milliseconds: 700));
        expect(sender.relayLiveSendCount, 0);
        expect(senderRepo.saved, hasLength(1));
        expect(senderRepo.saved.single.id, fixedId);

        // Receiver side: deliver every actual transmission (LAN send + any
        // relay-live send). Receiver dedup collapses them to one row.
        final transmissions =
            sender.localSendCallCount + sender.relayLiveSendCount;
        for (var i = 0; i < transmissions; i++) {
          deliverToReceiver(fixedId);
        }
        expect(receiverRows, hasLength(1));
        expect(receiverRows.single, fixedId);
      },
    );

    // TC-02-12 — a media send with a live circuit reaches the receiver via inbox
    // custody, never the live relay leg.
    test(
      'FDC-02 e2e: media send with live circuit reaches the receiver via inbox, '
      'never the live circuit',
      () async {
        const encryptedAttachment = MediaAttachment(
          id: 'att-fdc02-e2e-media',
          messageId: '',
          mime: 'image/jpeg',
          size: 1024,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-06-26T11:00:00.000Z',
          contentHash:
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          encryptionKeyBase64: 'key-1',
          encryptionNonce: 'nonce-1',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        final sender = FakeP2PService(
          currentState: circuitOnlyState(),
          dialPeerResult: false, // direct leg fails at dial
          probeRelayResult: RelayProbeResult.error, // probe tail off
          storeInInboxResult: true, // inbox takes custody
        );
        const fixedId = 'msg-fdc02-e2e-media-001';

        final (result, message) = await sendChatMessage(
          p2pService: sender,
          messageRepo: senderRepo,
          targetPeerId: receiverPeerId,
          text: 'photo over a live circuit, e2e?',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: fixedId,
          mediaAttachments: const [encryptedAttachment],
          mediaAttachmentRepo: FakeMediaAttachmentRepository(),
        );

        // Media never traversed the live relay leg; it took durable custody.
        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(sender.relayLiveSendCount, 0);
        expect(message!.transport, 'inbox');

        // Receiver eventually drains the inbox custody → one media row.
        final transmissions =
            sender.storeInInboxCallCount + sender.relayLiveSendCount;
        for (var i = 0; i < transmissions; i++) {
          deliverToReceiver(fixedId);
        }
        expect(receiverRows, hasLength(1));
        expect(receiverRows.single, fixedId);
      },
    );
  });
}
