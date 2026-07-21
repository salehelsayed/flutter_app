import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart'
    show decodeInboxMessage;
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/self_removed_group_lifecycle_guard.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Default page size for the cursor-independent dissolve probe.
const int defaultReconcileDissolveProbePageSize = 50;

/// Default page cap for the probe. The relay group inbox is capped at 500
/// messages (oldest-evicted), so 12 × 50 = 600 covers a full inbox with slack.
/// A group that somehow exceeds this is logged as truncated (no silent cap).
const int defaultReconcileDissolveProbeMaxPages = 12;

/// The inner system marker for a terminal group dissolve, as it appears in the
/// decoded replay payload's `text` field.
const String _dissolveSysTextPrefix = '{"__sys":"group_dissolved"';

class ReconcileMissedGroupDissolvesResult {
  /// Number of locally-live groups probed.
  final int groupsProbed;

  /// Number of groups for which a durable dissolve was found and routed.
  final int dissolvesConverged;

  /// Number of groups whose probe errored (retrieval failure, etc.).
  final int errorCount;

  /// True if any group's probe hit [defaultReconcileDissolveProbeMaxPages]
  /// before exhausting the inbox (a dissolve beyond the cap may be missed).
  final bool truncated;

  const ReconcileMissedGroupDissolvesResult({
    required this.groupsProbed,
    required this.dissolvesConverged,
    required this.errorCount,
    required this.truncated,
  });
}

/// 123 S1 — cursor-independent reconciliation of terminal group dissolves.
///
/// When an admin dissolves a group it stores a durable, signed `group_dissolved`
/// replay envelope to the relay group inbox for the frozen recipient set. A
/// member who missed the live GossipSub publish should re-derive the dissolve
/// from that durable copy on next connect. The incremental
/// [drainGroupOfflineInbox] *can* do this, but three gates silently drop the
/// terminal dissolve (Phase 0 of the 123 plan, proven in tests):
///
///  * the persisted drain **cursor** can advance past the dissolve (T2);
///  * the drain **pre-join-replay** skip drops it when self `joinedAt` is after
///    the dissolve's relay timestamp (T3);
///  * the listener **stale-membership-event** watermark drops it when the local
///    watermark is ahead of the dissolve `eventAt` (T4).
///
/// And even with the gates relaxed, a dissolve a *prior* drain already
/// dropped-and-cursor-advanced stays behind the cursor forever.
///
/// This probe is deliberately **distinct from the incremental drain**: for each
/// locally-live group it re-reads the inbox from cursor 0 (cursor-independent,
/// read-only — it never advances the drain cursor), scans for a
/// `group_dissolved` system payload it can decrypt + is authorized for, and
/// routes it through the public [GroupMessageListener.handleReplayEnvelope].
/// That entrypoint applies the 122 terminal-dissolve relaxation, the admin
/// authorization gate, the signed-audit verification, and the membership /
/// audit-hash / deterministic-timeline-id idempotency — so re-running this is
/// safe and never duplicates the dissolve.
///
/// It must run **before** [rejoinGroupTopics] re-subscribes so the live group
/// is not re-joined inside the recovery window (T1).
///
/// Keyless / undecryptable dissolves (S2: re-added-after-dissolve, >7d, >cap)
/// throw inside decrypt and are skipped here — they are out of reach without a
/// key-independent relay tombstone (Phase 2, not built).
Future<ReconcileMissedGroupDissolvesResult> reconcileMissedGroupDissolves({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageListener groupMessageListener,
  String? selfPeerId,
  int pageSize = defaultReconcileDissolveProbePageSize,
  int maxPages = defaultReconcileDissolveProbeMaxPages,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_RECONCILE_DISSOLVES_BEGIN',
    details: {},
  );

  final groups = await groupRepo.getAllGroups();
  var groupsProbed = 0;
  var dissolvesConverged = 0;
  var errorCount = 0;
  var truncated = false;

  for (final group in groups) {
    if (group.isDissolved || group.selfRemovedAt != null) {
      continue;
    }
    groupsProbed++;
    try {
      final converged = await _probeGroupForDissolve(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageListener: groupMessageListener,
        groupId: group.id,
        selfPeerId: selfPeerId,
        pageSize: pageSize,
        maxPages: maxPages,
        onTruncated: () => truncated = true,
      );
      if (converged) {
        dissolvesConverged++;
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_RECONCILE_DISSOLVES_CONVERGED',
          details: {'groupId': _safeId(group.id)},
        );
      }
    } catch (e) {
      errorCount++;
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_RECONCILE_DISSOLVES_ERROR',
        details: {'groupId': _safeId(group.id), 'error': e.toString()},
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_RECONCILE_DISSOLVES_DONE',
    details: {
      'groupCount': groups.length,
      'groupsProbed': groupsProbed,
      'dissolvesConverged': dissolvesConverged,
      'errorCount': errorCount,
      'truncated': truncated,
    },
  );

  return ReconcileMissedGroupDissolvesResult(
    groupsProbed: groupsProbed,
    dissolvesConverged: dissolvesConverged,
    errorCount: errorCount,
    truncated: truncated,
  );
}

/// Scans [groupId]'s relay inbox from cursor 0 for a terminal dissolve, routing
/// the first one found through the listener. Returns true if a dissolve was
/// routed. Read-only: never advances the drain cursor.
Future<bool> _probeGroupForDissolve({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageListener groupMessageListener,
  required String groupId,
  required String? selfPeerId,
  required int pageSize,
  required int maxPages,
  required void Function() onTruncated,
}) async {
  var cursor = '';
  final seenCursors = <String>{''};
  var pageCount = 0;

  while (true) {
    if (pageCount >= maxPages) {
      onTruncated();
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_RECONCILE_DISSOLVES_TRUNCATED',
        details: {'groupId': _safeId(groupId), 'pageCount': pageCount},
      );
      return false;
    }
    pageCount++;

    final guardedPage = await runSelfRemovedGroupLifecycleLeaf<GroupInboxPage>(
      groupRepo: groupRepo,
      groupId: groupId,
      action: (_) =>
          callGroupInboxRetrieveWithCursor(bridge, groupId, cursor, pageSize),
    );
    if (!guardedPage.didRun) return false;
    final page = guardedPage.value!;

    for (final msg in page.messages) {
      Map<String, dynamic> payload;
      try {
        final guardedPayload =
            await runSelfRemovedGroupLifecycleLeaf<Map<String, dynamic>>(
              groupRepo: groupRepo,
              groupId: groupId,
              action: (_) => decodeInboxMessage(
                bridge,
                groupRepo,
                msg,
                groupId,
                expectedRecipientPeerId: selfPeerId,
              ),
            );
        if (!guardedPayload.didRun) return false;
        payload = guardedPayload.value!;
      } catch (_) {
        // Keyless (S2), unsigned, recipient-not-entitled, etc. — not a dissolve
        // we can re-derive here. Skip; never persist anything.
        continue;
      }

      final text = payload['text'] as String? ?? '';
      if (!text.startsWith(_dissolveSysTextPrefix)) {
        continue;
      }

      final senderId =
          (payload['senderId'] as String?) ?? (msg['from'] as String? ?? '');
      final payloadTransportPeerId = payload['transportPeerId'] as String?;
      final effectiveTransportPeerId =
          payloadTransportPeerId != null && payloadTransportPeerId.isNotEmpty
          ? payloadTransportPeerId
          : (msg['from'] as String? ?? '');
      final senderDeviceId = payload['senderDeviceId'] as String?;

      // Retrieval/decrypt may span a removal transition. Make a fresh routing
      // decision after decrypt, then release the phase before the listener
      // callback because that callback can acquire the same group phase.
      final routeAuthority = await runSelfRemovedGroupLifecycleLeaf<bool>(
        groupRepo: groupRepo,
        groupId: groupId,
        action: (_) async => true,
      );
      if (!routeAuthority.didRun || routeAuthority.value != true) {
        return false;
      }

      // Route through the public listener entrypoint — it owns authorization,
      // signed-audit verification, the 122 terminal-dissolve relaxation, and
      // all idempotency. We do NOT rethrow: a rejected/garbled dissolve must
      // not abort the rest of recovery.
      try {
        await groupMessageListener.handleReplayEnvelope({
          'groupId': (payload['groupId'] as String?) ?? groupId,
          'senderId': senderId,
          'senderUsername': payload['senderUsername'] as String? ?? '',
          'keyEpoch': payload['keyEpoch'] as int? ?? 0,
          'text': text,
          if (payload['timestamp'] is String) 'timestamp': payload['timestamp'],
          if (effectiveTransportPeerId.isNotEmpty)
            'transportPeerId': effectiveTransportPeerId,
          if (senderDeviceId != null && senderDeviceId.isNotEmpty)
            'senderDeviceId': senderDeviceId,
          if (payload['messageId'] is String) 'messageId': payload['messageId'],
        });
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_RECONCILE_DISSOLVES_ROUTE_ERROR',
          details: {'groupId': _safeId(groupId), 'error': e.toString()},
        );
        // Found the dissolve but routing failed; treat as handled so we stop
        // scanning this group (the listener gates already decided not to apply).
        return false;
      }

      // A dissolve is terminal — first match is enough.
      return true;
    }

    final nextCursor = page.cursor;
    if (nextCursor.isEmpty || seenCursors.contains(nextCursor)) {
      break;
    }
    seenCursors.add(nextCursor);
    cursor = nextCursor;
  }

  return false;
}

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;
