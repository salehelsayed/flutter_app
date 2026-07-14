import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/push/application/push_decrypt_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'APL-07 private announcement notification keeps group sender policy and bytes out of visible copy',
    () async {
      const message = RemoteMessage(
        data: <String, String>{
          'type': 'group_message',
          'groupId': 'announcement-private',
          'sender_id': 'announcement-admin',
          'message_id': 'announcement-private-message',
          'keyEpoch': '7',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      );
      final resolved = await resolveBackgroundPushNotification(
        message,
        locale: const Locale('en'),
        groupMessageContext: const GroupMessageNotificationContext(
          groupId: 'announcement-private',
          groupName: 'SECRET announcement title',
          localPeerId: 'announcement-reader',
          senderPeerId: 'announcement-admin',
          senderUsername: 'SECRET admin name',
          expectedMessageId: 'announcement-private-message',
        ),
        decryptGroup:
            ({
              required groupId,
              required keyEpoch,
              required ciphertext,
              required nonce,
            }) async => jsonEncode(<String, Object?>{
              'groupId': groupId,
              'messageId': 'announcement-private-message',
              'senderPeerId': 'announcement-admin',
              'senderUsername': 'SECRET payload admin',
              'text': 'SECRET private announcement caption',
              'media': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'SECRET-private-announcement-blob',
                  'mime': 'video/mp4',
                  'mediaType': 'video',
                },
              ],
              'mediaPolicyVersion': 1,
              'mediaLifecycle': 'viewOnce',
              'mediaDurationSeconds': null,
              'mediaProtected': true,
            }),
      );

      expect(resolved.title, 'Mknoon');
      expect(resolved.body, 'New private media');
      final visibleCopy = '${resolved.title}|${resolved.body}';
      for (final forbidden in const <String>[
        'SECRET',
        'announcement title',
        'admin name',
        'caption',
        'video',
        'viewOnce',
        'private-announcement-blob',
      ]) {
        expect(visibleCopy, isNot(contains(forbidden)), reason: forbidden);
      }
    },
  );
}
