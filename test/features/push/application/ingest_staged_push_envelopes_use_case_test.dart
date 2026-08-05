import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/application/ingest_staged_push_envelopes_use_case.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryPushEnvelopeStore implements PushEnvelopeStagingStore {
  final entries = <String, StagedPushEnvelope>{};
  final cleared = <String>[];

  @override
  Future<void> stage(StagedPushEnvelope entry) async {
    entries[entry.id] = entry;
  }

  @override
  Future<List<StagedPushEnvelope>> readAll() async =>
      entries.values.toList()
        ..sort((a, b) => a.receivedAtMs.compareTo(b.receivedAtMs));

  @override
  Future<void> clear(String id) async {
    cleared.add(id);
    entries.remove(id);
  }

  @override
  Future<void> prune() async {}
}

StagedPushEnvelope _envelope({
  String nonce = 'nonce-1',
  String senderPeerId = 'peer-alice',
  String? messageId = 'push-message-1',
  int receivedAtMs = 1,
  bool identityResolutionPending = false,
}) {
  return StagedPushEnvelope(
    kind: 'chat',
    kem: 'kem-$nonce',
    ciphertext: 'cipher-$nonce',
    nonce: nonce,
    senderPeerId: senderPeerId,
    messageId: messageId,
    identityResolutionPending: identityResolutionPending,
    receivedAtMs: receivedAtMs,
  );
}

StagedPushEnvelope _reactionEnvelope({
  String nonce = 'reaction-nonce-1',
  String eventId = 'reaction-event-1',
  String action = ReactionPayload.addAction,
  String targetMessageId = 'target-message-1',
}) {
  return StagedPushEnvelope(
    kind: 'reaction',
    kem: 'reaction-kem',
    ciphertext: 'reaction-ciphertext',
    nonce: nonce,
    senderPeerId: 'peer-alice',
    messageId: eventId,
    eventId: eventId,
    action: action,
    targetMessageId: targetMessageId,
    receivedAtMs: 2,
  );
}

RecoveredInboxReplayOutcome _committed() => (
  disposition: RecoveredInboxChatDisposition.committed,
  reasonCode: 'stored',
  reasonDetail: null,
);

RecoveredInboxReplayOutcome _retryable() => (
  disposition: RecoveredInboxChatDisposition.retryable,
  reasonCode: 'deferred',
  reasonDetail: null,
);

RecoveredInboxReplayOutcome _rejected(String reasonCode) => (
  disposition: RecoveredInboxChatDisposition.rejected,
  reasonCode: reasonCode,
  reasonDetail: null,
);

void main() {
  test(
    'canonical completeness rejects retained and migration-deferred work',
    () {
      expect(
        const IngestStagedPushEnvelopesResult.empty().isCanonicalStateComplete,
        isTrue,
      );
      expect(
        const IngestStagedPushEnvelopesResult(
          attempted: 1,
          committed: 0,
          blocked: 0,
          deferredByMigration: 0,
          retained: 1,
          clearedMalformed: 0,
        ).isCanonicalStateComplete,
        isFalse,
      );
      expect(
        const IngestStagedPushEnvelopesResult(
          attempted: 0,
          committed: 0,
          blocked: 0,
          deferredByMigration: 1,
          retained: 1,
          clearedMalformed: 0,
        ).isCanonicalStateComplete,
        isFalse,
      );
    },
  );

  group('IngestStagedPushEnvelopesUseCase', () {
    test(
      'young unreadable final-file custody keeps canonical state incomplete',
      () async {
        final now = DateTime.utc(2026, 8, 4, 12);
        final directory = await Directory.systemTemp.createTemp(
          'push-envelope-unreadable-status-',
        );
        addTearDown(() async {
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        });
        final torn = File('${directory.path}/nonce-v1-torn.json');
        await torn.writeAsString('{"kind":"chat",');
        await torn.setLastModified(now);
        final store = FilePushEnvelopeStagingStore(
          directory: directory,
          now: () => now,
          malformedRetryWindow: const Duration(seconds: 5),
        );
        final useCase = IngestStagedPushEnvelopesUseCase(
          store: store,
          localPeerIdProvider: () async => 'local-peer',
          replayChatMessage:
              (
                message, {
                required suppressNotification,
                String? stagedEntryId,
              }) async => _committed(),
        );

        final retained = await useCase();

        expect(retained.attempted, 0);
        expect(retained.retainedUnreadableFinalFiles, 1);
        expect(retained.isCanonicalStateComplete, isFalse);
        expect(await torn.exists(), isTrue);

        await torn.setLastModified(now.subtract(const Duration(minutes: 1)));
        final afterAgedCleanup = await useCase();
        expect(afterAgedCleanup.retainedUnreadableFinalFiles, 0);
        expect(afterAgedCleanup.isCanonicalStateComplete, isTrue);
        expect(await torn.exists(), isFalse);

        final normalEmpty = await useCase();
        expect(normalEmpty.retainedUnreadableFinalFiles, 0);
        expect(normalEmpty.isCanonicalStateComplete, isTrue);
      },
    );

    test(
      'identity-pending ciphertext custody is retained without replay',
      () async {
        final store = _MemoryPushEnvelopeStore();
        await store.stage(
          _envelope(messageId: null, identityResolutionPending: true),
        );
        var replayed = false;
        final useCase = IngestStagedPushEnvelopesUseCase(
          store: store,
          localPeerIdProvider: () async => 'local-peer',
          replayChatMessage:
              (
                message, {
                required suppressNotification,
                String? stagedEntryId,
              }) async {
                replayed = true;
                return _committed();
              },
        );

        final result = await useCase();

        expect(replayed, isFalse);
        expect(result.retained, 1);
        expect(result.clearedMalformed, 0);
        expect(store.entries, hasLength(1));
      },
    );

    test('staged reaction dispatches to reaction replay', () async {
      final store = _MemoryPushEnvelopeStore();
      await store.stage(_reactionEnvelope());
      final replayedReactions = <ChatMessage>[];
      final stagedIds = <String?>[];

      final useCase = IngestStagedPushEnvelopesUseCase(
        store: store,
        localPeerIdProvider: () async => 'local-peer',
        replayChatMessage:
            (
              message, {
              required suppressNotification,
              String? stagedEntryId,
            }) async {
              fail('a staged reaction must never enter replayChatMessage');
            },
        replayReactionMessage: (message, {String? stagedEntryId}) async {
          replayedReactions.add(message);
          stagedIds.add(stagedEntryId);
          return _committed();
        },
      );

      final result = await useCase();

      expect(result.attempted, 1);
      expect(result.committed, 1);
      expect(store.entries, isEmpty);
      expect(stagedIds, ['reaction-nonce-1']);
      expect(replayedReactions, hasLength(1));
      final message = replayedReactions.single;
      expect(message.from, 'peer-alice');
      expect(message.to, 'local-peer');
      expect(message.transport, 'push');
      final envelope = ReactionPayload.parseEncryptedEnvelope(message.content);
      expect(envelope, isNotNull);
      expect(envelope!['eventId'], 'reaction-event-1');
      expect(envelope['action'], ReactionPayload.addAction);
      expect(envelope['targetMessageId'], 'target-message-1');
    });

    test(
      'staged envelope decrypts through the standard incoming pipeline, fills local to, and clears only committed entries',
      () async {
        final store = _MemoryPushEnvelopeStore();
        await store.stage(_envelope(nonce: 'nonce-a', messageId: null));
        await store.stage(_envelope(nonce: 'nonce-b', receivedAtMs: 2));
        final replayed = <ChatMessage>[];
        final suppressions = <bool>[];
        final stagedIds = <String?>[];

        final useCase = IngestStagedPushEnvelopesUseCase(
          store: store,
          localPeerIdProvider: () async => 'local-peer',
          replayChatMessage:
              (
                message, {
                required suppressNotification,
                String? stagedEntryId,
              }) async {
                replayed.add(message);
                suppressions.add(suppressNotification);
                stagedIds.add(stagedEntryId);
                return stagedEntryId == 'nonce-a' ? _committed() : _retryable();
              },
        );

        final result = await useCase();

        expect(result.attempted, 2);
        expect(result.committed, 1);
        expect(replayed, hasLength(2));
        expect(replayed.first.from, 'peer-alice');
        expect(replayed.first.to, 'local-peer');
        expect(replayed.first.transport, 'push');
        expect(replayed.first.content, contains('"version":"2"'));
        expect(suppressions, [true, true]);
        expect(stagedIds, ['nonce-a', 'nonce-b']);
        expect(store.cleared, ['nonce-a']);
        expect(store.entries.keys, ['nonce-b']);
      },
    );

    test(
      'confirmed-persisted duplicate clears its staging entry; other rejected reasons stay retained',
      () async {
        final store = _MemoryPushEnvelopeStore();
        await store.stage(_envelope(nonce: 'nonce-dup'));
        await store.stage(_envelope(nonce: 'nonce-stranger', receivedAtMs: 2));

        final useCase = IngestStagedPushEnvelopesUseCase(
          store: store,
          localPeerIdProvider: () async => 'local-peer',
          replayChatMessage:
              (
                message, {
                required suppressNotification,
                String? stagedEntryId,
              }) async => stagedEntryId == 'nonce-dup'
              ? _rejected('duplicate_confirmed_visible')
              : _rejected('unknown_sender_stranger'),
        );

        final result = await useCase();

        // The duplicate's prior copy is durably persisted and visible in the
        // DB (that is what duplicate_confirmed_visible asserts), so the
        // redundant push-envelope cache entry must be cleared instead of
        // being re-decrypted on every later ingest until TTL/cap eviction.
        expect(store.cleared, ['nonce-dup']);
        expect(store.entries.keys, ['nonce-stranger']);
        expect(result.attempted, 2);
        expect(result.committed, 0);
        expect(result.retained, 1);
      },
    );

    test(
      'blocked sender is rejected before replay, malformed entries clear, and active migration gate retains entries',
      () async {
        final blockedStore = _MemoryPushEnvelopeStore();
        await blockedStore.stage(_envelope(senderPeerId: 'blocked-peer'));
        var replayCount = 0;
        final blocked = IngestStagedPushEnvelopesUseCase(
          store: blockedStore,
          localPeerIdProvider: () async => 'local-peer',
          isSenderBlocked: (senderPeerId) async =>
              senderPeerId == 'blocked-peer',
          replayChatMessage:
              (
                message, {
                required suppressNotification,
                String? stagedEntryId,
              }) async {
                replayCount++;
                return _committed();
              },
        );
        final blockedResult = await blocked();
        expect(blockedResult.blocked, 1);
        expect(replayCount, 0);
        expect(blockedStore.cleared, ['nonce-1']);

        final gatedStore = _MemoryPushEnvelopeStore();
        await gatedStore.stage(_envelope(nonce: 'gated'));
        final gated = IngestStagedPushEnvelopesUseCase(
          store: gatedStore,
          localPeerIdProvider: () async => 'local-peer',
          accountMigrationNetworkGate: () async => false,
          replayChatMessage:
              (
                message, {
                required suppressNotification,
                String? stagedEntryId,
              }) async {
                fail('migration-gated ingest must not replay');
              },
        );
        final gatedResult = await gated();
        expect(gatedResult.deferredByMigration, 1);
        expect(gatedStore.cleared, isEmpty);
        expect(gatedStore.entries.keys, ['gated']);
      },
    );

    test(
      'two concurrent ingest passes over the same entry coalesce to one clear and one replay',
      () async {
        final store = _MemoryPushEnvelopeStore();
        await store.stage(_envelope(nonce: 'shared'));
        final replayGate = Completer<void>();
        var replayCount = 0;
        final useCase = IngestStagedPushEnvelopesUseCase(
          store: store,
          localPeerIdProvider: () async => 'local-peer',
          replayChatMessage:
              (
                message, {
                required suppressNotification,
                String? stagedEntryId,
              }) async {
                replayCount++;
                await replayGate.future;
                return _committed();
              },
        );

        final first = useCase();
        final second = useCase();
        await Future<void>.delayed(Duration.zero);
        expect(replayCount, 1);
        replayGate.complete();
        await Future.wait([first, second]);

        expect(replayCount, 1);
        expect(store.cleared, ['shared']);
        expect(store.entries, isEmpty);
      },
    );

    test('startup/resume ingestion runs without a notification tap', () async {
      final store = _MemoryPushEnvelopeStore();
      await store.stage(_envelope(nonce: 'resume'));
      final sources = <String?>[];
      final useCase = IngestStagedPushEnvelopesUseCase(
        store: store,
        localPeerIdProvider: () async => 'local-peer',
        replayChatMessage:
            (
              message, {
              required suppressNotification,
              String? stagedEntryId,
            }) async {
              return _committed();
            },
        onIngestStarted: (source) {
          sources.add(source);
        },
      );

      await useCase(source: 'runtime_ready');

      expect(sources, ['runtime_ready']);
      expect(store.entries, isEmpty);
    });
  });
}
