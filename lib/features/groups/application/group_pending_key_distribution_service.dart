import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/self_removed_group_lifecycle_guard.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_distribution.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_distribution_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;

/// Process-wide drain sink fired when a previously-keyless group member gains a
/// usable ML-KEM key (the prompt member-key-arrival trigger), so its deferred
/// distributions drain immediately instead of waiting for the next app resume.
/// Wired by main.dart to the runner; a no-op until then (and in tests). Mirrors
/// the rotate use case's deferred-distribution enqueue sink.
Future<void> Function({required String groupId, required String peerId})?
_deferredDistributionDrainSink;

void setDeferredDistributionDrainSink(
  Future<void> Function({required String groupId, required String peerId})?
  sink,
) {
  _deferredDistributionDrainSink = sink;
}

/// Fire-and-forget: drains any deferred distributions owed to [peerId] in
/// [groupId] through the process-wide sink. Safe to call from member-config
/// apply sites — never throws.
Future<void> triggerDeferredDistributionDrainForPeer({
  required String groupId,
  required String peerId,
}) async {
  final sink = _deferredDistributionDrainSink;
  if (sink == null) return;
  try {
    await sink(groupId: groupId, peerId: peerId);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_KEY_DISTRIBUTION_DRAIN_TRIGGER_ERROR',
      details: {'peerId': _safeId(peerId), 'error': e.toString()},
    );
  }
}

/// True when [saved] can now receive a deferred group-key distribution that it
/// could NOT before: it carries at least one deliverable device (active, usable
/// ML-KEM) AND that material is newly present relative to [existing] (existing
/// was null, was previously keyless, or its deliverable device set changed).
///
/// Gates the member-key-arrival drain trigger at the config-apply RECEIVE sites
/// (Finding 03 Slice 2, G-A) so a benign username-only roster refresh of an
/// already-converged member never fires a drain — which would otherwise re-walk
/// the queue and, for a still-keyless member, burn a deferred-distribution
/// attempt against the cap with nothing to deliver. The local admin add path
/// fires unconditionally instead because the added member just passed key-
/// material validation, so there a fresh arrival is implied.
bool groupMemberRegainedDeliverableKey({
  required GroupMember? existing,
  required GroupMember saved,
}) {
  final savedDevices = deliverableGroupKeyDevices(saved);
  if (savedDevices.isEmpty) {
    return false; // still keyless — nothing deliverable to drain
  }
  if (existing == null) {
    return true; // first persisted save already carries a usable key
  }
  final existingDevices = deliverableGroupKeyDevices(existing);
  if (existingDevices.isEmpty) {
    return true; // keyless -> keyed transition
  }
  // Both keyed: fire only when the deliverable device set actually changed
  // (e.g. a new device's ML-KEM landed); identical material is a no-op refresh.
  return !_sameDeliverableMlKemSet(existingDevices, savedDevices);
}

bool _sameDeliverableMlKemSet(
  List<GroupMemberDeviceIdentity> existing,
  List<GroupMemberDeviceIdentity> saved,
) {
  if (existing.length != saved.length) return false;
  final savedById = {for (final device in saved) device.deviceId: device};
  if (savedById.length != saved.length) return false;
  for (final device in existing) {
    final other = savedById[device.deviceId];
    if (other == null ||
        (other.mlKemPublicKey ?? '') != (device.mlKemPublicKey ?? '')) {
      return false;
    }
  }
  return true;
}

/// Slice 2 of Finding 03 (removal-rotation fails-closed): drains the durable
/// [GroupPendingKeyDistribution] queue by re-distributing the **current** group
/// key to deferred members once they regain a usable ML-KEM key on an active
/// device. Parallel to `GroupPendingKeyRepairRunner`, but it pushes a key
/// (sender-side) instead of replaying a decrypt (receiver-side).
///
/// Invariants: convergence (INV-D1), epoch-monotonic — always the latest key,
/// never the row's stale `key_epoch` (INV-D2), bounded by [attemptCap] →
/// `unreachable` (INV-D3), finalize-once / idempotent (INV-D4).
class GroupPendingKeyDistributionRunner {
  final Bridge bridge;
  final GroupRepository groupRepo;
  final GroupPendingKeyDistributionRepository repository;
  final Future<IdentityModel?> Function() loadIdentity;
  final Future<bool> Function(String peerId, String message)? sendP2PMessage;
  final Future<bool> Function(String peerId, String message)?
  storeP2PMessageInInbox;
  final int attemptCap;
  final Duration perRecipientTimeout;

  GroupPendingKeyDistributionRunner({
    required this.bridge,
    required this.groupRepo,
    required this.repository,
    required this.loadIdentity,
    required this.sendP2PMessage,
    this.storeP2PMessageInInbox,
    this.attemptCap = 8,
    this.perRecipientTimeout = const Duration(seconds: 5),
  });

  /// Drains every pending row for a single `(group, peer)` — the prompt
  /// member-key-arrival trigger. Returns the count distributed.
  Future<int> drainPendingForPeer({
    required String groupId,
    required String peerId,
  }) async {
    final rows = await repository.getPendingForPeer(
      peerId: peerId,
      groupId: groupId,
    );
    var distributed = 0;
    for (final row in rows) {
      if (await _drainOne(row)) distributed++;
    }
    return distributed;
  }

  /// Drains every pending row for a group — the app-resume catch-all sweep.
  Future<int> drainPendingForGroup({required String groupId}) async {
    final rows = await repository.getPendingForGroup(groupId: groupId);
    var distributed = 0;
    for (final row in rows) {
      if (await _drainOne(row)) distributed++;
    }
    return distributed;
  }

  /// Drains pending distributions across every active group — the app-resume
  /// catch-all that covers key arrivals while backgrounded or with the app dead.
  Future<int> drainAllPending() async {
    final groups = await groupRepo.getActiveGroups();
    var distributed = 0;
    for (final group in groups) {
      distributed += await drainPendingForGroup(groupId: group.id);
    }
    return distributed;
  }

  Future<bool> _drainOne(GroupPendingKeyDistribution row) async {
    final guarded = await runSelfRemovedGroupLifecycleLeaf<bool>(
      groupRepo: groupRepo,
      groupId: row.groupId,
      action: (_) async {
        // The outer loaders are shortlist-only. Re-read the exact row and all
        // authority needed by this one distribution while holding the same
        // membership phase as its network sends and terminal write.
        final current = await repository.getDistribution(row.id);
        if (current == null ||
            !sameExactGroupPendingKeyDistribution(current, row) ||
            current.status != groupPendingKeyDistributionStatusPending) {
          return false;
        }

        final identity = await loadIdentity();
        if (identity == null) {
          // Transient local condition — retry on the next trigger without
          // burning an attempt against the target.
          return false;
        }
        final self = await groupRepo.getMember(
          current.groupId,
          identity.peerId,
        );
        final target = await groupRepo.getMember(
          current.groupId,
          current.peerId,
        );
        final key = await groupRepo.getLatestKey(current.groupId);
        if (self == null || target == null || key == null) {
          return false;
        }

        return _drainOneLocked(current, identity, target);
      },
    );
    return guarded.didRun && (guarded.value ?? false);
  }

  Future<bool> _drainOneLocked(
    GroupPendingKeyDistribution row,
    IdentityModel identity,
    GroupMember target,
  ) async {
    try {
      final delivered = await distributeCurrentGroupKeyToDeferredPeer(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: row.groupId,
        peerId: row.peerId,
        selfPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        sendP2PMessage: sendP2PMessage,
        storeP2PMessageInInbox: storeP2PMessageInInbox,
        perRecipientTimeout: perRecipientTimeout,
      );

      final protectedAuthorityOwned =
          hasProtectedGroupAuthorityAdapter &&
          hasProtectedGroupPhysicalAuthority(
            await groupRepo.getMembers(row.groupId),
          );
      final requiredDeliveryCount = protectedAuthorityOwned
          ? deliverableGroupKeyDevices(target).length
          : 1;
      if (delivered > 0 && delivered >= requiredDeliveryCount) {
        final finalized = await finalizeGroupPendingKeyDistributionIfExact(
          repository,
          row,
        );
        if (!finalized) return false;
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_KEY_DISTRIBUTION_DISTRIBUTED',
          details: {
            'groupId': _safeId(row.groupId),
            'peerId': _safeId(row.peerId),
            'deviceCount': delivered,
          },
        );
        return true;
      }

      if (protectedAuthorityOwned) {
        // Exact protected rows remain the retry owner. Do not burn the legacy
        // attempt cap while one physical target still lacks strict custody.
        return false;
      }

      // Still undeliverable (keyless or every send failed): record + maybe cap.
      final attempted = await recordGroupPendingKeyDistributionAttemptIfExact(
        repository,
        row,
        lastError: 'undeliverable',
      );
      if (attempted != null) {
        await _maybeFinalizeUnreachable(attempted, 'attempt cap reached');
      }
      return false;
    } catch (e) {
      final attempted = await recordGroupPendingKeyDistributionAttemptIfExact(
        repository,
        row,
        lastError: e.toString(),
      );
      if (attempted != null) {
        await _maybeFinalizeUnreachable(attempted, e.toString());
      }
      return false;
    }
  }

  Future<void> _maybeFinalizeUnreachable(
    GroupPendingKeyDistribution row,
    String lastError,
  ) async {
    // [row] is the exact post-attempt tuple returned by the atomic CAS.
    if (row.attempts >= attemptCap) {
      final finalized =
          await finalizeGroupPendingKeyDistributionUnreachableIfExact(
            repository,
            row,
            lastError: lastError,
          );
      if (!finalized) return;
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_KEY_DISTRIBUTION_UNREACHABLE',
        details: {
          'groupId': _safeId(row.groupId),
          'peerId': _safeId(row.peerId),
          'attempts': row.attempts,
        },
      );
    }
  }
}
