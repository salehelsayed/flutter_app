import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/group_notification_presentation_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';
import 'package:flutter_app/features/push/application/resolve_group_notification_route_target_use_case.dart';

import '../../../shared/fakes/fake_notification_service.dart';

void main() {
  group('background push fallback notifications', () {
    late Directory groupMessageCoordinatorDirectory;
    late DurableNotificationToneLease groupMessageCoordinator;
    late ActiveConversationTracker groupConversationTracker;

    setUp(() {
      groupMessageCoordinatorDirectory = Directory.systemTemp.createTempSync(
        'foreground-group-fallback-coordinator-',
      );
      groupMessageCoordinator = DurableNotificationToneLease(
        directory: groupMessageCoordinatorDirectory,
        pendingClaimWait: Duration.zero,
      );
      groupConversationTracker = ActiveConversationTracker();
      addTearDown(() {
        if (groupMessageCoordinatorDirectory.existsSync()) {
          groupMessageCoordinatorDirectory.deleteSync(recursive: true);
        }
      });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('shows a fallback for Android-style data-only chat pushes', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const message = RemoteMessage(
        data: {'type': 'new_message', 'sender_id': '12D3KooWPeer'},
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, backgroundPushDefaultTitle);
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, '12D3KooWPeer');
    });

    test('ignores title/body data on protected chat pushes', () {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': '12D3KooWPeer',
          'title': 'Alice',
          'body': 'Hello',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, backgroundPushDefaultTitle);
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, '12D3KooWPeer');
    });

    test(
      'message_reaction uses semantic fallback and event dedupe identity',
      () {
        const message = RemoteMessage(
          data: {
            'type': 'message_reaction',
            'sender_id': 'peer-reactor',
            'event_id': 'reaction-event-1',
            'target_message_id': 'target-message-1',
            'action': 'add',
            'title': 'Sender controlled title',
            'body': 'Sender controlled body 👍',
          },
        );

        final fallback = buildBackgroundPushFallbackNotification(message);
        expect(fallback.title, backgroundPushReactionFallbackTitle);
        expect(fallback.body, backgroundPushReactionFallbackBody);
        expect(fallback.payload, 'peer-reactor');
        expect(
          backgroundPushFallbackDedupeKey(message),
          contains('id=reaction-event-1'),
        );
      },
    );

    test('ignores retired pushTitle/pushBody preview fields', () {
      const message = RemoteMessage(
        data: {
          'type': 'group_message',
          'groupId': 'group-abc-123',
          'pushTitle': 'Team Chat',
          'pushBody': 'Alice: Hello',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, backgroundPushDefaultTitle);
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, 'group:group-abc-123');
    });

    test('ignores retired senderUsername preview fallback', () {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': '12D3KooWPeer',
          'senderUsername': 'Alice',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, backgroundPushDefaultTitle);
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, '12D3KooWPeer');
    });

    test('preserves mixed-script title/body for non-message fallback copy', () {
      const message = RemoteMessage(
        data: {
          'type': 'contact_request',
          'sender_id': '12D3KooWPeer',
          'title': '  \u0644\u064a\u0644\u0649 Alpha  ',
          'body': '\n\u0645\u0631\u062d\u0628\u0627 Team 42\t',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, '\u0644\u064a\u0644\u0649 Alpha');
      expect(fallback.body, '\u0645\u0631\u062d\u0628\u0627 Team 42');
      expect(fallback.payload, 'contact_request:12D3KooWPeer');
    });

    test('preserves bidi control marks in non-message fallback body', () {
      const message = RemoteMessage(
        data: {
          'type': 'contact_request',
          'sender_id': '12D3KooWPeer',
          'body': ' \u200f\u0645\u0631\u062d\u0628\u0627 Alpha\u200f ',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.body, '\u200f\u0645\u0631\u062d\u0628\u0627 Alpha\u200f');
    });

    test(
      'skips the fallback when FCM already carries a visible notification',
      () {
        const message = RemoteMessage(
          notification: RemoteNotification(
            title: 'New Message',
            body: 'You have a new message',
          ),
          data: {'type': 'new_message', 'sender_id': '12D3KooWPeer'},
        );

        expect(shouldShowBackgroundPushFallbackNotification(message), isFalse);
      },
    );

    test(
      'shows iOS fallback for data-only chat pushes when Flutter sees no visible notification payload',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        const message = RemoteMessage(
          data: {'type': 'new_message', 'sender_id': '12D3KooWPeer'},
        );

        expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);
      },
    );

    test(
      'skips named chat fallback on iOS when RemoteMessage already has a visible notification payload',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        const message = RemoteMessage(
          notification: RemoteNotification(title: 'Alice', body: 'Hello'),
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWPeer',
            'title': 'Alice',
            'body': 'Hello',
          },
        );

        expect(shouldShowBackgroundPushFallbackNotification(message), isFalse);
      },
    );

    test('shows fallback for group_message type with groupId', () {
      const message = RemoteMessage(
        data: {
          'type': 'group_message',
          'groupId': 'group-abc-123',
          'messageId': 'msg-123',
          'title': 'Team Chat',
          'body': 'New group message',
        },
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, backgroundPushDefaultTitle);
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, 'group:group-abc-123|message:msg-123');
    });

    test('shows fallback for group-message aliases', () {
      const message = RemoteMessage(
        data: {
          'payloadType': 'group_message',
          'group_id': 'group-snake-123',
          'message_id': 'msg-123',
          'title': 'Team Chat',
          'body': 'New group message',
        },
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, backgroundPushDefaultTitle);
      expect(fallback.body, backgroundPushDefaultBody);
      expect(fallback.payload, 'group:group-snake-123|message:msg-123');
    });

    test(
      'foreground fallback helper shows local notification when requested',
      () async {
        final notificationService = FakeNotificationService();
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'message_id': 'msg-123',
            'title': 'Team Chat',
            'body': 'New group message',
          },
        );

        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: message,
          groupMessageDisplayEligibilityResolver: (_) async =>
              const GroupMessageNotificationDisplayEligibility.allowCurrentMember(),
          groupConversationTracker: groupConversationTracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          durableGroupMessageNotificationCoordinatorResolver: () async =>
              groupMessageCoordinator,
        );

        expect(shown, isTrue);
        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.single.senderUsername, 'Mknoon');
        expect(notificationService.shown.single.messageText, 'Message');
        expect(
          notificationService.shown.single.payload,
          'group:group-abc-123|message:msg-123',
        );
      },
    );

    test(
      'foreground group reaction claims transition and uses stable group card and tone lease',
      () async {
        final notificationService = FakeNotificationService();
        const message = RemoteMessage(
          data: {
            'type': 'group_reaction',
            'action': 'add',
            'group_id': 'group-abc-123',
            'event_id': 'reaction-event-1',
            'target_message_id': 'target-message-1',
            'reactor_peer_id': 'peer-reactor',
          },
        );
        final priorTone = await groupMessageCoordinator.reserveTone(
          'group:group-abc-123',
        );
        expect(priorTone, isNotNull);
        expect(await priorTone!.commit(), isTrue);

        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: message,
          groupReactionNotificationResolver: (_) async =>
              const BackgroundPushNotificationFallback(
                title: 'Project group',
                body: 'Alice reacted 👍 to your message',
                payload: 'group:group-abc-123|message:target-message-1',
              ),
          durableReactionNotificationCoordinatorResolver: () async =>
              groupMessageCoordinator,
          groupConversationTracker: groupConversationTracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
        );

        expect(shown, isTrue);
        expect(notificationService.shown, hasLength(1));
        expect(
          notificationService.shown.single.contactPeerId,
          'group:group-abc-123',
        );
        expect(
          notificationService.shown.single.senderUsername,
          'Project group',
        );
        expect(
          notificationService.shown.single.messageText,
          'Alice reacted 👍 to your message',
        );
        expect(
          notificationService.shown.single.payload,
          'group:group-abc-123|message:target-message-1',
        );
        expect(notificationService.shown.single.silent, isTrue);
        expect(
          notificationService.shown.single.contentKind,
          ConversationNotificationContentKind.reaction,
        );
        expect(notificationService.shownGeneric, isEmpty);
        final eventClaim = File(
          '${groupMessageCoordinatorDirectory.path}/'
          '${DurableNotificationToneLease.eventClaimsDirectoryName}/'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'message_reaction', eventIdentity: boundedReactionEventIdentity('reaction-event-1'))}',
        );
        expect(eventClaim.existsSync(), isTrue);
        expect(eventClaim.readAsStringSync(), contains('"state":"committed"'));
      },
    );

    test(
      'canonical message read after drain suppresses before maybeShow',
      () async {
        final notificationService = FakeNotificationService();
        var readCheckCount = 0;

        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-read-replay',
              'message_id': 'message-read-replay',
            },
          ),
          groupMessageDisplayEligibilityResolver: (_) async =>
              const GroupMessageNotificationDisplayEligibility.allowCurrentMember(),
          groupConversationTracker: groupConversationTracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          durableGroupMessageNotificationCoordinatorResolver: () async =>
              groupMessageCoordinator,
          groupNotificationPresentationCoordinator:
              GroupNotificationPresentationCoordinator(),
          groupNotificationReadAcknowledgementResolver:
              ({
                required groupId,
                required contentKind,
                required eventIdentity,
                required comparand,
              }) async {
                readCheckCount += 1;
                expect(groupId, 'group-read-replay');
                expect(
                  contentKind,
                  ConversationNotificationContentKind.message,
                );
                expect(eventIdentity, 'message-read-replay');
                expect(comparand, isNull);
                return true;
              },
        );

        expect(shown, isFalse);
        expect(readCheckCount, 1);
        expect(notificationService.shown, isEmpty);
      },
    );

    test(
      'canonical reaction acknowledgement after drain suppresses before maybeShow',
      () async {
        final notificationService = FakeNotificationService();
        const reactionComparand = BackgroundGroupReactionNotificationComparand(
          groupId: 'group-reaction-read-replay',
          reactionId: 'reaction-state-read-replay',
          messageId: 'target-read-replay',
          senderPeerId: 'peer-reactor',
          timestamp: '2026-08-03T10:00:00.000Z',
          notificationEventIdentity: 'bounded-read-replay',
        );

        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_reaction',
              'action': 'add',
              'group_id': 'group-reaction-read-replay',
              'event_id': 'reaction-event-read-replay',
              'target_message_id': 'target-read-replay',
              'reactor_peer_id': 'peer-reactor',
            },
          ),
          groupReactionNotificationResolver: (_) async =>
              const BackgroundPushNotificationFallback(
                title: 'Project group',
                body: 'Alice reacted to your message',
                payload:
                    'group:group-reaction-read-replay|message:target-read-replay',
                groupComparand: reactionComparand,
              ),
          durableReactionNotificationCoordinatorResolver: () async =>
              groupMessageCoordinator,
          groupConversationTracker: groupConversationTracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          groupNotificationPresentationCoordinator:
              GroupNotificationPresentationCoordinator(),
          groupNotificationReadAcknowledgementResolver:
              ({
                required groupId,
                required contentKind,
                required eventIdentity,
                required comparand,
              }) async {
                expect(groupId, 'group-reaction-read-replay');
                expect(
                  contentKind,
                  ConversationNotificationContentKind.reaction,
                );
                expect(
                  eventIdentity,
                  boundedReactionEventIdentity('reaction-event-read-replay'),
                );
                expect(comparand, same(reactionComparand));
                return true;
              },
        );

        expect(shown, isFalse);
        expect(notificationService.shown, isEmpty);
      },
    );

    test('exact canonical read comparands preserve distinct newer content', () {
      expect(
        isExactForegroundGroupMessageReadAcknowledgement(
          groupId: 'group-a',
          eventIdentity: 'message-a',
          canonicalGroupId: 'group-a',
          canonicalMessageId: 'message-a',
          canonicalIsIncoming: true,
          canonicalReadAt: DateTime.utc(2026, 8, 3, 10),
        ),
        isTrue,
      );
      expect(
        isExactForegroundGroupMessageReadAcknowledgement(
          groupId: 'group-a',
          eventIdentity: 'message-new',
          canonicalGroupId: 'group-a',
          canonicalMessageId: 'message-a',
          canonicalIsIncoming: true,
          canonicalReadAt: DateTime.utc(2026, 8, 3, 10),
        ),
        isFalse,
      );

      const acknowledged = BackgroundGroupReactionNotificationComparand(
        groupId: 'group-a',
        reactionId: 'reaction-old',
        messageId: 'target-a',
        senderPeerId: 'peer-alice',
        timestamp: '2026-08-03T10:00:00.000Z',
        notificationEventIdentity: 'bounded-old',
      );
      expect(
        isExactForegroundGroupReactionReadAcknowledgement(
          comparand: acknowledged,
          canonicalReactionId: 'reaction-old',
          canonicalMessageId: 'target-a',
          canonicalSenderPeerId: 'peer-alice',
          canonicalTimestamp: '2026-08-03T10:00:00Z',
          canonicalNotificationAcknowledgedAt: '2026-08-03T10:00:01.000Z',
        ),
        isTrue,
      );
      const newer = BackgroundGroupReactionNotificationComparand(
        groupId: 'group-a',
        reactionId: 'reaction-new',
        messageId: 'target-a',
        senderPeerId: 'peer-alice',
        timestamp: '2026-08-03T10:00:02.000Z',
        notificationEventIdentity: 'bounded-new',
      );
      expect(
        isExactForegroundGroupReactionReadAcknowledgement(
          comparand: newer,
          canonicalReactionId: 'reaction-old',
          canonicalMessageId: 'target-a',
          canonicalSenderPeerId: 'peer-alice',
          canonicalTimestamp: '2026-08-03T10:00:00.000Z',
          canonicalNotificationAcknowledgedAt: '2026-08-03T10:00:01.000Z',
        ),
        isFalse,
        reason: 'an acknowledged old transition cannot suppress the next ADD',
      );
    });

    test(
      'pending push-before-inbox acknowledgement wins before canonical lookup',
      () async {
        var canonicalChecks = 0;
        final acknowledged =
            await resolveForegroundGroupNotificationReadAcknowledgement(
              groupId: 'group-pending-read',
              contentKind: ConversationNotificationContentKind.message,
              eventIdentity: 'message-before-inbox',
              pendingReadAcknowledgementResolver:
                  ({
                    required groupId,
                    required contentKind,
                    required eventIdentity,
                  }) async {
                    expect(groupId, 'group-pending-read');
                    expect(
                      contentKind,
                      ConversationNotificationContentKind.message,
                    );
                    expect(eventIdentity, 'message-before-inbox');
                    return true;
                  },
              canonicalReadAcknowledgementResolver: () async {
                canonicalChecks += 1;
                return false;
              },
            );

        expect(acknowledged, isTrue);
        expect(canonicalChecks, 0);

        expect(
          await resolveForegroundGroupNotificationReadAcknowledgement(
            groupId: 'group-pending-read',
            contentKind: ConversationNotificationContentKind.reaction,
            eventIdentity: 'different-reaction',
            pendingReadAcknowledgementResolver:
                ({
                  required groupId,
                  required contentKind,
                  required eventIdentity,
                }) async => false,
            canonicalReadAcknowledgementResolver: () async {
              canonicalChecks += 1;
              return true;
            },
          ),
          isTrue,
          reason: 'a distinct pending tuple cannot suppress canonical lookup',
        );
        expect(canonicalChecks, 1);
      },
    );

    test('legacy payloadType group reaction remains reaction-owned', () async {
      final notificationService = FakeNotificationService();
      const message = RemoteMessage(
        data: <String, dynamic>{
          'payloadType': 'group_reaction',
          'action': 'add',
          'group_id': 'group-legacy-reaction',
          'event_id': 'legacy-reaction-event',
          'target_message_id': 'legacy-target-message',
          'reactor_peer_id': 'peer-reactor',
        },
      );

      final shown = await showForegroundPushFallbackNotificationIfNeeded(
        result: ForegroundRemoteMessageResult.notificationNeeded,
        notificationService: notificationService,
        message: message,
        groupReactionNotificationResolver: (_) async =>
            const BackgroundPushNotificationFallback(
              title: 'Legacy group',
              body: 'Alice reacted to your message',
              payload:
                  'group:group-legacy-reaction|message:legacy-target-message',
            ),
        durableReactionNotificationCoordinatorResolver: () async =>
            groupMessageCoordinator,
        groupConversationTracker: groupConversationTracker,
        getAppLifecycleState: () => AppLifecycleState.paused,
      );

      expect(shown, isTrue);
      expect(notificationService.shown, hasLength(1));
      expect(
        notificationService.shown.single.contentKind,
        ConversationNotificationContentKind.reaction,
      );
    });

    test(
      'canonical group drain fallback deduplicates exact ids and suppresses active conversations',
      () async {
        final notificationService = FakeNotificationService();
        Future<bool> show(String messageId) {
          return showForegroundPushFallbackNotificationIfNeeded(
            result: ForegroundRemoteMessageResult.notificationNeeded,
            notificationService: notificationService,
            message: RemoteMessage(
              data: <String, dynamic>{
                'type': 'group_message',
                'groupId': 'group-drain',
                'message_id': messageId,
              },
            ),
            groupMessageDisplayEligibilityResolver: (_) async =>
                const GroupMessageNotificationDisplayEligibility.allowCurrentMember(),
            groupConversationTracker: groupConversationTracker,
            getAppLifecycleState: () => AppLifecycleState.resumed,
            durableGroupMessageNotificationCoordinatorResolver: () async =>
                groupMessageCoordinator,
          );
        }

        expect(await show('message-exact'), isTrue);
        expect(await show('message-exact'), isTrue);
        expect(notificationService.shown, hasLength(1));

        groupConversationTracker.setActive('group:group-drain');
        expect(await show('message-while-viewing'), isTrue);
        expect(notificationService.shown, hasLength(1));
      },
    );

    test('canonical group drain fallback shares durable tone debounce', () async {
      final notificationService = FakeNotificationService();
      for (final messageId in const <String>['message-a', 'message-b']) {
        await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-tone',
              'message_id': messageId,
            },
          ),
          groupMessageDisplayEligibilityResolver: (_) async =>
              const GroupMessageNotificationDisplayEligibility.allowCurrentMember(),
          groupConversationTracker: groupConversationTracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          durableGroupMessageNotificationCoordinatorResolver: () async =>
              groupMessageCoordinator,
        );
      }

      expect(notificationService.shown, hasLength(2));
      expect(
        notificationService.shown.map((notification) => notification.silent),
        <bool>[false, true],
      );
    });

    test(
      'unanchored group drain fallback is generic, bare-route, and always silent',
      () async {
        final notificationService = FakeNotificationService();
        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-unanchored',
              'title': 'ATTACKER TITLE',
              'body': 'ATTACKER BODY',
            },
          ),
          groupMessageDisplayEligibilityResolver: (_) async =>
              const GroupMessageNotificationDisplayEligibility.allowCurrentMember(),
          groupConversationTracker: groupConversationTracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          durableGroupMessageNotificationCoordinatorResolver: () async =>
              groupMessageCoordinator,
        );

        expect(shown, isTrue);
        expect(notificationService.shown, hasLength(1));
        final notification = notificationService.shown.single;
        expect(notification.senderUsername, 'Mknoon');
        expect(notification.messageText, 'Message');
        expect(notification.payload, 'group:group-unanchored');
        expect(notification.silent, isTrue);
        expect(
          '${notification.senderUsername}|${notification.messageText}',
          isNot(contains('ATTACKER')),
        );
      },
    );

    test('group drain show error releases the exact claim for retry', () async {
      final notificationService = _FailOnceNotificationService();
      const message = RemoteMessage(
        data: <String, dynamic>{
          'type': 'group_message',
          'groupId': 'group-retry',
          'message_id': 'message-retry',
        },
      );

      Future<bool> show() => showForegroundPushFallbackNotificationIfNeeded(
        result: ForegroundRemoteMessageResult.notificationNeeded,
        notificationService: notificationService,
        message: message,
        groupMessageDisplayEligibilityResolver: (_) async =>
            const GroupMessageNotificationDisplayEligibility.allowCurrentMember(),
        groupConversationTracker: groupConversationTracker,
        getAppLifecycleState: () => AppLifecycleState.resumed,
        durableGroupMessageNotificationCoordinatorResolver: () async =>
            groupMessageCoordinator,
      );

      await expectLater(show(), throwsA(isA<StateError>()));
      expect(await show(), isTrue);
      expect(notificationService.shown, hasLength(1));
      expect(await show(), isTrue);
      expect(notificationService.shown, hasLength(1));
    });

    for (final anchored in <bool>[true, false]) {
      final path = anchored ? 'anchored' : 'unanchored';

      test(
        'read cancellation first holds $path foreground group message presentation',
        () async {
          final groupId = 'group-race-message-$path-read-first';
          final presentationCoordinator =
              GroupNotificationPresentationCoordinator();
          final notificationService = _BlockingNotificationService();
          final readEntered = Completer<void>();
          final releaseRead = Completer<void>();
          final read = presentationCoordinator.runForGroup(groupId, () async {
            readEntered.complete();
            await releaseRead.future;
          });
          await readEntered.future;

          final show = showForegroundPushFallbackNotificationIfNeeded(
            result: ForegroundRemoteMessageResult.notificationNeeded,
            notificationService: notificationService,
            message: RemoteMessage(
              data: <String, dynamic>{
                'type': 'group_message',
                'groupId': groupId,
                if (anchored) 'message_id': 'message-after-read',
              },
            ),
            groupMessageDisplayEligibilityResolver: (_) async =>
                const GroupMessageNotificationDisplayEligibility.allowCurrentMember(),
            groupConversationTracker: groupConversationTracker,
            getAppLifecycleState: () => AppLifecycleState.resumed,
            durableGroupMessageNotificationCoordinatorResolver: () async =>
                groupMessageCoordinator,
            groupNotificationPresentationCoordinator: presentationCoordinator,
          );
          final showOvertookRead = await Future.any<bool>(<Future<bool>>[
            notificationService.showEntered.future.then((_) => true),
            Future<void>.delayed(
              const Duration(milliseconds: 50),
            ).then((_) => false),
          ]);

          try {
            expect(
              showOvertookRead,
              isFalse,
              reason: '$path presentation must wait for read cancellation',
            );
          } finally {
            releaseRead.complete();
            await notificationService.showEntered.future;
            notificationService.releaseShow.complete();
            await Future.wait<void>(<Future<void>>[read, show.then((_) {})]);
          }

          expect(notificationService.shown, hasLength(1));
          expect(presentationCoordinator.debugActiveKeyCount, 0);
        },
      );

      test(
        '$path foreground group message presentation holds later read cancellation',
        () async {
          final groupId = 'group-race-message-$path-show-first';
          final presentationCoordinator =
              GroupNotificationPresentationCoordinator();
          final notificationService = _BlockingNotificationService();
          final show = showForegroundPushFallbackNotificationIfNeeded(
            result: ForegroundRemoteMessageResult.notificationNeeded,
            notificationService: notificationService,
            message: RemoteMessage(
              data: <String, dynamic>{
                'type': 'group_message',
                'groupId': groupId,
                if (anchored) 'message_id': 'message-before-read',
              },
            ),
            groupMessageDisplayEligibilityResolver: (_) async =>
                const GroupMessageNotificationDisplayEligibility.allowCurrentMember(),
            groupConversationTracker: groupConversationTracker,
            getAppLifecycleState: () => AppLifecycleState.resumed,
            durableGroupMessageNotificationCoordinatorResolver: () async =>
                groupMessageCoordinator,
            groupNotificationPresentationCoordinator: presentationCoordinator,
          );
          await notificationService.showEntered.future;

          final readEntered = Completer<void>();
          final read = presentationCoordinator.runForGroup(groupId, () async {
            readEntered.complete();
          });
          final readOvertookShow = await Future.any<bool>(<Future<bool>>[
            readEntered.future.then((_) => true),
            Future<void>.delayed(
              const Duration(milliseconds: 50),
            ).then((_) => false),
          ]);

          try {
            expect(
              readOvertookShow,
              isFalse,
              reason: 'read cancellation must wait for $path presentation',
            );
          } finally {
            notificationService.releaseShow.complete();
            await show;
            await read;
          }

          expect(readEntered.isCompleted, isTrue);
          expect(notificationService.shown, hasLength(1));
          expect(presentationCoordinator.debugActiveKeyCount, 0);
        },
      );
    }

    test(
      'group policy is resolved inside the keyed foreground presentation lane',
      () async {
        const groupId = 'group-policy-lane-final-check';
        final presentationCoordinator =
            GroupNotificationPresentationCoordinator();
        final notificationService = FakeNotificationService();
        final holdEntered = Completer<void>();
        final releaseHold = Completer<void>();
        final held = presentationCoordinator.runForGroup(groupId, () async {
          holdEntered.complete();
          await releaseHold.future;
        });
        await holdEntered.future;

        var policyChecks = 0;
        var stillEligible = true;
        final show = showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': groupId,
              'message_id': 'message-policy-lane',
            },
          ),
          groupMessageDisplayEligibilityResolver: (_) async {
            policyChecks += 1;
            return stillEligible
                ? const GroupMessageNotificationDisplayEligibility.allowCurrentMember()
                : const GroupMessageNotificationDisplayEligibility.suppressed(
                    'group_muted',
                  );
          },
          groupConversationTracker: groupConversationTracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          durableGroupMessageNotificationCoordinatorResolver: () async =>
              groupMessageCoordinator,
          groupNotificationPresentationCoordinator: presentationCoordinator,
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          policyChecks,
          0,
          reason: 'policy cannot be snapshotted before an earlier publisher',
        );
        stillEligible = false;
        releaseHold.complete();
        await held;

        expect(await show, isFalse);
        expect(policyChecks, 1);
        expect(notificationService.shown, isEmpty);
      },
    );

    test(
      'reaction canonical resolver runs inside the keyed presentation lane',
      () async {
        const groupId = 'group-reaction-lane-final-check';
        final presentationCoordinator =
            GroupNotificationPresentationCoordinator();
        final notificationService = FakeNotificationService();
        final holdEntered = Completer<void>();
        final releaseHold = Completer<void>();
        final held = presentationCoordinator.runForGroup(groupId, () async {
          holdEntered.complete();
          await releaseHold.future;
        });
        await holdEntered.future;

        var resolverChecks = 0;
        var exactEventStillEligible = true;
        final show = showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_reaction',
              'action': 'add',
              'group_id': groupId,
              'event_id': 'reaction-lane-event-a',
              'target_message_id': 'reaction-lane-target',
              'reactor_peer_id': 'peer-reactor',
            },
          ),
          groupReactionNotificationResolver: (_) async {
            resolverChecks += 1;
            if (!exactEventStillEligible) return null;
            return const BackgroundPushNotificationFallback(
              title: 'Project group',
              body: 'Alice reacted to your message',
              payload:
                  'group:group-reaction-lane-final-check|message:reaction-lane-target',
            );
          },
          durableReactionNotificationCoordinatorResolver: () async =>
              groupMessageCoordinator,
          groupConversationTracker: groupConversationTracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          groupNotificationPresentationCoordinator: presentationCoordinator,
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          resolverChecks,
          0,
          reason:
              'a reaction comparand cannot be cached before an earlier publisher',
        );
        exactEventStillEligible = false;
        releaseHold.complete();
        await held;

        expect(await show, isFalse);
        expect(resolverChecks, 1);
        expect(notificationService.shown, isEmpty);
      },
    );

    test(
      'anchored foreground group reaction presentation holds later read cancellation',
      () async {
        final presentationCoordinator =
            GroupNotificationPresentationCoordinator();
        final notificationService = _BlockingNotificationService();

        final show = showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_reaction',
              'action': 'add',
              'group_id': 'group-race-reaction',
              'event_id': 'reaction-race-event',
              'target_message_id': 'reaction-race-target',
              'reactor_peer_id': 'peer-reactor',
            },
          ),
          groupReactionNotificationResolver: (_) async =>
              const BackgroundPushNotificationFallback(
                title: 'Project group',
                body: 'Alice reacted to your photo',
                payload:
                    'group:group-race-reaction|message:reaction-race-target',
              ),
          durableReactionNotificationCoordinatorResolver: () async =>
              groupMessageCoordinator,
          groupConversationTracker: groupConversationTracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          groupNotificationPresentationCoordinator: presentationCoordinator,
        );
        await notificationService.showEntered.future;

        var readCancellationRan = false;
        final read = presentationCoordinator.runForGroup(
          'group-race-reaction',
          () async => readCancellationRan = true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(readCancellationRan, isFalse);

        notificationService.releaseShow.complete();
        await show;
        await read;
        expect(readCancellationRan, isTrue);
        expect(notificationService.shown, hasLength(1));
        expect(presentationCoordinator.debugActiveKeyCount, 0);
      },
    );

    test(
      'foreground fallback shows current-member group_message with visible FCM payload',
      () async {
        final notificationService = FakeNotificationService();
        const message = RemoteMessage(
          notification: RemoteNotification(
            title: 'Team Chat',
            body: 'Alice: Hello',
          ),
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'message_id': 'msg-123',
            'title': 'Team Chat',
            'body': 'Alice: Hello',
          },
        );

        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: message,
          groupMessageDisplayEligibilityResolver: (groupId) async {
            expect(groupId, 'group-abc-123');
            return const GroupMessageNotificationDisplayEligibility.allowCurrentMember();
          },
          groupConversationTracker: groupConversationTracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          durableGroupMessageNotificationCoordinatorResolver: () async =>
              groupMessageCoordinator,
        );

        expect(shown, isTrue);
        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.single.senderUsername, 'Mknoon');
        expect(notificationService.shown.single.messageText, 'Message');
        expect(
          notificationService.shown.single.payload,
          'group:group-abc-123|message:msg-123',
        );
      },
    );

    test(
      'foreground fallback suppresses non-current group_message with visible FCM payload',
      () async {
        final notificationService = FakeNotificationService();
        const message = RemoteMessage(
          notification: RemoteNotification(
            title: 'Team Chat',
            body: 'Alice: Hello',
          ),
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'message_id': 'msg-123',
            'title': 'Team Chat',
            'body': 'Alice: Hello',
          },
        );

        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: message,
          groupMessageDisplayEligibilityResolver: (groupId) async {
            expect(groupId, 'group-abc-123');
            return const GroupMessageNotificationDisplayEligibility.suppressed(
              'local_member_missing',
            );
          },
          groupConversationTracker: groupConversationTracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          durableGroupMessageNotificationCoordinatorResolver: () async =>
              groupMessageCoordinator,
        );

        expect(shown, isFalse);
        expect(notificationService.shownGeneric, isEmpty);
      },
    );

    test('foreground fallback helper is a no-op when not requested', () async {
      final notificationService = FakeNotificationService();
      const message = RemoteMessage(
        data: {'type': 'group_message', 'groupId': 'group-abc-123'},
      );

      final shown = await showForegroundPushFallbackNotificationIfNeeded(
        result: ForegroundRemoteMessageResult.drained,
        notificationService: notificationService,
        message: message,
      );

      expect(shown, isFalse);
      expect(notificationService.shownGeneric, isEmpty);
    });

    test(
      'display eligibility suppresses ordinary group_message fallback without current membership',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'message_id': 'msg-123',
          },
        );

        final result = await resolveBackgroundPushFallbackDisplayEligibility(
          message,
          groupMessageDisplayEligibilityResolver: (groupId) async {
            expect(groupId, 'group-abc-123');
            return const GroupMessageNotificationDisplayEligibility.suppressed(
              'group_missing',
            );
          },
        );

        expect(result.shouldDisplay, isFalse);
        expect(result.reason, 'group_missing');
      },
    );

    test(
      'display eligibility preserves ordinary group_message fallback for current members',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'message_id': 'msg-123',
          },
        );

        final result = await resolveBackgroundPushFallbackDisplayEligibility(
          message,
          groupMessageDisplayEligibilityResolver: (groupId) async {
            expect(groupId, 'group-abc-123');
            return const GroupMessageNotificationDisplayEligibility.allowCurrentMember();
          },
        );

        expect(result.shouldDisplay, isTrue);
        expect(result.reason, 'display_allowed');
      },
    );

    test(
      'display eligibility suppresses payload-only group route without current membership',
      () async {
        const message = RemoteMessage(
          data: {'payload': 'group:group-abc-123|message:msg-legacy'},
        );

        final result = await resolveBackgroundPushFallbackDisplayEligibility(
          message,
          groupMessageDisplayEligibilityResolver: (groupId) async {
            expect(groupId, 'group-abc-123');
            return const GroupMessageNotificationDisplayEligibility.suppressed(
              'local_member_missing',
            );
          },
        );

        expect(result.shouldDisplay, isFalse);
        expect(result.reason, 'local_member_missing');
      },
    );

    test(
      'foreground fallback preserves payload-only group route for current members',
      () async {
        final notificationService = FakeNotificationService();
        const message = RemoteMessage(
          data: {'payload': 'group:group-abc-123|message:msg-legacy'},
        );

        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: message,
          groupMessageDisplayEligibilityResolver: (groupId) async {
            expect(groupId, 'group-abc-123');
            return const GroupMessageNotificationDisplayEligibility.allowCurrentMember();
          },
          groupConversationTracker: groupConversationTracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          durableGroupMessageNotificationCoordinatorResolver: () async =>
              groupMessageCoordinator,
        );

        expect(shown, isTrue);
        expect(notificationService.shown, hasLength(1));
        expect(
          notificationService.shown.single.payload,
          'group:group-abc-123|message:msg-legacy',
        );
      },
    );

    test(
      'display eligibility leaves group_invite fallback on the intros route',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_invite',
            'groupId': 'group-abc-123',
            'title': 'Book Club',
          },
        );

        final result = await resolveBackgroundPushFallbackDisplayEligibility(
          message,
        );

        expect(result.shouldDisplay, isTrue);
        expect(
          buildBackgroundPushFallbackNotification(message).payload,
          'intros',
        );
      },
    );

    test(
      'foreground fallback helper suppresses group_message when display eligibility denies it',
      () async {
        final notificationService = FakeNotificationService();
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'message_id': 'msg-123',
          },
        );

        final shown = await showForegroundPushFallbackNotificationIfNeeded(
          result: ForegroundRemoteMessageResult.notificationNeeded,
          notificationService: notificationService,
          message: message,
          groupMessageDisplayEligibilityResolver: (_) async =>
              const GroupMessageNotificationDisplayEligibility.suppressed(
                'local_member_missing',
              ),
          groupConversationTracker: groupConversationTracker,
          getAppLifecycleState: () => AppLifecycleState.resumed,
          durableGroupMessageNotificationCoordinatorResolver: () async =>
              groupMessageCoordinator,
        );

        expect(shown, isFalse);
        expect(notificationService.shownGeneric, isEmpty);
      },
    );

    test(
      'shows group fallback on iOS when Flutter sees only the data payload',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'title': 'Team Chat',
            'body': 'Alice: Hello',
          },
        );

        expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);
        final fallback = buildBackgroundPushFallbackNotification(message);
        expect(fallback.title, backgroundPushDefaultTitle);
        expect(fallback.body, backgroundPushDefaultBody);
      },
    );

    test(
      'skips group fallback on iOS when RemoteMessage already has a visible notification payload',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        const message = RemoteMessage(
          notification: RemoteNotification(
            title: 'Team Chat',
            body: 'Alice: Hello',
          ),
          data: {
            'type': 'group_message',
            'groupId': 'group-abc-123',
            'title': 'Team Chat',
            'body': 'Alice: Hello',
          },
        );

        expect(shouldShowBackgroundPushFallbackNotification(message), isFalse);
      },
    );

    test('skips fallback for group_message type without groupId', () {
      const message = RemoteMessage(data: {'type': 'group_message'});

      expect(shouldShowBackgroundPushFallbackNotification(message), isFalse);
    });

    test(
      'intros fallback without provider copy uses meaningful introduction update copy',
      () {
        const message = RemoteMessage(data: {'type': 'intros'});

        expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

        final fallback = buildBackgroundPushFallbackNotification(message);
        expect(fallback.title, 'Introduction update');
        expect(fallback.body, 'Open Mknoon to see the latest update.');
        expect(fallback.title, isNot(backgroundPushDefaultTitle));
        expect(fallback.body, isNot(backgroundPushDefaultBody));
        expect(fallback.payload, 'intros');
      },
    );

    test('preserves provided copy for a new-introduction intros fallback', () {
      const message = RemoteMessage(
        data: {
          'type': 'intros',
          'title': 'New Introduction',
          'body': 'Noor introduced Sarah to you',
        },
      );

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'New Introduction');
      expect(fallback.body, 'Noor introduced Sarah to you');
      expect(fallback.payload, 'intros');
    });

    test(
      'preserves provided role-correct copy for an introducer mutual-accept intros fallback',
      () {
        const message = RemoteMessage(
          data: {
            'type': 'intros',
            'title': 'New Connection',
            'body':
                'Sarah accepted your intro to Lina. Lina and Sarah are now connected',
          },
        );

        final fallback = buildBackgroundPushFallbackNotification(message);
        expect(fallback.title, 'New Connection');
        expect(
          fallback.body,
          'Sarah accepted your intro to Lina. Lina and Sarah are now connected',
        );
        expect(fallback.payload, 'intros');
      },
    );

    test('shows fallback for contact_request type', () {
      const message = RemoteMessage(
        data: {
          'type': 'contact_request',
          'sender_id': '12D3KooWRequestPeer',
          'title': 'New Contact Request',
          'body': 'Alice wants to connect',
        },
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'New Contact Request');
      expect(fallback.body, 'Alice wants to connect');
      expect(fallback.payload, 'contact_request:12D3KooWRequestPeer');
    });

    test('shows fallback for group_invite type and routes to intros', () {
      const message = RemoteMessage(
        data: {
          'type': 'group_invite',
          'groupId': 'group-abc-123',
          'title': 'Book Club',
          'body': 'Alice invited you to Book Club',
        },
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'Book Club');
      expect(fallback.body, 'Alice invited you to Book Club');
      expect(fallback.payload, 'intros');
    });

    test('shows fallback for unknown type with payload data key', () {
      const message = RemoteMessage(
        data: {'type': 'custom', 'payload': 'some-payload-data'},
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.payload, 'some-payload-data');
    });

    test('skips fallback for unknown type without payload data key', () {
      const message = RemoteMessage(data: {'type': 'unknown_type'});

      expect(shouldShowBackgroundPushFallbackNotification(message), isFalse);
    });

    test(
      'route key alone does not trigger fallback (only payload key does)',
      () {
        const message = RemoteMessage(
          data: {'type': 'custom', 'route': '/some/route'},
        );

        expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

        final fallback = buildBackgroundPushFallbackNotification(message);
        expect(fallback.payload, '/some/route');
      },
    );

    test('uses route as payload fallback when payload key is present', () {
      const message = RemoteMessage(
        data: {'type': 'custom', 'payload': 'trigger'},
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.payload, 'trigger');
    });

    test('builds a stable dedupe key from payload and message identity', () {
      final message = RemoteMessage(
        messageId: 'fcm-msg-123',
        sentTime: DateTime.utc(2026, 4, 4, 12),
        data: {'type': 'new_message', 'sender_id': '12D3KooWPeer'},
      );

      expect(
        backgroundPushFallbackDedupeKey(message),
        'payload=12D3KooWPeer|id=fcm-msg-123|ts=1775304000000',
      );
    });

    test(
      'GIRD-006 uses canonical group payload and message identity for fallback dedupe',
      () {
        const message = RemoteMessage(
          messageId: 'fcm-gird006-group-transport',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-group-image',
            'title': 'Team Chat',
            'body': 'Alice: Photo',
          },
        );

        final fallback = buildBackgroundPushFallbackNotification(message);

        expect(
          fallback.payload,
          'group:group-gird006|message:msg-gird006-group-image',
        );
        expect(fallback.title, backgroundPushDefaultTitle);
        expect(fallback.body, backgroundPushDefaultBody);
        expect(
          backgroundPushFallbackDedupeKey(message),
          'payload=group:group-gird006|message:msg-gird006-group-image|id=msg-gird006-group-image',
        );
      },
    );

    test('shows fallback for post_create with post payload routing', () {
      const message = RemoteMessage(
        data: {
          'type': 'post_create',
          'post_id': 'post-123',
          'title': 'Alice posted',
          'body': 'Hello posts',
        },
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'Alice posted');
      expect(fallback.body, 'Hello posts');
      expect(fallback.payload, 'post:post-123');
    });

    test('shows fallback for post_comment with comment payload routing', () {
      const message = RemoteMessage(
        data: {
          'type': 'post_comment',
          'post_id': 'post-123',
          'comment_id': 'comment-7',
          'title': 'Bob commented',
          'body': 'I can lend one.',
        },
      );

      expect(shouldShowBackgroundPushFallbackNotification(message), isTrue);

      final fallback = buildBackgroundPushFallbackNotification(message);
      expect(fallback.title, 'Bob commented');
      expect(fallback.body, 'I can lend one.');
      expect(fallback.payload, 'post_comment:post-123:comment-7');
    });

    test('treats whitespace-only values as absent', () {
      const message = RemoteMessage(data: {'type': '  ', 'payload': '   '});

      // type trims to null → falls through to payload check,
      // payload trims to null → should not show
      expect(shouldShowBackgroundPushFallbackNotification(message), isFalse);
    });
  });
}

class _FailOnceNotificationService extends FakeNotificationService {
  var _shouldFail = true;

  @override
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    ConversationNotificationContentKind? contentKind,
    String? contentEventIdentity,
  }) async {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('synthetic group fallback display failure');
    }
    await super.showMessageNotification(
      contactPeerId: contactPeerId,
      senderUsername: senderUsername,
      messageText: messageText,
      payload: payload,
      silent: silent,
      contentKind: contentKind,
      contentEventIdentity: contentEventIdentity,
    );
  }
}

class _BlockingNotificationService extends FakeNotificationService {
  final showEntered = Completer<void>();
  final releaseShow = Completer<void>();

  @override
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    ConversationNotificationContentKind? contentKind,
    String? contentEventIdentity,
  }) async {
    if (!showEntered.isCompleted) showEntered.complete();
    await releaseShow.future;
    await super.showMessageNotification(
      contactPeerId: contactPeerId,
      senderUsername: senderUsername,
      messageText: messageText,
      payload: payload,
      silent: silent,
      contentKind: contentKind,
      contentEventIdentity: contentEventIdentity,
    );
  }
}
