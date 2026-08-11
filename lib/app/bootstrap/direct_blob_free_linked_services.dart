import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// 361: the ONE restricted runtime start path for an ACTIVE linked secondary.
///
/// It starts exactly: the bridge, the incoming message router, the direct
/// chat/reaction/deletion/delivery-receipt listeners, one exact P2P inbox
/// retrieve/stage/replay+ACK pass, and the exact v113 blob-free fanout drain.
/// Provider registration, contact request/key exchange, contact/history
/// hydration, group/post/feed, media/voice/private authoring/download, and
/// generic push/wake owners stay stopped. It never calls the generic
/// `startLiveServices`.
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
