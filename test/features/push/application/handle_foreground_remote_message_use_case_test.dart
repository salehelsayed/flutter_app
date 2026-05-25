import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';

import 'remote_message_fixtures.dart';

void main() {
  group('handleForegroundRemoteMessage', () {
    test('group_message routes to the targeted group drain', () async {
      var oneToOneCalls = 0;
      final drainedGroups = <String>[];

      final events = await _captureFlowEvents(() async {
        await handleForegroundRemoteMessage(
          data: groupMessageData(),
          messageId: 'fcm-1',
          drainOfflineInbox: () async {
            oneToOneCalls += 1;
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );
      });

      expect(oneToOneCalls, 0);
      expect(drainedGroups, ['group-1']);
      expect(events, hasLength(1));
      expect(events.single.event, 'PUSH_FOREGROUND_MESSAGE_ROUTED');
      expect(events.single.details['kind'], 'group');
      expect(events.single.details['hasGroupId'], isTrue);
      expect(events.single.details['hasMessageId'], isTrue);
    });

    test('new_message routes to the 1:1 drain', () async {
      var oneToOneCalls = 0;
      final drainedGroups = <String>[];

      final events = await _captureFlowEvents(() async {
        await handleForegroundRemoteMessage(
          data: newMessageData(),
          messageId: 'fcm-2',
          drainOfflineInbox: () async {
            oneToOneCalls += 1;
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );
      });

      expect(oneToOneCalls, 1);
      expect(drainedGroups, isEmpty);
      expect(events, hasLength(1));
      expect(events.single.event, 'PUSH_FOREGROUND_MESSAGE_ROUTED');
      expect(events.single.details['kind'], 'conversation');
    });

    test(
      'contact request, intros, and group invite stay on the 1:1 path',
      () async {
        var oneToOneCalls = 0;
        final drainedGroups = <String>[];

        final events = await _captureFlowEvents(() async {
          await handleForegroundRemoteMessage(
            data: contactRequestData(),
            messageId: 'fcm-3',
            drainOfflineInbox: () async {
              oneToOneCalls += 1;
            },
            drainGroupOfflineInboxForGroup: (groupId) async {
              drainedGroups.add(groupId);
            },
          );
          await handleForegroundRemoteMessage(
            data: introsData(),
            messageId: 'fcm-4',
            drainOfflineInbox: () async {
              oneToOneCalls += 1;
            },
            drainGroupOfflineInboxForGroup: (groupId) async {
              drainedGroups.add(groupId);
            },
          );
          await handleForegroundRemoteMessage(
            data: groupInviteData(),
            messageId: 'fcm-5',
            drainOfflineInbox: () async {
              oneToOneCalls += 1;
            },
            drainGroupOfflineInboxForGroup: (groupId) async {
              drainedGroups.add(groupId);
            },
          );
        });

        expect(oneToOneCalls, 3);
        expect(drainedGroups, isEmpty);
        expect(
          events.map((event) => event.event),
          everyElement('PUSH_FOREGROUND_MESSAGE_ROUTED'),
        );
        expect(events.map((event) => event.details['kind']), [
          'contactRequest',
          'intros',
          'intros',
        ]);
      },
    );

    test('post and unknown kinds are unroutable', () async {
      var oneToOneCalls = 0;
      final drainedGroups = <String>[];

      final events = await _captureFlowEvents(() async {
        await handleForegroundRemoteMessage(
          data: postCreateData(),
          messageId: 'fcm-6',
          drainOfflineInbox: () async {
            oneToOneCalls += 1;
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );
        await handleForegroundRemoteMessage(
          data: {'type': 'weird'},
          messageId: 'fcm-7',
          drainOfflineInbox: () async {
            oneToOneCalls += 1;
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );
      });

      expect(oneToOneCalls, 0);
      expect(drainedGroups, isEmpty);
      expect(events.map((event) => event.event), [
        'PUSH_FOREGROUND_MESSAGE_UNROUTABLE',
        'PUSH_FOREGROUND_MESSAGE_UNROUTABLE',
      ]);
      expect(events.first.details['type'], 'post_create');
      expect(events.last.details['type'], 'weird');
    });

    test('empty groupId on group_message is unroutable', () async {
      var oneToOneCalls = 0;
      final drainedGroups = <String>[];
      late ForegroundRemoteMessageResult result;

      final events = await _captureFlowEvents(() async {
        result = await handleForegroundRemoteMessage(
          data: groupMessageData(groupId: '', messageId: 'msg-empty'),
          messageId: 'fcm-8',
          drainOfflineInbox: () async {
            oneToOneCalls += 1;
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );
      });

      expect(oneToOneCalls, 0);
      expect(drainedGroups, isEmpty);
      expect(result, ForegroundRemoteMessageResult.unroutable);
      expect(events, hasLength(1));
      expect(events.single.event, 'PUSH_GROUP_ROUTE_MISSING_GROUP_ID');
      expect(events.single.details['type'], 'group_message');
    });

    test(
      'missing group id on group-message-like payload emits dedicated event',
      () async {
        var oneToOneCalls = 0;
        final drainedGroups = <String>[];
        late ForegroundRemoteMessageResult result;

        final events = await _captureFlowEvents(() async {
          result = await handleForegroundRemoteMessage(
            data: const {
              'payloadType': 'group_message',
              'message_id': 'msg-missing-group',
            },
            messageId: 'fcm-missing-group',
            drainOfflineInbox: () async {
              oneToOneCalls += 1;
            },
            drainGroupOfflineInboxForGroup: (groupId) async {
              drainedGroups.add(groupId);
            },
          );
        });

        expect(oneToOneCalls, 0);
        expect(drainedGroups, isEmpty);
        expect(result, ForegroundRemoteMessageResult.unroutable);
        expect(events, hasLength(1));
        expect(events.single.event, 'PUSH_GROUP_ROUTE_MISSING_GROUP_ID');
        expect(events.single.details['payloadType'], 'group_message');
        expect(events.single.details['hasGroupId'], isFalse);
        expect(events.single.details['hasGroup_id'], isFalse);
        expect(events.single.details['hasGid'], isFalse);
        expect(events.single.details['hasConversationId'], isFalse);
      },
    );

    test(
      'payload-only group fallback still routes to the group drain',
      () async {
        var oneToOneCalls = 0;
        final drainedGroups = <String>[];

        final events = await _captureFlowEvents(() async {
          await handleForegroundRemoteMessage(
            data: payloadOnlyGroupData(),
            messageId: null,
            drainOfflineInbox: () async {
              oneToOneCalls += 1;
            },
            drainGroupOfflineInboxForGroup: (groupId) async {
              drainedGroups.add(groupId);
            },
          );
        });

        expect(oneToOneCalls, 0);
        expect(drainedGroups, ['group-1']);
        expect(events, hasLength(1));
        expect(events.single.event, 'PUSH_FOREGROUND_MESSAGE_ROUTED');
        expect(events.single.details['kind'], 'group');
      },
    );

    test(
      'group drain failures request a local fallback notification',
      () async {
        var oneToOneCalls = 0;
        late ForegroundRemoteMessageResult result;

        final events = await _captureFlowEvents(() async {
          result = await handleForegroundRemoteMessage(
            data: groupMessageData(),
            messageId: 'fcm-9',
            drainOfflineInbox: () async {
              oneToOneCalls += 1;
            },
            drainGroupOfflineInboxForGroup: (_) async {
              throw StateError('boom');
            },
          );
        });

        expect(oneToOneCalls, 0);
        expect(events.map((event) => event.event), [
          'PUSH_FOREGROUND_MESSAGE_ROUTED',
          'PUSH_FOREGROUND_DRAIN_ERROR',
        ]);
        expect(result, ForegroundRemoteMessageResult.notificationNeeded);
        expect(events.last.details['kind'], 'group');
        expect(events.last.details['error'], contains('boom'));
      },
    );

    test('1:1 drain failures are swallowed and logged', () async {
      final drainedGroups = <String>[];
      late ForegroundRemoteMessageResult result;

      final events = await _captureFlowEvents(() async {
        result = await handleForegroundRemoteMessage(
          data: newMessageData(),
          messageId: 'fcm-10',
          drainOfflineInbox: () async {
            throw StateError('boom');
          },
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );
      });

      expect(drainedGroups, isEmpty);
      expect(events.map((event) => event.event), [
        'PUSH_FOREGROUND_MESSAGE_ROUTED',
        'PUSH_FOREGROUND_DRAIN_ERROR',
      ]);
      expect(result, ForegroundRemoteMessageResult.drained);
      expect(events.last.details['kind'], 'conversation');
      expect(events.last.details['error'], contains('boom'));
    });

    test('missing or non-string message ids do not block routing', () async {
      final drainedGroups = <String>[];

      final events = await _captureFlowEvents(() async {
        await handleForegroundRemoteMessage(
          data: groupMessageData(messageId: null),
          messageId: null,
          drainOfflineInbox: () async {},
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );
        final nonStringIdPayload = groupMessageData()..['id'] = 42;
        await handleForegroundRemoteMessage(
          data: nonStringIdPayload,
          messageId: null,
          drainOfflineInbox: () async {},
          drainGroupOfflineInboxForGroup: (groupId) async {
            drainedGroups.add(groupId);
          },
        );
      });

      expect(drainedGroups, ['group-1', 'group-1']);
      expect(events.map((event) => event.event), [
        'PUSH_FOREGROUND_MESSAGE_ROUTED',
        'PUSH_FOREGROUND_MESSAGE_ROUTED',
      ]);
      expect(events.first.details['hasMessageId'], isFalse);
      expect(events.last.details['hasMessageId'], isTrue);
    });
  });
}

Future<List<_CapturedFlowEvent>> _captureFlowEvents(
  Future<void> Function() action,
) async {
  final events = <_CapturedFlowEvent>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null || !message.startsWith('[FLOW] ')) {
      return;
    }
    final decoded = jsonDecode(message.substring(7)) as Map<String, dynamic>;
    events.add(
      _CapturedFlowEvent(
        event: decoded['event'] as String,
        details: Map<String, dynamic>.from(
          decoded['details'] as Map<dynamic, dynamic>,
        ),
      ),
    );
  };

  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return events;
}

class _CapturedFlowEvent {
  const _CapturedFlowEvent({required this.event, required this.details});

  final String event;
  final Map<String, dynamic> details;
}
