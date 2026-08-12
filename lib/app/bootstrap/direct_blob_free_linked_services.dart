import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// 361: the ONE restricted runtime start path for an ACTIVE linked secondary.
///
/// It starts exactly: the bridge, the incoming message router, the direct
/// chat/reaction/deletion/delivery-receipt listeners, one exact P2P inbox
/// retrieve/stage/replay+ACK pass, and the exact v113 blob-free fanout drain.
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
    required this.drainOfflineInbox,
    required this.drainExactBlobFreeFanoutOutboxes,
    this.cleanupLinkedDirectMediaBlobCustodyLocally,
    this.drainLinkedDirectMediaBlobCustody,
  });

  final Future<void> Function() initializeBridge;
  final void Function() startMessageRouter;
  final void Function() startChatMessageListener;
  final void Function() startReactionListener;
  final void Function() startMessageDeletionListener;
  final void Function() startDeliveryReceiptListener;

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

  Future<bool> start() async {
    try {
      await initializeBridge();
      startMessageRouter();
      startChatMessageListener();
      startReactionListener();
      startMessageDeletionListener();
      startDeliveryReceiptListener();
      emitFlowEvent(
        layer: 'FL',
        event: 'DIRECT_BLOB_FREE_LINKED_SERVICES_STARTED',
        details: const {
          'owners':
              'router,chat,reaction,deletion,receipt,inbox_replay,fanout_drain',
        },
      );
      // Replay + drain run after the exact listener set exists so recovered
      // envelopes route into the restricted surface only.
      await drainOfflineInbox();
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
