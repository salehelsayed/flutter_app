import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Shows a local notification for an incoming message unless the user
/// is currently viewing that conversation in the foreground.
///
/// Suppression logic:
///   - App resumed AND viewing sender's conversation -> suppress
///   - Otherwise -> show notification
Future<void> maybeShowNotification({
  required NotificationService notificationService,
  required ActiveConversationTracker conversationTracker,
  required AppLifecycleState Function() getAppLifecycleState,
  required String contactPeerId,
  required String senderUsername,
  required String messageText,
}) async {
  final lifecycleState = getAppLifecycleState();
  final isViewingConversation = conversationTracker.isViewing(contactPeerId);

  if (lifecycleState == AppLifecycleState.resumed && isViewingConversation) {
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_SUPPRESSED',
      details: {
        'reason': 'viewing_conversation',
        'contactPeerId': contactPeerId.length > 10
            ? contactPeerId.substring(0, 10)
            : contactPeerId,
      },
    );
    return;
  }

  await notificationService.showMessageNotification(
    contactPeerId: contactPeerId,
    senderUsername: senderUsername,
    messageText: messageText,
  );
}
