import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/debug/direct_notification_state_probe.dart';

void main() {
  late Database db;
  Map<String, Object?> request({String phase = 'before'}) => <String, Object?>{
    'schema': directNotificationStateProbeRequestSchema,
    'transport_action': directNotificationStateProbeAction,
    'runId': 'run-1',
    'nonce': 'nonce-1',
    'stepId': 'direct-observe-run-1-$phase',
    'phase': phase,
    'contactPeerId': 'private-peer',
    'scenario': 'android_message_unread_lifecycle',
    'markers': <String>['TC256-run-1-first', 'TC256-run-1-second'],
  };
  Future<void> message(
    String id,
    String marker, {
    String peer = 'private-peer',
    bool incoming = true,
    String? readAt,
    String? hiddenAt,
  }) => db
      .insert('messages', <String, Object?>{
        'id': id,
        'contact_peer_id': peer,
        'text': marker,
        'is_incoming': incoming ? 1 : 0,
        'read_at': readAt,
        'hidden_at': hiddenAt,
      })
      .then((_) {});
  Future<Map<String, Object?>> observe({String phase = 'before'}) =>
      runDirectNotificationStateProbe(
        database: db,
        config: request(phase: phase),
      );
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE messages (id TEXT PRIMARY KEY, '
      'contact_peer_id TEXT, text TEXT, is_incoming INTEGER, '
      'read_at TEXT, hidden_at TEXT)',
    );
    await db.execute(
      'CREATE TABLE message_reactions '
      '(id TEXT PRIMARY KEY, message_id TEXT)',
    );
  });
  tearDown(() => db.close());

  test(
    'observes the five unread boundaries without committing read state',
    () async {
      final observations = <Map<String, Object?>>[await observe()];
      await message('private-message-1', 'TC256-run-1-first');
      observations.add(await observe(phase: 'first'));
      final changes = await db.rawQuery('SELECT total_changes() AS changes');
      observations.add(await observe(phase: 'dismissed'));
      expect(await db.rawQuery('SELECT total_changes() AS changes'), changes);
      await message('private-message-2', 'TC256-run-1-second');
      observations.add(await observe(phase: 'second'));
      expect(
        (observations.last['messages'] as List).cast<Map>().map(
          (row) => row['read'],
        ),
        <bool>[false, false],
      );
      // Only the production read boundary, represented by this external write,
      // changes read_at. The observer must not do so itself.
      await db.update('messages', <String, Object?>{'read_at': 'read-time'});
      observations.add(await observe(phase: 'read'));
      expect(observations.map((row) => row['unreadCount']), <int>[
        0,
        1,
        1,
        2,
        0,
      ]);
      expect(
        (observations.last['messages'] as List).cast<Map>().map(
          (row) => row['read'],
        ),
        <bool>[true, true],
      );
      final encoded = jsonEncode(observations);
      for (final secret in <String>[
        'private-peer',
        'private-message',
        'TC256-run-1-first',
        'read-time',
      ]) {
        expect(encoded, isNot(contains(secret)));
      }
    },
  );

  test(
    'counts only visible unread incoming rows for the exact contact',
    () async {
      await message('a', 'TC256-run-1-first');
      await message('b', 'hidden', hiddenAt: 'hidden-time');
      await message('c', 'outgoing', incoming: false);
      await message('d', 'already-read', readAt: 'read-time');
      await message('e', 'foreign', peer: 'other-peer');
      final result = await observe(phase: 'first');
      expect(result['unreadCount'], 1);
      expect(result['messageCount'], 4);
    },
  );

  test('reports reaction rows without inventing message rows', () async {
    await message('target-id', 'TC256-run-1-target', incoming: false);
    final config = <String, Object?>{
      ...request(),
      'scenario': 'android_physical_recipient',
      'markers': <String>['TC256-run-1-target'],
    };
    final before = await runDirectNotificationStateProbe(
      database: db,
      config: config,
    );
    await db.insert('message_reactions', <String, Object?>{
      'id': 'secret-reaction',
      'message_id': 'target-id',
    });
    final after = await runDirectNotificationStateProbe(
      database: db,
      config: <String, Object?>{
        ...config,
        'phase': 'delivered',
        'stepId': 'direct-observe-run-1-delivered',
      },
    );
    expect(before['messageCount'], after['messageCount']);
    expect(after['unreadCount'], 0);
    expect((after['messages'] as List).single['reactionRows'], 1);
    expect(jsonEncode(after), isNot(contains('secret-reaction')));
  });

  test('rejects duplicated marker rows instead of choosing one', () async {
    await message('a', 'TC256-run-1-first');
    await message('b', 'TC256-run-1-first');
    await expectLater(observe(), throwsStateError);
  });

  test(
    'rejects cross-run markers, duplicate markers and unbounded input',
    () async {
      for (final markers in <List<Object?>>[
        <String>['TC256-other-first', 'TC256-run-1-second'],
        <String>['TC256-run-1-first', 'TC256-run-1-first'],
        <String>['TC256-run-1-first'],
        <Object?>[null, 'TC256-run-1-second'],
        <String>['TC256-run-1-${'x' * 160}', 'TC256-run-1-second'],
      ]) {
        await expectLater(
          runDirectNotificationStateProbe(
            database: db,
            config: <String, Object?>{...request(), 'markers': markers},
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'rejects another action, scenario, phase, schema or step identity',
    () async {
      for (final entry in <String, Object?>{
        'transport_action': 'direct_notification_mark_read',
        'scenario': 'android_group_reaction_recipient',
        'phase': 'arbitrary',
        'schema': 'unknown',
        'stepId': 'direct-observe-stale-before',
        'contactPeerId': "peer' OR 1=1",
        'nonce': '',
      }.entries) {
        await expectLater(
          runDirectNotificationStateProbe(
            database: db,
            config: <String, Object?>{...request(), entry.key: entry.value},
          ),
          throwsFormatException,
        );
      }
    },
  );
}
