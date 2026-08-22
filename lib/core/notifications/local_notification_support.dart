import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

const mknoonMessagesChannelId = 'mknoon_messages';
const mknoonMessagesChannelName = 'Messages';
const mknoonMessagesChannelDescription = 'Incoming message notifications';

// 118 Phase 3: a separate, low-importance SILENT channel. An Android channel's
// sound is immutable after `createNotificationChannel`, so a no-sound variant
// requires a distinct channel id rather than mutating the high channel above.
const mknoonMessagesSilentChannelId = 'mknoon_messages_silent';
const mknoonMessagesSilentChannelName = 'Messages (silent)';
const mknoonMessagesSilentChannelDescription =
    'Silent follow-up message updates';

const mknoonMessagesChannel = AndroidNotificationChannel(
  mknoonMessagesChannelId,
  mknoonMessagesChannelName,
  description: mknoonMessagesChannelDescription,
  importance: Importance.high,
);

const mknoonMessagesSilentChannel = AndroidNotificationChannel(
  mknoonMessagesSilentChannelId,
  mknoonMessagesSilentChannelName,
  description: mknoonMessagesSilentChannelDescription,
  importance: Importance.low,
  playSound: false,
  enableVibration: false,
);

const mknoonMessagesNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    mknoonMessagesChannelId,
    mknoonMessagesChannelName,
    channelDescription: mknoonMessagesChannelDescription,
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
  ),
  iOS: DarwinNotificationDetails(
    presentSound: true,
    presentAlert: true,
    presentBadge: true,
  ),
);

NotificationDetails mknoonGenericNotificationDetails({String? androidTag}) {
  if (androidTag == null) {
    return mknoonMessagesNotificationDetails;
  }
  return NotificationDetails(
    android: AndroidNotificationDetails(
      mknoonMessagesChannelId,
      mknoonMessagesChannelName,
      channelDescription: mknoonMessagesChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      tag: androidTag,
    ),
    iOS: const DarwinNotificationDetails(
      presentSound: true,
      presentAlert: true,
      presentBadge: true,
    ),
  );
}

// 118 Phase 3: no-sound, no-vibration variant for the per-conversation tone
// debounce. Reusing the same per-conversation notification id with these
// details performs a silent in-place update of the existing notification.
const mknoonMessagesSilentNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    mknoonMessagesSilentChannelId,
    mknoonMessagesSilentChannelName,
    channelDescription: mknoonMessagesSilentChannelDescription,
    importance: Importance.low,
    priority: Priority.low,
    playSound: false,
    enableVibration: false,
    onlyAlertOnce: true,
  ),
  iOS: DarwinNotificationDetails(
    presentSound: false,
    presentAlert: true,
    presentBadge: true,
  ),
);

/// Message-category details with a stable conversation thread. This is built
/// dynamically because the iOS thread identifier is recipient/conversation
/// specific; Android continues using the existing channel ids.
NotificationDetails mknoonConversationNotificationDetails({
  required String conversationKey,
  bool silent = false,
  bool preservePrimaryAndroidChannel = false,
  bool autoCancel = true,
  ConversationNotificationSnapshot? snapshot,
}) {
  final useSilentAndroidChannel = silent && !preservePrimaryAndroidChannel;
  final historyLines = snapshot?.historyLines
      .where((line) => line.trim().isNotEmpty)
      .take(5)
      .toList(growable: false);
  final unreadMessageCount = snapshot?.totalUnreadMessageCount;
  return NotificationDetails(
    android: AndroidNotificationDetails(
      useSilentAndroidChannel
          ? mknoonMessagesSilentChannelId
          : mknoonMessagesChannelId,
      useSilentAndroidChannel
          ? mknoonMessagesSilentChannelName
          : mknoonMessagesChannelName,
      channelDescription: useSilentAndroidChannel
          ? mknoonMessagesSilentChannelDescription
          : mknoonMessagesChannelDescription,
      importance: useSilentAndroidChannel ? Importance.low : Importance.high,
      priority: useSilentAndroidChannel ? Priority.low : Priority.high,
      playSound: !silent,
      enableVibration: !silent,
      onlyAlertOnce: silent,
      // A same-ID update on the primary channel must retain that channel so
      // Android does not tear down the visible high-importance card. `silent`
      // and `onlyAlertOnce` suppress a second alert without moving the card to
      // the low-importance continuation channel.
      silent: silent,
      category: AndroidNotificationCategory.message,
      autoCancel: autoCancel,
      number: unreadMessageCount != null && unreadMessageCount > 0
          ? unreadMessageCount
          : null,
      styleInformation: historyLines == null || historyLines.isEmpty
          ? null
          : InboxStyleInformation(historyLines),
    ),
    iOS: DarwinNotificationDetails(
      presentSound: !silent,
      presentAlert: true,
      presentBadge: true,
      threadIdentifier: conversationKey,
    ),
  );
}

typedef MknoonActiveNotificationReader =
    Future<List<ActiveNotification>> Function();

/// Whether a silent same-ID update should remain on the primary Android
/// channel.
///
/// Android treats changing the channel of an existing notification as a card
/// replacement. If an audible `mknoon_messages` card is already active, moving
/// its reconciliation update to `mknoon_messages_silent` can collapse the
/// heads-up card and permanently demote it. Keep that exact active card on its
/// current primary channel and use the per-notification silent flags instead.
/// A first silent publication, or an existing low-importance card, continues
/// to use the silent channel.
Future<bool> shouldPreserveMknoonPrimaryChannelForSilentUpdate({
  required bool silent,
  required int notificationId,
  required FlutterLocalNotificationsPlugin plugin,
  MknoonActiveNotificationReader? activeNotificationsFn,
}) async {
  if (!silent || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return false;
  }

  try {
    final activeNotifications =
        await (activeNotificationsFn ?? plugin.getActiveNotifications)();
    return activeNotifications.any(
      (notification) =>
          notification.id == notificationId &&
          notification.channelId == mknoonMessagesChannelId,
    );
  } on Object catch (error) {
    // Inventory is an optimization, not publication authority. Falling back
    // to the low-importance channel remains silent and cannot create a second
    // audible alert.
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_ACTIVE_CHANNEL_READ_FAILED',
      details: <String, Object?>{'errorType': error.runtimeType.toString()},
    );
    return false;
  }
}

/// Reads whether the user-facing `mknoon_messages` channel may still post.
typedef MknoonMessageChannelEnabledReader = Future<bool> Function();

/// Whether the OS still allows posts on the user-facing `mknoon_messages`
/// channel.
///
/// `getNotificationChannels()` reports the LIVE channel, including the user's
/// own Settings edits, so a channel the user switched off comes back at
/// `Importance.none`. There is no other read-back: neither
/// `areNotificationsEnabled()` nor the POST_NOTIFICATIONS permission moves when
/// a single channel is blocked, so app-level checks cannot see this state.
///
/// Fails OPEN on every uncertain reading — off-Android, an unresolved platform
/// plugin, a null channel list, or a channel that has not been created yet.
///
/// Platform selection is the same one `ensureMknoonNotificationChannel` uses:
/// `resolvePlatformSpecificImplementation` returns null on every non-Android
/// target. A `dart:io Platform.isAndroid` gate would be equivalent in
/// production but makes this unreachable under host tests, where the platform
/// override moves `defaultTargetPlatform` and not `Platform`.
Future<bool> mknoonPrimaryMessageChannelEnabled(
  FlutterLocalNotificationsPlugin plugin,
) async {
  if (kIsWeb) return true;
  final android = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (android == null) return true;
  final channels = await android.getNotificationChannels();
  if (channels == null) return true;
  for (final channel in channels) {
    if (channel.id == mknoonMessagesChannelId) {
      return channel.importance != Importance.none;
    }
  }
  return true;
}

/// Decides which channel a message publication may actually use.
///
/// `mknoon_messages_silent` is NOT an independent subscription. It exists only
/// so the tone debounce and the same-ID reconcile can refresh a card without
/// alerting a second time (`mknoonConversationNotificationDetails`), which
/// makes it a continuation of `mknoon_messages`. So when a user switches
/// "Messages" off, routing the same card to the still-open silent channel
/// delivers exactly the notification they just turned off — and the app cannot
/// notice, because nothing else in the stack reads per-channel state.
///
/// Downgrading to silent is therefore withdrawn while the primary channel is
/// blocked, which leaves the publication on the blocked primary channel and
/// the OS refuses it. The post attempt stays real — the SHOWN flow events
/// still fire, which is what the Android device matrix measures — and no card
/// reaches the user on either channel.
///
/// Fails OPEN: any read failure keeps today's silent routing.
Future<bool> resolveMknoonMessagePublicationSilence({
  required bool silent,
  required FlutterLocalNotificationsPlugin plugin,
  MknoonMessageChannelEnabledReader? primaryChannelEnabledFn,
}) async {
  // An audible publication already targets the primary channel; there is no
  // second route to withdraw, so it never pays for the platform read.
  if (!silent) return false;

  final readPrimaryEnabled =
      primaryChannelEnabledFn ??
      () => mknoonPrimaryMessageChannelEnabled(plugin);

  bool primaryEnabled;
  try {
    primaryEnabled = await readPrimaryEnabled();
  } catch (e) {
    // Deliberately BROAD: a platform/plugin failure surfaces as an Error
    // subtype as often as an Exception, and an escaping throw here would abort
    // a publication that is otherwise fine.
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_CHANNEL_STATE_READ_FAILED',
      details: <String, Object?>{'errorType': e.runtimeType.toString()},
    );
    return true;
  }

  if (primaryEnabled) return true;

  emitFlowEvent(
    layer: 'FL',
    event: 'NOTIFICATION_SILENT_CHANNEL_WITHHELD',
    details: <String, Object?>{
      'primaryChannelId': mknoonMessagesChannelId,
      'withheldChannelId': mknoonMessagesSilentChannelId,
    },
  );
  return false;
}

Future<void> ensureMknoonNotificationChannel(
  FlutterLocalNotificationsPlugin plugin,
) async {
  final android = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await android?.createNotificationChannel(mknoonMessagesChannel);
  await android?.createNotificationChannel(mknoonMessagesSilentChannel);
}
