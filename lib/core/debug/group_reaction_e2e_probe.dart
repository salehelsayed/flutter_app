import 'dart:convert';

import 'package:background_push_crypto/background_push_crypto.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../database/helpers/canonical_notification_badge_state_db_helpers.dart';
import '../secure_storage/secret_storage_references.dart';
import '../secure_storage/secure_key_store.dart';

const String groupReactionE2EProbeRequestSchema =
    'mknoon.plan257.runtime-probe-request.v1';
const String groupReactionE2EProbeResultSchema =
    'mknoon.plan257.runtime-probe-result.v1';
const String groupReactionE2EObserveAction = 'group_reaction_sqlcipher_observe';
const String groupReactionE2EExactAddRedriveAction =
    'group_reaction_exact_add_redrive';

const Set<String> groupReactionE2EAndroidScenarios = <String>{
  'android_group_message_unread_lifecycle',
  'android_announcement_message_unread_lifecycle',
  'android_group_reaction_recipient',
  'android_announcement_reaction_recipient',
  // Plan 315 TC-12: backgrounded-but-connected recipient (process alive, HOME
  // press, no kill). The harness-side registrations live in the criteria
  // catalog + capture script + validator id-set; this in-app allow-list is the
  // SEVENTH registration surface — an id missing here makes the runtime echo a
  // non-conforming result and the capture fails with
  // group_reaction_runtime_result_contract_mismatch.
  'android_group_reaction_recipient_background_connected',
  // Plan 379 G4: the muted-group device lane. These ids are out-of-catalog
  // (their harness registrations live in the Plan-379 criteria/validator and
  // their own Sims capability), but this in-app allow-list is not optional —
  // an id missing here makes the runtime echo a non-conforming result and the
  // capture fails with group_reaction_runtime_result_contract_mismatch.
  // Neither id carries the `_message_unread_lifecycle` suffix, so the marker
  // gate below requires them to send a target-only probe request.
  'android_group_muted_message_suppression',
  'android_group_muted_reaction_background_suppression',
  'ios_chat_group_message_and_reaction_recipient',
};

bool isGroupReactionE2EProbeAction(Object? value) =>
    value == groupReactionE2EObserveAction ||
    value == groupReactionE2EExactAddRedriveAction;

/// Inputs for the Plan 257 group-reaction device observer.
///
/// This helper is deliberately transport-free. It reads or updates the already
/// open production SQLCipher database and returns only redacted observations.
/// The `$sims` host controller owns device orchestration and artifact verdicts.
final class GroupReactionE2EProbeRequest {
  const GroupReactionE2EProbeRequest({
    required this.scenario,
    required this.groupName,
    this.firstMarker = '',
    this.secondMarker = '',
    this.targetMarker = '',
    this.phase = '',
  });

  final String scenario;
  final String groupName;
  final String firstMarker;
  final String secondMarker;
  final String targetMarker;
  final String phase;
}

/// Runs one nonce-bound installed-app probe request.
///
/// File polling and atomic result publication stay with the E2E app driver.
/// Keeping request validation and the SQLCipher operation together prevents a
/// host controller from silently widening this seam into arbitrary database
/// access.
Future<Map<String, Object?>> runGroupReactionE2EProbeAction({
  required Database database,
  required SecureKeyStore secureKeyStore,
  required Map<String, Object?> config,
}) async {
  String token(String key, {int maxLength = 160, bool allowEmpty = false}) {
    final value = config[key];
    if (value is! String ||
        (!allowEmpty && value.isEmpty) ||
        value.length > maxLength ||
        (value.isNotEmpty && !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value))) {
      throw FormatException('Plan 257 runtime probe has invalid $key');
    }
    return value;
  }

  final action = token('transport_action', maxLength: 80);
  final scenario = token('scenario', maxLength: 80);
  final runId = token('runId', maxLength: 80);
  final nonce = token('nonce', maxLength: 128);
  final stepId = token('stepId', maxLength: 180);
  final groupName = token('groupName', maxLength: 120);
  final firstMarker = token('firstMarker', maxLength: 120, allowEmpty: true);
  final secondMarker = token('secondMarker', maxLength: 120, allowEmpty: true);
  final targetMarker = token('targetMarker', maxLength: 120, allowEmpty: true);
  final phase = token('phase', maxLength: 16, allowEmpty: true);
  if (config['schema'] != groupReactionE2EProbeRequestSchema ||
      !groupReactionE2EAndroidScenarios.contains(scenario) ||
      !<String>{
        groupReactionE2EObserveAction,
        groupReactionE2EExactAddRedriveAction,
      }.contains(action) ||
      stepId != 'plan257-$action-$runId') {
    throw const FormatException('Plan 257 runtime probe request rejected');
  }
  final isCombinedIosJourney =
      scenario == 'ios_chat_group_message_and_reaction_recipient';
  final isMessage = scenario.endsWith('_message_unread_lifecycle');
  if ((isCombinedIosJourney &&
          (action != groupReactionE2EObserveAction ||
              !<String>{'message', 'reaction'}.contains(phase) ||
              firstMarker.isEmpty ||
              secondMarker.isNotEmpty ||
              targetMarker.isEmpty)) ||
      (!isCombinedIosJourney && phase.isNotEmpty) ||
      (!isCombinedIosJourney &&
          isMessage &&
          (firstMarker.isEmpty ||
              secondMarker.isEmpty ||
              targetMarker.isNotEmpty)) ||
      (!isCombinedIosJourney &&
          !isMessage &&
          (firstMarker.isNotEmpty ||
              secondMarker.isNotEmpty ||
              targetMarker.isEmpty)) ||
      (action == groupReactionE2EExactAddRedriveAction && isMessage)) {
    throw const FormatException(
      'Plan 257 runtime probe markers do not match the scenario/action',
    );
  }

  final request = GroupReactionE2EProbeRequest(
    scenario: scenario,
    groupName: groupName,
    firstMarker: firstMarker,
    secondMarker: secondMarker,
    targetMarker: targetMarker,
    phase: phase,
  );
  final observation = action == groupReactionE2EObserveAction
      ? await observeGroupReactionE2EState(
          database: database,
          secureKeyStore: secureKeyStore,
          request: request,
        )
      : await prepareExactGroupReactionAddRedrive(
          database: database,
          secureKeyStore: secureKeyStore,
          request: request,
        );
  return <String, Object?>{
    'schema': groupReactionE2EProbeResultSchema,
    'transport_action': action,
    'scenario': scenario,
    'stepId': stepId,
    'runId': runId,
    'nonce': nonce,
    if (isCombinedIosJourney) 'phase': phase,
    'status': 'complete',
    'success': true,
    'observation': observation,
  };
}

Future<String?> _hydrateStoredGroupKey(
  String? storedKey,
  SecureKeyStore secureKeyStore,
) async {
  if (storedKey == null || storedKey.trim().isEmpty) return null;
  if (!isSecureStoreReference(storedKey)) return storedKey;
  return secureKeyStore.read(secureStoreKeyFromReference(storedKey));
}

String _sha256Text(String value) =>
    sha256.convert(utf8.encode(value)).toString();

Never _reject(String detail) =>
    throw StateError('Plan 257 group-reaction probe rejected: $detail');

void _require(bool condition, String detail) {
  if (!condition) _reject(detail);
}

/// Reads the real group/message/reaction rows from the app's open SQLCipher DB.
///
/// Raw IDs, keys, and marker text are never returned. The result intentionally
/// matches `mknoon.plan257.sqlcipher-observation.v1`, so the existing durable
/// artifact validator remains the single acceptance authority.
Future<Map<String, Object?>> observeGroupReactionE2EState({
  required Database database,
  required SecureKeyStore secureKeyStore,
  required GroupReactionE2EProbeRequest request,
}) async {
  _require(request.scenario.trim().isNotEmpty, 'scenario is empty');
  _require(request.groupName.trim().isNotEmpty, 'group name is empty');

  final groups = await database.query(
    'groups',
    columns: <String>['id', 'name', 'type', 'my_role', 'is_muted'],
    where: 'name = ?',
    whereArgs: <Object?>[request.groupName],
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
    secureKeyStore,
  );

  final markerValues = <String>[
    if (request.firstMarker.isNotEmpty) request.firstMarker,
    if (request.secondMarker.isNotEmpty) request.secondMarker,
    if (request.targetMarker.isNotEmpty) request.targetMarker,
  ];
  final messages = groupId == null || markerValues.isEmpty
      ? const <Map<String, Object?>>[]
      : await database.query(
          'group_messages',
          columns: <String>['id', 'text', 'is_incoming', 'read_at', 'status'],
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

  final combinedIosJourney =
      request.scenario == 'ios_chat_group_message_and_reaction_recipient';
  final matchingAddRows = !combinedIosJourney || groupId == null
      ? const <Map<String, Object?>>[]
      : await database.rawQuery(
          'SELECT o.reaction_id, o.group_id, o.message_id, o.delivery_status '
          'FROM group_reaction_replay_outbox o '
          'JOIN groups g ON g.id = o.group_id '
          'JOIN group_messages gm ON gm.id = o.message_id '
          'WHERE g.name = ? AND gm.text = ? AND o.action = ? '
          'ORDER BY o.created_at DESC, o.rowid DESC LIMIT 2',
          <Object?>[request.groupName, request.targetMarker, 'add'],
        );
  if (combinedIosJourney) {
    _require(
      request.phase == 'message'
          ? matchingAddRows.isEmpty
          : matchingAddRows.length == 1,
      '${request.phase} phase matching ADD row count is '
      '${matchingAddRows.length}',
    );
  }

  final markerObservations = messages
      .map((row) {
        final text = row['text'] as String? ?? '';
        final id = row['id'] as String? ?? '';
        return <String, Object?>{
          'marker': switch (text) {
            _
                when text == request.firstMarker &&
                    request.firstMarker.isNotEmpty =>
              'first',
            _
                when text == request.secondMarker &&
                    request.secondMarker.isNotEmpty =>
              'second',
            _
                when text == request.targetMarker &&
                    request.targetMarker.isNotEmpty =>
              'target',
            _ => 'unexpected',
          },
          'idSha256': _sha256Text(id),
          'incoming': row['is_incoming'] == 1,
          'read': row['read_at'] != null,
          'status': row['status'],
        };
      })
      .toList(growable: false);

  final canonicalBadgeState = await _observeCanonicalBadgeState(
    database,
    groupId,
  );

  return <String, Object?>{
    'schema': 'mknoon.plan257.sqlcipher-observation.v1',
    'scenario': request.scenario,
    if (combinedIosJourney) 'phase': request.phase,
    'groupName': request.groupName,
    'groupRows': groups.length,
    'groupIdSha256': groupId == null ? null : _sha256Text(groupId),
    'groupType': group?['type'],
    'localRole': group?['my_role'],
    // Plan 379: read from the same encrypted `groups` row as the rest of this
    // observation. The muted device lane fails closed when this is not `true`,
    // so a Group Info switch tap that missed its target REDs the capture
    // instead of proving "no notification" against a still-unmuted group.
    // `null` (no such group row) is deliberately distinct from `false`.
    'groupIsMuted': group == null ? null : group['is_muted'] == 1,
    'latestGroupKeyEpoch': latestGroupKey?['key_generation'],
    'latestGroupKeySha256': groupKey == null ? null : _sha256Text(groupKey),
    'markers': markerObservations,
    'unreadCount': unreadRows.isEmpty
        ? null
        : (unreadRows.single['count'] as num?)?.toInt(),
    'reactionRows': reactions.length,
    'reactionMessageRows': reactionMessageRows.isEmpty
        ? null
        : (reactionMessageRows.single['count'] as num?)?.toInt(),
    'reactionEmoji': reactions.length == 1 ? reactions.single['emoji'] : null,
    'reactionTargetIdSha256': reactions.length == 1
        ? _sha256Text(reactions.single['message_id'] as String)
        : null,
    if (combinedIosJourney)
      'reactionIdSha256': matchingAddRows.length == 1
          ? _sha256Text(matchingAddRows.single['reaction_id'] as String)
          : null,
    'canonicalBadgeState': canonicalBadgeState,
  };
}

/// Redacted projection of the PRODUCTION canonical notification badge state.
///
/// Deliberately delegates to [dbLoadCanonicalNotificationBadgeState] rather
/// than re-deriving the predicate here: a hand-rolled probe query would not
/// re-red when a production exclusion (mute, archive, dissolve, self-removal)
/// is dropped, which is the whole point of observing it.
///
/// Conversation/event ids are hashed before they leave the probe, matching the
/// rest of `mknoon.plan257.sqlcipher-observation.v1`.
///
/// `available: false` is reported when the badge projection cannot run against
/// the open database (a fixture with a partial schema). Device captures assert
/// `available == true`, so a real regression cannot hide behind this branch.
Future<Map<String, Object?>> _observeCanonicalBadgeState(
  Database database,
  String? groupId,
) async {
  final CanonicalNotificationBadgeState badgeState;
  try {
    badgeState = await dbLoadCanonicalNotificationBadgeState(database);
  } on DatabaseException {
    return <String, Object?>{
      'available': false,
      'reason': 'badge_projection_unavailable',
    };
  }

  final groupIdentities = badgeState.identities
      .where(
        (identity) => identity.lane == CanonicalNotificationLane.group,
      )
      .toList(growable: false);
  final observedGroupIdentities = groupId == null
      ? const <CanonicalNotificationIdentity>[]
      : groupIdentities
            .where((identity) => identity.conversationId == groupId)
            .toList(growable: false);

  return <String, Object?>{
    'available': true,
    'unreadCount': badgeState.unreadCount,
    'groupIdentityCount': groupIdentities.length,
    'includesObservedGroup': observedGroupIdentities.isNotEmpty,
    'observedGroupIdentityCount': observedGroupIdentities.length,
    'groupConversationIdSha256':
        (groupIdentities
              .map((identity) => _sha256Text(identity.conversationId))
              .toSet()
              .toList(growable: false)
          ..sort()),
  };
}

/// Marks the latest exact stored ADD envelope for production retry.
///
/// The returned record contains hashes and byte counts only. The unchanged
/// signed/ciphertext payload stays in SQLCipher for the production retry loop.
Future<Map<String, Object?>> prepareExactGroupReactionAddRedrive({
  required Database database,
  required SecureKeyStore secureKeyStore,
  required GroupReactionE2EProbeRequest request,
  BackgroundPushCrypto crypto = const BackgroundPushCrypto(),
}) async {
  _require(request.scenario.trim().isNotEmpty, 'scenario is empty');
  _require(request.groupName.trim().isNotEmpty, 'group name is empty');
  _require(request.targetMarker.trim().isNotEmpty, 'target marker is empty');

  final rows = await database.rawQuery(
    'SELECT o.reaction_id, o.group_id, o.message_id, '
    'o.inbox_retry_payload, o.delivery_status '
    'FROM group_reaction_replay_outbox o '
    'JOIN groups g ON g.id = o.group_id '
    'JOIN group_messages gm ON gm.id = o.message_id '
    // Plan 319: exclude needs_build rows — their payload is the sentinel
    // empty string and this probe hard-casts it.
    "WHERE g.name = ? AND gm.text = ? AND o.action = ? "
    "AND o.delivery_status != 'needs_build' "
    'ORDER BY o.created_at DESC, o.rowid DESC LIMIT 1',
    <Object?>[request.groupName, request.targetMarker, 'add'],
  );
  _require(rows.length == 1, 'stored ADD retry row count is ${rows.length}');
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

  _require(transitionId.isNotEmpty, 'transition ID is empty');
  _require(stateId.isNotEmpty, 'reaction state ID is empty');
  _require(targetId.isNotEmpty, 'target message ID is empty');
  _require(
    <String>{transitionId, stateId, targetId}.length == 3,
    'reaction identifiers are not distinct',
  );
  _require(
    extension['transitionId'] == transitionId,
    'notification extension transition is unbound',
  );
  _require(
    extension['targetMessageId'] == targetId,
    'notification extension target is unbound',
  );
  _require(extension['action'] == 'add', 'stored transition is not ADD');
  for (final signedField in const <String>[
    'ciphertext',
    'nonce',
    'signedPayload',
    'signature',
  ]) {
    final value = envelope[signedField];
    _require(
      value is String && value.isNotEmpty,
      'envelope $signedField is missing',
    );
  }
  for (final signedField in const <String>['signedPayload', 'signature']) {
    final value = extension[signedField];
    _require(
      value is String && value.isNotEmpty,
      'notification extension $signedField is missing',
    );
  }

  final keyRows = await database.query(
    'group_keys',
    columns: <String>['encrypted_key'],
    where: 'group_id = ? AND key_generation = ?',
    whereArgs: <Object?>[groupId, keyEpoch],
  );
  _require(keyRows.length == 1, 'group key row count is ${keyRows.length}');
  final groupKey = await _hydrateStoredGroupKey(
    keyRows.single['encrypted_key'] as String,
    secureKeyStore,
  );
  _require(groupKey != null && groupKey.isNotEmpty, 'group key is unavailable');
  final resolvedGroupKey = groupKey!;
  final decryptResult = await crypto.decryptGroup(
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
  _require(updated == 1, 'exact stored ADD retry update count is $updated');

  final transitionPrefix = transitionId.length > 8
      ? transitionId.substring(0, 8)
      : transitionId;
  return <String, Object?>{
    'schema': 'mknoon.plan257.duplicate-redrive-observation.v1',
    'scenario': request.scenario,
    'prepared': true,
    'transitionIdSha256': _sha256Text(transitionId),
    'transitionIdPrefixSha256': _sha256Text(transitionPrefix),
    'reactionStateIdSha256': _sha256Text(stateId),
    'targetMessageIdSha256': _sha256Text(targetId),
    'inboxRetryPayloadSha256': _sha256Text(retryPayload),
    'notificationExtensionBound': true,
    'signedEnvelopePresent': true,
    'previousDeliveryStatus': row['delivery_status'],
    'retryPayloadBytes': utf8.encode(retryPayload).length,
    'envelopeBytes': utf8.encode(message).length,
    'notificationExtensionBytes': utf8.encode(jsonEncode(extension)).length,
    'ciphertextBytes': utf8.encode(envelope['ciphertext'] as String).length,
    'nonceBytes': utf8.encode(envelope['nonce'] as String).length,
    'groupKeySha256': _sha256Text(resolvedGroupKey),
    'storedEnvelopeDecryptOk': decryptResult['ok'] == true,
    'storedEnvelopeDecryptErrorCode': decryptResult['errorCode'],
  };
}
