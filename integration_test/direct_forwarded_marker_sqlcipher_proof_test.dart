import 'dart:io';

import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'encrypted v97 rejects downgrade and wrong password then preserves forwarded owner state',
    (_) async {
      final tempDir = await Directory.systemTemp.createTemp('forward_v97_');
      final path = p.join(tempDir.path, 'identity.db');
      const password = 'plan-232-correct-password';
      sqlcipher.Database? db;
      try {
        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 96,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        await db.insert('messages', {
          'id': 'direct-parent',
          'contact_peer_id': 'contact-1',
          'sender_peer_id': 'contact-1',
          'text': 'caption',
          'timestamp': '2026-07-10T00:00:00.000Z',
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-07-10T00:00:00.000Z',
        });
        await db.insert('group_messages', {
          'id': 'group-parent',
          'group_id': 'group-1',
          'sender_peer_id': 'group-peer',
          'sender_username': 'Group peer',
          'text': 'group predecessor',
          'timestamp': '2026-07-10T00:00:00.000Z',
          'key_generation': 0,
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-07-10T00:00:00.000Z',
        });
        for (final row in const [
          ('direct-att', 'direct-parent', 'direct', '/media/direct.mp4'),
          ('group-att', 'group-parent', 'group', '/media/group.mp4'),
          (
            'unresolved-att',
            'missing-parent',
            'unresolved',
            '/media/unresolved.mp4',
          ),
        ]) {
          await db.insert('media_attachments', {
            'id': row.$1,
            'message_id': row.$2,
            'mime': 'video/mp4',
            'size': 10,
            'media_type': 'video',
            'local_path': row.$4,
            'download_status': 'done',
            'created_at': '2026-07-10T00:00:01.000Z',
            'owner_lane': row.$3,
            'is_bookmarked': 1,
            'last_playback_position_ms': 321,
          });
        }
        await db.close();
        db = null;

        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 97,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        final cipherVersion = (await db.rawQuery(
          'PRAGMA cipher_version',
        )).first.values.first.toString();
        expect(cipherVersion, isNotEmpty);
        await db.update(
          'messages',
          {'is_forwarded': 1},
          where: 'id = ?',
          whereArgs: ['direct-parent'],
        );
        final actual097 = productionUpgradeMigrations.singleWhere(
          (entry) => entry.version == 97,
        );
        await actual097.run(db);
        await db.close();
        db = null;

        await expectLater(() async {
          final wrong = await sqlcipher.openDatabase(
            path,
            password: 'wrong-password',
            singleInstance: false,
          );
          try {
            await wrong.query('messages');
          } finally {
            await wrong.close();
          }
        }(), throwsA(anything));
        await expectLater(
          sqlcipher.openDatabase(
            path,
            password: password,
            version: 96,
            singleInstance: false,
            onDowngrade: sqlcipher.onDatabaseVersionChangeError,
          ),
          throwsA(anything),
        );

        db = await sqlcipher.openDatabase(
          path,
          password: password,
          version: 97,
          singleInstance: false,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: sqlcipher.onDatabaseVersionChangeError,
        );
        expect((await db.query('messages')).single['is_forwarded'], 1);
        final media = await db.query('media_attachments', orderBy: 'id');
        expect(media, hasLength(3));
        expect(media.map((row) => row['owner_lane']).toSet(), {
          'direct',
          'group',
          'unresolved',
        });
        expect(media.every((row) => row['is_bookmarked'] == 1), isTrue);
        expect(
          media.every((row) => row['last_playback_position_ms'] == 321),
          isTrue,
        );
        expect(media.map((row) => row['local_path']).toSet(), {
          '/media/direct.mp4',
          '/media/group.mp4',
          '/media/unresolved.mp4',
        });
        final indexes = (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND tbl_name='media_attachments'",
        )).map((row) => row['name']);
        expect(indexes, contains('idx_media_attachments_owner_message'));
        expect(
          indexes,
          contains('idx_media_attachments_owner_bookmark_message'),
        );
      } finally {
        if (db != null && db.isOpen) await db.close();
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      }
    },
  );
}
