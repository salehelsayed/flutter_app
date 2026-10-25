import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_presentation_gate.dart';
import 'package:flutter_app/features/contact_request/application/resolve_contact_request_notification_target_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';

import '../core/bridge/fake_bridge.dart';
import '../features/contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../shared/fakes/ed25519_contact_request_crypto.dart';

void main() {
  late StreamController<ChatMessage> contactRequestStream;
  late FakeContactRequestRepository requestRepository;
  late FakeContactRepository contactRepository;
  late ContactRequestPresentationGate presentationGate;
  late ContactRequestListener listener;
  late List<ContactRequestModel> liveRequests;
  late FakeBridge bridge;

  setUp(() {
    contactRequestStream = StreamController<ChatMessage>.broadcast();
    requestRepository = FakeContactRequestRepository();
    contactRepository = FakeContactRepository();
    presentationGate = ContactRequestPresentationGate();
    liveRequests = <ContactRequestModel>[];
    bridge = FakeBridge(
      initialResponses: {
        'payload.verify': {'ok': true, 'valid': true},
      },
    );

    listener = ContactRequestListener(
      contactRequestStream: contactRequestStream.stream,
      requestRepo: requestRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnPeerId: () => 'peer-self',
      shouldSuppressPresentationForPeerId: presentationGate.shouldSuppress,
      presentationGateChanges: presentationGate,
    )..start();

    listener.requestStream.listen(liveRequests.add);
  });

  tearDown(() async {
    listener.dispose();
    await contactRequestStream.close();
  });

  test(
    'missed notification presentation replays the pending inbox request when suppression ends',
    () async {
      final sender = TestEd25519Identity.fromSeedByte(0x13);
      final peerId = sender.peerId;
      ContactRequestNotificationTarget? resolvedTarget;

      presentationGate.suppress(peerId);
      try {
        await routeRemoteNotificationOpen(
          data: {'type': 'contact_request', 'sender_id': peerId},
          onBeforeRouteTarget: (target) async {
            final result = await prepareNotificationOpen(
              routeTarget: target,
              drainOfflineInbox: () async {
                contactRequestStream.add(_makeContactRequestMessage(sender));
                await _flushMicrotasks();
              },
              drainGroupOfflineInboxForGroup: (_) async {},
            );
            expect(result.ok, isTrue, reason: result.error);
          },
          onRouteTarget: (target) async {
            resolvedTarget = await resolveContactRequestNotificationTarget(
              peerId: target.peerId!,
              requestRepository: requestRepository,
              contactRepository: contactRepository,
            );
          },
          onMissingRouteTarget: () async => fail('route target should exist'),
        );
      } finally {
        presentationGate.release(peerId);
      }

      await _flushMicrotasks();

      expect(liveRequests.map((request) => request.peerId), [peerId]);
      expect(await contactRepository.getAllContacts(), isEmpty);
      expect(
        (await requestRepository.getRequest(peerId))?.status,
        ContactRequestStatus.pending,
      );
      expect(
        resolvedTarget?.state,
        ContactRequestNotificationTargetState.pendingRequest,
      );
      expect(
        resolvedTarget?.request?.peerId,
        peerId,
        reason:
            'notification routing should still resolve the replayed request',
      );
    },
  );

  test('suppression is scoped to the tapped peer only', () async {
    final suppressed = TestEd25519Identity.fromSeedByte(0x13);
    final unsuppressed = TestEd25519Identity.fromSeedByte(0x14);
    final suppressedPeerId = suppressed.peerId;
    final unsuppressedPeerId = unsuppressed.peerId;

    presentationGate.suppress(suppressedPeerId);
    contactRequestStream.add(_makeContactRequestMessage(suppressed));
    contactRequestStream.add(_makeContactRequestMessage(unsuppressed));

    await _flushMicrotasks();
    expect(liveRequests.map((request) => request.peerId), [unsuppressedPeerId]);
    presentationGate.release(suppressedPeerId);
    await _flushMicrotasks();

    expect(
      liveRequests.where((request) => request.peerId == suppressedPeerId),
      hasLength(1),
    );
    expect(await contactRepository.getAllContacts(), isEmpty);
    expect(
      (await requestRepository.getRequest(suppressedPeerId))?.status,
      ContactRequestStatus.pending,
    );
    expect(
      (await requestRepository.getRequest(unsuppressedPeerId))?.status,
      ContactRequestStatus.pending,
    );
  });
}

ChatMessage _makeContactRequestMessage(TestEd25519Identity sender) {
  final peerId = sender.peerId;
  final payload = SplayTreeMap<String, dynamic>.from({
    'ns': peerId,
    'pk': sender.publicKey,
    'rv': '/dns4/rendezvous.example.com/tcp/4001/p2p/$peerId',
    'ts': '2026-04-03T12:00:00.000Z',
    'un': 'User $peerId',
    'sig': 'sig-$peerId',
  });

  return ChatMessage(
    from: peerId,
    to: 'peer-self',
    content: jsonEncode({'type': 'contact_request', 'payload': payload}),
    timestamp: '2026-04-03T12:00:00.000Z',
    isIncoming: true,
  );
}

Future<void> _flushMicrotasks([int count = 6]) async {
  for (var i = 0; i < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
