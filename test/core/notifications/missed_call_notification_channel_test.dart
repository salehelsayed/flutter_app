import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/notifications/local_notification_support.dart';

/// 406: missed calls get their own Android channel.
///
/// A missed call is not a message. Sharing `mknoon_messages` would mean the
/// user cannot silence one without silencing the other, and a channel the user
/// disabled for chat would silently take calls down with it.
void main() {
  test('TC-406-20 the calls channel is distinct and importance-high', () {
    expect(mknoonCallsChannelId, isNot(mknoonMessagesChannelId));
    expect(mknoonCallsChannelId, isNot(mknoonMessagesSilentChannelId));
    expect(mknoonCallsChannel.id, mknoonCallsChannelId);
    expect(mknoonCallsChannel.name, mknoonCallsChannelName);
    expect(mknoonCallsChannel.importance, Importance.high);
  });

  test('TC-406-21 missed-call details publish on the calls channel', () {
    final android = mknoonMissedCallNotificationDetails.android;
    expect(android, isNotNull);
    expect(android!.channelId, mknoonCallsChannelId);
    expect(android.importance, Importance.high);
    expect(
      android.category,
      AndroidNotificationCategory.missedCall,
      reason: 'the OS ranks and groups a missed call by this category',
    );
  });

  test('TC-406-22 the channel census names every channel the app creates', () {
    expect(
      mknoonNotificationChannels.map((channel) => channel.id).toList(),
      containsAll(<String>[
        mknoonMessagesChannelId,
        mknoonMessagesSilentChannelId,
        mknoonCallsChannelId,
      ]),
      reason:
          'ensureMknoonNotificationChannel creates exactly this list; a '
          'channel that is never created posts nothing on Android 8+',
    );
  });
}
