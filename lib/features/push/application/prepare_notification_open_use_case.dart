import 'dart:async';

import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

typedef DrainGroupOfflineInboxForGroupFn =
    Future<void> Function(String groupId);
typedef IngestStagedPushEnvelopesFn = Future<void> Function();

class PrepareNotificationOpenResult {
  final bool ok;
  final String? error;

  const PrepareNotificationOpenResult._({required this.ok, this.error});

  const PrepareNotificationOpenResult.success() : this._(ok: true);

  const PrepareNotificationOpenResult.failed(String error)
    : this._(ok: false, error: error);
}

Future<PrepareNotificationOpenResult> prepareNotificationOpen({
  required NotificationRouteTarget routeTarget,
  required Future<void> Function() drainOfflineInbox,
  required DrainGroupOfflineInboxForGroupFn drainGroupOfflineInboxForGroup,
  // FDC-04: optional eager-warm hook for the 1:1 conversation route. Default
  // null keeps existing callers unchanged. On a WARM notif-tap (node already
  // started) this overlaps the dial with the screen appearing; on a COLD tap
  // it is a no-op (the service-level PS-3 gate). Forwarded from
  // prepareNotificationRouteTarget, supplied at main.dart.
  Future<void> Function(String peerId)? warmPeer,
  IngestStagedPushEnvelopesFn? ingestStagedPushEnvelopes,
  Duration stagedPushEnvelopeIngestTimeout = const Duration(milliseconds: 400),
}) async {
  try {
    switch (routeTarget.kind) {
      case NotificationRouteTargetKind.conversation:
        final ingest = ingestStagedPushEnvelopes;
        if (ingest != null) {
          try {
            await Future<void>.sync(
              ingest,
            ).timeout(stagedPushEnvelopeIngestTimeout, onTimeout: () {});
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'NOTIFICATION_OPEN_STAGED_PUSH_INGEST_ERROR',
              details: {'error': e.toString()},
            );
          }
        }
        // 145: do NOT block routing on the relay drain. The conversation screen
        // self-heals via its own notif-tap drain (see ConversationWired), so
        // awaiting here only delays the screen from appearing on warm resume.
        // Fire-and-forget with swallowed+logged errors. `Future.sync` captures a
        // synchronous throw too, so the error never escapes to the awaited-path
        // catch below.
        unawaited(
          Future<void>.sync(drainOfflineInbox).catchError((Object e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'NOTIFICATION_OPEN_CONVERSATION_DRAIN_ERROR',
              details: {'error': e.toString()},
            );
          }),
        );
        // FDC-04: warm the target peer (conversation route only). peerId is
        // String? on NotificationRouteTarget but the .conversation ctor
        // guarantees non-null. Fire-and-forget; warmPeer is total/never-throws,
        // but mirror the drain's swallow so a stray throw can't escape to the
        // outer catch (which would fail the route).
        final warmPeerId = routeTarget.peerId;
        if (warmPeer != null && warmPeerId != null) {
          unawaited(
            Future<void>.sync(
              () => warmPeer(warmPeerId),
            ).catchError((Object _) {}),
          );
        }
        break;
      case NotificationRouteTargetKind.contactRequest:
      case NotificationRouteTargetKind.intros:
        await drainOfflineInbox();
        break;
      case NotificationRouteTargetKind.group:
        final groupId = routeTarget.groupId;
        if (groupId == null || groupId.isEmpty) {
          return const PrepareNotificationOpenResult.failed(
            'missing groupId for group notification route',
          );
        }
        try {
          await drainGroupOfflineInboxForGroup(groupId);
        } catch (e) {
          // A cold notification tap can arrive before the Go node is ready.
          // The target group/message is already recipient-owned local state;
          // catch-up is helpful but must never make the deep link disappear.
          // GroupConversationWired retries recovery after the route opens.
          emitFlowEvent(
            layer: 'FL',
            event: 'NOTIFICATION_OPEN_GROUP_DRAIN_ERROR',
            details: {'error': e.toString()},
          );
        }
        break;
      case NotificationRouteTargetKind.post:
      case NotificationRouteTargetKind.postComment:
        break;
    }

    return const PrepareNotificationOpenResult.success();
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_OPEN_PREPARATION_ERROR',
      details: {'kind': routeTarget.kind.name, 'error': e.toString()},
    );
    return PrepareNotificationOpenResult.failed(e.toString());
  }
}
