import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';

export 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';

/// Result of attempting to publish one canonical notification event.
///
/// A retry outbox may clear [shown] and [terminalSuppressed] work. It must keep
/// [contendedRetryable], because another producer still owns only a provisional
/// claim and has not proved that an OS card was published.
enum NotificationPresentationResult {
  shown,
  terminalSuppressed,
  contendedRetryable,
}

/// Narrow optional capability for retiring one conversation card.
///
/// Keeping this separate from [NotificationService] means lightweight fakes
/// and non-OS presenters are not forced to implement cancellation. Callers
/// should capability-check before projecting a read event.
abstract interface class ConversationNotificationCancellation {
  Future<void> cancelConversationNotification(
    String conversationKey, {
    ConversationNotificationContentKind? onlyIfContentKind,
    ConversationNotificationContentCancellationPredicate? shouldCancelContent,
  });
}

/// Optional exact-generation capability used when a visible conversation
/// acknowledges whichever managed card was current at that instant.
///
/// Snapshot and cancellation are separate so callers can perform canonical DB
/// work in between. Implementations must compare the generation again at native
/// cancellation time; a later stable-id replacement must survive.
abstract interface class ConversationNotificationGenerationCancellation {
  Future<ConversationNotificationContentMetadata?>
  lookupConversationNotificationContentMetadata(String conversationKey);

  Future<bool> cancelConversationNotificationGeneration(
    String conversationKey,
    String generation,
  );
}

/// Privacy-bounded content needed to rebuild one managed conversation card.
///
/// Reconciliation deliberately bypasses event-tone claims: it refreshes an
/// already represented conversation after canonical state invalidated its
/// previous content, and must never produce a second audible announcement.
final class CanonicalConversationNotificationReplacement {
  const CanonicalConversationNotificationReplacement({
    required this.senderUsername,
    required this.messageText,
    required this.routePayload,
    required this.contentKind,
    required this.eventIdentity,
  });

  final String senderUsername;
  final String messageText;
  final String routePayload;
  final ConversationNotificationContentKind contentKind;
  final String eventIdentity;
}

/// Optional exact-generation capability for atomically rebuilding a shared
/// stable-id card.
///
/// The generation comparison and native replacement must share the durable
/// registry lock. Returning false means another isolate replaced the card and
/// the caller must re-read current metadata instead of overwriting it.
abstract interface class ConversationNotificationGenerationReplacement {
  Future<bool> replaceConversationNotificationGeneration(
    String conversationKey,
    String expectedGeneration,
    CanonicalConversationNotificationReplacement replacement,
  );
}

/// Abstract interface for showing local notifications.
abstract class NotificationService {
  /// Initialize the notification plugin and create channels.
  Future<void> initialize();

  /// Show a notification for an incoming message.
  ///
  /// When [silent] is true (118 Phase 3/4: within the per-conversation tone
  /// debounce window) the notification updates in place with no sound or
  /// vibration, reusing the per-conversation notification id.
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    ConversationNotificationContentKind? contentKind,
    String? contentEventIdentity,
  });

  /// Show a generic notification with a title, body, and optional payload.
  ///
  /// The [payload] string is passed to [onNotificationTap] when the user taps
  /// the notification, enabling deep-link navigation.
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  });

  /// Callback invoked when the user taps a notification.
  void Function(String payload)? onNotificationTap;

  /// Returns the launch payload if the app was opened from a local notification.
  Future<String?> consumeInitialPayload();

  /// Clears delivered notifications owned by the app.
  Future<void> clearDeliveredNotifications();

  /// Clean up resources.
  void dispose();
}
