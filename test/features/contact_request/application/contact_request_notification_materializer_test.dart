import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_notification_materializer.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_presentation_gate.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import '../domain/repositories/fake_contact_request_repository.dart';

void main() {
  late FakeContactRequestRepository requestRepository;
  late FakeContactRepository contactRepository;
  late FakeIdentityRepository identityRepository;
  late FakeP2PService p2pService;
  late FakeBridge bridge;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() {
    requestRepository = FakeContactRequestRepository();
    contactRepository = FakeContactRepository();
    identityRepository = FakeIdentityRepository();
    p2pService = FakeP2PService();
    bridge = FakeBridge();
    navigatorKey = GlobalKey<NavigatorState>();
  });

  ContactRequestNotificationMaterializer buildMaterializer({
    ContactRequestListener? listener,
  }) {
    final requestListener =
        listener ??
        ContactRequestListener(
          contactRequestStream: const Stream<ChatMessage>.empty(),
          requestRepo: requestRepository,
          contactRepo: contactRepository,
          bridge: bridge,
          getOwnPeerId: () => 'peer-self',
        );
    if (listener == null) addTearDown(requestListener.dispose);
    return ContactRequestNotificationMaterializer(
      contactRequestListener: requestListener,
      requestRepository: requestRepository,
      contactRepository: contactRepository,
      identityRepository: identityRepository,
      p2pService: p2pService,
      bridge: bridge,
      presentPendingRequest:
          ({
            required navigator,
            required request,
            required onAccept,
            required onDecline,
          }) async {
            Future<void>? decision;
            await showDialog<void>(
              context: navigator.context,
              barrierDismissible: false,
              builder: (dialogContext) => AlertDialog(
                title: Text(request.username),
                content: const Text('wants to connect with you'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      decision = onDecline();
                    },
                    child: const Text('Decline'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      decision = onAccept();
                    },
                    child: const Text('Accept'),
                  ),
                ],
              ),
            );
            await decision;
          },
      openConversation: ({required navigator, required contact}) {
        return navigator.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                Scaffold(body: Text('conversation:${contact.peerId}')),
          ),
        );
      },
    );
  }

  Widget buildHost() {
    return MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('home')),
    );
  }

  test(
    'root retains consent ownership until the selected decision completes',
    () {
      final source = File('lib/app/application_root.dart').readAsStringSync();
      final presenter = source.substring(
        source.indexOf('presentPendingRequest:'),
        source.indexOf(
          'openConversation:',
          source.indexOf('presentPendingRequest:'),
        ),
      );
      expect(presenter, contains('decision = onAccept();'));
      expect(presenter, contains('decision = onDecline();'));
      expect(
        presenter.indexOf('await decision;'),
        greaterThan(presenter.indexOf('await showDialog<void>(')),
      );
    },
  );

  testWidgets(
    'notification decline persists before gate release replays pending rows',
    (tester) async {
      final delayed = _DelayedDecisionRepository();
      requestRepository = delayed;
      addTearDown(() {
        if (!delayed.writeAllowed.isCompleted) delayed.writeAllowed.complete();
      });
      final gate = ContactRequestPresentationGate();
      final replayed = <ContactRequestModel>[];
      final listener = ContactRequestListener(
        contactRequestStream: const Stream<ChatMessage>.empty(),
        requestRepo: requestRepository,
        contactRepo: contactRepository,
        bridge: bridge,
        getOwnPeerId: () => 'peer-self',
        shouldSuppressPresentationForPeerId: gate.shouldSuppress,
        presentationGateChanges: gate,
      )..start();
      final subscription = listener.requestStream.listen(replayed.add);
      addTearDown(() async {
        await subscription.cancel();
        listener.dispose();
        gate.dispose();
      });
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      final request = _makeRequest();
      requestRepository.seed([request]);
      gate.suppress(request.peerId);
      var completed = false;
      final routed = (() async {
        try {
          await buildMaterializer(listener: listener).handleRoute(
            navigator: navigatorKey.currentState!,
            peerId: request.peerId,
          );
        } finally {
          gate.release(request.peerId);
          completed = true;
        }
      })();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(find.text('wants to connect with you'), findsNothing);
      expect(
        (await requestRepository.getRequest(request.peerId))?.status,
        ContactRequestStatus.pending,
      );
      expect(
        completed,
        isFalse,
        reason: 'route completion must await the database decision',
      );
      expect(gate.shouldSuppress(request.peerId), isTrue);
      expect(replayed, isEmpty);
      delayed.writeAllowed.complete();
      await tester.pumpAndSettle();
      await routed;
      expect(
        (await requestRepository.getRequest(request.peerId))?.status,
        ContactRequestStatus.declined,
      );
      expect(gate.shouldSuppress(request.peerId), isFalse);
      expect(
        replayed,
        isEmpty,
        reason: 'release must read the persisted declined row',
      );
    },
  );

  testWidgets('pending request materializes as a dialog', (tester) async {
    final materializer = buildMaterializer();
    final request = _makeRequest();
    requestRepository.seed([request]);

    await tester.pumpWidget(buildHost());

    materializer.handleRoute(
      navigator: navigatorKey.currentState!,
      peerId: request.peerId,
    );
    await tester.pumpAndSettle();

    expect(find.text('Charlie'), findsOneWidget);
    expect(find.text('wants to connect with you'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
  });

  testWidgets('accepting a pending request opens the conversation', (
    tester,
  ) async {
    final materializer = buildMaterializer();
    final request = _makeRequest();
    requestRepository.seed([request]);

    await tester.pumpWidget(buildHost());

    materializer.handleRoute(
      navigator: navigatorKey.currentState!,
      peerId: request.peerId,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(find.text('conversation:${request.peerId}'), findsOneWidget);
    expect(
      (await requestRepository.getRequest(request.peerId))?.status,
      ContactRequestStatus.accepted,
    );
    expect(await contactRepository.getContact(request.peerId), isNotNull);
  });

  testWidgets(
    'declining a pending request closes the dialog without navigation',
    (tester) async {
      final materializer = buildMaterializer();
      final request = _makeRequest();
      requestRepository.seed([request]);

      await tester.pumpWidget(buildHost());

      materializer.handleRoute(
        navigator: navigatorKey.currentState!,
        peerId: request.peerId,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();

      expect(find.text('wants to connect with you'), findsNothing);
      expect(find.text('conversation:${request.peerId}'), findsNothing);
      expect(
        (await requestRepository.getRequest(request.peerId))?.status,
        ContactRequestStatus.declined,
      );
    },
  );

  testWidgets('existing contact opens conversation without dialog', (
    tester,
  ) async {
    final materializer = buildMaterializer();
    final contact = _makeContact(peerId: 'peer-existing-123');
    contactRepository.seed([contact]);

    await tester.pumpWidget(buildHost());

    materializer.handleRoute(
      navigator: navigatorKey.currentState!,
      peerId: contact.peerId,
    );
    await tester.pumpAndSettle();

    expect(find.text('conversation:${contact.peerId}'), findsOneWidget);
    expect(find.text('wants to connect with you'), findsNothing);
  });

  testWidgets('missing target is a no-op', (tester) async {
    final materializer = buildMaterializer();

    await tester.pumpWidget(buildHost());

    await materializer.handleRoute(
      navigator: navigatorKey.currentState!,
      peerId: 'peer-missing-123',
    );
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.text('wants to connect with you'), findsNothing);
    expect(find.textContaining('conversation:'), findsNothing);
  });
}

ContactRequestModel _makeRequest({
  String peerId = 'peer-request-123',
  String username = 'Charlie',
  ContactRequestStatus status = ContactRequestStatus.pending,
}) {
  return ContactRequestModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/rendezvous.example.com/tcp/4001/p2p/$peerId',
    username: username,
    signature: 'sig-$peerId',
    receivedAt: '2026-04-03T12:00:00.000Z',
    status: status,
  );
}

ContactModel _makeContact({required String peerId}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/rendezvous.example.com/tcp/4001/p2p/$peerId',
    username: 'Existing $peerId',
    signature: 'sig-$peerId',
    scannedAt: '2026-04-03T12:00:00.000Z',
  );
}

class _DelayedDecisionRepository extends FakeContactRequestRepository {
  final writeAllowed = Completer<void>();

  @override
  Future<void> updateStatus(String peerId, ContactRequestStatus status) async {
    await writeAllowed.future;
    await super.updateStatus(peerId, status);
  }
}
