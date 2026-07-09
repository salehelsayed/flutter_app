import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/application/ingest_staged_push_envelopes_use_case.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_test/flutter_test.dart';

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
    'ingested row is returned by the conversation initial-page query',
    () async {
      final messageRepo = InMemoryMessageRepository();
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
      final useCase = IngestStagedPushEnvelopesUseCase(
        store: store,
        localPeerIdProvider: () async => 'local-peer',
        replayChatMessage:
            (
              ChatMessage message, {
              required suppressNotification,
              String? stagedEntryId,
            }) async {
              await messageRepo.saveMessage(
                ConversationMessage(
                  id: 'decrypted-payload-id',
                  contactPeerId: message.from,
                  senderPeerId: message.from,
                  text: 'Announced text',
                  timestamp: message.timestamp,
                  status: 'delivered',
                  isIncoming: true,
                  createdAt: message.timestamp,
                  transport: message.transport,
                ),
              );
              return (
                disposition: RecoveredInboxChatDisposition.committed,
                reasonCode: 'stored',
                reasonDetail: null,
              );
            },
      );

      await useCase(source: 'notification_tap_prepare');

      final page = await messageRepo.getMessagesForContact('peer-alice');
      expect(page, hasLength(1));
      expect(page.single.text, 'Announced text');
      expect(page.single.transport, 'push');
      expect(store.entries, isEmpty);
    },
  );
}
