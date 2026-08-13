import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/protected_group_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/linked_group_bootstrap_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_sibling_device_repository.dart';

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;

/// Drains the durable [GroupPendingBroadcastRepository] queue by re-pushing each
/// stored (already-signed) broadcast through [rePush]. A row clears only on a
/// successful re-push; a failed re-push retains it for the next drain
/// (idempotent — the receive-side dedups by the broadcast's source message id).
class GroupPendingBroadcastRunner {
  final GroupPendingBroadcastRepository repository;

  /// Re-pushes a stored broadcast through the bridge; returns `true` on success.
  final Future<bool> Function(GroupPendingBroadcast broadcast) rePush;

  /// Production re-pushes remove the exact row inside their membership phase,
  /// after the final inbox action. Tests and simple callers may retain the
  /// legacy runner-owned completion by leaving this false.
  final bool rePushFinalizesSuccess;

  /// Narrow strict-custody dependencies. When absent, protected rows stay
  /// pending; they are never downgraded through [rePush].
  final AckOrExpiryInboxStore? protectedInboxStore;
  final PendingSiblingDeviceRepository? pendingSiblingDeviceRepository;
  final LinkedGroupBootstrapRepository? linkedGroupBootstrapRepository;

  /// Repairs or verifies sender-side complete authority before a protected
  /// outbox row can retire. Production supplies the durable event-log owner;
  /// simple repositories may omit it for non-production queue tests.
  final Future<bool> Function(GroupPendingBroadcast broadcast)?
  ensureProtectedAuthorityComplete;

  /// Dedicated prepared -> strict custody -> atomic terminal+COMPLETE recovery
  /// for dissolve rows. The callback owns every exact row for the transition;
  /// the generic per-row removal path must never retire one early.
  final Future<bool> Function(GroupPendingBroadcast broadcast)?
  finalizeProtectedDissolve;

  /// One identity-safe serial tail per group. The map always points at the
  /// newest queued turn; an older completion may remove it only when it still
  /// owns that exact entry.
  final Map<String, Future<void>> _groupTails = <String, Future<void>>{};

  GroupPendingBroadcastRunner({
    required this.repository,
    required this.rePush,
    this.rePushFinalizesSuccess = false,
    this.protectedInboxStore,
    this.pendingSiblingDeviceRepository,
    this.linkedGroupBootstrapRepository,
    this.ensureProtectedAuthorityComplete,
    this.finalizeProtectedDissolve,
  });

  /// Drains every pending broadcast for [groupId]. Returns the count re-pushed.
  Future<int> drainForGroup(String groupId) => _enqueueGroupDrain(groupId);

  /// Drains every pending broadcast across all groups (app-resume sweep).
  ///
  /// The all-row read is discovery only. Every discovered group enters the
  /// same keyed path as a direct/manual drain and reloads inside its turn.
  Future<int> drainAll() async {
    final discovered = await repository.all();
    final groupIds = <String>{
      for (final broadcast in discovered) broadcast.groupId,
    };
    if (groupIds.isEmpty) return 0;
    final counts = await Future.wait(groupIds.map(_enqueueGroupDrain));
    return counts.fold<int>(0, (total, count) => total + count);
  }

  /// Drains only Plan-363 protected rows. Restricted linked pause uses this
  /// exact owner so historical generic system broadcasts remain stopped.
  Future<int> drainProtectedAll() async {
    final discovered = await repository.all();
    final groupIds = <String>{
      for (final broadcast in discovered)
        if (isProtectedGroupPendingBroadcastKind(broadcast.kind))
          broadcast.groupId,
    };
    if (groupIds.isEmpty) return 0;
    final counts = await Future.wait(
      groupIds.map(
        (groupId) => _enqueueGroupDrain(groupId, protectedOnly: true),
      ),
    );
    return counts.fold<int>(0, (total, count) => total + count);
  }

  Future<int> _enqueueGroupDrain(String groupId, {bool protectedOnly = false}) {
    final result = Completer<int>();
    final previous = _groupTails[groupId] ?? Future<void>.value();
    late final Future<void> current;
    current = previous
        .then((_) async {
          try {
            result.complete(
              await _drain(
                () => repository.forGroup(groupId),
                scope: _safeId(groupId),
                protectedOnly: protectedOnly,
              ),
            );
          } catch (error, stackTrace) {
            result.completeError(error, stackTrace);
          }
        })
        .whenComplete(() {
          if (identical(_groupTails[groupId], current)) {
            _groupTails.remove(groupId);
          }
        });
    _groupTails[groupId] = current;
    return result.future;
  }

  Future<int> _drain(
    Future<List<GroupPendingBroadcast>> Function() load, {
    required String scope,
    bool protectedOnly = false,
  }) async {
    final loaded = await load();
    final pending = protectedOnly
        ? loaded
              .where((row) => isProtectedGroupPendingBroadcastKind(row.kind))
              .toList(growable: false)
        : loaded;
    if (pending.isEmpty) {
      return 0;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_PENDING_BROADCAST_DRAIN_START',
      details: {'scope': scope, 'count': pending.length},
    );

    var drained = 0;
    for (final broadcast in pending) {
      // Durable voluntary-leave notices advance an adjacent intent state in
      // the same SQL transaction that removes their exact row. The generic
      // queue runner must leave them to GroupExitIntentRunner.
      if (broadcast.kind == groupPendingBroadcastKindExitLeaveNotice) {
        continue;
      }
      bool pushed;
      try {
        pushed = isProtectedGroupPendingBroadcastKind(broadcast.kind)
            ? await _pushProtected(broadcast)
            : await rePush(broadcast);
      } catch (e) {
        pushed = false;
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_PENDING_BROADCAST_REPUSH_ERROR',
          details: {
            'groupId': _safeId(broadcast.groupId),
            'error': e.toString(),
          },
        );
      }
      if (pushed &&
          !isProtectedGroupPendingBroadcastKind(broadcast.kind) &&
          !rePushFinalizesSuccess) {
        pushed = await removeGroupPendingBroadcastIfExact(
          repository,
          broadcast,
        );
      }
      if (pushed) {
        drained++;
      }
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_PENDING_BROADCAST_DRAIN_DONE',
      details: {'scope': scope, 'drained': drained, 'total': pending.length},
    );
    return drained;
  }

  Future<bool> _pushProtected(GroupPendingBroadcast broadcast) async {
    final store = protectedInboxStore;
    if (store == null || broadcast.recipientPeerIds.length != 1) return false;
    final recipient = broadcast.recipientPeerIds.single;
    final expectedType =
        broadcast.kind == groupPendingBroadcastKindLinkedBootstrap
        ? linkedGroupBootstrapEnvelopeType
        : protectedGroupAuthorityEnvelopeType;
    final envelope = ProtectedGroupEnvelope.tryParse(
      broadcast.sysText,
      expectedType: expectedType,
    );
    if (envelope == null ||
        envelope.id != broadcast.sourceMessageId ||
        envelope.recipientPeerId != recipient) {
      return false;
    }
    if (broadcast.kind == groupPendingBroadcastKindProtectedAuthority) {
      final pendingRepository = pendingSiblingDeviceRepository;
      if (pendingRepository != null) {
        final pending = await pendingRepository
            .getPendingSiblingDevicesForGroup(broadcast.groupId);
        if (pending.any((row) => row.transportPeerId == recipient)) {
          // Bootstrap custody is the target's readiness barrier. The prepared
          // authority row remains exact and durable, but cannot overtake it.
          return false;
        }
      }
      final identity = parseProtectedGroupAuthorityDeliveryId(
        broadcast.sourceMessageId ?? '',
      );
      if (identity?.control == ProtectedGroupAuthorityControl.groupDissolve) {
        if (identity?.recipientTransportPeerId != recipient) return false;
        final finalize = finalizeProtectedDissolve;
        return finalize != null && await finalize(broadcast);
      }
      final ensureComplete = ensureProtectedAuthorityComplete;
      if (ensureComplete != null && !await ensureComplete(broadcast)) {
        // A prepared sender row may survive a crash before its local
        // projection. Do not expose that transition or retire its owner until
        // complete history has been proven from durable local state.
        return false;
      }
    }
    final custodyKind =
        broadcast.kind == groupPendingBroadcastKindLinkedBootstrap
        ? AckCustodyKind.groupBootstrapV1
        : AckCustodyKind.groupAuthorityV1;
    final outcome = await store.storeInAckCustodyInboxDetailed(
      recipient,
      broadcast.sysText,
      custodyKind: custodyKind,
    );
    if (!outcome.ackOrExpiryAccepted) return false;

    if (broadcast.kind == groupPendingBroadcastKindLinkedBootstrap) {
      final pendingRepository = pendingSiblingDeviceRepository;
      final bootstrapRepository = linkedGroupBootstrapRepository;
      if (pendingRepository == null || bootstrapRepository == null) {
        return false;
      }
      final candidates = await pendingRepository
          .getPendingSiblingDevicesForGroup(broadcast.groupId);
      final matches = candidates
          .where(
            (candidate) =>
                candidate.transportPeerId == recipient &&
                candidate.memberPeerId == envelope.senderPeerId,
          )
          .toList(growable: false);
      if (matches.length != 1) return false;
      return bootstrapRepository.completeLinkedGroupBootstrapCustody(
        expectedDevice: matches.single,
        expectedBroadcast: broadcast,
      );
    }

    final recipientRepository = repository;
    if (recipientRepository
        is! GroupPendingBroadcastProtectedRecipientRepository) {
      return false;
    }
    return (recipientRepository
            as GroupPendingBroadcastProtectedRecipientRepository)
        .removeRecipientIfExact(broadcast, recipient);
  }
}
