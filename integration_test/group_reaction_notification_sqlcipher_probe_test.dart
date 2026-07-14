/// Plan 257 device-lab SQLCipher observer.
///
/// The host capture controller runs this test *after* the OS notification/tap
/// journey. It opens the same encrypted `identity.db` and secure key store as
/// the installed app, prints one redacted observation record, and never turns
/// observations into a pass boolean. The standalone artifact validator owns
/// the acceptance decision.
library;

import 'dart:convert';

import 'package:background_push_crypto/background_push_crypto.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';

const _scenario = String.fromEnvironment('MKNOON_257_PROBE_SCENARIO');
const _groupName = String.fromEnvironment('MKNOON_257_PROBE_GROUP_NAME');
const _firstMarker = String.fromEnvironment('MKNOON_257_PROBE_FIRST_MARKER');
const _secondMarker = String.fromEnvironment('MKNOON_257_PROBE_SECOND_MARKER');
const _targetMarker = String.fromEnvironment('MKNOON_257_PROBE_TARGET_MARKER');
const _duplicateRedrivePrefix = 'MKNOON_257_DUPLICATE_REDRIVE_OBSERVATION ';

Future<String?> _hydrateStoredGroupKey(String? storedKey) async {
  if (storedKey == null || storedKey.trim().isEmpty) return null;
  if (!isSecureStoreReference(storedKey)) return storedKey;
  return FlutterSecureKeyStore().read(secureStoreKeyFromReference(storedKey));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Plan 257 reads the installed app SQLCipher state', (
    tester,
  ) async {
    expect(_scenario, isNotEmpty);
    expect(_groupName, isNotEmpty);

    final database = await openEncryptedDatabase(
      secureKeyStore: FlutterSecureKeyStore(),
      dbName: 'identity.db',
      version: currentIdentityDatabaseVersion,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    );
    try {
      final groups = await database.query(
        'groups',
        columns: <String>['id', 'name', 'type', 'my_role'],
        where: 'name = ?',
        whereArgs: <Object?>[_groupName],
      );
      final group = groups.length == 1 ? groups.single : null;
      final groupId = group?['id'] as String?;
      final groupKeys = groupId == null
          ? const <Map<String, Object?>>[]
          : await database.query(
              'group_keys',
              columns: <String>['key_generation', 'encrypted_key'],
              where: 'group_id = ?',
              whereArgs: <Object?>[groupId],
              orderBy: 'key_generation DESC',
              limit: 1,
            );
      final latestGroupKey = groupKeys.singleOrNull;
      final groupKey = await _hydrateStoredGroupKey(
        latestGroupKey?['encrypted_key'] as String?,
      );

      final markerValues = <String>[
        if (_firstMarker.isNotEmpty) _firstMarker,
        if (_secondMarker.isNotEmpty) _secondMarker,
        if (_targetMarker.isNotEmpty) _targetMarker,
      ];
      final messages = groupId == null || markerValues.isEmpty
          ? const <Map<String, Object?>>[]
          : await database.query(
              'group_messages',
              columns: <String>[
                'id',
                'text',
                'is_incoming',
                'read_at',
                'status',
              ],
              where:
                  'group_id = ? AND text IN '
                  '(${List<String>.filled(markerValues.length, '?').join(',')})',
              whereArgs: <Object?>[groupId, ...markerValues],
            );
      final unreadRows = groupId == null
          ? const <Map<String, Object?>>[]
          : await database.rawQuery(
              'SELECT COUNT(*) AS count FROM group_messages '
              'WHERE group_id = ? AND is_incoming = 1 AND read_at IS NULL '
              "AND id NOT LIKE 'sys-remove-cutoff:%'",
              <Object?>[groupId],
            );
      final reactions = groupId == null
          ? const <Map<String, Object?>>[]
          : await database.rawQuery(
              'SELECT r.id, r.message_id, r.emoji '
              'FROM message_reactions r '
              'JOIN group_messages gm ON gm.id = r.message_id '
              'WHERE gm.group_id = ?',
              <Object?>[groupId],
            );
      final reactionMessageRows = groupId == null
          ? const <Map<String, Object?>>[]
          : await database.rawQuery(
              'SELECT COUNT(*) AS count FROM group_messages gm '
              'JOIN message_reactions r ON r.id = gm.id '
              'WHERE gm.group_id = ?',
              <Object?>[groupId],
            );

      final markerObservations = messages
          .map((row) {
            final text = row['text'] as String? ?? '';
            final id = row['id'] as String? ?? '';
            return <String, Object?>{
              'marker': switch (text) {
                _ when text == _firstMarker && _firstMarker.isNotEmpty =>
                  'first',
                _ when text == _secondMarker && _secondMarker.isNotEmpty =>
                  'second',
                _ when text == _targetMarker && _targetMarker.isNotEmpty =>
                  'target',
                _ => 'unexpected',
              },
              'idSha256': sha256.convert(utf8.encode(id)).toString(),
              'incoming': row['is_incoming'] == 1,
              'read': row['read_at'] != null,
              'status': row['status'],
            };
          })
          .toList(growable: false);

      final observation = <String, Object?>{
        'schema': 'mknoon.plan257.sqlcipher-observation.v1',
        'scenario': _scenario,
        'groupName': _groupName,
        'groupRows': groups.length,
        'groupIdSha256': groupId == null
            ? null
            : sha256.convert(utf8.encode(groupId)).toString(),
        'groupType': group?['type'],
        'localRole': group?['my_role'],
        'latestGroupKeyEpoch': latestGroupKey?['key_generation'],
        'latestGroupKeySha256': groupKey == null
            ? null
            : sha256.convert(utf8.encode(groupKey)).toString(),
        'markers': markerObservations,
        'unreadCount': unreadRows.isEmpty
            ? null
            : (unreadRows.single['count'] as num?)?.toInt(),
        'reactionRows': reactions.length,
        'reactionMessageRows': reactionMessageRows.isEmpty
            ? null
            : (reactionMessageRows.single['count'] as num?)?.toInt(),
        'reactionEmoji': reactions.length == 1
            ? reactions.single['emoji']
            : null,
        'reactionTargetIdSha256': reactions.length == 1
            ? sha256
                  .convert(
                    utf8.encode(reactions.single['message_id'] as String),
                  )
                  .toString()
            : null,
      };

      // The capture controller persists only this prefix-matched line. Raw
      // peer ids, keys, ciphertext, and message text never cross the boundary.
      // ignore: avoid_print
      print('MKNOON_257_SQLCIPHER_OBSERVATION ${jsonEncode(observation)}');
    } finally {
      await database.close();
    }
  });

  testWidgets('Plan 257 prepares the exact stored ADD retry', (tester) async {
    expect(_scenario, isNotEmpty);
    expect(_groupName, isNotEmpty);
    expect(_targetMarker, isNotEmpty);

    final database = await openEncryptedDatabase(
      secureKeyStore: FlutterSecureKeyStore(),
      dbName: 'identity.db',
      version: currentIdentityDatabaseVersion,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    );
    try {
      final rows = await database.rawQuery(
        'SELECT o.reaction_id, o.group_id, o.message_id, '
        'o.inbox_retry_payload, '
        'o.delivery_status '
        'FROM group_reaction_replay_outbox o '
        'JOIN groups g ON g.id = o.group_id '
        'JOIN group_messages gm ON gm.id = o.message_id '
        'WHERE g.name = ? AND gm.text = ? AND o.action = ? '
        'ORDER BY o.created_at DESC, o.rowid DESC LIMIT 1',
        <Object?>[_groupName, _targetMarker, 'add'],
      );
      expect(rows, hasLength(1));
      final row = rows.single;
      final transitionId = row['reaction_id'] as String;
      final targetId = row['message_id'] as String;
      final retryPayload = row['inbox_retry_payload'] as String;
      final retry = Map<String, dynamic>.from(jsonDecode(retryPayload) as Map);
      final message = retry['message'] as String;
      final envelope = Map<String, dynamic>.from(jsonDecode(message) as Map);
      final stateId = envelope['messageId'] as String;
      final groupId = row['group_id'] as String;
      final keyEpoch = envelope['keyEpoch'] as int;
      final extension = Map<String, dynamic>.from(
        envelope['notificationExtension'] as Map,
      );
      expect(transitionId, isNotEmpty);
      expect(stateId, isNotEmpty);
      expect(targetId, isNotEmpty);
      expect(<String>{transitionId, stateId, targetId}, hasLength(3));
      expect(extension['transitionId'], transitionId);
      expect(extension['targetMessageId'], targetId);
      expect(extension['action'], 'add');
      for (final signedField in const <String>[
        'ciphertext',
        'nonce',
        'signedPayload',
        'signature',
      ]) {
        expect(envelope[signedField], isA<String>());
        expect(envelope[signedField] as String, isNotEmpty);
      }
      expect(extension['signedPayload'], isA<String>());
      expect(extension['signedPayload'] as String, isNotEmpty);
      expect(extension['signature'], isA<String>());
      expect(extension['signature'] as String, isNotEmpty);

      final keyRows = await database.query(
        'group_keys',
        columns: <String>['encrypted_key'],
        where: 'group_id = ? AND key_generation = ?',
        whereArgs: <Object?>[groupId, keyEpoch],
      );
      expect(keyRows, hasLength(1));
      final groupKey = await _hydrateStoredGroupKey(
        keyRows.single['encrypted_key'] as String,
      );
      expect(groupKey, isNotNull);
      final resolvedGroupKey = groupKey!;
      final decryptResult = await const BackgroundPushCrypto().decryptGroup(
        groupKey: resolvedGroupKey,
        ciphertext: envelope['ciphertext'] as String,
        nonce: envelope['nonce'] as String,
      );

      final updated = await database.update(
        'group_reaction_replay_outbox',
        <String, Object?>{
          'delivery_status': 'failed',
          'last_error': 'plan257_exact_duplicate_redrive',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'reaction_id = ? AND inbox_retry_payload = ?',
        whereArgs: <Object?>[transitionId, retryPayload],
      );
      expect(updated, 1);

      String hash(String value) =>
          sha256.convert(utf8.encode(value)).toString();
      final transitionPrefix = transitionId.length > 8
          ? transitionId.substring(0, 8)
          : transitionId;
      final observation = <String, Object?>{
        'schema': 'mknoon.plan257.duplicate-redrive-observation.v1',
        'scenario': _scenario,
        'prepared': true,
        'transitionIdSha256': hash(transitionId),
        'transitionIdPrefixSha256': hash(transitionPrefix),
        'reactionStateIdSha256': hash(stateId),
        'targetMessageIdSha256': hash(targetId),
        'inboxRetryPayloadSha256': hash(retryPayload),
        'notificationExtensionBound': true,
        'signedEnvelopePresent': true,
        'previousDeliveryStatus': row['delivery_status'],
        'retryPayloadBytes': utf8.encode(retryPayload).length,
        'envelopeBytes': utf8.encode(message).length,
        'notificationExtensionBytes': utf8.encode(jsonEncode(extension)).length,
        'ciphertextBytes': utf8.encode(envelope['ciphertext'] as String).length,
        'nonceBytes': utf8.encode(envelope['nonce'] as String).length,
        'groupKeySha256': hash(resolvedGroupKey),
        'storedEnvelopeDecryptOk': decryptResult['ok'] == true,
        'storedEnvelopeDecryptErrorCode': decryptResult['errorCode'],
      };
      // Only hashes and the prior status cross the host boundary. The exact
      // signed/ciphertext retry bytes stay inside SQLCipher for production's
      // retry driver to re-submit unchanged.
      // ignore: avoid_print
      print('$_duplicateRedrivePrefix${jsonEncode(observation)}');
    } finally {
      await database.close();
    }
  });
}
