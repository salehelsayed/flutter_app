import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';

import '../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../features/conversation/domain/repositories/fake_message_repository.dart';
import '../shared/fakes/fake_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'background push announcement suppresses later local chat notification for the same conversation',
    () async {
      flowEventLoggingEnabled = false;

      final gate = RecentRemoteNotificationGate(
        filePath:
            '${Directory.systemTemp.path}/chat-notification-dedupe-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      debugSetRecentRemoteNotificationGate(gate);
      addTearDown(() async {
        await gate.clear();
        debugResetRecentRemoteNotificationGate();
      });

      const peerId = 'peer-alice';
      await firebaseMessagingBackgroundHandler(
        const RemoteMessage(
          notification: RemoteNotification(title: 'Alice', body: 'Hey!'),
          data: {
            'type': 'new_message',
            'sender_id': peerId,
            'message_id': 'msg-remote-dedupe-1',
          },
        ),
      );

      final chatStreamController = StreamController<ChatMessage>.broadcast();
      addTearDown(chatStreamController.close);

      final contactRepo = FakeContactRepository()
        ..seed([
          const ContactModel(
            peerId: peerId,
            publicKey: 'pk-peer-alice',
            rendezvous: '/dns4/rendezvous.example.com/tcp/4001/p2p/peer-alice',
            username: 'Alice',
            signature: 'sig-peer-alice',
            scannedAt: '2026-04-03T12:00:00.000Z',
          ),
        ]);
      final messageRepo = FakeMessageRepository();
      final notificationService = FakeNotificationService();
      final listener = ChatMessageListener(
        chatMessageStream: chatStreamController.stream,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        notificationService: notificationService,
        conversationTracker: ActiveConversationTracker(),
        getAppLifecycleState: () => AppLifecycleState.paused,
        remoteNotificationGate: gate,
        backgroundNotificationDuplicateGuardDelay: Duration.zero,
      )..start();
      addTearDown(listener.dispose);

      chatStreamController.add(
        ChatMessage(
          from: peerId,
          to: 'peer-self',
          content: jsonEncode({
            'type': 'chat_message',
            'version': '1',
            'payload': {
              'id': 'msg-remote-dedupe-1',
              'text': 'Hello from Alice',
              'senderPeerId': peerId,
              'senderUsername': 'Alice',
              'timestamp': '2026-04-03T12:00:01.000Z',
            },
          }),
          timestamp: '2026-04-03T12:00:01.000Z',
          isIncoming: true,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(notificationService.shown, isEmpty);
      expect(messageRepo.lastSavedMessage?.id, 'msg-remote-dedupe-1');
      expect(
        await gate.consumeIfRecentAnnouncement(
          payload: peerId,
          messageId: 'msg-remote-dedupe-1',
        ),
        isFalse,
      );
    },
  );
}
