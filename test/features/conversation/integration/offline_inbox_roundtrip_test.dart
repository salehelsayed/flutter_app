// Integration tests for offline inbox roundtrip scenarios.
//
// Tests verify that:
// - Inbox drain completes before relay shows green online status
// - Resume delivers queued messages before live reconnect
// - Large backlogs show first page quickly with background continuation
// - Cold start after reboot uses inbox-first recovery
// - Foreground send uses short budget while background recovery is separate

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_chat_disposition.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_sibling_dispositions.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/verify_inbox_custody_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/fake_p2p_network.dart' as shared_fakes;
import '../../../shared/fakes/in_memory_contact_repository.dart'
    as temporal_fakes;
import '../../../shared/fakes/in_memory_inbox_staging_repository.dart'
    as temporal_fakes;
import '../../../shared/fakes/in_memory_message_repository.dart'
    as temporal_fakes;
import '../../../shared/fakes/test_user.dart' as shared_fakes;
import '../domain/repositories/fake_reaction_repository.dart';

// Reuse the integration test infrastructure from two_user_message_exchange_test.dart
import 'two_user_message_exchange_test.dart';

/// Captures the [FLOW] events emitted (via debugPrint) during [action]. Mirrors
/// the unit-test helper so the integration tier can assert the concurrent-deposit
/// discriminator (CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN).
Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) printed.add(message);
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }
  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

final class _TemporalInboxStagingRepository
    extends temporal_fakes.InMemoryInboxStagingRepository {
  _TemporalInboxStagingRepository(this.order);

  final List<String> order;
  String phase = 'legacy';
  int stageCallCount = 0;

  @override
  Future<List<String>> stageEntries(List<InboxStagingEntry> entries) async {
    stageCallCount++;
    order.add('$phase-stage');
    return super.stageEntries(entries);
  }
}

final class _TemporalReactionRepository extends FakeReactionRepository
    implements AtomicIncomingReactionMutationRepository {
  final Map<String, String> _lastRemoveEventIds = <String, String>{};
  int canonicalMutationCount = 0;

  String _key(MessageReaction reaction) =>
      '${reaction.messageId}\u0000${reaction.senderPeerId}';

  @override
  Future<ReactionAddApplyResult> applyIncomingAdd(
    MessageReaction reaction,
  ) async {
    final result = await super.applyIncomingAdd(reaction);
    if (result == ReactionAddApplyResult.inserted ||
        result == ReactionAddApplyResult.updated) {
      canonicalMutationCount++;
    }
    return result;
  }

  @override
  Future<ReactionRemoveApplyResult> applyIncomingRemove(
    MessageReaction reaction,
  ) async {
    final key = _key(reaction);
    final current = await getReactionForSenderIncludingRemoved(
      messageId: reaction.messageId,
      senderPeerId: reaction.senderPeerId,
    );
    final incomingAt = DateTime.tryParse(reaction.timestamp);
    final currentAt = current == null
        ? null
        : DateTime.tryParse(current.removedAt ?? current.timestamp);
    if (incomingAt != null &&
        currentAt != null &&
        incomingAt.isBefore(currentAt)) {
      return ReactionRemoveApplyResult.stale;
    }
    if (_lastRemoveEventIds[key] == reaction.id &&
        current?.isRemoved == true &&
        current?.removedAt == reaction.timestamp) {
      return ReactionRemoveApplyResult.exactReplay;
    }

    await saveReaction(reaction.copyWith(removedAt: reaction.timestamp));
    _lastRemoveEventIds[key] = reaction.id;
    canonicalMutationCount++;
    return ReactionRemoveApplyResult.applied;
  }
}

final class _TemporalUpgradeBridge extends PassthroughCryptoBridge {
  _TemporalUpgradeBridge({required this.rows, required this.order});

  final List<Map<String, dynamic>> rows;
  final List<String> order;
  final List<String?> retrieveContracts = <String?>[];
  final List<String?> ackContracts = <String?>[];
  final List<String> ackedEntryIds = <String>[];
  var _retrieved = false;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final command = request['cmd'] as String?;
    final payload = request['payload'] as Map<String, dynamic>?;
    switch (command) {
      case 'node:start':
        return jsonEncode({
          'ok': true,
          'peerId': 'temporal-bob',
          'isStarted': true,
          'listenAddresses': <String>[],
          'circuitAddresses': <String>[],
          'connections': <dynamic>[],
        });
      case 'inbox:retrieve_pending':
        retrieveContracts.add(payload?['custodyContract'] as String?);
        order.add('protected-retrieve');
        final page = _retrieved ? const <Map<String, dynamic>>[] : rows;
        _retrieved = true;
        return jsonEncode({
          'ok': true,
          'messages': page,
          'hasMore': false,
          'custodyContract': ackOrExpiryInboxCustodyContract,
        });
      case 'inbox:ack':
        ackContracts.add(payload?['custodyContract'] as String?);
        final ids = (payload?['entryIds'] as List<dynamic>? ?? const [])
            .map((id) => id.toString())
            .toList(growable: false);
        ackedEntryIds.addAll(ids);
        order.add('protected-ack');
        return jsonEncode({
          'ok': true,
          'acked': ids.length,
          'custodyContract': ackOrExpiryInboxCustodyContract,
        });
      default:
        return super.send(message);
    }
  }
}

void main() {
  late FakeP2PNetwork network;
  late TestUser alice;
  late TestUser bob;

  setUp(() {
    network = FakeP2PNetwork();

    alice = TestUser.create(
      peerId: '12D3KooWAlicePeerId00000000001',
      username: 'Alice',
      network: network,
    );

    bob = TestUser.create(
      peerId: '12D3KooWBobPeerIdxxx00000000002',
      username: 'Bob',
      network: network,
    );

    alice.addContact(bob);
    bob.addContact(alice);

    alice.start();
    bob.start();
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
  });

  group('Offline inbox roundtrip', () {
    test('FDC-03-06 first-ever offline send deposits a concurrent inbox copy that '
        'drains on resume', () async {
      // Fresh alice→bob with NO prior history. On HEAD this first-ever send is
      // "high confidence" (no prior failed attempt), so the inbox copy fires
      // SERIALLY after the race and CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN never
      // appears. FDC-03 fires it CONCURRENTLY for the unknown-presence peer.
      bob.setOnline(false);

      late SendChatMessageResult result;
      ConversationMessage? sent;
      final events = await _captureFlowEvents(() async {
        final (r, m) = await alice.sendMessage(
          bob.peerId,
          'First ever, while you were away',
        );
        result = r;
        sent = m;
      });

      expect(result, SendChatMessageResult.success);
      expect(sent, isNotNull);
      // Durable custody, not delivery (doc 115).
      expect(sent!.status, 'inboxed');
      expect(sent!.transport, 'inbox');
      // The deposit was CONCURRENT (the discriminator): the BEGIN flow-event
      // fires even though no prior failed attempt exists. Mutation: re-gate the
      // concurrent arm behind the recency lookup → BEGIN absent → RED.
      final names = events.map((e) => e['event']).toList();
      expect(names, contains('CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN'));

      // Round-trips correctly: Bob drains and ends with exactly one copy
      // (receiver messageId dedup → no duplicate).
      bob.setOnline(true);
      await bob.drainOfflineInbox();
      await Future.delayed(const Duration(milliseconds: 50));

      final bobConvo = await bob.loadConversation(alice.peerId);
      expect(bobConvo, hasLength(1));
      expect(bobConvo.single.text, 'First ever, while you were away');
    });

    test(
      'startup inbox drain completes before relay online state is green',
      () async {
        // Bob goes offline
        bob.setOnline(false);

        // Alice sends to offline Bob (goes to inbox)
        final (result, _) = await alice.sendMessage(
          bob.peerId,
          'While you were away',
        );
        expect(result, SendChatMessageResult.success);

        // Bob comes back online
        bob.setOnline(true);

        // Bob drains inbox — this should complete regardless of relay status
        final drained = await bob.drainOfflineInbox();
        expect(drained, 1);

        // Give listener time to process the injected messages
        await Future.delayed(const Duration(milliseconds: 100));

        // Bob should have the message
        final bobConvo = await bob.messageRepo.getMessagesForContact(
          alice.peerId,
        );
        expect(bobConvo.length, 1);
        expect(bobConvo.first.text, 'While you were away');
      },
    );

    test(
      'resume delivers queued inbox messages before later live reconnect finishes',
      () async {
        bob.setOnline(false);

        // Alice sends multiple messages while Bob is offline
        await alice.sendMessage(bob.peerId, 'Message 1');
        await alice.sendMessage(bob.peerId, 'Message 2');

        // Bob comes back (simulating resume)
        bob.setOnline(true);

        // Drain inbox (simulating resume drain)
        final drained = await bob.drainOfflineInbox();
        expect(drained, 2);

        // Give listener time to process
        await Future.delayed(const Duration(milliseconds: 100));

        // Verify messages are available
        final bobConvo = await bob.messageRepo.getMessagesForContact(
          alice.peerId,
        );
        expect(bobConvo.length, 2);
      },
    );

    test(
      'both offline peers catch up cleanly when they return together',
      () async {
        alice.setOnline(false);
        bob.setOnline(false);

        final (aliceResult1, _) = await alice.sendMessage(
          bob.peerId,
          'Alice offline 1',
        );
        expect(aliceResult1, SendChatMessageResult.success);
        await Future<void>.delayed(const Duration(milliseconds: 2));

        final (bobResult1, _) = await bob.sendMessage(
          alice.peerId,
          'Bob offline 1',
        );
        expect(bobResult1, SendChatMessageResult.success);
        await Future<void>.delayed(const Duration(milliseconds: 2));

        final (aliceResult2, _) = await alice.sendMessage(
          bob.peerId,
          'Alice offline 2',
        );
        expect(aliceResult2, SendChatMessageResult.success);
        await Future<void>.delayed(const Duration(milliseconds: 2));

        final (bobResult2, _) = await bob.sendMessage(
          alice.peerId,
          'Bob offline 2',
        );
        expect(bobResult2, SendChatMessageResult.success);

        alice.setOnline(true);
        bob.setOnline(true);

        final drainedCounts = await Future.wait([
          alice.drainOfflineInbox(),
          bob.drainOfflineInbox(),
        ]);
        expect(drainedCounts, [2, 2]);

        await Future.delayed(const Duration(milliseconds: 100));

        final aliceConvo = await alice.loadConversation(bob.peerId);
        final bobConvo = await bob.loadConversation(alice.peerId);

        expect(aliceConvo, hasLength(4));
        expect(bobConvo, hasLength(4));

        expect(aliceConvo.map((message) => message.text).toList(), [
          'Alice offline 1',
          'Bob offline 1',
          'Alice offline 2',
          'Bob offline 2',
        ]);
        expect(bobConvo.map((message) => message.text).toList(), [
          'Alice offline 1',
          'Bob offline 1',
          'Alice offline 2',
          'Bob offline 2',
        ]);

        expect(aliceConvo.where((message) => message.isIncoming), hasLength(2));
        expect(bobConvo.where((message) => message.isIncoming), hasLength(2));
        expect(
          aliceConvo.map((message) => message.id).toSet().length,
          aliceConvo.length,
        );
        expect(
          bobConvo.map((message) => message.id).toSet().length,
          bobConvo.length,
        );
      },
    );

    test(
      'large 1:1 backlog shows first page quickly and drains remaining pages in background',
      () async {
        bob.setOnline(false);

        // Send many messages while Bob is offline
        for (var i = 0; i < 10; i++) {
          await alice.sendMessage(bob.peerId, 'Backlog msg $i');
        }

        bob.setOnline(true);

        // First drain gets available messages
        final drained = await bob.drainOfflineInbox();
        expect(drained, 10);

        // Give listener time to process
        await Future.delayed(const Duration(milliseconds: 200));

        // All messages should be retrieved
        final bobConvo = await bob.messageRepo.getMessagesForContact(
          alice.peerId,
        );
        expect(bobConvo.length, 10);
      },
    );

    test(
      'cold start after reboot retrieves queued inbox messages before group warm tasks finish',
      () async {
        bob.setOnline(false);

        await alice.sendMessage(bob.peerId, 'Before reboot');

        bob.setOnline(true);

        // Inbox drain should work immediately (simulating cold start inbox-first)
        final drained = await bob.drainOfflineInbox();
        expect(drained, 1);

        // Give listener time to process
        await Future.delayed(const Duration(milliseconds: 100));

        final bobConvo = await bob.messageRepo.getMessagesForContact(
          alice.peerId,
        );
        expect(bobConvo.length, 1);
        expect(bobConvo.first.text, 'Before reboot');
      },
    );

    test(
      'edit-first inbox drain stays phantom-free until the original arrives and then materializes the edited row',
      () async {
        bob.setOnline(false);

        const messageId = 'msg-edit-before-original';
        final editEnvelope = MessagePayload(
          id: messageId,
          text: 'Edited before original',
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          timestamp: '2026-04-01T09:59:00.000Z',
          action: MessagePayload.actionEdit,
          editedAt: '2026-04-01T10:00:00.000Z',
        ).toJson();
        final originalEnvelope = MessagePayload(
          id: messageId,
          text: 'Original text',
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          timestamp: '2026-04-01T09:58:00.000Z',
        ).toJson();

        expect(
          network.storeInInbox(alice.peerId, bob.peerId, editEnvelope),
          isTrue,
        );
        expect(
          bob.messageRepo.getMessagesForContact(alice.peerId),
          completion(isEmpty),
        );
        expect(
          network.storeInInbox(alice.peerId, bob.peerId, originalEnvelope),
          isTrue,
        );

        bob.setOnline(true);
        final emitted = <ConversationMessage>[];
        final sub = bob.chatListener.incomingMessageStream.listen(emitted.add);

        final drained = await bob.drainOfflineInbox();
        expect(drained, 2);

        await Future.delayed(const Duration(milliseconds: 100));

        final bobConvo = await bob.loadConversation(alice.peerId);
        expect(bobConvo, hasLength(1));
        expect(bobConvo.single.id, messageId);
        expect(bobConvo.single.text, 'Edited before original');
        expect(bobConvo.single.isHidden, isFalse);
        expect(bobConvo.single.editedAt, '2026-04-01T10:00:00.000Z');
        expect(emitted, hasLength(1));
        expect(emitted.single.id, messageId);
        expect(emitted.single.text, 'Edited before original');

        await sub.cancel();
      },
    );

    test(
      'offline edit delivery survives receiver restart and applies once inbox drain resumes',
      () async {
        final (sendResult, original) = await alice.sendMessage(
          bob.peerId,
          'Original before offline edit',
        );
        expect(sendResult, SendChatMessageResult.success);
        expect(original, isNotNull);
        await Future.delayed(const Duration(milliseconds: 100));

        final originalId = original!.id;
        bob.setOnline(false);

        final editEnvelope = MessagePayload(
          id: originalId,
          text: 'Edited after restart',
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          timestamp: original.timestamp,
          action: MessagePayload.actionEdit,
          editedAt: '2026-04-01T11:00:00.000Z',
        ).toJson();

        expect(
          network.storeInInbox(alice.peerId, bob.peerId, editEnvelope),
          isTrue,
        );

        final persistedBobRepo = bob.messageRepo;
        final persistedBobContacts = bob.contactRepo;
        bob.dispose();

        bob = TestUser.create(
          peerId: '12D3KooWBobPeerIdxxx00000000002',
          username: 'Bob',
          network: network,
          messageRepo: persistedBobRepo,
          contactRepo: persistedBobContacts,
        );
        bob.start();
        bob.setOnline(true);

        final drained = await bob.drainOfflineInbox();
        // FDC-03: the original send also left a concurrent durable copy in the
        // inbox (the fake models every send as unknown-presence). It dedups as a
        // no-op on drain — the edit still applies (asserted below), so this is a
        // benign +1 to the drained count.
        expect(drained, 2);
        await Future.delayed(const Duration(milliseconds: 100));

        final bobConvo = await bob.loadConversation(alice.peerId);
        expect(bobConvo, hasLength(1));
        expect(bobConvo.single.id, originalId);
        expect(bobConvo.single.text, 'Edited after restart');
        expect(bobConvo.single.editedAt, '2026-04-01T11:00:00.000Z');
      },
    );

    test(
      'foreground send completes on short budget while longer background recovery continues separately',
      () async {
        // Both online — foreground send should be fast
        final stopwatch = Stopwatch()..start();
        final (result, msg) = await alice.sendMessage(bob.peerId, 'Quick send');
        stopwatch.stop();

        expect(result, SendChatMessageResult.success);
        expect(msg, isNotNull);
        // Foreground send should complete quickly
        expect(stopwatch.elapsed.inSeconds, lessThan(5));
      },
    );

    test(
      'cap-rejected send stays retryable and delivers after receiver drains capacity',
      () async {
        final cappedNetwork = shared_fakes.FakeP2PNetwork()
          ..maxInboxPerPeer = 2;
        final receiptAlice = shared_fakes.TestUser.create(
          peerId: '12D3KooWSharedAlicePeer0001',
          username: 'Alice',
          network: cappedNetwork,
          withDeliveryReceipts: true,
        );
        final receiptBob = shared_fakes.TestUser.create(
          peerId: '12D3KooWSharedBobPeer000002',
          username: 'Bob',
          network: cappedNetwork,
          withDeliveryReceipts: true,
        );
        receiptAlice.addContact(receiptBob);
        receiptBob.addContact(receiptAlice);
        receiptAlice.start();
        receiptBob.start();

        try {
          receiptBob.setOnline(false);

          final (firstResult, first) = await receiptAlice.sendMessage(
            receiptBob.peerId,
            'cap accepted 1',
          );
          final (secondResult, second) = await receiptAlice.sendMessage(
            receiptBob.peerId,
            'cap accepted 2',
          );
          final (rejectedResult, rejected) = await receiptAlice.sendMessage(
            receiptBob.peerId,
            'cap rejected retryable',
          );

          expect(firstResult, SendChatMessageResult.success);
          expect(secondResult, SendChatMessageResult.success);
          expect(rejectedResult, SendChatMessageResult.success);
          expect(first?.status, 'inboxed');
          expect(second?.status, 'inboxed');
          expect(rejected?.status, 'sent');
          expect(rejected?.transport, 'inbox');
          expect(rejected?.wireEnvelope, isNotNull);
          expect(cappedNetwork.inboxCount(receiptBob.peerId), 2);

          receiptBob.setOnline(true);
          expect(await receiptBob.drainOfflineInbox(), 2);
          await Future<void>.delayed(const Duration(milliseconds: 100));

          expect(
            (await receiptAlice.messageRepo.getMessage(first!.id))?.status,
            'delivered',
          );
          expect(
            (await receiptAlice.messageRepo.getMessage(second!.id))?.status,
            'delivered',
          );
          expect(
            (await receiptAlice.messageRepo.getMessage(rejected!.id))?.status,
            'sent',
          );

          final retried = await retryUnackedMessages(
            messageRepo: receiptAlice.messageRepo,
            p2pService: receiptAlice.p2pService,
          );
          expect(retried, 0);
          expect(cappedNetwork.inboxCount(receiptBob.peerId), 0);

          final completed = await drainDirectInboxCustodyOutbox(
            custodyRepository: receiptAlice.messageRepo,
            storeInAckCustodyInboxDetailed:
                receiptAlice.p2pService.storeInAckCustodyInboxDetailed,
          );
          expect(completed, 1);
          expect(cappedNetwork.inboxCount(receiptBob.peerId), 1);
          expect(
            (await receiptAlice.messageRepo.getMessage(rejected.id))?.status,
            'inboxed',
          );

          expect(await receiptBob.drainOfflineInbox(), 1);
          await Future<void>.delayed(const Duration(milliseconds: 100));

          expect(
            (await receiptAlice.messageRepo.getMessage(rejected.id))?.status,
            'delivered',
          );
          expect(
            await receiptBob.loadConversationWith(receiptAlice.peerId),
            hasLength(3),
          );
        } finally {
          receiptAlice.dispose();
          receiptBob.dispose();
        }
      },
    );

    test(
      'lost receipt after drain is repaired by re-store and duplicate receipt',
      () async {
        final receiptNetwork = shared_fakes.FakeP2PNetwork();
        final receiptAlice = shared_fakes.TestUser.create(
          peerId: '12D3KooWSharedAlicePeer0003',
          username: 'Alice',
          network: receiptNetwork,
          withDeliveryReceipts: true,
        );
        final receiptBob = shared_fakes.TestUser.create(
          peerId: '12D3KooWSharedBobPeer000004',
          username: 'Bob',
          network: receiptNetwork,
          withDeliveryReceipts: true,
        );
        receiptAlice.addContact(receiptBob);
        receiptBob.addContact(receiptAlice);
        receiptAlice.start();
        receiptBob.start();

        try {
          receiptBob.setOnline(false);
          final (sentResult, sent) = await receiptAlice.sendMessage(
            receiptBob.peerId,
            'receipt lost once',
          );
          expect(sentResult, SendChatMessageResult.success);
          expect(sent?.status, 'inboxed');

          receiptAlice.setOnline(false);
          receiptNetwork.inboxDisabled = true;
          receiptBob.setOnline(true);
          expect(await receiptBob.drainOfflineInbox(), 1);
          await Future<void>.delayed(const Duration(milliseconds: 100));

          final stillInboxed = await receiptAlice.messageRepo.getMessage(
            sent!.id,
          );
          expect(stillInboxed?.status, 'inboxed');
          expect(stillInboxed?.wireEnvelope, isNotNull);
          expect(
            await receiptBob.loadConversationWith(receiptAlice.peerId),
            hasLength(1),
          );

          receiptNetwork.inboxDisabled = false;
          final staleUnreceipted = stillInboxed!.copyWith(
            custodyCheckedAt: DateTime.now()
                .toUtc()
                .subtract(const Duration(hours: 25))
                .toIso8601String(),
          );
          final restored = await verifyInboxCustody(
            loadInboxCustody: ({required recheckOlderThan}) async => [
              staleUnreceipted,
            ],
            storeInInboxDetailed: receiptAlice.p2pService.storeInInboxDetailed,
            markCustodyChecked: (messageId, {relayExpiresAtMs}) async {
              final current = await receiptAlice.messageRepo.getMessage(
                messageId,
              );
              if (current != null) {
                await receiptAlice.messageRepo.saveMessage(
                  current.copyWith(relayExpiresAt: relayExpiresAtMs),
                );
              }
            },
            messageRepo: receiptAlice.messageRepo,
          );
          expect(restored, 1);
          expect(receiptNetwork.inboxCount(receiptBob.peerId), 1);
          receiptAlice.setOnline(true);

          expect(await receiptBob.drainOfflineInbox(), 1);
          await Future<void>.delayed(const Duration(milliseconds: 100));

          expect(
            (await receiptAlice.messageRepo.getMessage(sent.id))?.status,
            'delivered',
          );
          expect(
            await receiptBob.loadConversationWith(receiptAlice.peerId),
            hasLength(1),
          );
        } finally {
          receiptAlice.dispose();
          receiptBob.dispose();
        }
      },
    );

    test(
      'Plan 344 legacy receive then upgraded protected redelivery converges once',
      () async {
        const alicePeerId = 'temporal-alice';
        const bobPeerId = 'temporal-bob';
        const textMessageId = 'temporal-text-message';
        const reactionTargetId = 'temporal-reaction-target';
        const addEventId = 'temporal-reaction-add';
        const removeEventId = 'temporal-reaction-remove';
        const textTimestamp = '2026-08-07T10:00:00.000Z';
        const addTimestamp = '2026-08-07T10:01:00.000Z';
        const removeTimestamp = '2026-08-07T10:02:00.000Z';

        final order = <String>[];
        final staging = _TemporalInboxStagingRepository(order);
        final messages = temporal_fakes.InMemoryMessageRepository();
        final contacts = temporal_fakes.InMemoryContactRepository()
          ..addTestContact(
            const ContactModel(
              peerId: alicePeerId,
              publicKey: 'alice-public-key',
              rendezvous: '/dns4/relay/tcp/443/p2p/relay',
              username: 'Alice',
              signature: 'alice-signature',
              scannedAt: '2026-08-07T09:00:00.000Z',
              mlKemPublicKey: 'alice-mlkem-key',
            ),
          );
        final reactions = _TemporalReactionRepository();
        final notifications = FakeNotificationService();
        final tracker = ActiveConversationTracker();
        final cryptoBridge = PassthroughCryptoBridge();
        var reactionChanges = 0;

        await messages.saveMessage(
          const ConversationMessage(
            id: reactionTargetId,
            contactPeerId: alicePeerId,
            senderPeerId: bobPeerId,
            text: 'Bob-authored reaction target',
            timestamp: '2026-08-07T09:59:00.000Z',
            status: 'delivered',
            isIncoming: false,
            createdAt: '2026-08-07T09:59:00.000Z',
          ),
        );

        final textPayload = MessagePayload(
          id: textMessageId,
          text: 'one logical temporal message',
          senderPeerId: alicePeerId,
          senderUsername: 'Alice',
          timestamp: textTimestamp,
        );
        final textEnvelope = MessagePayload.buildEncryptedEnvelope(
          id: textMessageId,
          senderPeerId: alicePeerId,
          senderUsername: 'Alice',
          kem: 'test-kem',
          ciphertext: textPayload.toInnerJson(),
          nonce: 'test-nonce-text',
        );
        const addPayload = ReactionPayload(
          id: addEventId,
          messageId: reactionTargetId,
          emoji: '👍',
          action: ReactionPayload.addAction,
          senderPeerId: alicePeerId,
          timestamp: addTimestamp,
        );
        const removePayload = ReactionPayload(
          id: removeEventId,
          messageId: reactionTargetId,
          emoji: '👍',
          action: ReactionPayload.removeAction,
          senderPeerId: alicePeerId,
          timestamp: removeTimestamp,
        );
        final addEnvelope = ReactionPayload.buildEncryptedEnvelope(
          senderPeerId: alicePeerId,
          eventId: addEventId,
          action: ReactionPayload.addAction,
          targetMessageId: reactionTargetId,
          kem: 'test-kem',
          ciphertext: addPayload.toInnerJson(),
          nonce: 'test-nonce-add',
        );
        final removeEnvelope = ReactionPayload.buildEncryptedEnvelope(
          senderPeerId: alicePeerId,
          eventId: removeEventId,
          action: ReactionPayload.removeAction,
          targetMessageId: reactionTargetId,
          kem: 'test-kem',
          ciphertext: removePayload.toInnerJson(),
          nonce: 'test-nonce-remove',
        );

        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream<ChatMessage>.empty(),
          messageRepo: messages,
          contactRepo: contacts,
          bridge: cryptoBridge,
          getOwnMlKemSecretKey: () async => 'bob-mlkem-secret',
          notificationService: notifications,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          backgroundNotificationDuplicateGuardDelay: Duration.zero,
          durableNotificationCoordinatorResolver: () async =>
              throw StateError('durable notification store unavailable'),
        );
        addTearDown(chatListener.dispose);

        Future<RecoveredInboxReplayOutcome> replayChat(
          ChatMessage message, {
          String? stagedEntryId,
        }) async {
          order.add('${staging.phase}-replay-text');
          final outcome = await chatListener.processIncomingMessage(
            message,
            stagedEntryId: stagedEntryId,
          );
          return mapChatReplayOutcomeToDisposition(outcome);
        }

        Future<RecoveredInboxReplayOutcome> replayReaction(
          ChatMessage message, {
          String? stagedEntryId,
        }) async {
          final envelope = jsonDecode(message.content) as Map<String, dynamic>;
          order.add('${staging.phase}-replay-reaction-${envelope['action']}');
          final (result, change) = await handleIncomingReaction(
            message: message,
            messageRepo: messages,
            reactionRepo: reactions,
            contactRepo: contacts,
            bridge: cryptoBridge,
            ownMlKemSecretKey: 'bob-mlkem-secret',
            notificationService: notifications,
            conversationTracker: tracker,
            getAppLifecycleState: () => AppLifecycleState.resumed,
          );
          if (change != null) reactionChanges++;
          return mapReactionReplayResultToDisposition(result);
        }

        final shadowEntries = <InboxStagingEntry>[
          InboxStagingEntry(
            entryId: 'temporal-text-entry',
            ownerPeerId: bobPeerId,
            senderPeerId: alicePeerId,
            messageType: 'chat_message',
            relayTimestamp: textTimestamp,
            envelope: textEnvelope,
            stagedAt: textTimestamp,
          ),
          InboxStagingEntry(
            entryId: 'temporal-add-entry',
            ownerPeerId: bobPeerId,
            senderPeerId: alicePeerId,
            messageType: 'message_reaction',
            relayTimestamp: addTimestamp,
            envelope: addEnvelope,
            stagedAt: addTimestamp,
          ),
          InboxStagingEntry(
            entryId: 'temporal-remove-entry',
            ownerPeerId: bobPeerId,
            senderPeerId: alicePeerId,
            messageType: 'message_reaction',
            relayTimestamp: removeTimestamp,
            envelope: removeEnvelope,
            stagedAt: removeTimestamp,
          ),
        ];

        // Legacy receiver phase: persist each destructive shadow locally,
        // replay it through production handlers, then issue the legacy ACK.
        final legacyAckable = await staging.stageEntries(shadowEntries);
        expect(legacyAckable, shadowEntries.map((entry) => entry.entryId));
        for (final entryId in legacyAckable) {
          final entry = staging.entry(entryId)!;
          final replay = entry.messageType == 'message_reaction'
              ? await replayReaction(
                  entry.toChatMessage(),
                  stagedEntryId: entryId,
                )
              : await replayChat(entry.toChatMessage(), stagedEntryId: entryId);
          expect(replay.disposition, RecoveredInboxChatDisposition.committed);
          await staging.deleteEntry(entryId);
          order.add('legacy-ack:$entryId');
        }

        final conversationAfterLegacy = await messages.getMessagesForContact(
          alicePeerId,
        );
        expect(
          conversationAfterLegacy.where(
            (message) => message.id == textMessageId,
          ),
          hasLength(1),
        );
        expect(await messages.getUnreadCountForContact(alicePeerId), 1);
        final reactionAfterLegacy = await reactions
            .getReactionForSenderIncludingRemoved(
              messageId: reactionTargetId,
              senderPeerId: alicePeerId,
            );
        expect(reactionAfterLegacy?.id, removeEventId);
        expect(reactionAfterLegacy?.isRemoved, isTrue);
        expect(reactions.canonicalMutationCount, 2);
        expect(reactionChanges, 2);
        expect(notifications.shown, hasLength(2));

        final canonicalCountAfterLegacy = conversationAfterLegacy.length;
        final unreadAfterLegacy = await messages.getUnreadCountForContact(
          alicePeerId,
        );
        final reactionMutationsAfterLegacy = reactions.canonicalMutationCount;
        final reactionChangesAfterLegacy = reactionChanges;
        final notificationsAfterLegacy = notifications.shown.length;

        // Upgrade phase: the protected copy is redelivered after its legacy
        // shadow was consumed. The real strict coordinator stages/replays it,
        // then exact-ACKs all three logical IDs.
        staging.phase = 'protected';
        final protectedRows = shadowEntries
            .map(
              (entry) => <String, dynamic>{
                'id': entry.entryId,
                'from': entry.senderPeerId,
                'message': entry.envelope,
                'timestamp': entry.relayTimestamp,
              },
            )
            .toList(growable: false);
        final upgradeBridge = _TemporalUpgradeBridge(
          rows: protectedRows,
          order: order,
        );
        final upgradedService = P2PServiceImpl(
          bridge: upgradeBridge,
          inboxStagingRepository: staging,
          replayRecoveredInboxChatMessage: replayChat,
          replayRecoveredInboxReaction: replayReaction,
        );
        addTearDown(upgradedService.dispose);

        expect(
          await upgradedService.startNodeCore('test-private-key', bobPeerId),
          isTrue,
        );
        final upgradedDrain = await upgradedService.drainOfflineInboxFully();
        expect(upgradedDrain.isSuccessful, isTrue);
        expect(upgradedDrain.hasMore, isFalse);

        final conversationAfterUpgrade = await messages.getMessagesForContact(
          alicePeerId,
        );
        expect(conversationAfterUpgrade, hasLength(canonicalCountAfterLegacy));
        expect(
          conversationAfterUpgrade.where(
            (message) => message.id == textMessageId,
          ),
          hasLength(1),
        );
        expect(
          await messages.getUnreadCountForContact(alicePeerId),
          unreadAfterLegacy,
        );
        expect(reactions.canonicalMutationCount, reactionMutationsAfterLegacy);
        expect(reactionChanges, reactionChangesAfterLegacy);
        expect(notifications.shown, hasLength(notificationsAfterLegacy));
        final reactionAfterUpgrade = await reactions
            .getReactionForSenderIncludingRemoved(
              messageId: reactionTargetId,
              senderPeerId: alicePeerId,
            );
        expect(reactionAfterUpgrade?.id, removeEventId);
        expect(reactionAfterUpgrade?.isRemoved, isTrue);

        expect(staging.stageCallCount, 2);
        expect(
          await staging.getRecoverableEntries(),
          isEmpty,
          reason: 'protected duplicate/stale rows must not remain retryable',
        );
        expect(upgradeBridge.retrieveContracts, <String?>[
          ackOrExpiryInboxCustodyContract,
        ]);
        expect(upgradeBridge.ackContracts, <String?>[
          ackOrExpiryInboxCustodyContract,
        ]);
        expect(
          upgradeBridge.ackedEntryIds,
          shadowEntries.map((entry) => entry.entryId),
        );
        expect(
          order.where((event) => event.startsWith('legacy-ack:')),
          hasLength(3),
        );
        expect(
          order.indexOf('protected-stage'),
          lessThan(order.indexOf('protected-replay-text')),
        );
        expect(
          order.indexOf('protected-replay-reaction-remove'),
          lessThan(order.indexOf('protected-ack')),
        );
      },
    );
  });
}
