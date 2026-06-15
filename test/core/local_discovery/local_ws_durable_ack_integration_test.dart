// LAN ack-after-commit integration coverage — host-runnable (real
// LocalWsServer over loopback plus real inbox_staging DB helpers, no mDNS, no
// device).
//
// Tracking: Test-Flight-Improv/114-lan-ack-after-commit.md Phase 4.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/database/helpers/inbox_staging_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/045_inbox_staging_entries.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository_impl.dart';
import 'package:flutter_app/core/local_discovery/lan_ack.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const senderPeerId = 'phase4-sender';
const receiverPeerId = 'phase4-receiver';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('114 S4 LAN durable ack loopback', () {
    test(
      'receiver killed after committed ack does not lose the message: staged row replays on restart',
      () async {
        final dbPath = await _newDbPath('lan_ack_restart_');
        final receiverDb = await _DbHarness.open(dbPath);
        final sender = LocalWsServer();
        final receiver = LocalWsServer();
        final replayedIds = <String>[];

        try {
          receiver.configureInboundChatCommitHandler(
            _stageLanChat(receiverDb.repo),
          );
          await sender.start();
          final receiverPort = await receiver.start();

          final ack = await sender.sendMessageWithAck(
            'localhost',
            receiverPort,
            _chatEnvelope(messageId: 'msg-restart'),
            senderPeerId,
            receiverPeerId,
          );

          expect(ack, LanSendAck.committed);

          final staged = await receiverDb.singleRecoverable();
          expect(staged.entryId, startsWith('lan:'));
          expect(staged.senderPeerId, senderPeerId);
          expect(staged.ownerPeerId, receiverPeerId);

          receiver.dispose();
          await receiverDb.close();

          final restartedDb = await _DbHarness.open(dbPath);
          try {
            await _replayRecoverableLanChats(
              restartedDb.repo,
              replayedIds: replayedIds,
            );
            await _replayRecoverableLanChats(
              restartedDb.repo,
              replayedIds: replayedIds,
            );

            expect(replayedIds, ['msg-restart']);
            expect(
              await restartedDb.repo.getEntry(staged.entryId),
              isNull,
              reason: 'committed replay must delete the staged row',
            );
          } finally {
            await restartedDb.close();
          }
        } finally {
          sender.dispose();
          receiver.dispose();
          await receiverDb.close();
          await _deleteDbPath(dbPath);
        }
      },
    );

    test(
      'decrypt failure after committed ack quarantines the staged row instead of losing the message',
      () async {
        final dbPath = await _newDbPath('lan_ack_quarantine_');
        final db = await _DbHarness.open(dbPath);
        final sender = LocalWsServer();
        final receiver = LocalWsServer();

        try {
          receiver.configureInboundChatCommitHandler(_stageLanChat(db.repo));
          await sender.start();
          final receiverPort = await receiver.start();

          final ack = await sender.sendMessageWithAck(
            'localhost',
            receiverPort,
            _chatEnvelope(messageId: 'msg-quarantine'),
            senderPeerId,
            receiverPeerId,
          );

          expect(ack, LanSendAck.committed);

          final staged = await db.singleRecoverable();
          await _quarantineRecoverableLanChats(db.repo);

          final quarantined = await db.repo.getEntry(staged.entryId);
          expect(quarantined, isNotNull);
          expect(quarantined!.status, 'quarantined');
          expect(quarantined.rejectReasonCode, 'decryption_failed');
          expect(quarantined.envelope, contains('msg-quarantine'));
          expect(await db.repo.countQuarantinedEntries(), 1);
        } finally {
          sender.dispose();
          receiver.dispose();
          await db.close();
          await _deleteDbPath(dbPath);
        }
      },
    );

    test(
      'old sender matcher accepts the committed ack within the interactive budget',
      () async {
        final dbPath = await _newDbPath('lan_ack_old_matcher_');
        final db = await _DbHarness.open(dbPath);
        final receiver = LocalWsServer();

        try {
          receiver.configureInboundChatCommitHandler(_stageLanChat(db.repo));
          final receiverPort = await receiver.start();

          final sw = Stopwatch()..start();
          final result = await _sendWithOldMatcher(
            port: receiverPort,
            nonce: 'old-committed-1',
            envelope: _chatEnvelope(messageId: 'msg-old-committed'),
            budget: const Duration(milliseconds: 1500),
          );
          sw.stop();

          expect(result.matched, isTrue);
          expect(result.skippedNacks, 0);
          expect(sw.elapsedMilliseconds, lessThan(1500));
          expect(await db.repo.getEntry('lan:old-committed-1'), isNotNull);
        } finally {
          receiver.dispose();
          await db.close();
          await _deleteDbPath(dbPath);
        }
      },
    );

    test(
      'new sender against old receiver classifies the parse-time ack as legacy and non-durable',
      () async {
        final sender = LocalWsServer();
        final oldReceiver = LocalWsServer();

        try {
          await sender.start();
          final oldPort = await oldReceiver.start();

          final ack = await sender.sendMessageWithAck(
            'localhost',
            oldPort,
            _chatEnvelope(messageId: 'msg-old-receiver'),
            senderPeerId,
            receiverPeerId,
          );

          expect(ack, LanSendAck.legacyAck);
        } finally {
          sender.dispose();
          oldReceiver.dispose();
        }
      },
    );

    test(
      'rejected commit nack resolves the sender promptly with no delivered state possible',
      () async {
        final sender = LocalWsServer();
        final receiver = LocalWsServer();

        try {
          receiver.configureInboundChatCommitHandler(
            (message, {required nonce}) =>
                LanInboundDecision.rejected('migration_blocked'),
          );
          await sender.start();
          final receiverPort = await receiver.start();

          final sw = Stopwatch()..start();
          final ack = await sender.sendMessageWithAck(
            'localhost',
            receiverPort,
            _chatEnvelope(messageId: 'msg-rejected'),
            senderPeerId,
            receiverPeerId,
            timeoutMs: 1000,
          );
          sw.stop();

          expect(ack, LanSendAck.failed);
          expect(sw.elapsedMilliseconds, lessThan(500));
        } finally {
          sender.dispose();
          receiver.dispose();
        }
      },
    );

    test(
      'old sender matcher skips a nack frame mid-wait and times out into fallback',
      () async {
        final receiver = LocalWsServer(
          commitBudget: const Duration(milliseconds: 80),
        );

        try {
          receiver.configureInboundChatCommitHandler(
            (message, {required nonce}) =>
                LanInboundDecision.rejected('staging_failed'),
          );
          final receiverPort = await receiver.start();

          final sw = Stopwatch()..start();
          final result = await _sendWithOldMatcher(
            port: receiverPort,
            nonce: 'old-reject-1',
            envelope: _chatEnvelope(messageId: 'msg-old-reject'),
            budget: const Duration(milliseconds: 250),
          );
          sw.stop();

          expect(result.matched, isFalse);
          expect(result.skippedNacks, 1);
          expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(200));
          expect(sw.elapsedMilliseconds, lessThan(1000));
        } finally {
          receiver.dispose();
        }
      },
    );

    test(
      'media-bearing LAN message replay after receiver kill preserves text and media metadata without silent loss',
      () async {
        final dbPath = await _newDbPath('lan_ack_media_');
        final receiverDb = await _DbHarness.open(dbPath);
        final sender = LocalWsServer();
        final receiver = LocalWsServer();
        final replayedMediaIds = <String>[];

        try {
          receiver.configureInboundChatCommitHandler(
            _stageLanChat(receiverDb.repo),
          );
          await sender.start();
          final receiverPort = await receiver.start();

          final ack = await sender.sendMessageWithAck(
            'localhost',
            receiverPort,
            _chatEnvelope(
              messageId: 'msg-media',
              media: const [
                {
                  'id': 'media-1',
                  'mime': 'image/jpeg',
                  'size': 1200,
                  'downloadStatus': 'pending',
                },
              ],
            ),
            senderPeerId,
            receiverPeerId,
          );

          expect(ack, LanSendAck.committed);
          receiver.dispose();
          await receiverDb.close();

          final restartedDb = await _DbHarness.open(dbPath);
          try {
            final entry = await restartedDb.singleRecoverable();
            final payload = _payloadFromEnvelope(entry.envelope);
            expect(payload['id'], 'msg-media');
            expect(payload['text'], 'media text');
            final media = payload['media'] as List<dynamic>;
            expect(media.single['id'], 'media-1');
            expect(media.single['downloadStatus'], 'pending');

            await _replayRecoverableLanChats(
              restartedDb.repo,
              replayedIds: <String>[],
              replayedMediaIds: replayedMediaIds,
            );

            expect(replayedMediaIds, ['media-1']);
            expect(await restartedDb.repo.getEntry(entry.entryId), isNull);
          } finally {
            await restartedDb.close();
          }
        } finally {
          sender.dispose();
          receiver.dispose();
          await receiverDb.close();
          await _deleteDbPath(dbPath);
        }
      },
    );
  });
}

Future<String> _newDbPath(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  return '${dir.path}/inbox_staging.db';
}

Future<void> _deleteDbPath(String dbPath) async {
  final file = File(dbPath);
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {}
  try {
    final dir = file.parent;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  } catch (_) {}
}

LanInboundChatCommitHandler _stageLanChat(InboxStagingRepository repo) {
  return (message, {required nonce}) async {
    final safeNonce = nonce?.trim();
    if (safeNonce == null || safeNonce.isEmpty) {
      return LanInboundDecision.rejected('missing_nonce');
    }
    final entry = InboxStagingEntry(
      entryId: 'lan:$safeNonce',
      ownerPeerId: message.to,
      senderPeerId: message.from,
      messageType: _messageTypeFromEnvelope(message.content),
      relayTimestamp: message.timestamp.toUtc().toIso8601String(),
      envelope: message.content,
      stagedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await repo.stageEntries([entry]);
    return const LanInboundDecision.committed();
  };
}

Future<void> _replayRecoverableLanChats(
  InboxStagingRepository repo, {
  required List<String> replayedIds,
  List<String>? replayedMediaIds,
}) async {
  final entries = await repo.getRecoverableEntries();
  for (final entry in entries) {
    final payload = _payloadFromEnvelope(entry.envelope);
    replayedIds.add(payload['id'] as String);
    final media = payload['media'];
    if (media is List && media.isNotEmpty && replayedMediaIds != null) {
      replayedMediaIds.add(media.first['id'] as String);
    }
    await repo.deleteEntry(entry.entryId);
  }
}

Future<void> _quarantineRecoverableLanChats(InboxStagingRepository repo) async {
  final entries = await repo.getRecoverableEntries();
  for (final entry in entries) {
    await repo.markQuarantined(
      entry.entryId,
      reasonCode: 'decryption_failed',
      reasonDetail: 'test decrypt failed',
    );
  }
}

Future<({bool matched, int skippedNacks})> _sendWithOldMatcher({
  required int port,
  required String nonce,
  required String envelope,
  required Duration budget,
}) async {
  final ws = await WebSocket.connect('ws://localhost:$port');
  var skippedNacks = 0;
  final matched = Completer<bool>();
  final sub = ws.listen((event) {
    if (event is! String || matched.isCompleted) return;
    final decoded = jsonDecode(event) as Map<String, dynamic>;
    if (decoded['ack'] == true && decoded['nonce'] == nonce) {
      matched.complete(true);
    } else if (decoded['ack'] == false && decoded['nonce'] == nonce) {
      skippedNacks++;
    }
  });

  ws.add(
    jsonEncode({
      'from': senderPeerId,
      'to': receiverPeerId,
      'content': envelope,
      'nonce': nonce,
    }),
  );

  try {
    final didMatch = await matched.future.timeout(
      budget,
      onTimeout: () => false,
    );
    return (matched: didMatch, skippedNacks: skippedNacks);
  } finally {
    await sub.cancel();
    await ws.close();
  }
}

String _chatEnvelope({
  required String messageId,
  List<Map<String, Object?>> media = const [],
}) {
  return jsonEncode({
    'type': 'chat_message',
    'version': '2',
    'payload': {
      'id': messageId,
      'text': media.isEmpty ? 'hello' : 'media text',
      'senderPeerId': senderPeerId,
      'senderUsername': 'Alice',
      'timestamp': DateTime.utc(2026, 6, 13).toIso8601String(),
      if (media.isNotEmpty) 'media': media,
    },
  });
}

String? _messageTypeFromEnvelope(String envelope) {
  final decoded = jsonDecode(envelope) as Map<String, dynamic>;
  return decoded['type']?.toString();
}

Map<String, dynamic> _payloadFromEnvelope(String envelope) {
  final decoded = jsonDecode(envelope) as Map<String, dynamic>;
  return decoded['payload'] as Map<String, dynamic>;
}

class _DbHarness {
  final Database db;
  final InboxStagingRepositoryImpl repo;

  const _DbHarness._({required this.db, required this.repo});

  static Future<_DbHarness> open(String path) async {
    final db = await openDatabase(path, version: 1);
    await runInboxStagingEntriesMigration(db);
    final repo = InboxStagingRepositoryImpl(
      dbInsertInboxStagingEntry: (row) => dbInsertInboxStagingEntry(db, row),
      dbLoadRecoverableInboxStagingEntries: ({limit = 50, entryIds}) =>
          dbLoadRecoverableInboxStagingEntries(
            db,
            limit: limit,
            entryIds: entryIds,
          ),
      dbLoadInboxStagingEntry: (entryId) =>
          dbLoadInboxStagingEntry(db, entryId),
      dbDeleteInboxStagingEntry: (entryId) =>
          dbDeleteInboxStagingEntry(db, entryId),
      dbMarkInboxStagingEntryRetryable:
          (entryId, {required reasonCode, reasonDetail}) =>
              dbMarkInboxStagingEntryRetryable(
                db,
                entryId,
                reasonCode: reasonCode,
                reasonDetail: reasonDetail,
              ),
      dbMarkInboxStagingEntryRejected:
          (entryId, {required reasonCode, reasonDetail}) =>
              dbMarkInboxStagingEntryRejected(
                db,
                entryId,
                reasonCode: reasonCode,
                reasonDetail: reasonDetail,
              ),
      dbMarkInboxStagingEntryQuarantined:
          (entryId, {required reasonCode, reasonDetail}) =>
              dbMarkInboxStagingEntryQuarantined(
                db,
                entryId,
                reasonCode: reasonCode,
                reasonDetail: reasonDetail,
              ),
      dbCountQuarantinedInboxStagingEntries: () =>
          dbCountQuarantinedInboxStagingEntries(db),
    );
    return _DbHarness._(db: db, repo: repo);
  }

  Future<InboxStagingEntry> singleRecoverable() async {
    final entries = await repo.getRecoverableEntries();
    expect(entries, hasLength(1));
    return entries.single;
  }

  Future<void> close() => db.close();
}
