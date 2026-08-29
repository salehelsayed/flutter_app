import 'dart:convert';

import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/application/ingest_staged_push_envelopes_use_case.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';

class _MemoryPushEnvelopeStore implements PushEnvelopeStagingStore {
  final entries = <String, StagedPushEnvelope>{};

  @override
  Future<void> stage(StagedPushEnvelope entry) async {
    entries[entry.id] = entry;
  }

  @override
  Future<List<StagedPushEnvelope>> readAll() async => entries.values.toList();

  @override
  Future<void> clear(String id) async {
    entries.remove(id);
  }

  @override
  Future<void> prune() async {}
}

void main() {
  test(
    'staged ingest followed by canonical inbox replay keeps one inbox row',
    () async {
      final messageRepo = InMemoryMessageRepository();
      final contactRepo = InMemoryContactRepository()
        ..addTestContact(
          ContactModel(
            peerId: 'peer-alice',
            publicKey: 'pk-alice',
            rendezvous: '/dns4/relay/tcp/443/p2p/relay',
            username: 'Alice',
            signature: 'sig-alice',
            scannedAt: '1970-01-01T00:00:00.000Z',
          ),
        );
      final store = _MemoryPushEnvelopeStore();
      await store.stage(
        const StagedPushEnvelope(
          kind: 'chat',
          kem: 'kem',
          ciphertext: 'cipher',
          nonce: 'nonce-persist',
          senderPeerId: 'peer-alice',
          messageId: 'push-msg',
          receivedAtMs: 1,
        ),
      );
      final plaintext = jsonEncode({
        'id': 'push-msg',
        'text': 'Announced text',
        'senderPeerId': 'peer-alice',
        'senderUsername': 'Alice',
        'timestamp': '1970-01-01T00:00:00.001Z',
      });
      ChatMessage? stagedMessage;
      var notificationStages = 0;
      final useCase = IngestStagedPushEnvelopesUseCase(
        store: store,
        localPeerIdProvider: () async => 'local-peer',
        replayChatMessage:
            (
              ChatMessage message, {
              required suppressNotification,
              String? stagedEntryId,
            }) async {
              stagedMessage = message;
              final (result, _, _) = await handleIncomingChatMessage(
                message: message,
                messageRepo: messageRepo,
                contactRepo: contactRepo,
                predecryptedText: plaintext,
                transport: message.transport,
                stageNotificationDisplayCustody: (_) async {
                  notificationStages++;
                },
              );
              expect(result, HandleChatMessageResult.chatMessage);
              return (
                disposition: RecoveredInboxChatDisposition.committed,
                reasonCode: 'stored',
                reasonDetail: null,
              );
            },
      );

      await useCase(source: 'notification_tap_prepare');

      final staged = stagedMessage!;
      final (replayResult, _, _) = await handleIncomingChatMessage(
        message: ChatMessage(
          from: staged.from,
          to: staged.to,
          content: staged.content,
          timestamp: staged.timestamp,
          isIncoming: true,
          transport: 'inbox',
        ),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        predecryptedText: plaintext,
        transport: 'inbox',
        stageNotificationDisplayCustody: (_) async {
          notificationStages++;
        },
      );

      final page = await messageRepo.getMessagesForContact('peer-alice');
      expect(replayResult, HandleChatMessageResult.duplicate);
      expect(page, hasLength(1));
      expect(page.single.text, 'Announced text');
      expect(page.single.transport, 'inbox');
      expect(notificationStages, 1);
      expect(store.entries, isEmpty);
    },
  );
}
