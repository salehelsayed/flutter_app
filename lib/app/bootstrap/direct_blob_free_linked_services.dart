import 'package:flutter_app/core/application/protected_group_content_runtime_quiescence.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// 361: the ONE restricted runtime start path for an ACTIVE linked secondary.
///
/// It starts exactly: the bridge, the incoming message router, the direct
/// chat/reaction/deletion/delivery-receipt listeners, the persisted linked
/// transport, one exact P2P inbox retrieve/stage/replay+ACK pass, and the exact
/// v113 blob-free fanout drain.
/// 362 adds ONLY the target-qualified direct strict-media custody owners
/// (local cleanup plus the exact v114/v108 drain-and-download convergers),
/// injected optionally so the 361 blob-free composition stays byte-identical
/// when they are absent. Provider registration, contact request/key exchange,
/// contact/history hydration, group/post/feed, broad share-intent startup,
/// linked LAN discovery, and generic push/wake owners stay stopped. It never
/// calls the generic `startLiveServices`.
class DirectBlobFreeLinkedServices {
  const DirectBlobFreeLinkedServices({
    required this.initializeBridge,
    required this.startMessageRouter,
    required this.startChatMessageListener,
    required this.startReactionListener,
    required this.startMessageDeletionListener,
    required this.startDeliveryReceiptListener,
    required this.startLinkedTransport,
    this.afterLinkedTransportQualified,
    required this.drainOfflineInbox,
    required this.drainExactBlobFreeFanoutOutboxes,
    this.cleanupLinkedDirectMediaBlobCustodyLocally,
    this.drainLinkedDirectMediaBlobCustody,
    this.materializeLinkedGroupBootstrap,
    this.replayLinkedGroupAuthority,
    this.pauseLinkedGroupContentAdmission,
    this.resumeLinkedGroupContentAdmission,
    this.replayLinkedGroupContent,
    this.drainLinkedGroupOutgoingMedia,
    this.retryLinkedGroupContent,
    this.drainLinkedGroupIncomingMedia,
    this.drainLinkedGroupNotificationDisplayCustody,
    this.refreshLinkedGroupList,
  });

  final Future<void> Function() initializeBridge;
  final void Function() startMessageRouter;
  final void Function() startChatMessageListener;
  final void Function() startReactionListener;
  final void Function() startMessageDeletionListener;
  final void Function() startDeliveryReceiptListener;

  /// Starts and qualifies the exact transport named by the persisted ACTIVE
  /// linked credential. Recovery must never run before this succeeds: the
  /// protected relay mailbox is keyed by the physical transport peer, not the
  /// logical account peer.
  final Future<bool> Function() startLinkedTransport;

  /// Optional role-qualified owner that may publish/register this physical
  /// linked route after node returned-peer verification. Absent is a strict
  /// zero-work path (including no Firebase/listener subscription).
  final Future<void> Function()? afterLinkedTransportQualified;

  /// One exact relay-inbox retrieve/stage/replay+ACK pass.
  final Future<void> Function() drainOfflineInbox;

  /// The exact v113 blob-free fanout drain — already-committed rows drain
  /// even with the authoring selector OFF.
  final Future<int> Function() drainExactBlobFreeFanoutOutboxes;

  /// 362: bounded local v114 cleanup (terminalization / last-reference
  /// artifact retirement) for the linked strict-media owners. Absent keeps
  /// the 361 blob-free runtime byte-identical.
  final Future<void> Function()? cleanupLinkedDirectMediaBlobCustodyLocally;

  /// 362: the exact target-qualified strict-media network drain (incoming
  /// expiry/ACK convergence and eligible re-download). Durable rows drain
  /// regardless of any authoring selector.
  final Future<void> Function()? drainLinkedDirectMediaBlobCustody;

  /// 363 restricted ordering: a second typed protected pass lets an authority
  /// row that appeared before its bootstrap become eligible without starting
  /// generic group recovery.
  final Future<void> Function()? materializeLinkedGroupBootstrap;
  final Future<void> Function()? replayLinkedGroupAuthority;
  final ProtectedGroupContentPauseLease Function()?
  pauseLinkedGroupContentAdmission;
  final Future<bool> Function(ProtectedGroupContentPauseLease lease)?
  resumeLinkedGroupContentAdmission;
  final Future<int> Function()? replayLinkedGroupContent;
  final Future<int> Function()? drainLinkedGroupOutgoingMedia;
  final Future<int> Function()? retryLinkedGroupContent;
  final Future<int> Function()? drainLinkedGroupIncomingMedia;
  final Future<void> Function()? drainLinkedGroupNotificationDisplayCustody;
  final Future<void> Function()? refreshLinkedGroupList;

  Future<bool> start() async {
    try {
      await initializeBridge();
      startMessageRouter();
      startChatMessageListener();
      startReactionListener();
      startMessageDeletionListener();
      startDeliveryReceiptListener();
      if (!await startLinkedTransport()) {
        emitFlowEvent(
          layer: 'FL',
          event: 'DIRECT_BLOB_FREE_LINKED_TRANSPORT_START_FAILED',
          details: const {},
        );
        return false;
      }
      await afterLinkedTransportQualified?.call();
      emitFlowEvent(
        layer: 'FL',
        event: 'DIRECT_BLOB_FREE_LINKED_SERVICES_STARTED',
        details: const {
          'owners':
              'router,chat,reaction,deletion,receipt,linked_transport,'
              'inbox_replay,fanout_drain',
        },
      );
      // Replay + drain run after the exact listener set exists so recovered
      // envelopes route into the restricted surface only.
      final contentPause = pauseLinkedGroupContentAdmission?.call();
      if (contentPause != null) await contentPause.quiesced;
      await drainOfflineInbox();
      // 363: group bootstrap is the prerequisite for every protected group
      // authority row. Keep this ordering immediately behind the typed P2P
      // stage/replay pass and ahead of every unrelated direct/media owner.
      await materializeLinkedGroupBootstrap?.call();
      await replayLinkedGroupAuthority?.call();
      if (contentPause != null &&
          !(await resumeLinkedGroupContentAdmission?.call(contentPause) ??
              false)) {
        return false;
      }
      await drainProtectedGroupContentMediaFixedPoint(
        replayContent: replayLinkedGroupContent,
        drainOutgoingMedia: drainLinkedGroupOutgoingMedia,
        retryContent: retryLinkedGroupContent,
        drainIncomingMedia: drainLinkedGroupIncomingMedia,
      );
      // The generic group listener is intentionally absent in linked mode,
      // so its bounded READY display-custody pass must be driven explicitly
      // after canonical content has reached its fixed point.
      await drainLinkedGroupNotificationDisplayCustody?.call();
      await refreshLinkedGroupList?.call();
      final drained = await drainExactBlobFreeFanoutOutboxes();
      emitFlowEvent(
        layer: 'FL',
        event: 'DIRECT_BLOB_FREE_LINKED_FANOUT_DRAINED',
        details: {'completed': drained},
      );
      // 362: the strict-media custody convergers run last, after the exact
      // event surface is live; both are optional and bounded.
      await cleanupLinkedDirectMediaBlobCustodyLocally?.call();
      await drainLinkedDirectMediaBlobCustody?.call();
      return true;
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DIRECT_BLOB_FREE_LINKED_SERVICES_START_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
      return false;
    }
  }
}
