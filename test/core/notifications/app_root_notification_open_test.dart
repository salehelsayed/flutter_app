import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/notification_open_dedupe_gate.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';

void main() {
  group('app-root notification open', () {
    late _AppRootNotificationHarness harness;

    setUp(() {
      harness = _AppRootNotificationHarness();
    });

    test(
      'warm remote push prepares conversation target before route',
      () async {
        await routeAppRootRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-123',
          },
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
          onMissingRouteTarget: harness.missing,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:peer-123',
          'route:peer-123',
        ]);
        expect(
          harness.routed.single.kind,
          NotificationRouteTargetKind.conversation,
        );
        expect(harness.routed.single.peerId, 'peer-123');
        expect(harness.missingCalls, 0);
      },
    );

    test(
      'terminated local notification launch prepares group target before route',
      () async {
        await routeAppRootInitialLocalNotificationOpen(
          consumeInitialPayload: () async => 'group:group-123|message:msg-123',
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:group:group-123|message:msg-123',
          'route:group:group-123|message:msg-123',
        ]);
        expect(harness.routed.single.kind, NotificationRouteTargetKind.group);
        expect(harness.routed.single.groupId, 'group-123');
        expect(harness.routed.single.messageId, 'msg-123');
      },
    );

    test(
      'warm local notification tap prepares conversation target before route',
      () async {
        await routeAppRootLocalNotificationTap(
          payload: 'peer-456',
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:peer-456',
          'route:peer-456',
        ]);
        expect(
          harness.routed.single.kind,
          NotificationRouteTargetKind.conversation,
        );
        expect(harness.routed.single.peerId, 'peer-456');
      },
    );

    test(
      'warm local contact-request tap prepares contact-request target before route',
      () async {
        await routeAppRootLocalNotificationTap(
          payload: 'contact_request:peer-request-123',
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:contact_request:peer-request-123',
          'route:contact_request:peer-request-123',
        ]);
        expect(
          harness.routed.single.kind,
          NotificationRouteTargetKind.contactRequest,
        );
        expect(harness.routed.single.peerId, 'peer-request-123');
      },
    );

    test(
      'warm remote contact-request push prepares contact-request target before route',
      () async {
        await routeAppRootRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'contact_request',
            'sender_id': 'peer-request-123',
          },
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
          onMissingRouteTarget: harness.missing,
        );

        expect(harness.events, <String>[
          'clear',
          'prepare:contact_request:peer-request-123',
          'route:contact_request:peer-request-123',
        ]);
        expect(
          harness.routed.single.kind,
          NotificationRouteTargetKind.contactRequest,
        );
        expect(harness.routed.single.peerId, 'peer-request-123');
      },
    );

    test(
      'missing warm remote route target skips prepare and calls missing handler',
      () async {
        await routeAppRootRemoteNotificationOpen(
          data: const <String, dynamic>{'type': 'unknown_type'},
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
          onMissingRouteTarget: harness.missing,
        );

        expect(harness.events, <String>['clear', 'missing']);
        expect(harness.routed, isEmpty);
        expect(harness.missingCalls, 1);
      },
    );

    test(
      'missing group id on warm remote group push emits dedicated hook before missing handler',
      () async {
        await routeAppRootRemoteNotificationOpen(
          data: const <String, dynamic>{
            'kind': 'group_message',
            'message_id': 'msg-missing-group',
          },
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: harness.prepare,
          onRouteTarget: harness.route,
          onMissingGroupRouteId: harness.missingGroupId,
          onMissingRouteTarget: harness.missing,
        );

        expect(harness.events, <String>[
          'clear',
          'missing-group-id',
          'missing',
        ]);
        expect(harness.routed, isEmpty);
        expect(harness.missingCalls, 1);
        expect(harness.missingGroupIdCalls, 1);
      },
    );

    test('route failure can finish the dedupe gate as retryable', () async {
      final gate = NotificationOpenDedupeGate();
      const data = <String, dynamic>{
        'type': 'group_message',
        'groupId': 'group-123',
        'message_id': 'msg-123',
      };

      expect(gate.tryBegin(data), isTrue);
      try {
        await routeAppRootRemoteNotificationOpenWithResult(
          data: data,
          onBeforeOpen: harness.clear,
          onBeforeRouteTarget: (_) async {
            throw StateError('prepare failed');
          },
          onRouteTarget: harness.route,
          onMissingRouteTarget: harness.missing,
        );
        fail('expected preparation failure');
      } catch (_) {
        gate.finish(data, success: false);
      }

      expect(gate.tryBegin(data), isTrue);
    });

    test('active group notification route can be skipped without stacking', () {
      final tracker = ActiveConversationTracker()..setActive('group:group-123');

      expect(
        isNotificationRouteTargetAlreadyActive(
          routeTarget: NotificationRouteTarget.group(
            'group-123',
            messageId: 'msg-123',
          ),
          groupConversationTracker: tracker,
        ),
        isTrue,
      );
      expect(
        isNotificationRouteTargetAlreadyActive(
          routeTarget: NotificationRouteTarget.group(
            'group-456',
            messageId: 'msg-123',
          ),
          groupConversationTracker: tracker,
        ),
        isFalse,
      );
      expect(
        isNotificationRouteTargetAlreadyActive(
          routeTarget: NotificationRouteTarget.conversation('peer-123'),
          groupConversationTracker: tracker,
        ),
        isFalse,
      );
    });

    // ── Report 139: 1:1 conversation already-active guard ────────────────
    // Mirrors the group guard above so a notification tap for a peer whose
    // conversation is already open does not push a second ConversationWired.
    test(
      'active 1:1 conversation route is skipped when its tracker is viewing that peer',
      () {
        final conv = ActiveConversationTracker()..setActive('peer-123');

        expect(
          isNotificationRouteTargetAlreadyActive(
            routeTarget: const NotificationRouteTarget.conversation('peer-123'),
            groupConversationTracker: ActiveConversationTracker(),
            conversationTracker: conv,
          ),
          isTrue,
        );
      },
    );

    test(
      '1:1 conversation route is NOT skipped for a different peer or a null tracker',
      () {
        final conv = ActiveConversationTracker()..setActive('peer-123');

        // Different peer than the one being viewed → still push (non-vacuity:
        // proves the GREEN above is peer-specific, not "always true").
        expect(
          isNotificationRouteTargetAlreadyActive(
            routeTarget: const NotificationRouteTarget.conversation('peer-999'),
            groupConversationTracker: ActiveConversationTracker(),
            conversationTracker: conv,
          ),
          isFalse,
        );

        // Null 1:1 tracker (no conversation open) → push, no crash.
        expect(
          isNotificationRouteTargetAlreadyActive(
            routeTarget: const NotificationRouteTarget.conversation('peer-123'),
            groupConversationTracker: ActiveConversationTracker(),
            conversationTracker: null,
          ),
          isFalse,
        );

        // Backward-compat: the group-only call (no conversationTracker arg,
        // as the group case at main.dart still uses) treats a conversation
        // target as not-active. Keeps every existing caller compiling.
        expect(
          isNotificationRouteTargetAlreadyActive(
            routeTarget: const NotificationRouteTarget.conversation('peer-123'),
            groupConversationTracker: ActiveConversationTracker(),
          ),
          isFalse,
        );
      },
    );

    test(
      'group already-active guard is unchanged when the 1:1 tracker is also supplied',
      () {
        final groupTracker = ActiveConversationTracker()
          ..setActive('group:group-123');
        final conv = ActiveConversationTracker()..setActive('peer-123');

        expect(
          isNotificationRouteTargetAlreadyActive(
            routeTarget: const NotificationRouteTarget.group(
              'group-123',
              messageId: 'm',
            ),
            groupConversationTracker: groupTracker,
            conversationTracker: conv,
          ),
          isTrue,
        );
        expect(
          isNotificationRouteTargetAlreadyActive(
            routeTarget: const NotificationRouteTarget.group('group-456'),
            groupConversationTracker: groupTracker,
            conversationTracker: conv,
          ),
          isFalse,
        );
      },
    );
  });
}

class _AppRootNotificationHarness {
  final List<String> events = <String>[];
  final List<NotificationRouteTarget> routed = <NotificationRouteTarget>[];
  int missingCalls = 0;
  int missingGroupIdCalls = 0;

  Future<void> prepare(NotificationRouteTarget routeTarget) async {
    events.add('prepare:${routeTarget.toPayload()}');
  }

  Future<void> clear() async {
    events.add('clear');
  }

  Future<void> route(NotificationRouteTarget routeTarget) async {
    events.add('route:${routeTarget.toPayload()}');
    routed.add(routeTarget);
  }

  Future<void> missing() async {
    missingCalls += 1;
    events.add('missing');
  }

  Future<void> missingGroupId(Map<String, dynamic> data) async {
    missingGroupIdCalls += 1;
    events.add('missing-group-id');
  }
}
