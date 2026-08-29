import 'dart:async';

import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/application/ingest_staged_push_envelopes_use_case.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_test/flutter_test.dart';

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
    'tapped message is available from payload ingest while relay drain never resolves',
    () async {
      final drain = Completer<void>();
      final store = _MemoryPushEnvelopeStore();
      await store.stage(
        const StagedPushEnvelope(
          kind: 'chat',
          kem: 'kem',
          ciphertext: 'cipher',
          nonce: 'nonce-fast',
          senderPeerId: 'peer-alice',
          messageId: 'push-msg',
          receivedAtMs: 1,
        ),
      );
      final rendered = <ChatMessage>[];
      final useCase = IngestStagedPushEnvelopesUseCase(
        store: store,
        localPeerIdProvider: () async => 'local-peer',
        replayChatMessage:
            (
              message, {
              required suppressNotification,
              String? stagedEntryId,
            }) async {
              rendered.add(message);
              return (
                disposition: RecoveredInboxChatDisposition.committed,
                reasonCode: 'stored',
                reasonDetail: null,
              );
            },
      );

      await useCase(source: 'notification_tap_prepare');

      expect(rendered, hasLength(1));
      expect(rendered.single.from, 'peer-alice');
      expect(rendered.single.to, 'local-peer');
      expect(rendered.single.transport, 'inbox');
      expect(drain.isCompleted, isFalse);
    },
  );

  test(
    'bounded-timeout path can fall through and render later via live stream',
    () async {
      final store = _MemoryPushEnvelopeStore();
      await store.stage(
        const StagedPushEnvelope(
          kind: 'chat',
          kem: 'kem',
          ciphertext: 'cipher',
          nonce: 'nonce-slow',
          senderPeerId: 'peer-alice',
          messageId: 'push-msg-slow',
          receivedAtMs: 1,
        ),
      );
      final gate = Completer<void>();
      final rendered = <ChatMessage>[];
      final useCase = IngestStagedPushEnvelopesUseCase(
        store: store,
        localPeerIdProvider: () async => 'local-peer',
        replayChatMessage:
            (
              message, {
              required suppressNotification,
              String? stagedEntryId,
            }) async {
              await gate.future;
              rendered.add(message);
              return (
                disposition: RecoveredInboxChatDisposition.committed,
                reasonCode: 'stored',
                reasonDetail: null,
              );
            },
      );

      final ingest = useCase(source: 'notification_tap_prepare');
      await Future<void>.delayed(Duration.zero);
      expect(rendered, isEmpty);
      gate.complete();
      await ingest;

      expect(rendered, hasLength(1));
    },
  );
}
