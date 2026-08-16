import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';

export 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';

/// Result of attempting to publish one canonical notification event.
///
/// Only [osPosted], [inChat], and [suppressedPolicy] describe an approved local
/// effect that may later become a durable wake outcome. [terminalWithoutOutcome]
/// deliberately covers replay, dedupe, compatibility, stale-policy, and other
/// terminal branches that are not proof of a completed effect.
enum NotificationPresentationResult {
  osPosted,
  inChat,
  suppressedPolicy,
  terminalWithoutOutcome,
  contendedRetryable;

  /// Compatibility aliases for callers that only need terminal/retry behavior.
  /// New outcome producers must switch on the five canonical values above.
  @Deprecated('Use osPosted')
  static const NotificationPresentationResult shown = osPosted;

  @Deprecated('Use terminalWithoutOutcome')
  static const NotificationPresentationResult terminalSuppressed =
      terminalWithoutOutcome;

  bool get carriesApprovedOutcome =>
      this == osPosted || this == inChat || this == suppressedPolicy;

  bool get isTerminal => this != contendedRetryable;
}

/// Privacy-normalized canonical unread state for one stable conversation card.
///
/// Callers derive this from the database immediately before projection. It is
/// never persisted in display custody: history is bounded to five lines while
/// [totalUnreadMessageCount] remains the uncapped canonical message count.
final class ConversationNotificationHistoryEntry {
  const ConversationNotificationHistoryEntry({
    required this.eventId,
    required this.line,
    required this.occurredAtMicros,
  });

  /// Canonical ordinary-message identity. Reactions never appear in history.
  final String eventId;
  final String line;
  final int occurredAtMicros;
}

final class ConversationNotificationSnapshot {
  ConversationNotificationSnapshot({
    required Iterable<String> historyLines,
    required this.totalUnreadMessageCount,
    Iterable<String> canonicalEventIds = const <String>[],
    Iterable<ConversationNotificationHistoryEntry> orderedHistory =
        const <ConversationNotificationHistoryEntry>[],
  }) : historyLines = List<String>.unmodifiable(historyLines),
       canonicalEventIds = Set<String>.unmodifiable(canonicalEventIds),
       orderedHistory = List<ConversationNotificationHistoryEntry>.unmodifiable(
         orderedHistory,
       ) {
    if (this.historyLines.length > 5) {
      throw ArgumentError.value(historyLines, 'historyLines', 'maximum is 5');
    }
    if (this.historyLines.any((line) => line.trim().isEmpty)) {
      throw ArgumentError.value(
        historyLines,
        'historyLines',
        'lines must be non-empty',
      );
    }
    if (totalUnreadMessageCount < this.historyLines.length) {
      throw ArgumentError.value(
        totalUnreadMessageCount,
        'totalUnreadMessageCount',
        'must cover every history line',
      );
    }
    if (this.canonicalEventIds.any((id) => id.trim().isEmpty)) {
      throw ArgumentError.value(
        canonicalEventIds,
        'canonicalEventIds',
        'ids must be non-empty',
      );
    }
    if (this.canonicalEventIds.length > totalUnreadMessageCount) {
      throw ArgumentError.value(
        canonicalEventIds,
        'canonicalEventIds',
        'cannot exceed total unread message count',
      );
    }
    if (this.orderedHistory.isNotEmpty &&
        (this.orderedHistory.length != this.historyLines.length ||
            !this.orderedHistory
                .map((entry) => entry.line)
                .toList(growable: false)
                .indexed
                .every((pair) => pair.$2 == this.historyLines[pair.$1]))) {
      throw ArgumentError.value(
        orderedHistory,
        'orderedHistory',
        'must align exactly with historyLines',
      );
    }
    if (this.orderedHistory.any(
      (entry) => entry.eventId.trim().isEmpty || entry.line.trim().isEmpty,
    )) {
      throw ArgumentError.value(
        orderedHistory,
        'orderedHistory',
        'entries must be non-empty canonical events',
      );
    }
  }

  final List<String> historyLines;
  final int totalUnreadMessageCount;

  /// Every eligible canonical unread ordinary-message id, not merely the five
  /// rendered history rows. Pending push projections use this set to retire an
  /// event as soon as the encrypted database materializes it.
  final Set<String> canonicalEventIds;

  /// Timestamped metadata for the bounded rendered history. Older callers may
  /// omit it; projection code then conservatively places pending arrivals after
  /// the already-rendered canonical lines.
  final List<ConversationNotificationHistoryEntry> orderedHistory;
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
    this.snapshot,
  });

  final String senderUsername;
  final String messageText;
  final String routePayload;
  final ConversationNotificationContentKind contentKind;
  final String eventIdentity;
  final ConversationNotificationSnapshot? snapshot;
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

/// The exact native show operation after notification-id/content-registry
/// preparation has completed.
typedef NativeMessageNotificationShow =
    Future<void> Function({required bool silent});

typedef PublishNativeMessageNotificationAtDurableBarrier =
    Future<bool> Function(
      NativeMessageNotificationShow showNative,
      AuthorizeDurableLocalNotificationNativeEntry authorize,
    );

/// Owns the narrow boundary where a prepared notification is handed to the
/// platform. Android durable event/tone owners use this seam so ordinary
/// registry failures remain known pre-publication failures, while a platform
/// error after entering [publishNative] is treated as an ambiguous attempt.
abstract interface class MessageNotificationNativePublicationBoundary {
  Future<void> showMessageNotificationAtNativeBoundary({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    ConversationNotificationContentKind? contentKind,
    String? contentEventIdentity,
    ConversationNotificationSnapshot? snapshot,
    required Future<void> Function(NativeMessageNotificationShow showNative)
    publishNative,
  });
}

/// Optional exact-correlation path whose terminal presentation result is
/// decided under the stable-id registry lock at the final native boundary.
/// Legacy and unanchored callers continue using [NotificationService].
abstract interface class MessageNotificationDurableFinalEffectBoundary {
  Future<DurableLocalNotificationEffectResult>
  showMessageNotificationWithDurableFinalEffect({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    required ConversationNotificationContentKind contentKind,
    required String contentEventIdentity,
    ConversationNotificationSnapshot? snapshot,
    required DurableLocalNotificationEffectContext durableEffectContext,
    required AppVisibilitySuppressionReader finalVisibility,
    required AppVisibilityConversationIdentity conversationIdentity,
    required PublishNativeMessageNotificationAtDurableBarrier publishNative,
  });
}

/// Optional post-handoff hook. It is invoked only after an exact terminal
/// observer has completed its SQL handoff and ledger settlement outside the
/// registry lock, so recovery reconciliation never interposes between them.
abstract interface class MessageNotificationDurablePostHandoffReconciliation {
  Future<void> notifyDurableEffectHandoffComplete(
    DurableLocalNotificationEffectReceipt receipt,
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
    ConversationNotificationSnapshot? snapshot,
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
