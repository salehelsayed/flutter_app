import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import '../../../shared/fakes/fake_notification_service.dart';

void main() {
  late FakeNotificationService notificationService;
  late ActiveConversationTracker tracker;

  setUp(() {
    notificationService = FakeNotificationService();
    tracker = ActiveConversationTracker();
  });

  group('maybeShowNotification', () {
    test(
      'keeps group payload contract for local group notifications',
      () async {
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'group:group-123',
          routePayload: 'group:group-123|message:msg-123',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Hello group!',
        );

        expect(notificationService.shown, hasLength(1));
        expect(
          notificationService.shown.first.contactPeerId,
          'group:group-123',
        );
        expect(
          notificationService.shown.first.payload,
          'group:group-123|message:msg-123',
        );
        expect(notificationService.shown.first.senderUsername, 'Team Chat');
        expect(
          notificationService.shown.first.messageText,
          'Alice: Hello group!',
        );
      },
    );

    test('shows notification when app is backgrounded', () async {
      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
        contactPeerId: 'peer-123',
        senderUsername: 'Alice',
        messageText: 'Hello!',
      );

      expect(notificationService.shown, hasLength(1));
      expect(notificationService.shown.first.senderUsername, 'Alice');
      expect(notificationService.shown.first.messageText, 'Hello!');
    });

    test(
      'suppresses background local notification when a recent remote push already announced the same conversation',
      () async {
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          consumeRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) async => true,
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test(
      'suppresses resumed local notification when a recent remote push already announced the same group message',
      () async {
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'group:group-123',
          routePayload: 'group:group-123|message:msg-123',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Hello group!',
          messageId: 'msg-123',
          consumeRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) async {
                expect(payload, 'group:group-123|message:msg-123');
                expect(messageId, 'msg-123');
                return true;
              },
          backgroundDuplicateGuardDelay: const Duration(minutes: 5),
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test('suppresses notification during recovery replay', () async {
      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
        contactPeerId: 'peer-123',
        senderUsername: 'Alice',
        messageText: 'Hello!',
        suppressNotification: true,
      );

      expect(notificationService.shown, isEmpty);
    });

    test(
      'resume-only recovery suppression does not synthesize a tap route',
      () async {
        final events = <Map<String, dynamic>>[];
        var routeCalls = 0;
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        notificationService.onNotificationTap = (_) {
          routeCalls += 1;
        };

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Recovered from inbox',
          suppressNotification: true,
        );

        expect(notificationService.shown, isEmpty);
        expect(routeCalls, 0);
        expect(
          events,
          contains(
            predicate<Map<String, dynamic>>((event) {
              final details = event['details'];
              return event['event'] == 'NOTIFICATION_SUPPRESSED' &&
                  details is Map &&
                  details['reason'] == 'recovery_replay';
            }),
          ),
        );
      },
    );

    test(
      'prefers exact message-id suppression over route-wide suppression when available',
      () async {
        var capturedPayload = '';
        String? capturedMessageId;

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          messageId: 'msg-123',
          consumeRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) async {
                capturedPayload = payload;
                capturedMessageId = messageId;
                return true;
              },
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(notificationService.shown, isEmpty);
        expect(capturedPayload, 'peer-123');
        expect(capturedMessageId, 'msg-123');
      },
    );

    test('uses route payload for remote suppression when present', () async {
      var capturedPayload = '';
      String? capturedMessageId;

      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
        contactPeerId: 'group:group-123',
        routePayload: 'group:group-123|message:msg-123',
        senderUsername: 'Team Chat',
        messageText: 'Alice: Hello group!',
        messageId: 'msg-123',
        consumeRecentRemoteNotificationAnnouncement:
            ({required payload, String? messageId}) async {
              capturedPayload = payload;
              capturedMessageId = messageId;
              return true;
            },
        backgroundDuplicateGuardDelay: Duration.zero,
      );

      expect(notificationService.shown, isEmpty);
      expect(capturedPayload, 'group:group-123|message:msg-123');
      expect(capturedMessageId, 'msg-123');
    });

    test(
      'preserves mixed-script sender and body when forwarding notification text',
      () async {
        const sender = '\u0644\u064a\u0644\u0649 Alpha';
        const body = '\u0645\u0631\u062d\u0628\u0627 Team 42';

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-123',
          senderUsername: sender,
          messageText: body,
        );

        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.first.senderUsername, sender);
        expect(notificationService.shown.first.messageText, body);
        expect(notificationService.shown.first.payload, 'peer-123');
      },
    );

    test(
      'preserves bidi control marks in mixed-script body passthrough',
      () async {
        const body = '\u200f\u0645\u0631\u062d\u0628\u0627 Alpha\u200f';

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: body,
        );

        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.first.messageText, body);
      },
    );

    test(
      'shows notification when app is resumed but on different screen',
      () async {
        // Not viewing any conversation
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
        );

        expect(notificationService.shown, hasLength(1));
      },
    );

    test(
      'shows notification when app is resumed and viewing a different conversation',
      () async {
        tracker.setActive('peer-456'); // viewing someone else

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
        );

        expect(notificationService.shown, hasLength(1));
      },
    );

    test(
      'suppresses notification when app is resumed and viewing active 1:1 conversation',
      () async {
        tracker.setActive('peer-123'); // viewing sender's conversation

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test(
      'suppresses notification when app is resumed and viewing active group conversation',
      () async {
        tracker.setActive('group:group-123');

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'group:group-123',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Hello group!',
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test(
      'suppresses active group notification when the contact key is message anchored',
      () async {
        tracker.setActive('group:group-123');

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'group:group-123|message:msg-123',
          routePayload: 'group:group-123|message:msg-123',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Hello group!',
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test(
      'suppresses active group notification using the anchored route payload',
      () async {
        tracker.setActive('group:group-123');

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'group:group-123',
          routePayload: 'group:group-123|message:msg-123',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Hello group!',
        );

        expect(notificationService.shown, isEmpty);
      },
    );

    test('shows notification when app is inactive (not resumed)', () async {
      tracker.setActive('peer-123');

      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.inactive,
        contactPeerId: 'peer-123',
        senderUsername: 'Alice',
        messageText: 'Hello!',
      );

      expect(notificationService.shown, hasLength(1));
    });

    test('shows notification after clearing active conversation', () async {
      tracker.setActive('peer-123');
      tracker.clear();

      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
        contactPeerId: 'peer-123',
        senderUsername: 'Alice',
        messageText: 'Hello!',
      );

      expect(notificationService.shown, hasLength(1));
    });
  });

  group('ActiveConversationTracker', () {
    test('isViewing returns false by default', () {
      expect(tracker.isViewing('any-peer'), isFalse);
    });

    test('isViewing returns true after setActive', () {
      tracker.setActive('peer-123');
      expect(tracker.isViewing('peer-123'), isTrue);
      expect(tracker.isViewing('peer-456'), isFalse);
    });

    test('isViewing returns false after clear', () {
      tracker.setActive('peer-123');
      tracker.clear();
      expect(tracker.isViewing('peer-123'), isFalse);
    });

    test('setActive replaces previous peer', () {
      tracker.setActive('peer-123');
      tracker.setActive('peer-456');
      expect(tracker.isViewing('peer-123'), isFalse);
      expect(tracker.isViewing('peer-456'), isTrue);
    });

    test('clearIfActive only clears the matching active key', () {
      tracker.setActive('peer-123');
      tracker.clearIfActive('peer-456');
      expect(tracker.isViewing('peer-123'), isTrue);

      tracker.clearIfActive('peer-123');
      expect(tracker.isViewing('peer-123'), isFalse);
    });

    test('clearIfActive normalizes anchored group route keys', () {
      tracker.setActive('group:group-123');
      tracker.clearIfActive('group:group-456|message:msg-456');
      expect(tracker.isViewing('group:group-123'), isTrue);

      tracker.clearIfActive('group:group-123|message:msg-123');
      expect(tracker.isViewing('group:group-123'), isFalse);
    });
  });
}
