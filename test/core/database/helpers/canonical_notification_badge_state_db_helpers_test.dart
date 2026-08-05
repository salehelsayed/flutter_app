import 'package:flutter_app/core/database/helpers/canonical_notification_badge_state_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runProductionOnCreate(db, 107);
  });

  tearDown(() => db.close());

  Future<void> insertContact(
    String peerId, {
    bool archived = false,
    bool blocked = false,
  }) => db.insert('contacts', <String, Object?>{
    'peer_id': peerId,
    'public_key': 'public-$peerId',
    'rendezvous': '/$peerId',
    'username': peerId,
    'signature': 'signature-$peerId',
    'scanned_at': '2026-08-04T00:00:00.000Z',
    'is_archived': archived ? 1 : 0,
    'is_blocked': blocked ? 1 : 0,
  });

  Future<void> insertDirect(
    String id,
    String peerId, {
    bool incoming = true,
    String? readAt,
    String? hiddenAt,
    String? deletedAt,
    String privateMediaMode = 'ordinary',
    String privateMediaState = 'none',
    int? privateMediaPolicyVersion,
    int? privateMediaDurationSeconds,
  }) => db.insert('messages', <String, Object?>{
    'id': id,
    'contact_peer_id': peerId,
    'sender_peer_id': peerId,
    'text': 'body',
    'timestamp': '2026-08-04T01:00:00.000Z',
    'status': 'delivered',
    'is_incoming': incoming ? 1 : 0,
    'created_at': '2026-08-04T01:00:00.000Z',
    'read_at': readAt,
    'hidden_at': hiddenAt,
    'deleted_at': deletedAt,
    'private_media_policy_version':
        privateMediaPolicyVersion ?? (privateMediaMode == 'ordinary' ? 0 : 1),
    'private_media_mode': privateMediaMode,
    'private_media_duration_seconds': privateMediaDurationSeconds,
    'private_media_state': privateMediaState,
  });

  Future<void> insertGroup(
    String groupId, {
    bool muted = false,
    bool archived = false,
    bool dissolved = false,
    String? selfRemovedAt,
  }) => db.insert('groups', <String, Object?>{
    'id': groupId,
    'name': groupId,
    'type': 'chat',
    'topic_name': '/$groupId',
    'created_at': '2026-08-04T00:00:00.000Z',
    'created_by': 'self',
    'my_role': 'admin',
    'is_muted': muted ? 1 : 0,
    'is_archived': archived ? 1 : 0,
    'is_dissolved': dissolved ? 1 : 0,
    'self_removed_at': selfRemovedAt,
  });

  Future<void> insertGroupMessage(
    String id,
    String groupId, {
    bool incoming = true,
    String? readAt,
    String mediaLifecycle = 'standard',
    int mediaPolicyVersion = 0,
    int mediaProtected = 0,
    int? mediaDurationSeconds,
    int? mediaConsumedAt,
    int? mediaExpiredAt,
  }) => db.insert('group_messages', <String, Object?>{
    'id': id,
    'group_id': groupId,
    'sender_peer_id': 'alice',
    'text': 'body',
    'timestamp': '2026-08-04T01:00:00.000Z',
    'status': 'delivered',
    'is_incoming': incoming ? 1 : 0,
    'read_at': readAt,
    'created_at': '2026-08-04T01:00:00.000Z',
    'media_policy_version': mediaPolicyVersion,
    'media_lifecycle': mediaLifecycle,
    'media_protected': mediaProtected,
    'media_duration_seconds': mediaDurationSeconds,
    'media_consumed_at': mediaConsumedAt,
    'media_expired_at': mediaExpiredAt,
  });

  test(
    'eligible direct and group unread messages form one exact aggregate',
    () async {
      await insertContact('alice');
      await insertDirect('direct-event', 'alice');
      await insertGroup('family');
      await insertGroupMessage('group-event', 'family');
      await db.insert('message_reactions', <String, Object?>{
        'id': 'reaction-does-not-count',
        'message_id': 'direct-event',
        'emoji': '👍',
        'sender_peer_id': 'bob',
        'timestamp': '2026-08-04T02:00:00.000Z',
        'created_at': '2026-08-04T02:00:00.000Z',
      });

      final state = await dbLoadCanonicalNotificationBadgeState(db);

      expect(state.unreadCount, 2);
      expect(state.identities, <CanonicalNotificationIdentity>[
        const CanonicalNotificationIdentity(
          lane: CanonicalNotificationLane.direct,
          conversationId: 'alice',
          eventId: 'direct-event',
        ),
        const CanonicalNotificationIdentity(
          lane: CanonicalNotificationLane.group,
          conversationId: 'family',
          eventId: 'group-event',
        ),
      ]);
    },
  );

  test('every notification policy exclusion is count neutral', () async {
    await insertContact('active');
    await insertContact('archived', archived: true);
    await insertContact('blocked', blocked: true);
    await insertDirect('direct-eligible', 'active');
    await insertDirect('direct-outgoing', 'active', incoming: false);
    await insertDirect('direct-read', 'active', readAt: 'read');
    await insertDirect('direct-hidden', 'active', hiddenAt: 'hidden');
    await insertDirect('direct-deleted', 'active', deletedAt: 'deleted');
    await insertDirect(
      'direct-consumed',
      'active',
      privateMediaMode: 'view_once',
      privateMediaState: 'consumed',
    );
    await insertDirect(
      'direct-expired',
      'active',
      privateMediaMode: 'disappearing',
      privateMediaState: 'expired',
    );
    await insertDirect(
      'direct-unsupported',
      'active',
      privateMediaMode: 'unsupported',
      privateMediaState: 'unsupported',
    );
    await insertDirect(
      'direct-invalid-policy',
      'active',
      privateMediaMode: 'protected',
      privateMediaState: 'available',
      privateMediaPolicyVersion: 2,
    );
    await insertDirect('direct-archived', 'archived');
    await insertDirect('direct-blocked', 'blocked');

    await insertGroup('active-group');
    await insertGroup('muted-group', muted: true);
    await insertGroup('archived-group', archived: true);
    await insertGroup('dissolved-group', dissolved: true);
    await insertGroup('removed-group', selfRemovedAt: 'removed');
    await insertGroupMessage('group-eligible', 'active-group');
    await insertGroupMessage('group-outgoing', 'active-group', incoming: false);
    await insertGroupMessage('group-read', 'active-group', readAt: 'read');
    await insertGroupMessage(
      'sys-member_removed_cutoff:active-group:alice:1',
      'active-group',
    );
    await insertGroupMessage(
      'group-consumed',
      'active-group',
      mediaLifecycle: 'view_once',
      mediaPolicyVersion: 1,
      mediaProtected: 1,
      mediaConsumedAt: 1,
    );
    await insertGroupMessage(
      'group-expired',
      'active-group',
      mediaLifecycle: 'disappearing',
      mediaPolicyVersion: 1,
      mediaProtected: 1,
      mediaExpiredAt: 1,
    );
    await insertGroupMessage(
      'group-unsupported',
      'active-group',
      mediaLifecycle: 'unsupported',
      mediaPolicyVersion: 1,
      mediaProtected: 1,
    );
    await insertGroupMessage(
      'group-invalid-policy',
      'active-group',
      mediaLifecycle: 'view_once',
      mediaPolicyVersion: 2,
      mediaProtected: 1,
    );
    await insertGroupMessage('group-muted', 'muted-group');
    await insertGroupMessage('group-archived', 'archived-group');
    await insertGroupMessage('group-dissolved', 'dissolved-group');
    await insertGroupMessage('group-removed', 'removed-group');

    final state = await dbLoadCanonicalNotificationBadgeState(db);

    expect(state.unreadCount, 2);
    expect(state.identities.map((identity) => identity.eventId), <String>[
      'direct-eligible',
      'group-eligible',
    ]);
  });

  test(
    'supported nonterminal private-media tuples remain notification eligible',
    () async {
      await insertContact('private-peer');
      await insertDirect(
        'direct-protected',
        'private-peer',
        privateMediaMode: 'protected',
        privateMediaState: 'available',
      );
      await insertDirect(
        'direct-view-once',
        'private-peer',
        privateMediaMode: 'view_once',
        privateMediaState: 'available',
      );
      await insertDirect(
        'direct-disappearing',
        'private-peer',
        privateMediaMode: 'disappearing',
        privateMediaState: 'available',
        privateMediaDurationSeconds: 3600,
      );

      await insertGroup('private-group');
      await insertGroupMessage(
        'group-protected-standard',
        'private-group',
        mediaLifecycle: 'standard',
        mediaPolicyVersion: 1,
        mediaProtected: 1,
      );
      await insertGroupMessage(
        'group-view-once',
        'private-group',
        mediaLifecycle: 'view_once',
        mediaPolicyVersion: 1,
        mediaProtected: 1,
      );
      await insertGroupMessage(
        'group-disappearing',
        'private-group',
        mediaLifecycle: 'disappearing',
        mediaPolicyVersion: 1,
        mediaProtected: 1,
        mediaDurationSeconds: 86400,
      );

      final state = await dbLoadCanonicalNotificationBadgeState(db);

      expect(state.unreadCount, 6);
      expect(state.identities.map((identity) => identity.eventId), <String>[
        'direct-disappearing',
        'direct-protected',
        'direct-view-once',
        'group-disappearing',
        'group-protected-standard',
        'group-view-once',
      ]);
    },
  );
}
