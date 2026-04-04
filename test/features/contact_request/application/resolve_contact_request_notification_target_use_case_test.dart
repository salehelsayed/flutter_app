import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/resolve_contact_request_notification_target_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';

import '../domain/repositories/fake_contact_request_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';

void main() {
  late FakeContactRequestRepository requestRepository;
  late FakeContactRepository contactRepository;

  setUp(() {
    requestRepository = FakeContactRequestRepository();
    contactRepository = FakeContactRepository();
  });

  test('returns pending request when the request is still pending', () async {
    const request = ContactRequestModel(
      peerId: 'peer-request-123',
      publicKey: 'public-key',
      rendezvous: '/dns4/example.com/tcp/4001',
      username: 'Alice',
      signature: 'signature',
      receivedAt: '2026-04-03T10:00:00.000Z',
    );
    requestRepository.seed([request]);

    final result = await resolveContactRequestNotificationTarget(
      peerId: request.peerId,
      requestRepository: requestRepository,
      contactRepository: contactRepository,
    );

    expect(result.state, ContactRequestNotificationTargetState.pendingRequest);
    expect(result.request, request);
    expect(result.contact, isNull);
  });

  test(
    'falls back to conversation when the request was already accepted',
    () async {
      const request = ContactRequestModel(
        peerId: 'peer-request-123',
        publicKey: 'public-key',
        rendezvous: '/dns4/example.com/tcp/4001',
        username: 'Alice',
        signature: 'signature',
        receivedAt: '2026-04-03T10:00:00.000Z',
        status: ContactRequestStatus.accepted,
      );
      requestRepository.seed([request]);
      await contactRepository.addContact(request.toContactModel());

      final result = await resolveContactRequestNotificationTarget(
        peerId: request.peerId,
        requestRepository: requestRepository,
        contactRepository: contactRepository,
      );

      expect(result.state, ContactRequestNotificationTargetState.conversation);
      expect(result.request, isNull);
      expect(result.contact?.peerId, request.peerId);
    },
  );

  test('returns missing when neither request nor contact exists', () async {
    final result = await resolveContactRequestNotificationTarget(
      peerId: 'peer-request-123',
      requestRepository: requestRepository,
      contactRepository: contactRepository,
    );

    expect(result.state, ContactRequestNotificationTargetState.missing);
    expect(result.request, isNull);
    expect(result.contact, isNull);
  });
}
