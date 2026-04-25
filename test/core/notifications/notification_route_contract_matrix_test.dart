import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';

void main() {
  const cases = <_RouteContractCase>[
    _RouteContractCase(
      label: 'conversation',
      remoteData: {'type': 'new_message', 'sender_id': 'peer-alice'},
      target: NotificationRouteTarget.conversation('peer-alice'),
      drainExpectation: _DrainExpectation.oneToOneInbox,
    ),
    _RouteContractCase(
      label: 'ciphertext conversation',
      remoteData: {
        'type': 'new_message',
        'sender_id': 'peer-alice',
        'message_id': 'msg-chat-1',
        'envelope_version': '2',
        'kem': 'kem',
        'ciphertext': 'ciphertext',
        'nonce': 'nonce',
      },
      target: NotificationRouteTarget.conversation('peer-alice'),
      drainExpectation: _DrainExpectation.oneToOneInbox,
    ),
    _RouteContractCase(
      label: 'contact request',
      remoteData: {'type': 'contact_request', 'sender_id': 'peer-bob'},
      target: NotificationRouteTarget.contactRequest('peer-bob'),
      drainExpectation: _DrainExpectation.oneToOneInbox,
    ),
    _RouteContractCase(
      label: 'intros',
      remoteData: {'type': 'intros'},
      target: NotificationRouteTarget.intros(),
      drainExpectation: _DrainExpectation.oneToOneInbox,
    ),
    _RouteContractCase(
      label: 'group',
      remoteData: {'type': 'group_message', 'groupId': 'group-team'},
      target: NotificationRouteTarget.group('group-team'),
      drainExpectation: _DrainExpectation.groupInbox,
    ),
    _RouteContractCase(
      label: 'ciphertext group',
      remoteData: {
        'type': 'group_message',
        'groupId': 'group-team',
        'message_id': 'msg-group-1',
        'kind': 'group_offline_replay',
        'payloadType': 'group_message',
        'keyEpoch': '7',
        'ciphertext': 'ciphertext',
        'nonce': 'nonce',
      },
      target: NotificationRouteTarget.group(
        'group-team',
        messageId: 'msg-group-1',
      ),
      drainExpectation: _DrainExpectation.groupInbox,
    ),
    _RouteContractCase(
      label: 'payload-only group',
      remoteData: {'payload': 'group:group-team'},
      target: NotificationRouteTarget.group('group-team'),
      drainExpectation: _DrainExpectation.groupInbox,
    ),
    _RouteContractCase(
      label: 'post',
      remoteData: {'type': 'post_create', 'post_id': 'post-42'},
      target: NotificationRouteTarget.post('post-42'),
      drainExpectation: _DrainExpectation.none,
    ),
    _RouteContractCase(
      label: 'post comment',
      remoteData: {
        'type': 'post_comment',
        'post_id': 'post-42',
        'comment_id': 'comment-7',
      },
      target: NotificationRouteTarget.postComment(
        postId: 'post-42',
        commentId: 'comment-7',
      ),
      drainExpectation: _DrainExpectation.none,
    ),
  ];

  group('notification route contract matrix', () {
    for (final testCase in cases) {
      test(
        '${testCase.label} remote data resolves to the canonical target',
        () {
          final target = NotificationRouteTarget.fromRemoteMessageData(
            testCase.remoteData,
          );

          expect(target, isNotNull);
          expect(target!.kind, testCase.target.kind);
          expect(target.peerId, testCase.target.peerId);
          expect(target.groupId, testCase.target.groupId);
          expect(target.postId, testCase.target.postId);
          expect(target.commentId, testCase.target.commentId);
          expect(target.toPayload(), testCase.target.toPayload());
        },
      );

      test('${testCase.label} local payload round-trips unchanged', () {
        final parsed = NotificationRouteTarget.fromPayload(
          testCase.target.toPayload(),
        );

        expect(parsed, isNotNull);
        expect(parsed!.kind, testCase.target.kind);
        expect(parsed.peerId, testCase.target.peerId);
        expect(parsed.groupId, testCase.target.groupId);
        expect(parsed.postId, testCase.target.postId);
        expect(parsed.commentId, testCase.target.commentId);
        expect(parsed.toPayload(), testCase.target.toPayload());
      });

      test(
        '${testCase.label} prepare policy matches the route contract',
        () async {
          final events = <String>[];

          final result = await prepareNotificationOpen(
            routeTarget: testCase.target,
            drainOfflineInbox: () async => events.add('drain:inbox'),
            drainGroupOfflineInboxForGroup: (groupId) async {
              events.add('drain:group:$groupId');
            },
          );

          expect(result.ok, isTrue, reason: result.error);
          switch (testCase.drainExpectation) {
            case _DrainExpectation.oneToOneInbox:
              expect(events, ['drain:inbox']);
            case _DrainExpectation.groupInbox:
              expect(events, ['drain:group:${testCase.target.groupId}']);
            case _DrainExpectation.none:
              expect(events, isEmpty);
          }
        },
      );

      test('${testCase.label} background fallback uses the same payload', () {
        final notification = buildBackgroundPushFallbackNotification(
          RemoteMessage(data: testCase.remoteData),
        );

        expect(notification, isNotNull);
        expect(notification!.payload, testCase.target.toPayload());
      });
    }
  });
}

enum _DrainExpectation { oneToOneInbox, groupInbox, none }

class _RouteContractCase {
  final String label;
  final Map<String, dynamic> remoteData;
  final NotificationRouteTarget target;
  final _DrainExpectation drainExpectation;

  const _RouteContractCase({
    required this.label,
    required this.remoteData,
    required this.target,
    required this.drainExpectation,
  });
}
