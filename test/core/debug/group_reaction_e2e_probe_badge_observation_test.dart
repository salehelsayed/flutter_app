import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/debug/group_reaction_e2e_probe.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';

/// Plan 378 TC-378-10.
///
/// The device mute campaign (TC-378-08/09) asserts that a muted group is
/// excluded from the notification badge. That assertion is only worth anything
/// if the probe reports the PRODUCTION projection — a hand-rolled probe query
/// would keep reporting "excluded" after someone dropped `AND g.is_muted = 0`
/// from `dbLoadCanonicalNotificationBadgeState`.
///
/// Runs on plain SQLite via ffi with the real production migrations; the
/// SQLCipher hop is closed separately by the on-device probe inside TC-378-08.
final class _MemoryKeyStore implements SecureKeyStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  late Database database;
  late _MemoryKeyStore keyStore;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await openDatabase(inMemoryDatabasePath, version: 1);
    await runProductionOnCreate(database, 107);
    keyStore = _MemoryKeyStore();
  });

  tearDown(() => database.close());

  Future<void> insertGroup(
    String groupId, {
    required String name,
    bool muted = false,
  }) => database.insert('groups', <String, Object?>{
    'id': groupId,
    'name': name,
    'type': 'chat',
    'topic_name': '/$groupId',
    'created_at': '2026-08-17T00:00:00.000Z',
    'created_by': 'self',
    'my_role': 'member',
    'is_muted': muted ? 1 : 0,
    'is_archived': 0,
    'is_dissolved': 0,
    'self_removed_at': null,
  });

  Future<void> insertUnreadIncoming(String id, String groupId) =>
      database.insert('group_messages', <String, Object?>{
        'id': id,
        'group_id': groupId,
        'sender_peer_id': 'alice',
        'text': 'body',
        'timestamp': '2026-08-17T01:00:00.000Z',
        'status': 'delivered',
        'is_incoming': 1,
        'read_at': null,
        'created_at': '2026-08-17T01:00:00.000Z',
        'media_policy_version': 0,
        'media_lifecycle': 'standard',
        'media_protected': 0,
        'media_duration_seconds': null,
        'media_consumed_at': null,
        'media_expired_at': null,
      });

  Future<Map<String, Object?>> observe(String groupName) =>
      observeGroupReactionE2EState(
        database: database,
        secureKeyStore: keyStore,
        request: GroupReactionE2EProbeRequest(
          scenario: 'android_group_reaction_recipient',
          groupName: groupName,
        ),
      );

  Map<String, Object?> badgeOf(Map<String, Object?> observation) =>
      Map<String, Object?>.from(
        observation['canonicalBadgeState']! as Map<dynamic, dynamic>,
      );

  test('probe observation exposes the canonical badge projection', () async {
    await insertGroup('unmuted-group-id', name: 'Loud Group');
    await insertUnreadIncoming('loud-unread-1', 'unmuted-group-id');

    final badge = badgeOf(await observe('Loud Group'));

    expect(badge['available'], isTrue);
    expect(badge['unreadCount'], 1);
    expect(badge['groupIdentityCount'], 1);
    expect(badge['includesObservedGroup'], isTrue);
    expect(badge['observedGroupIdentityCount'], 1);
  });

  test('muted group excluded from canonical badge observation', () async {
    await insertGroup('muted-group-id', name: 'Muted Group', muted: true);
    await insertUnreadIncoming('muted-unread-1', 'muted-group-id');
    await insertUnreadIncoming('muted-unread-2', 'muted-group-id');

    final observation = await observe('Muted Group');
    final badge = badgeOf(observation);

    expect(badge['available'], isTrue);
    // The rows are still persisted and still unread...
    expect(observation['unreadCount'], 2);
    // ...but the production badge projection excludes the muted group.
    expect(badge['unreadCount'], 0);
    expect(badge['groupIdentityCount'], 0);
    expect(badge['includesObservedGroup'], isFalse);
    expect(badge['observedGroupIdentityCount'], 0);
    expect(badge['groupConversationIdSha256'], isEmpty);
  });

  test('muting one group does not hide another group from the badge', () async {
    await insertGroup('muted-group-id', name: 'Muted Group', muted: true);
    await insertGroup('unmuted-group-id', name: 'Loud Group');
    await insertUnreadIncoming('muted-unread-1', 'muted-group-id');
    await insertUnreadIncoming('loud-unread-1', 'unmuted-group-id');

    final mutedBadge = badgeOf(await observe('Muted Group'));
    expect(mutedBadge['unreadCount'], 1);
    expect(mutedBadge['groupIdentityCount'], 1);
    expect(mutedBadge['includesObservedGroup'], isFalse);

    final loudBadge = badgeOf(await observe('Loud Group'));
    expect(loudBadge['includesObservedGroup'], isTrue);
    expect(loudBadge['observedGroupIdentityCount'], 1);
  });

  // Plan 379 TC-379-04.
  //
  // The muted device lane fails closed on `groupIsMuted != true`, so a missed
  // Group Info switch tap REDs the capture instead of silently proving
  // "no card" against an unmuted group. That only holds if the field is read
  // from the real encrypted row rather than echoed from the request.
  test('probe observation reports the persisted mute state', () async {
    await insertGroup('muted-group-id', name: 'Muted Group', muted: true);
    await insertGroup('unmuted-group-id', name: 'Loud Group');

    expect((await observe('Muted Group'))['groupIsMuted'], isTrue);
    expect((await observe('Loud Group'))['groupIsMuted'], isFalse);
  });

  test('mute state is null when the group row is absent', () async {
    expect((await observe('No Such Group'))['groupIsMuted'], isNull);
  });

  test('badge observation never emits a raw conversation id', () async {
    await insertGroup('raw-badge-group-id', name: 'Loud Group');
    await insertUnreadIncoming('raw-badge-event-id', 'raw-badge-group-id');

    final encoded = jsonEncode(await observe('Loud Group'));

    expect(encoded, contains('canonicalBadgeState'));
    expect(encoded, isNot(contains('raw-badge-group-id')));
    expect(encoded, isNot(contains('raw-badge-event-id')));
  });
}
