import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/posts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
import 'package:flutter_app/core/database/migrations/030_posts_pass_along.dart';
import 'package:flutter_app/core/database/migrations/037_posts_repost_engagement_state.dart';
import 'package:flutter_app/core/database/migrations/040_posts_repost_visual_metrics.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    flowEventLoggingEnabled = kDebugMode;
    debugPrint = debugPrintThrottled;
    await db.close();
  });

  Future<Database> openWithMigrations(
    List<Future<void> Function(Database)> migrations,
  ) async {
    final database = await openDatabase(inMemoryDatabasePath, version: 1);
    for (final migration in migrations) {
      await migration(database);
    }
    return database;
  }

  Map<String, Object?> makePostRow({bool includeNewColumns = true}) {
    return <String, Object?>{
      'post_id': 'post-1',
      'event_id': 'evt-post-1',
      'sender_peer_id': 'peer-alice',
      'author_peer_id': 'peer-alice',
      'author_username': 'Alice',
      'text': 'Need a ladder',
      'audience_kind': 'all_friends',
      'selected_peer_ids': null,
      'scope_label': null,
      'post_created_at': '2026-03-15T10:15:30.000Z',
      'visible_at': '2026-03-15T10:15:30.000Z',
      'expires_at': '2026-03-18T10:15:30.000Z',
      'keep_available': 0,
      'is_incoming': 0,
      'delivery_status': 'available',
      if (includeNewColumns) 'media_kind': 'image',
      if (includeNewColumns) 'last_engagement_at': '2026-03-15T11:15:30.000Z',
      if (includeNewColumns) 'audience_radius_m': 250,
      if (includeNewColumns) 'nearby_distance_m': 42,
      if (includeNewColumns) 'nearby_sender_lat_e3': 52345,
      if (includeNewColumns) 'nearby_sender_lng_e3': 13456,
      if (includeNewColumns)
        'nearby_sender_captured_at': '2026-03-15T10:10:00.000Z',
      if (includeNewColumns) 'nearby_sender_accuracy_m': 12.5,
    };
  }

  Future<List<Map<String, dynamic>>> captureFlowEvents(
    Future<void> Function() action,
  ) async {
    flowEventLoggingEnabled = true;
    final output = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        output.add(message);
      }
    };

    await action();

    debugPrint = debugPrintThrottled;
    return output
        .where((line) => line.startsWith('[FLOW] '))
        .map(
          (line) =>
              jsonDecode(line.substring('[FLOW] '.length))
                  as Map<String, dynamic>,
        )
        .toList();
  }

  group('dbLoadPost observability', () {
    test(
      'emits timing flow event for hit and miss without changing result shape',
      () async {
        db = await openWithMigrations(<Future<void> Function(Database)>[
          runPostsCoreMigration,
          runPostsEngagementMigration,
          runPostsNearbyMigration,
          runPostsPassAlongMigration,
          runPostsRepostEngagementStateMigration,
          runPostsRepostVisualMetricsMigration,
        ]);

        await dbInsertPost(db, makePostRow());

        late Map<String, Object?>? loadedRow;
        final hitEvents = await captureFlowEvents(() async {
          loadedRow = await dbLoadPost(db, 'post-1');
        });

        expect(loadedRow, isNotNull);
        expect(loadedRow!['post_id'], 'post-1');
        expect(loadedRow!['share_count'], isNotNull);
        expect(loadedRow!['total_shared_to_count'], isNotNull);
        final hitTiming = hitEvents.singleWhere(
          (event) => event['event'] == 'POSTS_DB_LOAD_POST_TIMING',
        );
        expect(hitTiming['layer'], 'DB');
        expect(hitTiming['details']['postId'], 'post-1');
        expect(hitTiming['details']['outcome'], 'hit');
        expect(hitTiming['details']['elapsedMs'], isA<int>());

        late Map<String, Object?>? missingRow;
        final missEvents = await captureFlowEvents(() async {
          missingRow = await dbLoadPost(db, 'missing-post');
        });

        expect(missingRow, isNull);
        final missTiming = missEvents.singleWhere(
          (event) => event['event'] == 'POSTS_DB_LOAD_POST_TIMING',
        );
        expect(missTiming['details']['postId'], 'missing-post');
        expect(missTiming['details']['outcome'], 'miss');
        expect(missTiming['details']['elapsedMs'], isA<int>());
      },
    );
  });

  group('dbLoadPostsByIds', () {
    test('loads the requested posts and skips missing ids', () async {
      db = await openWithMigrations(<Future<void> Function(Database)>[
        runPostsCoreMigration,
        runPostsEngagementMigration,
        runPostsNearbyMigration,
        runPostsPassAlongMigration,
        runPostsRepostEngagementStateMigration,
        runPostsRepostVisualMetricsMigration,
      ]);

      await dbInsertPost(db, makePostRow());
      await dbInsertPost(db, <String, Object?>{
        ...makePostRow(),
        'post_id': 'post-2',
        'event_id': 'evt-post-2',
        'text': 'Need a second ladder',
      });

      final rows = await dbLoadPostsByIds(db, <String>[
        'post-2',
        'missing-post',
        'post-1',
      ]);

      expect(rows.map((row) => row['post_id']).toSet(), <String>{
        'post-1',
        'post-2',
      });
      expect(
        rows.first.keys,
        containsAll(<String>[
          'post_id',
          'share_count',
          'total_shared_to_count',
          'is_hidden',
          'is_read',
        ]),
      );
    });

    test(
      'emits timing flow event for non-empty loads and stays quiet on empty input',
      () async {
        db = await openWithMigrations(<Future<void> Function(Database)>[
          runPostsCoreMigration,
          runPostsEngagementMigration,
          runPostsNearbyMigration,
          runPostsPassAlongMigration,
          runPostsRepostEngagementStateMigration,
          runPostsRepostVisualMetricsMigration,
        ]);

        await dbInsertPost(db, makePostRow());
        await dbInsertPost(db, <String, Object?>{
          ...makePostRow(),
          'post_id': 'post-2',
          'event_id': 'evt-post-2',
          'text': 'Need a second ladder',
        });

        late List<Map<String, Object?>> rows;
        final loadEvents = await captureFlowEvents(() async {
          rows = await dbLoadPostsByIds(db, <String>['post-2', 'post-1']);
        });

        expect(rows.map((row) => row['post_id']).toSet(), <String>{
          'post-1',
          'post-2',
        });
        final timing = loadEvents.singleWhere(
          (event) => event['event'] == 'POSTS_DB_LOAD_BY_IDS_TIMING',
        );
        expect(timing['details']['requestedCount'], 2);
        expect(timing['details']['loadedCount'], 2);
        expect(timing['details']['elapsedMs'], isA<int>());

        late List<Map<String, Object?>> emptyRows;
        final emptyEvents = await captureFlowEvents(() async {
          emptyRows = await dbLoadPostsByIds(db, const <String>[]);
        });

        expect(emptyRows, isEmpty);
        expect(
          emptyEvents.any(
            (event) => event['event'] == 'POSTS_DB_LOAD_BY_IDS_TIMING',
          ),
          isFalse,
        );
      },
    );
  });

  group('dbLoadPostsFeed observability', () {
    test(
      'emits timing flow event and preserves feed ordering/filtering',
      () async {
        db = await openWithMigrations(<Future<void> Function(Database)>[
          runPostsCoreMigration,
          runPostsEngagementMigration,
          runPostsNearbyMigration,
          runPostsPassAlongMigration,
          runPostsRepostEngagementStateMigration,
          runPostsRepostVisualMetricsMigration,
        ]);

        await dbInsertPost(db, makePostRow());
        await dbInsertPost(db, <String, Object?>{
          ...makePostRow(),
          'post_id': 'post-2',
          'event_id': 'evt-post-2',
          'text': 'Newest visible post',
          'visible_at': '2026-03-15T12:15:30.000Z',
          'post_created_at': '2026-03-15T12:15:30.000Z',
        });
        await db.update(
          'post_feed_state',
          <String, Object?>{'is_hidden': 1},
          where: 'post_id = ?',
          whereArgs: <Object?>['post-1'],
        );

        late List<Map<String, Object?>> feedRows;
        final flowEvents = await captureFlowEvents(() async {
          feedRows = await dbLoadPostsFeed(db);
        });

        expect(feedRows.map((row) => row['post_id']).toList(), <String>[
          'post-2',
        ]);
        final timing = flowEvents.singleWhere(
          (event) => event['event'] == 'POSTS_DB_LOAD_FEED_TIMING',
        );
        expect(timing['details']['loadedCount'], 1);
        expect(timing['details']['elapsedMs'], isA<int>());
      },
    );
  });
}
