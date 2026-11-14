import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _predecessorVersion = 129;
const _customStickersVersion = 130;
const _table = 'custom_stickers';
const _columns = <String>{
  'id',
  'content_sha256',
  'relative_path',
  'mime',
  'size_bytes',
  'width',
  'height',
  'frame_count',
  'duration_ms',
  'created_at_ms',
  'last_used_at_ms',
  'position',
};

Map<String, Object?> _row(int number, {int position = 0}) {
  final digest = number.toRadixString(16).padLeft(64, '0');
  return <String, Object?>{
    'id': 'sticker-$number',
    'content_sha256': digest,
    'relative_path': 'stickers/$digest.webp',
    'mime': 'image/webp',
    'size_bytes': 128,
    'width': 128,
    'height': 128,
    'frame_count': 1,
    'duration_ms': 0,
    'created_at_ms': 1700000000000 + number,
    'last_used_at_ms': 1700000010000 + number,
    'position': position,
  };
}

Future<bool> _hasLibraryTable(Database db) async =>
    (await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', _table],
    )).isNotEmpty;

Future<List<Map<String, Object?>>> _orderedRows(Database db) =>
    db.query(_table, orderBy: 'position ASC, id ASC');

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late List<Database> openedDatabases;

  Future<Database> open(int version) async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      '${directory.path}/library.db',
      options: OpenDatabaseOptions(
        version: version,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    openedDatabases.add(db);
    return db;
  }

  Future<Database> openLibrary({required bool upgrade}) async {
    if (upgrade) {
      final predecessor = await open(_predecessorVersion);
      expect(await predecessor.getVersion(), _predecessorVersion);
      expect(await _hasLibraryTable(predecessor), isFalse);
      await predecessor.close();
    }
    final db = await open(currentIdentityDatabaseVersion);
    // This assertion makes the initial RED a missing production behavior,
    // rather than an incidental "no such table" from a negative insert.
    expect(
      await _hasLibraryTable(db),
      isTrue,
      reason: 'The production callback must create the account-owned library.',
    );
    return db;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('custom-stickers-130-');
    openedDatabases = <Database>[];
  });

  tearDown(() async {
    for (final db in openedDatabases.reversed) {
      if (db.isOpen) await db.close();
    }
    await directory.delete(recursive: true);
  });

  test('the shipped version and both production paths include v130', () {
    expect(
      currentIdentityDatabaseVersion,
      greaterThanOrEqualTo(_customStickersVersion),
    );
    for (final registry in [
      productionCreateMigrations,
      productionUpgradeMigrations,
    ]) {
      expect(
        registry.where((entry) => entry.version == _customStickersVersion),
        hasLength(1),
      );
      expect(
        registry.indexWhere(
          (entry) => entry.version == _customStickersVersion,
        ),
        greaterThan(
          registry.indexWhere(
            (entry) => entry.version == _predecessorVersion,
          ),
        ),
      );
    }
  });

  // Run this same file with CUSTOM_STICKERS_ENABLED=false and true. Both
  // builds must satisfy the same schema contract, including stored rows.
  for (final upgrade in [false, true]) {
    final route = upgrade ? 'v129 upgrade' : 'fresh create';

    test('$route has the portable fields without creator metadata', () async {
      final db = await openLibrary(upgrade: upgrade);
      final columns = await db.rawQuery('PRAGMA table_info($_table)');
      expect(columns.map((column) => column['name']).toSet(), _columns);
      expect(await db.query(_table), isEmpty);
    });

    test('$route accepts canonical static and animation bounds', () async {
      final db = await openLibrary(upgrade: upgrade);
      final rows = <Map<String, Object?>>[
        {
          ..._row(1),
          'size_bytes': 262144,
          'width': 512,
          'height': 512,
        },
        {
          ..._row(2),
          'size_bytes': 524288,
          'width': 512,
          'height': 512,
          'frame_count': 24,
          'duration_ms': 2000,
        },
        {
          ..._row(3),
          'relative_path': 'stickers/independently-named.webp',
          'width': 1,
          'height': 1,
        },
      ];
      for (final row in rows) {
        await db.insert(_table, row);
      }
      // Equal positions are legal: callers resolve ties by id, and a
      // transaction can swap positions without transient UNIQUE failures.
      expect(await _orderedRows(db), rows);
    });

    test('$route rejects duplicate ids and duplicate content', () async {
      final db = await openLibrary(upgrade: upgrade);
      final accepted = _row(1);
      await db.insert(_table, accepted);

      for (final duplicate in <Map<String, Object?>>[
        {..._row(2), 'id': accepted['id']},
        {..._row(2), 'content_sha256': accepted['content_sha256']},
      ]) {
        await expectLater(
          db.insert(_table, duplicate),
          throwsA(
            isA<DatabaseException>().having(
              (error) => error.isUniqueConstraintError(),
              'unique constraint failure',
              isTrue,
            ),
          ),
        );
        expect(await db.query(_table), [accepted]);
      }
    });

    test('$route requires each durable field', () async {
      final db = await openLibrary(upgrade: upgrade);
      final accepted = _row(1);
      await db.insert(_table, accepted);

      for (final field in _columns) {
        await expectLater(
          db.insert(_table, {..._row(2), field: null}),
          throwsA(isA<DatabaseException>()),
          reason: '$field is required to restore a complete library item.',
        );
        expect(await db.query(_table), [accepted], reason: field);
      }
    });

    test('$route rejects out-of-contract canonical metadata', () async {
      final db = await openLibrary(upgrade: upgrade);
      final accepted = _row(1);
      await db.insert(_table, accepted);

      final invalidMetadata = <Map<String, Object?>>[
        {'mime': 'image/png'},
        {'size_bytes': 0},
        {'size_bytes': -1},
        {'size_bytes': 262145},
        {'size_bytes': 524289, 'frame_count': 24, 'duration_ms': 2000},
        {'width': 0},
        {'width': 513},
        {'height': 0},
        {'height': 513},
        {'frame_count': 0},
        {'frame_count': 25, 'duration_ms': 2000},
        {'duration_ms': -1},
        {'duration_ms': 1},
        {'frame_count': 2, 'duration_ms': 0},
        {'frame_count': 2, 'duration_ms': 2001},
        {'position': -1},
      ];
      for (final invalid in invalidMetadata) {
        await expectLater(
          db.insert(_table, {..._row(2), ...invalid}),
          throwsA(isA<DatabaseException>()),
          reason: '$invalid',
        );
        expect(await db.query(_table), [accepted], reason: '$invalid');
      }
    });

    test('$route rejects paths outside canonical sticker ownership', () async {
      final db = await openLibrary(upgrade: upgrade);
      final accepted = _row(1);
      await db.insert(_table, accepted);

      for (final path in [
        '',
        'stickers/',
        '/tmp/stickers/escaped.webp',
        '../stickers/escaped.webp',
        'stickers/../escaped.webp',
        'stickers/nested/../../escaped.webp',
        'media/escaped.webp',
        r'stickers\..\escaped.webp',
      ]) {
        await expectLater(
          db.insert(_table, {..._row(2), 'relative_path': path}),
          throwsA(isA<DatabaseException>()),
          reason: 'Unsafe account-relative path: $path',
        );
        expect(await db.query(_table), [accepted], reason: path);
      }
    });
  }

  test('v129 upgrade preserves existing sticker attachment data', () async {
    final predecessor = await open(_predecessorVersion);
    expect(await _hasLibraryTable(predecessor), isFalse);
    await predecessor.insert('media_attachments', <String, Object?>{
      'id': 'existing-pack-sticker',
      'message_id': 'existing-message',
      'mime': 'image/webp',
      'size': 96,
      'media_type': 'image',
      'download_status': 'done',
      'created_at': '2026-11-10T20:00:00.000Z',
      'sticker_id': 'orbit_crew.planet.angry',
    });
    final before = await predecessor.query('media_attachments');
    await predecessor.close();

    final upgraded = await open(currentIdentityDatabaseVersion);
    expect(await upgraded.query('media_attachments'), before);
    expect(await _hasLibraryTable(upgraded), isTrue);
    expect(await upgraded.query(_table), isEmpty);
    await upgraded.close();

    final reopened = await open(currentIdentityDatabaseVersion);
    expect(await reopened.getVersion(), currentIdentityDatabaseVersion);
    expect(await reopened.query('media_attachments'), before);
    expect(await reopened.query(_table), isEmpty);
  });

  test('an upgraded library retains order through replay and reopen', () async {
    final db = await openLibrary(upgrade: true);
    final first = _row(1, position: 0);
    final second = _row(2, position: 1);
    final third = _row(3, position: 2);
    for (final row in [first, second, third]) {
      await db.insert(_table, row);
    }

    // The first update temporarily shares position 2 with the third row.
    // A UNIQUE position constraint would reject this valid atomic reorder.
    await db.transaction((transaction) async {
      for (final (id, position) in [
        ('sticker-1', 2),
        ('sticker-2', 0),
        ('sticker-3', 1),
      ]) {
        expect(
          await transaction.update(
            _table,
            {'position': position},
            where: 'id = ?',
            whereArgs: [id],
          ),
          1,
        );
      }
    });
    final reordered = <Map<String, Object?>>[
      {...second, 'position': 0},
      {...third, 'position': 1},
      {...first, 'position': 2},
    ];
    expect(await _orderedRows(db), reordered);

    // Replay the new production upgrade step over an already populated table.
    await runProductionOnUpgrade(
      db,
      _predecessorVersion,
      _customStickersVersion,
    );
    expect(await _orderedRows(db), reordered);
    await db.close();

    final reopened = await open(currentIdentityDatabaseVersion);
    expect(await _orderedRows(reopened), reordered);
  });
}
