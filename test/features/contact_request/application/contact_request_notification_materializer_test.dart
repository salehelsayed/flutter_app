import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_notification_materializer.dart';
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

  ContactRequestNotificationMaterializer buildMaterializer() {
    return ContactRequestNotificationMaterializer(
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
                      onDecline();
                    },
                    child: const Text('Decline'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      onAccept();
                    },
                    child: const Text('Accept'),
                  ),
                ],
              ),
            );
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
