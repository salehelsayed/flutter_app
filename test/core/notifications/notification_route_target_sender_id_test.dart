import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';

void main() {
  group('NotificationRouteTarget.fromRemoteMessageData — sender_id field', () {
    test('resolves conversation from sender_id key (relay format)', () {
      final target = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'new_message',
        'sender_id': '12D3KooWRelayPeer',
      });
      expect(target, isNotNull);
      expect(target!.kind, NotificationRouteTargetKind.conversation);
      expect(target.peerId, '12D3KooWRelayPeer');
    });

    test('resolves conversation from from key (legacy format)', () {
      final target = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'new_message',
        'from': '12D3KooWLegacyPeer',
      });
      expect(target, isNotNull);
      expect(target!.peerId, '12D3KooWLegacyPeer');
    });

    test('sender_id takes precedence when both fields are present', () {
      final target = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'new_message',
        'sender_id': '12D3KooWNew',
        'from': '12D3KooWOld',
      });
      expect(target!.peerId, '12D3KooWNew');
    });

    test('returns null when neither sender_id nor from is present', () {
      final target = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'new_message',
      });
      expect(target, isNull);
    });

    test('whitespace-only sender_id falls back to from', () {
      final target = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'new_message',
        'sender_id': '   ',
        'from': '12D3KooWFallback',
      });
      expect(target!.peerId, '12D3KooWFallback');
    });
  });
}
