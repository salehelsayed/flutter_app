// ignore_for_file: file_names
import 'dart:io';

import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'v123 to v124 preserves existing thoughts, chat and cached media',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'thought-upgrade-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/identity.sqlite';
      final photo = File('${directory.path}/kept-photo.jpg');
      const photoBytes = [1, 2, 3, 4];
      await photo.writeAsBytes(photoBytes);

      Future<Database> open(int version) =>
          databaseFactoryFfiNoIsolate.openDatabase(
            path,
            options: OpenDatabaseOptions(
              version: version,
              singleInstance: false,
              onCreate: runProductionOnCreate,
              onUpgrade: runProductionOnUpgrade,
            ),
          );

      const createdAt = '2026-10-27T10:00:00Z';
      final old = await open(123);
      addTearDown(() async {
        if (old.isOpen) await old.close();
      });
      await old.insert('identity', {
        'id': 1,
        'peer_id': 'fixture-owner',
        'public_key': 'fixture-public-key',
        'username': 'Owner',
        'created_at': createdAt,
        'updated_at': createdAt,
      });
      await old.insert('contacts', {
        'peer_id': 'fixture-friend',
        'public_key': 'fixture-friend-public-key',
        'rendezvous': '/fixture-relay',
        'username': 'Friend',
        'signature': 'fixture-signature',
        'scanned_at': createdAt,
      });
      await old.insert('posts', {
        'post_id': 'kept-thought',
        'event_id': 'kept-thought-event',
        'sender_peer_id': 'fixture-owner',
        'author_peer_id': 'fixture-owner',
        'author_username': 'Owner',
        'text': 'Kept thought',
        'audience_kind': 'all_friends',
        'post_created_at': createdAt,
        'visible_at': createdAt,
        'expires_at': '2026-10-28T10:00:00Z',
        'media_kind': 'image',
        'is_incoming': 0,
        'delivery_status': 'sent',
      });
      await old.insert('post_media_attachments', {
        'media_id': 'kept-photo',
        'post_id': 'kept-thought',
        'blob_id': 'kept-blob',
        'kind': 'image',
        'mime': 'image/jpeg',
        'size_bytes': photoBytes.length,
        'position': 0,
        'width': 600,
        'height': 900,
        'local_path': photo.path,
        'download_status': 'done',
        'created_at': createdAt,
        'encryption_key_base64': 'fixture-key',
        'encryption_nonce': 'fixture-nonce',
        'encryption_scheme': 'blob_aes_gcm_v1',
        'content_hash': 'a' * 64,
        'is_encrypted': 1,
      });
      await old.insert('post_recipients', {
        'post_id': 'kept-thought',
        'recipient_peer_id': 'fixture-friend',
        'delivery_owner_kind': 'post',
        'delivery_owner_id': 'kept-thought',
        'delivery_status': 'sent',
        'last_attempt_at': createdAt,
        'delivery_path': 'direct',
        'created_at': createdAt,
        'updated_at': createdAt,
      });
      await old.insert('post_feed_state', {
        'post_id': 'kept-thought',
        'is_hidden': 0,
        'is_read': 0,
      });
      await old.insert('messages', {
        'id': 'kept-reply',
        'contact_peer_id': 'fixture-friend',
        'sender_peer_id': 'fixture-friend',
        'text': 'Kept reply',
        'timestamp': createdAt,
        'status': 'received',
        'is_incoming': 1,
        'created_at': createdAt,
        'quoted_message_id': 'kept-thought',
      });

      const tables = [
        'identity',
        'contacts',
        'posts',
        'post_media_attachments',
        'post_recipients',
        'post_feed_state',
        'messages',
      ];
      final columns = <String, List<String>>{};
      final before = <String, List<Map<String, Object?>>>{};
      for (final table in tables) {
        columns[table] = [
          for (final column in await old.rawQuery('PRAGMA table_info($table)'))
            column['name'] as String,
        ];
        before[table] = await old.query(table);
      }
      expect(
        columns['post_media_attachments'],
        isNot(contains('preview_base64')),
      );
      await old.close();

      final upgraded = await open(124);
      addTearDown(() async {
        if (upgraded.isOpen) await upgraded.close();
      });
      expect(await upgraded.getVersion(), 124);
      for (final table in tables) {
        expect(
          await upgraded.query(table, columns: columns[table]),
          before[table],
          reason: 'v124 must preserve every existing $table value',
        );
      }
      expect(
        (await upgraded.query('post_media_attachments'))
            .single['preview_base64'],
        isNull,
      );
      // A delivered post must not become a view receipt during an upgrade.
      expect(await upgraded.query('post_view_receipts'), isEmpty);
      expect(await photo.readAsBytes(), photoBytes);

      await upgraded.update(
        'post_media_attachments',
        {'preview_base64': 'QUJD'},
        where: 'media_id = ?',
        whereArgs: ['kept-photo'],
      );
      await upgraded.insert('post_view_receipts', {
        'post_id': 'kept-thought',
        'viewer_peer_id': 'fixture-friend',
        'viewed_at': '2026-10-27T10:01:00Z',
      });
      await upgraded.close();

      final reopened = await open(124);
      addTearDown(reopened.close);
      for (final table in tables) {
        expect(
          await reopened.query(table, columns: columns[table]),
          before[table],
          reason: '$table must remain intact after another open',
        );
      }
      expect(
        (await reopened.query('post_media_attachments'))
            .single['preview_base64'],
        'QUJD',
      );
      expect(
        (await reopened.query('post_view_receipts')).single['viewed_at'],
        '2026-10-27T10:01:00Z',
      );
      expect(await photo.readAsBytes(), photoBytes);
    },
  );
}
