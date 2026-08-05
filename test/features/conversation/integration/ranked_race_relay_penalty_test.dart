// FDC-02/R2 Tier-2 integration: staggered relay scheduling and proof authority
// across a SENDER and a RECEIVER (two fakes).
//
// The host fake cannot prove which live write arrived first on the wire
// (FDC-00 closure caveat: a race test can pass via the parallel
// inbox/dedup copy even when the live leg never fired). So the LOAD-BEARING
// discriminator here is the SENDER's relayLiveSendCount — the thing receiver
// messageId dedup masks. The receiver is modeled as a messageId-deduping store:
// no matter how many times a message is transmitted (LAN write plus an
// un-cancellable in-flight relay-live send), the receiver holds exactly ONE row; only
// relayLiveSendCount reveals whether the staggered relay-live leg actually fired.
//
// Real-wire "live-wins" proof is deferred to /sims + a two-device smoke
// (Device/Relay Proof Profile).

import 'dart:async';

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
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

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

  group('FDC-02 e2e — staggered relay proof race', () {
    // R2 replacement for TC-02-11: LAN writes remain operational, but only the
    // later authenticated relay ACK settles. Receiver message-ID dedup still
    // collapses every live transmission to one row.
    test(
      'FDC-02 e2e R2: sender LAN write cannot suppress relay proof, receiver '
      'persists one row',
      () async {
        final sender =
            DurableLanFakeP2PService(currentState: circuitOnlyState())
              ..localPeers.add(receiverPeerId)
              ..localSendDelay = const Duration(milliseconds: 40);
        sender.queuedSendMessageResults.addAll([
          Future<SendMessageResult>.value(
            const SendMessageResult(
              sent: true,
              acked: false,
              transport: 'relay',
            ),
          ),
          Future<SendMessageResult>.value(
            const SendMessageResult(
              sent: true,
              acked: true,
              transport: 'relay',
            ),
          ),
        ]);
        const fixedId = 'msg-fdc02-e2e-lan-001';

        final (result, message) = await sendChatMessage(
          p2pService: sender,
          messageRepo: senderRepo,
          targetPeerId: receiverPeerId,
          text: 'LAN write precedes relay proof, e2e',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          messageId: fixedId,
        );

        // Sender side: LAN wrote first, but authenticated relay proof settled.
        expect(result, SendChatMessageResult.success);
        expect(message, isNotNull);
        expect(message!.transport, 'relay');
        expect(sender.localSendCallCount, 1);
        expect(sender.relayLiveSendCount, 1);
        expect(senderRepo.saved, hasLength(1));
        expect(senderRepo.saved.single.id, fixedId);

        // Receiver side: deliver every actual transmission (LAN send + any
        // relay-live send). Receiver dedup collapses them to one row.
        final transmissions = sender.localSendCallCount + sender.sendCallCount;
        for (var i = 0; i < transmissions; i++) {
          deliverToReceiver(fixedId);
        }
        expect(receiverRows, hasLength(1));
        expect(receiverRows.single, fixedId);
      },
    );

    test(
      'R2 written direct or relay result cannot suppress later committed live proof',
      () async {
        for (final uncommittedAck in <bool?>[false, null]) {
          final sender = FakeP2PService(currentState: circuitOnlyState());
          sender.queuedSendMessageResults.addAll([
            Future<SendMessageResult>.value(
              SendMessageResult(
                sent: true,
                acked: uncommittedAck,
                reply: 'written direct diagnostic',
                transport: 'direct',
              ),
            ),
            Future<SendMessageResult>.value(
              const SendMessageResult(
                sent: true,
                acked: true,
                transport: 'relay',
              ),
            ),
          ]);

          final (result, message) = await sendChatMessage(
            p2pService: sender,
            messageRepo: FakeMessageRepository(),
            targetPeerId: receiverPeerId,
            text: 'written direct then relay proof $uncommittedAck',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
          );

          expect(result, SendChatMessageResult.success);
          expect(message!.status, 'delivered');
          expect(message.transport, 'relay');
          expect(sender.sendCallCount, 2);
          expect(sender.relayLiveSendCount, 1);
          expect(sender.storeInInboxCallCount, 0);
        }

        for (final uncommittedAck in <bool?>[false, null]) {
          final directProof = Completer<SendMessageResult>();
          final relayWrittenFirst = FakeP2PService(
            currentState: circuitOnlyState(),
          );
          relayWrittenFirst.queuedSendMessageResults.addAll([
            directProof.future,
            Future<SendMessageResult>.value(
              SendMessageResult(
                sent: true,
                acked: uncommittedAck,
                reply: 'relay wrote without commitment',
                transport: 'relay',
              ),
            ),
          ]);
          var settled = false;
          final send =
              sendChatMessage(
                p2pService: relayWrittenFirst,
                messageRepo: FakeMessageRepository(),
                targetPeerId: receiverPeerId,
                text: 'written relay then direct proof $uncommittedAck',
                senderPeerId: 'my-peer',
                senderUsername: 'Me',
              ).then((value) {
                settled = true;
                return value;
              });

          for (
            var i = 0;
            i < 100 && relayWrittenFirst.relayLiveSendCount == 0;
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(relayWrittenFirst.relayLiveSendCount, 1);
          expect(settled, isFalse);
          directProof.complete(
            const SendMessageResult(
              sent: true,
              acked: true,
              transport: 'direct',
            ),
          );
          final (result, message) = await send;
          expect(result, SendChatMessageResult.success);
          expect(message!.status, 'delivered');
          expect(message.transport, 'direct');
          expect(relayWrittenFirst.storeInInboxCallCount, 0);
        }
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
