import 'package:flutter/material.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/app_visibility_route_binding.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/direct_private_media_route_observer.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';

import 'production_journey_controller.dart';

bool productionNotificationOtherChatOwner(
  ProductionJourneyController controller,
) =>
    controller.invocation.scenarioId == notificationOpenJourney &&
    controller.invocation.role == 'bob' &&
    controller.profileId == 'android.production_fcm.journey';

/// Observes the real navigator, listener-owned rows and notification boundary.
/// The sole mutation seeds the unrelated user-C history used by the original
/// notification-open regression. Navigation, lifecycle, sending and taps are UI
/// operations; this module cannot create a route or publish a notification.
void bindProductionDirectJourneyControls({
  required ProductionJourneyController controller,
  required GlobalKey<NavigatorState> navigatorKey,
  required ContactRepository contactRepository,
  required MessageRepository messageRepository,
  required ActiveConversationTracker conversationTracker,
}) {
  if (controller.invocation.scenarioId != notificationOpenJourney) return;
  final observer = directPrivateMediaRouteObserver;
  if (observer is! AppVisibilityRouteObserver) {
    throw StateError('production navigation observer is absent');
  }
  final routeEvents = <Map<String, Object?>>[];
  final flowEvents = <Map<String, Object?>>[];
  final routeIds = Expando<int>();
  var nextRouteId = 0;
  var overflow = false;
  int routeId(Route<dynamic> route) => routeIds[route] ??= ++nextRouteId;
  controller.bindDisposer(
    observer.observeNavigation((operation, route) {
      if (routeEvents.length >= 512) {
        overflow = true;
        return;
      }
      routeEvents.add({
        'operation': operation,
        'observedAt': DateTime.now().toUtc().toIso8601String(),
        'routeId': routeId(route),
        'routeName': route.settings.name,
      });
    }),
  );
  final flowLease = installScopedE2EFlowEventSink((event) {
    final name = event['event'];
    if (name is! String ||
        !(name.startsWith('NOTIFICATION_') ||
            name.startsWith('INITIAL_LOCAL_NOTIFICATION_') ||
            name == 'CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE')) {
      return;
    }
    if (flowEvents.length >= 512) {
      overflow = true;
      return;
    }
    // The production emitter has already sanitized these details.
    flowEvents.add(Map<String, Object?>.from(event));
  });
  controller.bindDisposer(flowLease.release);

  controller.bindAction('prepare_other_chat', (_) async {
    if (!productionNotificationOtherChatOwner(controller)) {
      throw StateError('other-chat fixture belongs to the receiver');
    }
    const peerId = '12D3KooWFakeUserC0000000000000000000000000000000';
    final timestamp = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 1))
        .toIso8601String();
    await contactRepository.addContact(
      ContactModel(
        peerId: peerId,
        publicKey: 'pk-fake-user-c',
        rendezvous: '/mknoon/production-journey/${controller.invocation.runId}',
        username: 'UserCSeeded',
        signature: 'fixture-${controller.invocation.runId}',
        scannedAt: timestamp,
      ),
    );
    final messageId = 'seed-user-c-${controller.invocation.runId}';
    await messageRepository.saveMessage(
      ConversationMessage(
        id: messageId,
        contactPeerId: peerId,
        senderPeerId: peerId,
        text: 'Old message from user-c',
        timestamp: timestamp,
        status: 'read',
        isIncoming: true,
        createdAt: timestamp,
        readAt: timestamp,
      ),
    );
    return {'peerId': peerId, 'messageId': messageId};
  });

  controller.bindAction('direct_snapshot', (arguments) async {
    if (overflow) throw StateError('production observation overflow');
    final rawPeers = arguments['peerIds'];
    if (rawPeers is! List ||
        rawPeers.isEmpty ||
        rawPeers.any((peer) => peer is! String || peer.isEmpty)) {
      throw const FormatException('exact peer identities required');
    }
    final peers = rawPeers.cast<String>().toSet();
    final messages = <Map<String, Object?>>[];
    for (final peer in peers) {
      if (await contactRepository.getContact(peer) == null) {
        throw StateError('snapshot peer is not a prepared contact');
      }
      for (final row in await messageRepository.getMessagesForContact(peer)) {
        messages.add({
          'id': row.id,
          'contactPeerId': row.contactPeerId,
          'text': row.text,
          'incoming': row.isIncoming,
          'status': row.status,
          'readAt': row.readAt,
          'deletedAt': row.deletedAt,
          'transport': row.transport,
        });
      }
    }
    final navigator = navigatorKey.currentState;
    if (navigator == null) throw StateError('production navigator is absent');
    final conversations = <Map<String, Object?>>[];
    void visit(Element element) {
      final widget = element.widget;
      if (widget is ConversationWired &&
          peers.contains(widget.contact.peerId)) {
        final route = ModalRoute.of(element);
        if (route == null) throw StateError('conversation has no real route');
        conversations.add({
          'peerId': widget.contact.peerId,
          'onstage': route.isCurrent,
          'routeId': routeId(route),
          'routeName': route.settings.name,
        });
      }
      element.visitChildElements(visit);
    }

    (navigator.context as Element).visitChildElements(visit);
    return {
      'messages': messages,
      'conversations': conversations,
      'activePeerId': conversationTracker.activePeerId,
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      'navigationEvents': List.of(routeEvents),
      'flowEvents': List.of(flowEvents),
      'notifications': controller.foregroundPush.snapshotNotifications(),
    };
  });
}
