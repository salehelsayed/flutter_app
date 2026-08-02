import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/prepare_notification_route_target_use_case.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../conversation/domain/repositories/fake_media_attachment_repository.dart';

void main() {
  group('prepareNotificationRouteTarget warmPeer forwarding (FDC-04 WIRE-1)', () {
    // TC-04-10b: the notif-tap warm hook is actually WIRED THROUGH
    // `prepareNotificationRouteTarget` into `prepareNotificationOpen` — not a
    // dead optional param. Because the hook defaults to null, a null/dead wire
    // at this seam would pass TC-04-10 (which calls prepareNotificationOpen
    // directly) green while notif-tap warm silently never fires in production.
    // Mutation: stop passing `warmPeer: warmPeer` from
    // prepareNotificationRouteTarget into prepareNotificationOpen → re-red.
    test(
      'TC-04-10b: forwards warmPeer into prepareNotificationOpen for a '
      'conversation route',
      () async {
        final warmed = <String>[];
        await prepareNotificationRouteTarget(
          routeTarget: const NotificationRouteTarget.conversation('peer-123'),
          drainOfflineInbox: () async {},
          bridge: PassthroughCryptoBridge(),
          groupRepository: null,
          groupMessageRepository: null,
          mediaAttachmentRepository: FakeMediaAttachmentRepository(),
          reactionRepository: null,
          groupPendingReactionRepository: null,
          warmPeer: (pid) async {
            warmed.add(pid);
          },
        );
        expect(warmed, ['peer-123']);
      },
    );

    // A null warmPeer wire (the production path before main.dart supplies the
    // real fn) must be harmless — the route still completes without throwing.
    test(
      'TC-04-10b: a null warmPeer wire is harmless for a conversation route',
      () async {
        final result = prepareNotificationRouteTarget(
          routeTarget: const NotificationRouteTarget.conversation('peer-123'),
          drainOfflineInbox: () async {},
          bridge: PassthroughCryptoBridge(),
          groupRepository: null,
          groupMessageRepository: null,
          mediaAttachmentRepository: FakeMediaAttachmentRepository(),
          reactionRepository: null,
          groupPendingReactionRepository: null,
        );
        await expectLater(result, completes);
      },
    );
  });
}
