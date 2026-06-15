import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
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
      'GIRD-006 suppresses only the exact remotely announced group message',
      () async {
        final announced = <String>{'group:group-123|message:msg-remote'};

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'group:group-123',
          routePayload: 'group:group-123|message:msg-remote',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Photo',
          messageId: 'msg-remote',
          consumeRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) async {
                expect(messageId, 'msg-remote');
                return announced.remove(payload);
              },
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'group:group-123',
          routePayload: 'group:group-123|message:msg-local',
          senderUsername: 'Team Chat',
          messageText: 'Alice: Photo',
          messageId: 'msg-local',
          consumeRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) async {
                expect(messageId, 'msg-local');
                return announced.remove(payload);
              },
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(notificationService.shown, hasLength(1));
        expect(
          notificationService.shown.single.payload,
          'group:group-123|message:msg-local',
        );
      },
    );

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

    // 118 Phase 2: gate contract lock + live-wins FCM dedup handshake.
    test(
      'emits the provided suppressionReason instead of the default literal',
      () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          suppressNotification: true,
          suppressionReason: 'genuine_recovery_drain',
        );

        expect(notificationService.shown, isEmpty);
        expect(
          events,
          contains(
            predicate<Map<String, dynamic>>((event) {
              final details = event['details'];
              return event['event'] == 'NOTIFICATION_SUPPRESSED' &&
                  details is Map &&
                  details['reason'] == 'genuine_recovery_drain';
            }),
          ),
        );
      },
    );

    test(
      'live path writes a live-wins dedup marker so a late FCM isolate '
      'suppresses the same messageId',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'mknoon_dedup_marker_test',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final gate = RecentRemoteNotificationGate(
          filePath: '${tempDir.path}/gate.json',
        );

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          messageId: 'm1',
          markRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) =>
                  gate.markAnnouncement(payload: payload, messageId: messageId),
        );

        // The live message showed AND its marker is now recorded.
        expect(notificationService.shown, hasLength(1));

        // A late FCM background isolate consuming the SAME (payload|messageId)
        // finds-and-suppresses, preventing a second notification.
        final lateFcmWouldSuppress = await gate.consumeIfRecentAnnouncement(
          payload: 'peer-123',
          messageId: 'm1',
        );
        expect(lateFcmWouldSuppress, isTrue);
      },
    );

    test(
      'live path does NOT write a dedup marker when messageId is absent '
      '(no over-suppression of unrelated payload messages)',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'mknoon_dedup_marker_test_noid',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final gate = RecentRemoteNotificationGate(
          filePath: '${tempDir.path}/gate.json',
        );

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-123',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          // no messageId
          markRecentRemoteNotificationAnnouncement:
              ({required payload, String? messageId}) =>
                  gate.markAnnouncement(payload: payload, messageId: messageId),
        );

        expect(notificationService.shown, hasLength(1));
        final wouldSuppress = await gate.consumeIfRecentAnnouncement(
          payload: 'peer-123',
        );
        expect(wouldSuppress, isFalse);
      },
    );
  });

  // 118 Phase 5 (VERIFICATION/CHARACTERIZATION): these lock that the live↔FCM
  // dedup race does not double-notify, in BOTH orderings, against the Phase 1+2
  // code with no further production change. A failure here would be the signal
  // that a real fix is needed.
  group('118 Phase 5: live <-> FCM dedup-race characterization', () {
    late Directory tempDir;
    late RecentRemoteNotificationGate gate;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mknoon_p5_dedup');
      gate = RecentRemoteNotificationGate(filePath: '${tempDir.path}/gate.json');
    });
    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<bool> consume({required String payload, String? messageId}) =>
        gate.consumeIfRecentAnnouncement(payload: payload, messageId: messageId);
    Future<void> mark({required String payload, String? messageId}) =>
        gate.markAnnouncement(payload: payload, messageId: messageId);

    test(
      'live direct then FCM drain (same messageId) does not double-notify',
      () async {
        // Live-first: resumed-but-not-viewing shows AND writes the marker.
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-1',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          messageId: 'm1',
          consumeRecentRemoteNotificationAnnouncement: consume,
          markRecentRemoteNotificationAnnouncement: mark,
          backgroundDuplicateGuardDelay: Duration.zero,
        );
        expect(notificationService.shown, hasLength(1));

        // The late FCM drain of the SAME messageId consumes the marker and
        // suppresses with reason recent_remote_push.
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-1',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          messageId: 'm1',
          consumeRecentRemoteNotificationAnnouncement: consume,
          markRecentRemoteNotificationAnnouncement: mark,
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(notificationService.shown, hasLength(1));
        expect(
          events,
          contains(
            predicate<Map<String, dynamic>>((event) {
              final details = event['details'];
              return event['event'] == 'NOTIFICATION_SUPPRESSED' &&
                  details is Map &&
                  details['reason'] == 'recent_remote_push';
            }),
          ),
        );
      },
    );

    test(
      'FCM then live direct (same messageId) does not double-notify',
      () async {
        // FCM-first: the background isolate marked the announcement.
        await mark(payload: 'peer-1', messageId: 'm1');

        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        // Later live direct consumes it -> suppressed (existing FCM-first gate).
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-1',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          messageId: 'm1',
          consumeRecentRemoteNotificationAnnouncement: consume,
          markRecentRemoteNotificationAnnouncement: mark,
          backgroundDuplicateGuardDelay: Duration.zero,
        );

        expect(notificationService.shown, isEmpty);
        expect(
          events,
          contains(
            predicate<Map<String, dynamic>>((event) {
              final details = event['details'];
              return event['event'] == 'NOTIFICATION_SUPPRESSED' &&
                  details is Map &&
                  details['reason'] == 'recent_remote_push';
            }),
          ),
        );
      },
    );

    test(
      'resumed-but-not-viewing path is not delayed by the background guard '
      '(a 10-minute guard would time out if slept)',
      () async {
        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          contactPeerId: 'peer-1',
          senderUsername: 'Alice',
          messageText: 'Hello!',
          messageId: 'm1',
          consumeRecentRemoteNotificationAnnouncement: consume,
          markRecentRemoteNotificationAnnouncement: mark,
          backgroundDuplicateGuardDelay: const Duration(minutes: 10),
        );

        expect(notificationService.shown, hasLength(1));
      },
    );
  });

  // 118 Phase 4: at most one audible tone per conversation per window; the
  // tone key is normalizeActiveKey(contactPeerId), NOT the per-message route.
  group('118 Phase 4: per-conversation tone debounce', () {
    late DateTime now;
    late NotificationToneTracker toneTracker;

    setUp(() {
      now = DateTime.utc(2026, 6, 13, 12);
      toneTracker = NotificationToneTracker(
        clock: () => now,
        window: const Duration(seconds: 30),
      );
    });

    Future<void> showLive({
      required String contactPeerId,
      required String messageId,
      String? routePayload,
    }) {
      return maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
        contactPeerId: contactPeerId,
        routePayload: routePayload,
        senderUsername: 'Alice',
        messageText: 'Hello!',
        messageId: messageId,
        toneTracker: toneTracker,
      );
    }

    test('first live message sounds, second within window is silent', () async {
      await showLive(contactPeerId: 'peer-1', messageId: 'm1');
      expect(notificationService.shown, hasLength(1));
      expect(notificationService.shown.last.silent, isFalse);

      now = now.add(const Duration(seconds: 5));
      await showLive(contactPeerId: 'peer-1', messageId: 'm2');
      expect(notificationService.shown, hasLength(2));
      expect(notificationService.shown.last.silent, isTrue);
    });

    test('first live message after the window sounds again', () async {
      await showLive(contactPeerId: 'peer-1', messageId: 'm1');
      now = now.add(const Duration(seconds: 31));
      await showLive(contactPeerId: 'peer-1', messageId: 'm2');
      expect(
        notificationService.shown.map((s) => s.silent).toList(),
        <bool>[false, false],
      );
    });

    test('a viewed (suppressed) message never consumes the tone window', () async {
      tracker.setActive('peer-1'); // viewing -> suppressed before tone decision
      await showLive(contactPeerId: 'peer-1', messageId: 'm1');
      expect(notificationService.shown, isEmpty);

      tracker.clear();
      await showLive(contactPeerId: 'peer-1', messageId: 'm2');
      expect(notificationService.shown, hasLength(1));
      // The first real message still gets a tone — the suppressed one did not
      // touch shouldPlayTone.
      expect(notificationService.shown.last.silent, isFalse);
    });

    test(
      'group burst is single-tone keyed on the group, not the per-message route',
      () async {
        await showLive(
          contactPeerId: 'group:g1',
          routePayload: 'group:g1|message:a',
          messageId: 'a',
        );
        expect(notificationService.shown.last.silent, isFalse);

        now = now.add(const Duration(seconds: 5));
        await showLive(
          contactPeerId: 'group:g1',
          routePayload: 'group:g1|message:b',
          messageId: 'b',
        );
        // Same group, different routePayload -> still within the window -> silent.
        expect(notificationService.shown.last.silent, isTrue);
      },
    );

    test('when no tone tracker is wired, behavior is unchanged (audible)', () async {
      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
        contactPeerId: 'peer-1',
        senderUsername: 'Alice',
        messageText: 'Hello!',
        messageId: 'm1',
      );
      expect(notificationService.shown, hasLength(1));
      expect(notificationService.shown.last.silent, isFalse);
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
