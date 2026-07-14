import 'dart:io';

import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/notifications/remote_notification_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('message_reaction identity uses event id instead of target id', () {
    const data = <String, dynamic>{
      'type': 'message_reaction',
      'sender_id': 'peer-reactor',
      'event_id': 'reaction-event-1',
      'target_message_id': 'target-message-1',
      'action': 'add',
    };

    expect(remoteNotificationMessageIdFromData(data), 'reaction-event-1');
  });

  test('group_reaction identity uses transition id instead of target id', () {
    const data = <String, dynamic>{
      'type': 'group_reaction',
      'groupId': 'group-1',
      'reactor_peer_id': 'peer-reactor',
      'event_id': 'group-transition-1',
      'target_message_id': 'target-message-1',
      'action': 'add',
    };

    expect(remoteNotificationMessageIdFromData(data), 'group-transition-1');
  });

  test('reaction open marks canonical peer plus event announcement', () async {
    final directory = Directory.systemTemp.createTempSync('remote-reaction-');
    final gate = RecentRemoteNotificationGate(
      filePath: '${directory.path}/gate.json',
    );
    addTearDown(() async {
      await gate.clear();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    const data = <String, dynamic>{
      'type': 'message_reaction',
      'sender_id': 'peer-reactor',
      'event_id': 'reaction-event-1',
      'target_message_id': 'target-message-1',
      'action': 'add',
    };

    expect(
      await markRemoteNotificationOpenAsRecentAnnouncement(
        data: data,
        gate: gate,
      ),
      isTrue,
    );
    expect(
      await gate.consumeIfRecentAnnouncement(
        payload: 'peer-reactor',
        messageId: 'reaction-event-1',
      ),
      isTrue,
    );
  });
}
