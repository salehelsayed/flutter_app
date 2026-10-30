import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/local_ai_preview_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/translate_preview/translate_preview_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class LocalPreviewFixture {
  Directory? directory;
  late Database db;
  int nowMs = DateTime.utc(2030).millisecondsSinceEpoch;
  final pending = <Future<void>>[];

  Future<void> open({int version = currentIdentityDatabaseVersion}) async {
    directory ??= await Directory.systemTemp.createTemp('local-ai-preview-');
    db = await databaseFactoryFfi.openDatabase(
      '${directory!.path}/identity.db',
      options: OpenDatabaseOptions(
        version: version,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
  }

  Future<void> reopen() async {
    await db.close();
    await open();
  }

  Future<void> dispose() async {
    if (db.isOpen) await db.close();
    await directory?.delete(recursive: true);
  }

  Future<T> _track<T>(Future<T> future) {
    pending.add(future.then<void>((_) {}));
    return future;
  }

  TranslatePreviewPersistence get store => TranslatePreviewPersistence(
    loadTranscript: (owner) => _track(
      dbLoadLocalTranscript(db, owner.id, owner.messageId!, nowMs: nowMs),
    ),
    saveTranscript: (owner, result) => _track(
      dbSaveLocalTranscript(
        db,
        owner.id,
        owner.messageId!,
        result,
        nowMs: nowMs,
      ),
    ),
    loadTranslation: (owner, source, target) => _track(
      dbLoadLocalTranslation(
        db,
        ownerKind: owner.kind.name,
        ownerId: owner.id,
        messageId: owner.messageId,
        source: source,
        targetLanguage: target,
        nowMs: nowMs,
      ),
    ),
    saveTranslation: (owner, source, target, result) => _track(
      dbSaveLocalTranslation(
        db,
        ownerKind: owner.kind.name,
        ownerId: owner.id,
        messageId: owner.messageId,
        source: source,
        targetLanguage: target,
        result: result,
        nowMs: nowMs,
      ),
    ),
  );

  Future<void> flush(WidgetTester tester) async {
    await tester.pump();
    for (var turn = 0; turn < 20; turn++) {
      if (pending.isEmpty) return;
      final current = List<Future<void>>.from(pending);
      pending.clear();
      await tester.runAsync(() => Future.wait(current));
      await tester.pump();
    }
    throw StateError('Local preview operations did not settle');
  }

  Future<void> seedVoice({
    String id = 'voice',
    String messageId = 'message',
  }) async {
    final iso = DateTime.fromMillisecondsSinceEpoch(
      nowMs,
      isUtc: true,
    ).toIso8601String();
    await db.insert('messages', {
      'id': messageId,
      'contact_peer_id': 'contact',
      'sender_peer_id': 'contact',
      'text': '',
      'timestamp': iso,
      'created_at': iso,
      'is_incoming': 1,
    });
    await db.insert('media_attachments', {
      'id': id,
      'message_id': messageId,
      'mime': 'audio/mp4',
      'size': 2,
      'media_type': 'audio',
      'duration_ms': 1000,
      'local_path': '/voice.m4a',
      'download_status': 'done',
      'created_at': iso,
      'owner_lane': 'direct',
    });
  }

  Future<void> seedThought({
    String id = 'thought',
    String source = 'أنا في الطريق',
  }) async {
    final now = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);
    await dbInsertPost(db, {
      'post_id': id,
      'event_id': 'event-$id',
      'sender_peer_id': 'contact',
      'author_peer_id': 'contact',
      'author_username': 'Fixture',
      'text': source,
      'audience_kind': 'all',
      'post_created_at': now.toIso8601String(),
      'visible_at': now.toIso8601String(),
      'expires_at': now.add(const Duration(days: 1)).toIso8601String(),
    });
  }
}
