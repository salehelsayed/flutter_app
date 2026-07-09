import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';

typedef LocalPeerIdProvider = Future<String> Function();
typedef SenderBlockedCheck = Future<bool> Function(String senderPeerId);
typedef PushIngestMigrationGate = Future<bool> Function();
typedef PushIngestStarted = void Function(String? source);
typedef StagedPushReplayChatMessage =
    Future<RecoveredInboxReplayOutcome> Function(
      ChatMessage message, {
      required bool suppressNotification,
      String? stagedEntryId,
    });

class IngestStagedPushEnvelopesResult {
  final int attempted;
  final int committed;
  final int blocked;
  final int deferredByMigration;
  final int retained;
  final int clearedMalformed;

  const IngestStagedPushEnvelopesResult({
    required this.attempted,
    required this.committed,
    required this.blocked,
    required this.deferredByMigration,
    required this.retained,
    required this.clearedMalformed,
  });

  const IngestStagedPushEnvelopesResult.empty()
    : this(
        attempted: 0,
        committed: 0,
        blocked: 0,
        deferredByMigration: 0,
        retained: 0,
        clearedMalformed: 0,
      );
}

class IngestStagedPushEnvelopesUseCase {
  final PushEnvelopeStagingStore store;
  final LocalPeerIdProvider localPeerIdProvider;
  final StagedPushReplayChatMessage replayChatMessage;
  final SenderBlockedCheck isSenderBlocked;
  final PushIngestMigrationGate accountMigrationNetworkGate;
  final PushIngestStarted? onIngestStarted;

  Future<IngestStagedPushEnvelopesResult>? _inFlight;

  IngestStagedPushEnvelopesUseCase({
    required this.store,
    required this.localPeerIdProvider,
    required this.replayChatMessage,
    SenderBlockedCheck? isSenderBlocked,
    PushIngestMigrationGate? accountMigrationNetworkGate,
    this.onIngestStarted,
  }) : isSenderBlocked = isSenderBlocked ?? _allowSender,
       accountMigrationNetworkGate =
           accountMigrationNetworkGate ?? _allowMigrationNetwork;

  Future<IngestStagedPushEnvelopesResult> call({String? source}) {
    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }
    final started = _run(source: source);
    _inFlight = started;
    return started.whenComplete(() {
      if (identical(_inFlight, started)) {
        _inFlight = null;
      }
    });
  }

  Future<IngestStagedPushEnvelopesResult> _run({String? source}) async {
    onIngestStarted?.call(source);
    await store.prune();
    final entries = await store.readAll();
    if (entries.isEmpty) {
      return const IngestStagedPushEnvelopesResult.empty();
    }

    final allowed = await accountMigrationNetworkGate();
    if (!allowed) {
      return IngestStagedPushEnvelopesResult(
        attempted: 0,
        committed: 0,
        blocked: 0,
        deferredByMigration: entries.length,
        retained: entries.length,
        clearedMalformed: 0,
      );
    }

    final localPeerId = await localPeerIdProvider();
    var attempted = 0;
    var committed = 0;
    var blocked = 0;
    var retained = 0;
    var clearedMalformed = 0;

    for (final entry in entries) {
      if (entry.kind != 'chat' ||
          entry.kem.isEmpty ||
          entry.ciphertext.isEmpty ||
          entry.nonce.isEmpty ||
          entry.senderPeerId.isEmpty) {
        await store.clear(entry.id);
        clearedMalformed++;
        continue;
      }

      if (await isSenderBlocked(entry.senderPeerId)) {
        await store.clear(entry.id);
        blocked++;
        continue;
      }

      attempted++;
      final message = _messageFromEntry(entry, localPeerId: localPeerId);
      final outcome = await replayChatMessage(
        message,
        suppressNotification: true,
        stagedEntryId: entry.id,
      );
      switch (outcome.disposition) {
        case RecoveredInboxChatDisposition.committed:
          await store.clear(entry.id);
          committed++;
          break;
        case RecoveredInboxChatDisposition.rejected:
          // duplicate_confirmed_visible asserts the prior copy is durably
          // persisted AND visible in the DB, so this staged envelope is a
          // redundant cache entry — clearing it cannot destroy the last copy
          // (INV-1 custody). Every other rejected reason stays retained.
          if (outcome.reasonCode == 'duplicate_confirmed_visible') {
            await store.clear(entry.id);
            break;
          }
          retained++;
          break;
        case RecoveredInboxChatDisposition.retryable:
        case RecoveredInboxChatDisposition.quarantined:
          retained++;
          break;
      }
    }

    return IngestStagedPushEnvelopesResult(
      attempted: attempted,
      committed: committed,
      blocked: blocked,
      deferredByMigration: 0,
      retained: retained,
      clearedMalformed: clearedMalformed,
    );
  }

  ChatMessage _messageFromEntry(
    StagedPushEnvelope entry, {
    required String localPeerId,
  }) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      entry.receivedAtMs,
      isUtc: true,
    ).toIso8601String();
    final content = MessagePayload.buildEncryptedEnvelope(
      id: entry.messageId ?? entry.nonce,
      senderPeerId: entry.senderPeerId,
      senderUsername: '',
      kem: entry.kem,
      ciphertext: entry.ciphertext,
      nonce: entry.nonce,
    );
    return ChatMessage(
      from: entry.senderPeerId,
      to: localPeerId,
      content: content,
      timestamp: timestamp,
      isIncoming: true,
      transport: 'push',
    );
  }

  static Future<bool> _allowSender(String _) async => false;

  static Future<bool> _allowMigrationNetwork() async => true;
}
