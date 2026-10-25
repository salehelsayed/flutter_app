import 'package:flutter_app/features/conversation/domain/models/authored_direct_text_intent.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/inbox_staging_db_helpers.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository_impl.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_chat_disposition.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

enum _Checkpoint { beforeCustody, afterCustody, afterTransmit, afterRelayAck }

// Abandon the old send graph at an awaited boundary. Its continuations never
// resume, and its timers are cancelled before the same SQL file is reopened.
// This models lost Dart process state; it does not exercise an OS process kill.
class _SendCut {
  _SendCut(this.checkpoint);
  final _Checkpoint checkpoint;
  final reached = Completer<void>();
  final _never = Completer<void>();
  final _timers = <Timer>[];

  Future<void> pause() {
    for (final timer in _timers) {
      timer.cancel();
    }
    if (!reached.isCompleted) reached.complete();
    return _never.future;
  }

  Future<void> block() => _never.future;

  void start(Future<void> Function() action) {
    unawaited(
      runZoned(
        action,
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            _timers.add(timer);
            return timer;
          },
        ),
      ),
    );
  }
}

// The existing fake transport's ACK now waits for the real SQL/listener commit.
class _CommittedNetwork extends FakeP2PNetwork {
  final handlers = <String, Future<void> Function(ChatMessage)>{};

  @override
  Future<bool> deliver(
    String fromPeerId,
    String toPeerId,
    String content, {
    String transport = 'direct',
  }) async {
    deliverCallCount++;
    if (deliveryFails || !hasPeer(toPeerId)) return false;
    final handler = handlers[toPeerId];
    if (handler == null) return false;
    for (var copy = 0; copy < (duplicateOnDeliver ? 2 : 1); copy++) {
      await handler(
        ChatMessage(
          from: fromPeerId,
          to: toPeerId,
          content: content,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          transport: transport,
        ),
      );
    }
    return true;
  }
}

class _CutTransport extends FakeP2PService {
  _CutTransport({required super.peerId, required super.network, this.cut});
  final _SendCut? cut;
  final sentChatEnvelopes = <String>[];

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    if ((jsonDecode(message) as Map)['type'] == 'chat_message') {
      sentChatEnvelopes.add(message);
    }
    final result = await super.sendMessageWithReply(
      targetPeerId,
      message,
      timeoutMs: timeoutMs,
    );
    if (cut?.checkpoint == _Checkpoint.afterTransmit && result.acknowledged) {
      await cut!.pause();
    }
    return result;
  }

  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async {
    // Hold the competing hedge so it cannot settle an abandoned live attempt.
    if (cut?.checkpoint == _Checkpoint.afterTransmit) await cut!.block();
    return super.storeInAckCustodyInboxDetailed(
      toPeerId,
      message,
      custodyKind: custodyKind,
      timeoutMs: timeoutMs,
    );
  }
}

// Adapt the existing fake relay queue to the production protected-inbox drain.
// The backend/crypto remain fake; staging, replay, dedup and ACK ordering are real.
class _InboxBridge extends PassthroughCryptoBridge {
  _InboxBridge(this.peerId, this.network);
  final String peerId;
  final FakeP2PNetwork network;
  final acked = <String>[];
  int _entry = 0;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final payload = request['payload'] as Map<String, dynamic>?;
    switch (request['cmd']) {
      case 'node:start':
        return jsonEncode({
          'ok': true,
          'peerId': peerId,
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': [],
          'connections': [],
        });
      case 'inbox:retrieve_pending':
        return jsonEncode({
          'ok': true,
          'messages': [
            for (final row in network.retrieveInbox(peerId))
              {...row, 'id': 'sql-replay-${_entry++}'},
          ],
          'hasMore': false,
          'custodyContract': ackOrExpiryInboxCustodyContract,
        });
      case 'inbox:ack':
        final ids = (payload?['entryIds'] as List).cast<String>();
        acked.addAll(ids);
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

class _SqlPeer {
  _SqlPeer(this.id, this.otherId, this.path, this.network);
  final String id;
  final String otherId;
  final String path;
  final _CommittedNetwork network;
  late MediaRepositoryRealDbFixture sql;
  late _CutTransport transport;
  late _InboxBridge bridge;
  late InMemoryContactRepository contacts;
  late ChatMessageListener listener;
  late P2PServiceImpl inbox;

  Future<void> open({_SendCut? cut}) async {
    sql = await MediaRepositoryRealDbFixture.create(
      databasePath: path,
      beforeDirectTextCustodyStage: cut?.checkpoint == _Checkpoint.beforeCustody
          ? cut!.pause
          : null,
      afterDirectTextCustodyStage: cut?.checkpoint == _Checkpoint.afterCustody
          ? cut!.pause
          : null,
      beforeDirectInboxCustodyCompletion:
          cut?.checkpoint == _Checkpoint.afterRelayAck ? cut!.pause : null,
    );
    if ((await sql.db.query('identity', columns: ['peer_id'])).isEmpty) {
      await sql.db.insert('identity', {
        'id': 1,
        'peer_id': id,
        'public_key': '$id-public',
        'username': 'Fixture',
        'created_at': '2026-10-25T00:00:00.000Z',
        'updated_at': '2026-10-25T00:00:00.000Z',
      });
    }
    transport = _CutTransport(peerId: id, network: network, cut: cut);
    bridge = _InboxBridge(id, network);
    contacts = InMemoryContactRepository();
    final contact = ContactModel(
      peerId: otherId,
      publicKey: '$otherId-public',
      rendezvous: 'owned-host-fixture',
      username: 'Fixture',
      signature: 'fixture',
      scannedAt: '2026-10-25T00:00:00.000Z',
      mlKemPublicKey: '$otherId-mlkem',
    );
    await contacts.addContact(contact);
    if ((await sql.db.query('contacts')).isEmpty) {
      await sql.db.insert('contacts', contact.toMap());
    }
    listener = ChatMessageListener(
      chatMessageStream: const Stream.empty(),
      messageRepo: sql.messageRepo,
      contactRepo: contacts,
      bridge: bridge,
      mediaAttachmentRepo: sql.repo,
      getOwnMlKemSecretKey: () async => 'fixture-secret',
      sendDeliveryReceipt:
          ({
            required contactPeerId,
            required messageIds,
            mutationEventIds,
          }) async {
            await sendDeliveryReceipt(
              p2pService: transport,
              targetPeerId: contactPeerId,
              messageIds: messageIds,
              mutationEventIds: mutationEventIds,
            );
          },
    );
    network.handlers[id] = (message) async {
      if ((jsonDecode(message.content) as Map)['type'] == 'delivery_receipt') {
        await handleDeliveryReceipt(
          message: message,
          messageRepo: sql.messageRepo,
          mediaAttachmentRepo: sql.repo,
        );
      } else {
        final result = await listener.processIncomingMessage(message);
        expect(
          result.state,
          anyOf(
            ChatMessageProcessState.stored,
            ChatMessageProcessState.duplicate,
          ),
        );
      }
    };
    final db = sql.db;
    final staging = InboxStagingRepositoryImpl(
      dbInsertInboxStagingEntry: (row) => dbInsertInboxStagingEntry(db, row),
      dbLoadRecoverableInboxStagingEntries: ({limit = 50, entryIds}) =>
          dbLoadRecoverableInboxStagingEntries(
            db,
            limit: limit,
            entryIds: entryIds,
          ),
      dbLoadInboxStagingEntry: (id) => dbLoadInboxStagingEntry(db, id),
      dbDeleteInboxStagingEntry: (id) => dbDeleteInboxStagingEntry(db, id),
      dbMarkInboxStagingEntryRetryable:
          (id, {required reasonCode, reasonDetail}) =>
              dbMarkInboxStagingEntryRetryable(
                db,
                id,
                reasonCode: reasonCode,
                reasonDetail: reasonDetail,
              ),
      dbMarkInboxStagingEntryRejected:
          (id, {required reasonCode, reasonDetail}) =>
              dbMarkInboxStagingEntryRejected(
                db,
                id,
                reasonCode: reasonCode,
                reasonDetail: reasonDetail,
              ),
      dbMarkInboxStagingEntryQuarantined:
          (id, {required reasonCode, reasonDetail}) =>
              dbMarkInboxStagingEntryQuarantined(
                db,
                id,
                reasonCode: reasonCode,
                reasonDetail: reasonDetail,
              ),
      dbCountQuarantinedInboxStagingEntries: () =>
          dbCountQuarantinedInboxStagingEntries(db),
    );
    inbox = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: staging,
      recoveryOnly: true,
      replayRecoveredInboxChatMessage:
          (message, {String? stagedEntryId}) async =>
              mapChatReplayOutcomeToDisposition(
                await listener.processIncomingMessage(
                  message,
                  suppressNotification: true,
                  stagedEntryId: stagedEntryId,
                ),
              ),
    );
    expect(
      await inbox.startRecoveryOnlyNode(
        base64Encode(utf8.encode('fixture-key')),
        id,
      ),
      isTrue,
    );
  }

  Future<void> close() async {
    network.handlers.remove(id);
    transport.setOnline(false);
    transport.dispose();
    listener.dispose();
    inbox.dispose();
    await sql.dispose();
  }

  Future<void> restart() async {
    await close();
    await open();
  }

  Future<(SendChatMessageResult, ConversationMessage?)> send(
    int index, {
    bool authored = false,
  }) async {
    final timestamp = DateTime.utc(
      2026,
      10,
      24,
    ).add(Duration(milliseconds: index)).toIso8601String();
    final intent = authored
        ? AuthoredDirectTextIntent(
            id: 'direct-restart-$index',
            contactPeerId: otherId,
            text: 'Restart fixture item $index',
            timestamp: timestamp,
            token: 'intent-token-$index',
          )
        : null;
    if (intent != null) {
      expect(
        await sql.messageRepo.saveAuthoredDirectTextIntent(intent),
        isTrue,
      );
    }
    return sendChatMessage(
      p2pService: transport,
      messageRepo: sql.messageRepo,
      targetPeerId: otherId,
      text: 'Restart fixture item $index',
      senderPeerId: id,
      senderUsername: 'Fixture',
      messageId: 'direct-restart-$index',
      authoredTextIntentToken: intent?.token,
      preassignedMessageIdIsFresh: true,
      timestamp: DateTime.utc(
        2026,
        10,
        24,
      ).add(Duration(milliseconds: index)).toIso8601String(),
      bridge: bridge,
      recipientMlKemPublicKey: '$otherId-mlkem',
      storeInAckCustodyInboxDetailed: transport.storeInAckCustodyInboxDetailed,
    );
  }

  Future<List<ConversationMessage>> rows() =>
      sql.messageRepo.getMessagesForContact(otherId);

  Future<void> recover() async {
    await recoverStuckSendingMessages(messageRepo: sql.messageRepo);
    await drainDirectInboxCustodyOutbox(
      custodyRepository: sql.messageRepo,
      storeInAckCustodyInboxDetailed: transport.storeInAckCustodyInboxDetailed,
    );
    await retryFailedMessages(
      messageRepo: sql.messageRepo,
      identityRepo: FakeIdentityRepository()
        ..seed(FakeIdentityRepository.makeIdentity(peerId: id)),
      contactRepo: contacts,
      p2pService: transport,
      bridge: bridge,
    );
  }

  Future<void> drain() async {
    final result = await inbox.drainOfflineInboxFully();
    expect(result.isSuccessful, isTrue);
    expect(await sql.db.query('inbox_staging_entries'), isEmpty);
  }
}

void main() {
  Future<(_SqlPeer, _SqlPeer)> pair({_SendCut? cut}) async {
    final temp = await Directory.systemTemp.createTemp('direct-text-restart-');
    final network = _CommittedNetwork();
    final sender = _SqlPeer(
      'restart-sender',
      'restart-recipient',
      '${temp.path}/sender.sqlite',
      network,
    );
    final receiver = _SqlPeer(
      'restart-recipient',
      'restart-sender',
      '${temp.path}/receiver.sqlite',
      network,
    );
    await sender.open(cut: cut);
    await receiver.open();
    addTearDown(() async {
      await sender.close();
      await receiver.close();
      await temp.delete(recursive: true);
    });
    return (sender, receiver);
  }

  test(
    'authored intent projection can be deleted for me before custody',
    () async {
      final (sender, receiver) = await pair();
      final intent = AuthoredDirectTextIntent(
        id: 'cancel-before-custody',
        contactPeerId: sender.otherId,
        text: 'cancelled authored text',
        timestamp: '2026-10-25T00:00:00.000Z',
        token: 'cancel-token',
      );
      expect(
        await sender.sql.messageRepo.saveAuthoredDirectTextIntent(intent),
        isTrue,
      );
      final projection = (await sender.rows()).single;
      expect(await sender.sql.messageRepo.getMessage(intent.id), isNull);
      expect(
        await deleteMessageForMe(
          message: projection,
          messageRepo: sender.sql.messageRepo,
        ),
        1,
      );
      expect(await sender.rows(), isEmpty);
      await sender.restart();
      await sender.recover();
      expect(await sender.rows(), isEmpty);
      expect(await receiver.rows(), isEmpty);
      expect(sender.bridge.commandLog, isNot(contains('message.encrypt')));
    },
  );

  test('DC-002 exact 100 direct messages retain order and identity across '
      'both-peer SQLite restarts and already-delivered inbox replay', () async {
    final (sender, receiver) = await pair();
    sender.network.duplicateOnDeliver = true;
    final ids = <String>[];
    final envelopes = <String>[];
    final burst = await Future.wait([
      for (var i = 0; i < 100; i++) sender.send(i),
    ]);
    for (final sent in burst) {
      expect(sent.$1, SendChatMessageResult.success);
      ids.add(sent.$2!.id);
      // Replay the actual serialized envelope, not a regenerated message.
      final envelope = sender.transport.sentChatEnvelopes.firstWhere(
        (wire) => (jsonDecode(wire) as Map)['id'] == sent.$2!.id,
      );
      expect((jsonDecode(envelope) as Map)['id'], sent.$2!.id);
      envelopes.add(envelope);
    }
    final receiverIds = (await receiver.rows()).map((row) => row.id).toList();
    Future<void> exactRows() async {
      final outgoing = await sender.rows();
      final incoming = await receiver.rows();
      expect(outgoing.map((row) => row.id), orderedEquals(ids));
      expect(incoming.map((row) => row.dedupKey), orderedEquals(ids));
      expect(incoming.map((row) => row.id), orderedEquals(receiverIds));
      expect(
        incoming.map((row) => row.text),
        orderedEquals(outgoing.map((row) => row.text)),
      );
      expect(incoming.map((row) => row.id).toSet(), hasLength(100));
      expect(await sender.sql.db.query('messages'), hasLength(100));
      expect(await receiver.sql.db.query('messages'), hasLength(100));
      expect(outgoing.every((row) => row.status == 'delivered'), isTrue);
    }

    await exactRows();
    await sender.restart();
    await receiver.restart();
    await exactRows();
    // Production custody loads at most 50 obligations per recovery pass.
    for (var pass = 0; pass < 2; pass++) {
      await sender.recover();
      await receiver.drain();
    }
    expect(await sender.sql.messageRepo.loadDirectInboxCustody(), isEmpty);
    final ackedBeforeReplay = receiver.bridge.acked.length;
    for (final envelope in envelopes) {
      expect(
        sender.network.storeInInbox(sender.id, receiver.id, envelope),
        isTrue,
      );
    }
    await receiver.drain();
    expect(receiver.bridge.acked.length - ackedBeforeReplay, 100);
    await sender.recover();
    await receiver.drain();
    await exactRows();
    await sender.restart();
    await receiver.restart();
    await exactRows();
  }, timeout: const Timeout(Duration(seconds: 90)));

  for (final checkpoint in _Checkpoint.values) {
    test('DC-004 ${checkpoint.name}: abandoned sender resumes the same message '
        'exactly once after SQLite reopen', () async {
      final cut = _SendCut(checkpoint);
      final (sender, receiver) = await pair(cut: cut);
      if (checkpoint == _Checkpoint.afterRelayAck) {
        sender.transport.discoverAlwaysFails = true;
        sender.transport.dialAlwaysFails = true;
        sender.network.deliveryFails = true;
      }
      cut.start(() async {
        await sender.send(0, authored: true);
      });
      await cut.reached.future.timeout(const Duration(seconds: 10));
      final before = await sender.rows();
      final custodyBefore = await sender.sql.messageRepo
          .loadDirectInboxCustodyOwnerForMessageId(
            messageId: 'direct-restart-0',
          );
      expect(before, hasLength(1));
      if (before.isNotEmpty) expect(before.single.status, 'sending');
      expect(
        await sender.sql.db.query('authored_direct_text_intents'),
        checkpoint == _Checkpoint.beforeCustody ? hasLength(1) : isEmpty,
      );
      expect(
        await sender.sql.db.query('messages'),
        checkpoint == _Checkpoint.beforeCustody ? isEmpty : hasLength(1),
      );
      expect(
        custodyBefore,
        checkpoint == _Checkpoint.beforeCustody ? isNull : isNotNull,
      );
      expect(
        await receiver.rows(),
        checkpoint == _Checkpoint.afterTransmit ? hasLength(1) : isEmpty,
      );
      if (checkpoint == _Checkpoint.afterRelayAck) {
        expect(sender.network.inboxCount(receiver.id), greaterThan(0));
      } else if (checkpoint != _Checkpoint.afterTransmit) {
        expect(sender.network.deliverCallCount, 0);
        expect(sender.network.storeInInboxCallCount, 0);
      }
      await sender.restart();
      final custodyAfter = await sender.sql.messageRepo
          .loadDirectInboxCustodyOwnerForMessageId(
            messageId: 'direct-restart-0',
          );
      expect(custodyAfter?.wireEnvelope, custodyBefore?.wireEnvelope);
      expect(custodyAfter?.incarnationId, custodyBefore?.incarnationId);
      sender.network.deliveryFails = false;
      await sender.recover();
      await receiver.drain();
      await sender.recover();
      await receiver.drain();
      final incoming = await receiver.rows();
      final outgoing = await sender.rows();
      expect(incoming, hasLength(1));
      expect(incoming.single.dedupKey, 'direct-restart-0');
      expect(outgoing, hasLength(1));
      expect(outgoing.single.id, 'direct-restart-0');
      expect(outgoing.single.status, 'delivered');
      expect(await sender.sql.db.query('messages'), hasLength(1));
      expect(await receiver.sql.db.query('messages'), hasLength(1));
      expect(
        sender.bridge.commandLog.where((cmd) => cmd == 'message.encrypt'),
        checkpoint == _Checkpoint.beforeCustody ? hasLength(1) : isEmpty,
        reason:
            'prepare one pre-custody intent, otherwise replay exact ciphertext',
      );
      expect(await sender.sql.messageRepo.loadDirectInboxCustody(), isEmpty);
      await sender.restart();
      await receiver.restart();
      expect((await receiver.rows()).single.id, incoming.single.id);
      expect((await sender.rows()).single.status, 'delivered');
    }, timeout: const Timeout(Duration(seconds: 30)));
  }
}
