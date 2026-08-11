import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// One per-target encryption product.
typedef DirectEventFanoutEncryptFn =
    Future<({String kem, String ciphertext, String nonce})?> Function({
      required String recipientMlKemPublicKey,
      required String plaintext,
    });

/// Route decision for one blob-free direct event authoring attempt.
enum DirectEventFanoutRoute {
  /// Primary role with an UNINITIALIZED roster: the incumbent single-target
  /// path stays byte-for-byte, regardless of the selector.
  incumbentLegacy,

  /// Initialized roster (or linked origin) with the authoring selector OFF:
  /// refuse BEFORE any target crypto or network; never demote to legacy.
  refusedSelectorOff,

  /// Missing/blocked contact or zero authorized targets: fail closed rather
  /// than reinterpreting the state as an uninitialized legacy contact.
  refusedUnavailable,

  /// Author the v113 all-target batch.
  fanout,
}

/// Routing plus the persisted-contact snapshot the fanout stage re-verifies.
class DirectEventFanoutRouting {
  const DirectEventFanoutRouting(this.route, [this.snapshot]);

  final DirectEventFanoutRoute route;
  final DirectContactFanoutSnapshot? snapshot;
}

/// Plan 361: the ONE narrow blob-free target-batch owner shared by fresh text,
/// text EDIT, Delete-for-Everyone, and reaction ADD/REMOVE.
///
/// It owns route qualification (persisted nonblocked contact before crypto),
/// survivor-first replay BEFORE resolver/bridge crypto, per-target independent
/// encryption of ONE logical inner event, and the atomic all-target stage.
/// Per-row transport stays with the incumbent per-row live/protected-STORE
/// owners in each sender.
class DirectEventFanoutAuthoring {
  const DirectEventFanoutAuthoring({
    required this.selector,
    required this.linkedOrigin,
    required this.senderTransportPeerId,
    required this.readSnapshot,
    required this.encrypt,
    required this.loadTextSiblings,
    required this.stageTextFanout,
    required this.loadEventSiblings,
    required this.stageMutationFanout,
    required this.stageReactionFanout,
  });

  final DirectLinkedEventFanoutSelector selector;

  /// True when this installation is an ACTIVE linked secondary. Linked-origin
  /// blob-free authoring always requires the selector and v113, even when the
  /// resolver currently yields only the dynamic legacy target.
  final bool linkedOrigin;

  /// The local installation's actual authenticated transport peer: the outer
  /// envelope sender for EVERY candidate. On a primary this equals the
  /// account; on a linked secondary it does not.
  final String senderTransportPeerId;

  final Future<DirectContactFanoutSnapshot?> Function(
    String contactAccountPeerId,
  )
  readSnapshot;
  final DirectEventFanoutEncryptFn encrypt;

  final Future<List<Map<String, Object?>>> Function(String messageId)
  loadTextSiblings;
  final Future<DbDirectEventFanoutStageResult> Function({
    required Map<String, Object?> stagedRow,
    required String messageId,
    required String contactAccountPeerId,
    required String senderTransportPeerId,
    required DirectContactFanoutSnapshot expectedSnapshot,
    required List<DirectEventFanoutTargetCandidate> candidates,
  })
  stageTextFanout;

  final Future<List<Map<String, Object?>>> Function(String eventId)
  loadEventSiblings;
  final Future<DbDirectEventFanoutStageResult> Function({
    required Map<String, Object?>? expectedRow,
    required Map<String, Object?> stagedRow,
    required OutgoingOrdinaryAttemptKind kind,
    required String eventId,
    required String parentMessageId,
    required String contactAccountPeerId,
    required String senderTransportPeerId,
    required DirectContactFanoutSnapshot expectedSnapshot,
    required List<DirectEventFanoutTargetCandidate> candidates,
  })
  stageMutationFanout;
  final Future<DbDirectEventFanoutStageResult> Function({
    required Map<String, Object?> reactionRow,
    required String action,
    required String parentMessageId,
    required String contactAccountPeerId,
    required String senderTransportPeerId,
    required DirectContactFanoutSnapshot expectedSnapshot,
    required List<DirectEventFanoutTargetCandidate> candidates,
  })
  stageReactionFanout;

  /// Qualifies one authoring attempt BEFORE any crypto or network.
  ///
  /// The persisted nonblocked contact is required for every route — a removed
  /// contact refuses rather than falling back to an uninitialized legacy
  /// target that only exists in the caller's stale snapshot.
  Future<DirectEventFanoutRouting> decideRoute(
    String contactAccountPeerId,
  ) async {
    final snapshot = await readSnapshot(contactAccountPeerId);
    if (snapshot == null) {
      _emitRoute('refused_unavailable', contactAccountPeerId);
      return const DirectEventFanoutRouting(
        DirectEventFanoutRoute.refusedUnavailable,
      );
    }
    if (!linkedOrigin && !snapshot.rosterInitialized) {
      return const DirectEventFanoutRouting(
        DirectEventFanoutRoute.incumbentLegacy,
      );
    }
    if (!selector.allowsDirectLinkedEventFanoutAuthoring) {
      _emitRoute('refused_selector_off', contactAccountPeerId);
      return const DirectEventFanoutRouting(
        DirectEventFanoutRoute.refusedSelectorOff,
      );
    }
    if (snapshot.targets.isEmpty) {
      _emitRoute('refused_zero_targets', contactAccountPeerId);
      return const DirectEventFanoutRouting(
        DirectEventFanoutRoute.refusedUnavailable,
      );
    }
    return DirectEventFanoutRouting(DirectEventFanoutRoute.fanout, snapshot);
  }

  /// Encrypts ONE logical inner event independently for every target and
  /// builds the exact per-target outer envelopes. Null on any missing
  /// per-target candidate (the whole batch then refuses all-zero).
  Future<List<DirectEventFanoutTargetCandidate>?> buildCandidates({
    required DirectContactFanoutSnapshot snapshot,
    required String innerPayloadJson,
    required String Function({
      required String kem,
      required String ciphertext,
      required String nonce,
    })
    buildEnvelope,
  }) async {
    final candidates = <DirectEventFanoutTargetCandidate>[];
    for (final target in snapshot.targets) {
      final encrypted = await encrypt(
        recipientMlKemPublicKey: target.mlKemPublicKey,
        plaintext: innerPayloadJson,
      );
      if (encrypted == null) return null;
      candidates.add(
        DirectEventFanoutTargetCandidate(
          recipientPeerId: target.peerId,
          wireEnvelope: buildEnvelope(
            kem: encrypted.kem,
            ciphertext: encrypted.ciphertext,
            nonce: encrypted.nonce,
          ),
        ),
      );
    }
    return candidates;
  }

  void _emitRoute(String reason, String contactAccountPeerId) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DIRECT_EVENT_FANOUT_ROUTE',
      details: <String, Object?>{
        'reason': reason,
        'contact': contactAccountPeerId.length > 10
            ? contactAccountPeerId.substring(0, 10)
            : contactAccountPeerId,
      },
    );
  }
}
