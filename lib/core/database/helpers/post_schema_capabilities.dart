import 'package:sqflite_sqlcipher/sqflite.dart';

class PostSchemaCapabilities {
  const PostSchemaCapabilities({
    required this.hasPostsMediaKind,
    required this.hasPostsLastEngagementAt,
    required this.hasPostsAudienceRadiusM,
    required this.hasPostsNearbyDistanceM,
    required this.hasPostsNearbySenderLatE3,
    required this.hasPostsNearbySenderLngE3,
    required this.hasPostsNearbySenderCapturedAt,
    required this.hasPostsNearbySenderAccuracyM,
    required this.hasPassDeliveryStatus,
    required this.hasPassInnerPayloadJson,
    required this.hasPassRecipientCount,
    required this.hasRecipientNearbyDistanceM,
    required this.hasRecipientDeliveryOwnerKind,
    required this.hasRecipientDeliveryOwnerId,
    required this.hasRepostSharedToCountBaseline,
  });

  final bool hasPostsMediaKind;
  final bool hasPostsLastEngagementAt;
  final bool hasPostsAudienceRadiusM;
  final bool hasPostsNearbyDistanceM;
  final bool hasPostsNearbySenderLatE3;
  final bool hasPostsNearbySenderLngE3;
  final bool hasPostsNearbySenderCapturedAt;
  final bool hasPostsNearbySenderAccuracyM;
  final bool hasPassDeliveryStatus;
  final bool hasPassInnerPayloadJson;
  final bool hasPassRecipientCount;
  final bool hasRecipientNearbyDistanceM;
  final bool hasRecipientDeliveryOwnerKind;
  final bool hasRecipientDeliveryOwnerId;
  final bool hasRepostSharedToCountBaseline;

  bool get hasRecipientDeliveryOwnerColumns =>
      hasRecipientDeliveryOwnerKind && hasRecipientDeliveryOwnerId;
}

final Expando<Future<PostSchemaCapabilities>> _capabilityCache =
    Expando<Future<PostSchemaCapabilities>>('postSchemaCapabilities');

Future<PostSchemaCapabilities> loadPostSchemaCapabilities(Database db) {
  // Migrations complete before helpers use an opened app database, so the
  // schema stays stable for the lifetime of that Database instance.
  return _capabilityCache[db] ??= _readPostSchemaCapabilities(db);
}

Future<PostSchemaCapabilities> _readPostSchemaCapabilities(Database db) async {
  final postsColumns = await _loadColumnNames(db, 'posts');
  final passColumns = await _loadColumnNames(db, 'post_passes');
  final recipientColumns = await _loadColumnNames(db, 'post_recipients');
  final repostProjectionColumns = await _loadColumnNames(
    db,
    'post_repost_projection_state',
  );

  return PostSchemaCapabilities(
    hasPostsMediaKind: postsColumns.contains('media_kind'),
    hasPostsLastEngagementAt: postsColumns.contains('last_engagement_at'),
    hasPostsAudienceRadiusM: postsColumns.contains('audience_radius_m'),
    hasPostsNearbyDistanceM: postsColumns.contains('nearby_distance_m'),
    hasPostsNearbySenderLatE3: postsColumns.contains('nearby_sender_lat_e3'),
    hasPostsNearbySenderLngE3: postsColumns.contains('nearby_sender_lng_e3'),
    hasPostsNearbySenderCapturedAt: postsColumns.contains(
      'nearby_sender_captured_at',
    ),
    hasPostsNearbySenderAccuracyM: postsColumns.contains(
      'nearby_sender_accuracy_m',
    ),
    hasPassDeliveryStatus: passColumns.contains('delivery_status'),
    hasPassInnerPayloadJson: passColumns.contains('inner_payload_json'),
    hasPassRecipientCount: passColumns.contains('recipient_count'),
    hasRecipientNearbyDistanceM: recipientColumns.contains('nearby_distance_m'),
    hasRecipientDeliveryOwnerKind: recipientColumns.contains(
      'delivery_owner_kind',
    ),
    hasRecipientDeliveryOwnerId: recipientColumns.contains('delivery_owner_id'),
    hasRepostSharedToCountBaseline: repostProjectionColumns.contains(
      'shared_to_count_baseline',
    ),
  );
}

Future<Set<String>> _loadColumnNames(Database db, String table) async {
  final columns = await db.rawQuery('PRAGMA table_info($table)');
  return columns
      .map((column) => column['name'] as String? ?? '')
      .where((name) => name.isNotEmpty)
      .toSet();
}
