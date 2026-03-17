import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> runPostsRepostDeliveryStateMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'POSTS_REPOST_DELIVERY_STATE_MIGRATION_START',
    details: {'migration': '035_posts_repost_delivery_state'},
  );

  try {
    await db.transaction((txn) async {
      await _ensurePostPassDeliveryStatus(txn);
      await _rebuildPostRecipients(txn);
      await _migrateLegacyPostPassOutboxJobs(txn);
    });

    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_REPOST_DELIVERY_STATE_MIGRATION_SUCCESS',
      details: {'migration': '035_posts_repost_delivery_state'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'POSTS_REPOST_DELIVERY_STATE_MIGRATION_ERROR',
      details: {
        'migration': '035_posts_repost_delivery_state',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}

Future<void> _ensurePostPassDeliveryStatus(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(post_passes)');
  final hasDeliveryStatus = columns.any(
    (column) => column['name'] == 'delivery_status',
  );
  if (!hasDeliveryStatus) {
    await db.execute(
      "ALTER TABLE post_passes ADD COLUMN delivery_status TEXT NOT NULL DEFAULT 'available'",
    );
  }
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_post_passes_delivery_status ON post_passes(is_incoming, delivery_status, passed_at DESC, pass_id DESC)',
  );
}

Future<void> _rebuildPostRecipients(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(post_recipients)');
  final names = columns.map((column) => column['name'] as String).toSet();
  final pkColumns = columns
      .where((column) => ((column['pk'] as num?)?.toInt() ?? 0) > 0)
      .map((column) => column['name'] as String)
      .toList(growable: false);
  final alreadyMigrated =
      names.contains('delivery_owner_kind') &&
      names.contains('delivery_owner_id') &&
      pkColumns.length == 3 &&
      pkColumns.contains('delivery_owner_kind') &&
      pkColumns.contains('delivery_owner_id') &&
      pkColumns.contains('recipient_peer_id');
  if (alreadyMigrated) {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_recipients_post_id ON post_recipients(post_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_post_recipients_owner ON post_recipients(delivery_owner_kind, delivery_owner_id)',
    );
    return;
  }

  final hasNearbyDistanceM = names.contains('nearby_distance_m');
  final hasDeliveryOwnerKind = names.contains('delivery_owner_kind');
  final hasDeliveryOwnerId = names.contains('delivery_owner_id');
  final nearbyDistanceSelect = hasNearbyDistanceM
      ? 'nearby_distance_m'
      : 'NULL AS nearby_distance_m';
  final ownerKindSelect = hasDeliveryOwnerKind
      ? "COALESCE(delivery_owner_kind, 'post') AS delivery_owner_kind"
      : "'post' AS delivery_owner_kind";
  final ownerIdSelect = hasDeliveryOwnerId
      ? 'COALESCE(delivery_owner_id, post_id) AS delivery_owner_id'
      : 'post_id AS delivery_owner_id';

  await db.execute('ALTER TABLE post_recipients RENAME TO post_recipients_old');
  await db.execute('''
    CREATE TABLE post_recipients (
      post_id TEXT NOT NULL,
      recipient_peer_id TEXT NOT NULL,
      delivery_status TEXT NOT NULL,
      last_attempt_at TEXT NOT NULL,
      delivery_path TEXT NOT NULL,
      last_error TEXT,
      nearby_distance_m INTEGER,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      delivery_owner_kind TEXT NOT NULL DEFAULT 'post',
      delivery_owner_id TEXT NOT NULL,
      PRIMARY KEY (delivery_owner_kind, delivery_owner_id, recipient_peer_id)
    )
  ''');
  await db.execute('''
    INSERT INTO post_recipients (
      post_id,
      recipient_peer_id,
      delivery_status,
      last_attempt_at,
      delivery_path,
      last_error,
      nearby_distance_m,
      created_at,
      updated_at,
      delivery_owner_kind,
      delivery_owner_id
    )
    SELECT
      post_id,
      recipient_peer_id,
      delivery_status,
      last_attempt_at,
      delivery_path,
      last_error,
      $nearbyDistanceSelect,
      created_at,
      updated_at,
      $ownerKindSelect,
      $ownerIdSelect
    FROM post_recipients_old
  ''');
  await db.execute('DROP TABLE post_recipients_old');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_post_recipients_post_id ON post_recipients(post_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_post_recipients_owner ON post_recipients(delivery_owner_kind, delivery_owner_id)',
  );
}

Future<void> _migrateLegacyPostPassOutboxJobs(DatabaseExecutor db) async {
  final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name IN (
          'post_follow_on_outbox_events',
          'post_follow_on_outbox_recipient_deliveries'
        )
    ''');
  final tableNames = tables.map((row) => row['name'] as String).toSet();
  if (!tableNames.contains('post_follow_on_outbox_events') ||
      !tableNames.contains('post_follow_on_outbox_recipient_deliveries')) {
    return;
  }

  final eventRows = await db.rawQuery('''
      SELECT e.event_id, e.post_id, p.pass_id
      FROM post_follow_on_outbox_events e
      INNER JOIN post_passes p ON p.event_id = e.event_id
      WHERE e.event_type = 'post_pass_along'
      ORDER BY e.created_at ASC, e.event_id ASC
    ''');
  if (eventRows.isEmpty) {
    return;
  }

  for (final eventRow in eventRows) {
    final eventId = eventRow['event_id'] as String;
    final postId = eventRow['post_id'] as String;
    final passId = eventRow['pass_id'] as String;
    final deliveryRows = await db.query(
      'post_follow_on_outbox_recipient_deliveries',
      where: 'event_id = ?',
      whereArgs: <Object?>[eventId],
      orderBy: 'recipient_peer_id ASC',
    );
    if (deliveryRows.isEmpty) {
      continue;
    }

    final deliveryStatuses = <String>[];
    for (final deliveryRow in deliveryRows) {
      final deliveryStatus =
          deliveryRow['delivery_status'] as String? ?? 'pending';
      deliveryStatuses.add(deliveryStatus);
      final attemptedAt =
          deliveryRow['last_attempt_at'] as String? ??
          deliveryRow['updated_at'] as String? ??
          deliveryRow['created_at'] as String;
      await db.insert('post_recipients', <String, Object?>{
        'post_id': postId,
        'recipient_peer_id': deliveryRow['recipient_peer_id'] as String,
        'delivery_status': deliveryStatus,
        'last_attempt_at': attemptedAt,
        'delivery_path': deliveryRow['delivery_path'] as String? ?? 'unknown',
        'last_error': deliveryRow['last_error'] as String?,
        'nearby_distance_m': null,
        'created_at': deliveryRow['created_at'] as String,
        'updated_at': deliveryRow['updated_at'] as String,
        'delivery_owner_kind': 'post_pass',
        'delivery_owner_id': passId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await db.update(
      'post_passes',
      <String, Object?>{
        'delivery_status': _aggregateDeliveryStatus(deliveryStatuses),
      },
      where: 'pass_id = ?',
      whereArgs: <Object?>[passId],
    );
  }

  await db.execute('''
      DELETE FROM post_follow_on_outbox_recipient_deliveries
      WHERE event_id IN (
        SELECT event_id
        FROM post_follow_on_outbox_events
        WHERE event_type = 'post_pass_along'
      )
    ''');
  await db.delete(
    'post_follow_on_outbox_events',
    where: 'event_type = ?',
    whereArgs: const <Object?>['post_pass_along'],
  );
}

String _aggregateDeliveryStatus(List<String> deliveryStatuses) {
  var successCount = 0;
  var failureCount = 0;
  var pendingCount = 0;
  for (final status in deliveryStatuses) {
    if (status == 'delivered' || status == 'inbox') {
      successCount++;
      continue;
    }
    if (status == 'failed') {
      failureCount++;
      continue;
    }
    pendingCount++;
  }
  if (successCount == 0 && failureCount == 0) {
    return 'sending';
  }
  if (pendingCount > 0) {
    return 'sending';
  }
  if (successCount > 0 && failureCount == 0) {
    return 'sent';
  }
  if (successCount > 0 && failureCount > 0) {
    return 'partial';
  }
  return 'failed';
}
