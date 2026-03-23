import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
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
          senderUsername: 'Team Chat',
          messageText: 'Alice: Hello group!',
        );

        expect(notificationService.shown, hasLength(1));
        expect(
          notificationService.shown.first.contactPeerId,
          'group:group-123',
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
  });
}
