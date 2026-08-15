import 'dart:convert';

import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';

class FakeGroupReactionReplayOutboxRepository
    implements GroupReactionReplayOutboxRepository {
  final Map<String, GroupReactionReplayOutboxEntry> _entries = {};

  int saveEntryCallCount = 0;
  int attachBuiltPayloadCallCount = 0;

  /// Plan 319: models the group-parent write guard's silent zero-row insert.
  bool guardBlocksInserts = false;

  /// Plan 319: fails only the needs_build -> pending promotion.
  bool failAttachBuiltPayload = false;
  int updateEntryStatusCallCount = 0;
  int deleteEntryCallCount = 0;

  List<GroupReactionReplayOutboxEntry> get entries =>
      _entries.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<bool> saveEntry(GroupReactionReplayOutboxEntry entry) async {
    saveEntryCallCount++;
    if (guardBlocksInserts) return false;
    _entries[entry.reactionId] = entry;
    return true;
  }

  @override
  Future<bool> attachBuiltPayload({
    required String reactionId,
    required String inboxRetryPayload,
  }) async {
    attachBuiltPayloadCallCount++;
    if (failAttachBuiltPayload) {
      throw StateError('injected attachBuiltPayload failure');
    }
    final existing = _entries[reactionId];
    if (existing == null ||
        existing.deliveryStatus != GroupReactionReplayOutboxStatus.needsBuild) {
      return false;
    }
    _entries[reactionId] = existing.copyWith(
      inboxRetryPayload: inboxRetryPayload,
      deliveryStatus: GroupReactionReplayOutboxStatus.pending,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    return true;
  }

  @override
  Future<GroupReactionReplayOutboxEntry?> getEntry(String reactionId) async {
    final exact = _entries[reactionId];
    if (exact != null) return exact;

    // Compatibility helper for older tests that look up an outbox row by the
    // deterministic reaction-state id. Production rows are now keyed by the
    // unique transition id; the base replay messageId still exposes the state
    // id for frozen-reader compatibility.
    for (final entry in _entries.values) {
      try {
        final retry = jsonDecode(entry.inboxRetryPayload);
        if (retry is! Map) continue;
        final rawEnvelope = retry['message'];
        if (rawEnvelope is! String) continue;
        final envelope = jsonDecode(rawEnvelope);
        if (envelope is Map && envelope['messageId'] == reactionId) {
          return entry;
        }
      } catch (_) {
        // Malformed fixture rows simply do not support the compatibility lookup.
      }
    }
    return null;
  }

  @override
  Future<GroupReactionReplayOutboxEntry?> getLatestEntryForTarget({
    required String groupId,
    required String messageId,
    required String senderPeerId,
  }) async {
    final matches = _entries.values
        .where(
          (entry) =>
              entry.groupId == groupId &&
              entry.messageId == messageId &&
              entry.senderPeerId == senderPeerId,
        )
        .toList(growable: false);
    return matches.isEmpty ? null : matches.last;
  }

  @override
  Future<List<GroupReactionReplayOutboxEntry>> loadRetryableEntries({
    int limit = 20,
    bool strictContentOnly = false,
    int offset = 0,
  }) async {
    return entries
        .where(
          (entry) =>
              entry.deliveryStatus == GroupReactionReplayOutboxStatus.pending ||
              entry.deliveryStatus == GroupReactionReplayOutboxStatus.failed ||
              // Plan 319: needs_build rows are rebuildable custody.
              entry.deliveryStatus ==
                  GroupReactionReplayOutboxStatus.needsBuild,
        )
        .where(
          (entry) =>
              !strictContentOnly ||
              entry.inboxRetryPayload.contains('group_content_v1'),
        )
        .skip(offset)
        .take(limit)
        .toList();
  }

  @override
  Future<void> updateEntryStatus(
    String reactionId, {
    required String deliveryStatus,
    String? lastError,
  }) async {
    updateEntryStatusCallCount++;
    final existing = _entries[reactionId];
    if (existing == null) return;
    _entries[reactionId] = existing.copyWith(
      deliveryStatus: deliveryStatus,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<bool> updateEntryStatusIfExact(
    GroupReactionReplayOutboxEntry expected, {
    required String deliveryStatus,
    String? lastError,
  }) async {
    updateEntryStatusCallCount++;
    final current = _entries[expected.reactionId];
    if (current == null || !_sameEntry(current, expected)) return false;
    _entries[expected.reactionId] = current.copyWith(
      deliveryStatus: deliveryStatus,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    return true;
  }

  @override
  Future<void> deleteEntry(String reactionId) async {
    deleteEntryCallCount++;
    _entries.remove(reactionId);
  }
}

bool _sameEntry(
  GroupReactionReplayOutboxEntry current,
  GroupReactionReplayOutboxEntry expected,
) =>
    current.reactionId == expected.reactionId &&
    current.groupId == expected.groupId &&
    current.messageId == expected.messageId &&
    current.senderPeerId == expected.senderPeerId &&
    current.emoji == expected.emoji &&
    current.action == expected.action &&
    current.inboxRetryPayload == expected.inboxRetryPayload &&
    current.deliveryStatus == expected.deliveryStatus &&
    current.lastError == expected.lastError &&
    current.createdAt == expected.createdAt &&
    current.updatedAt == expected.updatedAt;
