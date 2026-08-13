import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';

enum LinkedGroupBootstrapDbDisposition {
  committed,
  duplicate,
  refusedStateChanged,
  refusedPendingConflict,
}

enum LinkedGroupBootstrapMaterializationDbDisposition {
  committed,
  duplicate,
  refusedConflict,
}

Future<bool> dbHasLinkedGroupBootstrapIntent(
  Database db, {
  required String groupId,
  required String transportPeerId,
}) async {
  final rows = await db.query(
    'pending_group_broadcasts',
    columns: const ['recipient_peer_ids'],
    where: 'group_id = ? AND kind = ?',
    whereArgs: [groupId, 'linked_group_bootstrap_v1'],
  );
  final exactRecipientJson = jsonEncode(<String>[transportPeerId]);
  return rows.any((row) => row['recipient_peer_ids'] == exactRecipientJson);
}

/// Atomically owns the sender-side same-account bootstrap transition.
///
/// Crypto and envelope construction happen before this call. Every durable
/// fact becomes visible together: the legacy-preserving self roster, v85 retry
/// intent, and the immutable v86 protected envelope.
Future<LinkedGroupBootstrapDbDisposition> dbCommitLinkedGroupBootstrapAuthoring(
  Database db, {
  required Map<String, Object?> expectedGroup,
  required List<Map<String, Object?>> expectedMembers,
  required Map<String, Object?> expectedSelfMember,
  required int expectedLatestKeyGeneration,
  required String expectedLatestKeyCreatedAt,
  required Map<String, Object?> updatedSelfMember,
  required Map<String, Object?> pendingDevice,
  required Map<String, Object?> pendingBroadcast,
}) {
  return dbWriteTransaction(db, (transaction) async {
    final groupId = expectedGroup['id'] as String? ?? '';
    final selfPeerId = expectedSelfMember['peer_id'] as String? ?? '';
    final deviceId = pendingDevice['device_id'] as String? ?? '';
    final sourceMessageId = pendingBroadcast['source_message_id'] as String?;
    if (groupId.isEmpty ||
        selfPeerId.isEmpty ||
        expectedMembers.isEmpty ||
        expectedMembers.any((row) => row['group_id'] != groupId) ||
        deviceId.isEmpty ||
        sourceMessageId == null ||
        sourceMessageId.isEmpty ||
        pendingDevice['group_id'] != groupId ||
        pendingBroadcast['group_id'] != groupId) {
      return LinkedGroupBootstrapDbDisposition.refusedStateChanged;
    }

    final groupRows = await transaction.query(
      'groups',
      where: 'id = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    if (groupRows.length != 1 || groupRows.single['is_dissolved'] == 1) {
      return LinkedGroupBootstrapDbDisposition.refusedStateChanged;
    }
    final allMemberRows = await transaction.query(
      'group_members',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    final expectedRosterMatches = _containsExactMemberRows(
      allMemberRows,
      expectedMembers,
    );
    final updatedExpectedMembers = expectedMembers
        .map(
          (member) =>
              member['peer_id'] == selfPeerId ? updatedSelfMember : member,
        )
        .toList(growable: false);
    final updatedRosterMatches = _containsExactMemberRows(
      allMemberRows,
      updatedExpectedMembers,
    );
    final memberRows = allMemberRows
        .where((row) => row['peer_id'] == selfPeerId)
        .toList(growable: false);
    if (memberRows.length != 1) {
      return LinkedGroupBootstrapDbDisposition.refusedStateChanged;
    }
    final keyRows = await transaction.query(
      'group_keys',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'key_generation DESC',
      limit: 1,
    );
    if (keyRows.length != 1 ||
        keyRows.single['key_generation'] != expectedLatestKeyGeneration ||
        keyRows.single['created_at'] != expectedLatestKeyCreatedAt) {
      return LinkedGroupBootstrapDbDisposition.refusedStateChanged;
    }

    final existingPending = await transaction.query(
      'pending_sibling_devices',
      where: 'group_id = ? AND member_peer_id = ? AND device_id = ?',
      whereArgs: [groupId, selfPeerId, deviceId],
      limit: 1,
    );
    final existingBroadcast = await transaction.query(
      'pending_group_broadcasts',
      where: 'group_id = ? AND source_message_id = ?',
      whereArgs: [groupId, sourceMessageId],
      limit: 1,
    );

    final alreadyCommitted =
        updatedRosterMatches &&
        existingPending.length == 1 &&
        _containsExpected(existingPending.single, pendingDevice) &&
        existingBroadcast.length == 1 &&
        _containsExpected(existingBroadcast.single, pendingBroadcast);
    if (alreadyCommitted) {
      return LinkedGroupBootstrapDbDisposition.duplicate;
    }
    if (existingPending.isNotEmpty || existingBroadcast.isNotEmpty) {
      return LinkedGroupBootstrapDbDisposition.refusedPendingConflict;
    }
    if (!_containsExpected(groupRows.single, expectedGroup) ||
        !expectedRosterMatches) {
      return LinkedGroupBootstrapDbDisposition.refusedStateChanged;
    }

    final updated = await transaction.update(
      'group_members',
      updatedSelfMember,
      where: 'group_id = ? AND peer_id = ?',
      whereArgs: [groupId, selfPeerId],
    );
    if (updated != 1) {
      throw StateError('linked bootstrap self roster update lost authority');
    }
    await transaction.insert(
      'pending_sibling_devices',
      pendingDevice,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await transaction.insert(
      'pending_group_broadcasts',
      pendingBroadcast,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return LinkedGroupBootstrapDbDisposition.committed;
  });
}

/// Deletes both sender-side owners only when both are still byte-exact.
Future<bool> dbCompleteLinkedGroupBootstrapCustody(
  Database db, {
  required Map<String, Object?> expectedDevice,
  required Map<String, Object?> expectedBroadcast,
}) {
  return dbWriteTransaction(db, (transaction) async {
    final groupId = expectedDevice['group_id'] as String? ?? '';
    final memberPeerId = expectedDevice['member_peer_id'] as String? ?? '';
    final deviceId = expectedDevice['device_id'] as String? ?? '';
    final broadcastId = expectedBroadcast['id'] as String? ?? '';
    if (groupId.isEmpty ||
        memberPeerId.isEmpty ||
        deviceId.isEmpty ||
        broadcastId.isEmpty ||
        expectedBroadcast['group_id'] != groupId) {
      return false;
    }
    final pendingRows = await transaction.query(
      'pending_sibling_devices',
      where: 'group_id = ? AND member_peer_id = ? AND device_id = ?',
      whereArgs: [groupId, memberPeerId, deviceId],
      limit: 1,
    );
    final broadcastRows = await transaction.query(
      'pending_group_broadcasts',
      where: 'id = ?',
      whereArgs: [broadcastId],
      limit: 1,
    );
    if (pendingRows.length != 1 ||
        broadcastRows.length != 1 ||
        !_containsExpected(pendingRows.single, expectedDevice) ||
        !_containsExpected(broadcastRows.single, expectedBroadcast)) {
      return false;
    }
    final broadcastDeleted = await transaction.delete(
      'pending_group_broadcasts',
      where: 'id = ?',
      whereArgs: [broadcastId],
    );
    final pendingDeleted = await transaction.delete(
      'pending_sibling_devices',
      where: 'group_id = ? AND member_peer_id = ? AND device_id = ?',
      whereArgs: [groupId, memberPeerId, deviceId],
    );
    if (broadcastDeleted != 1 || pendingDeleted != 1) {
      throw StateError(
        'linked bootstrap paired custody completion was partial',
      );
    }
    return true;
  });
}

/// One authoritative receiver transaction for group + exact roster + key ref.
Future<LinkedGroupBootstrapMaterializationDbDisposition>
dbCommitLinkedGroupBootstrapMaterialization(
  Database db, {
  required Map<String, Object?> groupRow,
  required List<Map<String, Object?>> memberRows,
  required Map<String, Object?> keyRow,
}) {
  return dbWriteTransaction(db, (transaction) async {
    final groupId = groupRow['id'] as String? ?? '';
    if (groupId.isEmpty ||
        memberRows.isEmpty ||
        memberRows.any((row) => row['group_id'] != groupId) ||
        keyRow['group_id'] != groupId) {
      return LinkedGroupBootstrapMaterializationDbDisposition.refusedConflict;
    }
    final peerIds = <String>{};
    for (final member in memberRows) {
      final peerId = member['peer_id'] as String? ?? '';
      if (peerId.isEmpty || !peerIds.add(peerId)) {
        return LinkedGroupBootstrapMaterializationDbDisposition.refusedConflict;
      }
    }

    final existingGroups = await transaction.query(
      'groups',
      where: 'id = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    if (existingGroups.isNotEmpty &&
        (existingGroups.length != 1 ||
            !_containsExpected(existingGroups.single, groupRow))) {
      return LinkedGroupBootstrapMaterializationDbDisposition.refusedConflict;
    }

    final existingMembers = await transaction.query(
      'group_members',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    if (existingMembers.any(
      (row) => !peerIds.contains(row['peer_id'] as String?),
    )) {
      return LinkedGroupBootstrapMaterializationDbDisposition.refusedConflict;
    }
    final missingMembers = <Map<String, Object?>>[];
    for (final expected in memberRows) {
      final peerId = expected['peer_id'] as String;
      final matching = existingMembers
          .where((row) => row['peer_id'] == peerId)
          .toList(growable: false);
      if (matching.isEmpty) {
        missingMembers.add(expected);
      } else if (matching.length != 1 ||
          !_containsExpected(matching.single, expected)) {
        return LinkedGroupBootstrapMaterializationDbDisposition.refusedConflict;
      }
    }

    final existingKeys = await transaction.query(
      'group_keys',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    if (existingKeys.isNotEmpty &&
        (existingKeys.length != 1 ||
            !_containsExpected(existingKeys.single, keyRow))) {
      return LinkedGroupBootstrapMaterializationDbDisposition.refusedConflict;
    }

    final changed =
        existingGroups.isEmpty ||
        missingMembers.isNotEmpty ||
        existingKeys.isEmpty;
    if (!changed) {
      return LinkedGroupBootstrapMaterializationDbDisposition.duplicate;
    }

    // All conflicts were rejected above. Only now expose any authoritative
    // rows, so an ordinary refused disposition cannot commit a partial group.
    if (existingGroups.isEmpty) {
      await transaction.insert(
        'groups',
        groupRow,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
    for (final member in missingMembers) {
      await transaction.insert(
        'group_members',
        member,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
    if (existingKeys.isEmpty) {
      await transaction.insert(
        'group_keys',
        keyRow,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    return LinkedGroupBootstrapMaterializationDbDisposition.committed;
  });
}

bool _containsExpected(
  Map<String, Object?> actual,
  Map<String, Object?> expected,
) {
  for (final entry in expected.entries) {
    if (!actual.containsKey(entry.key) || actual[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

bool _containsExactMemberRows(
  List<Map<String, Object?>> actualRows,
  List<Map<String, Object?>> expectedRows,
) {
  if (actualRows.length != expectedRows.length) return false;
  for (final expected in expectedRows) {
    final peerId = expected['peer_id'];
    final matches = actualRows
        .where((actual) => actual['peer_id'] == peerId)
        .toList(growable: false);
    if (matches.length != 1 || !_containsExpected(matches.single, expected)) {
      return false;
    }
  }
  return true;
}
