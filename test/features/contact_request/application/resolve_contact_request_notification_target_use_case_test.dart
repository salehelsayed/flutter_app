import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/recover_intro_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/resolve_contact_request_notification_target_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';

import '../domain/repositories/fake_contact_request_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';

void main() {
  late FakeContactRequestRepository requestRepository;
  late FakeContactRepository contactRepository;

  setUp(() {
    requestRepository = FakeContactRequestRepository();
    contactRepository = FakeContactRepository();
    requestRepository.contactRepository = contactRepository;
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
    expect(
      (await requestRepository.getRequest(request.peerId))!.status,
      ContactRequestStatus.pending,
    );
    expect(await contactRepository.contactExists(request.peerId), isFalse);
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

  test(
    'opens the conversation when the peer is already a contact even though a stale pending row remains',
    () async {
      const request = ContactRequestModel(
        peerId: 'peer-request-123',
        publicKey: 'public-key',
        rendezvous: '/dns4/example.com/tcp/4001',
        username: 'Alice',
        signature: 'signature',
        receivedAt: '2026-04-03T10:00:00.000Z',
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

  test(
    'falls back to conversation after silent intro recovery cleans a stale pending request row',
    () async {
      final introRepo = InMemoryIntroductionRepository();
      final messageRepo = InMemoryMessageRepository();
      const peerId = 'peer-request-123';

      requestRepository.seed([
        const ContactRequestModel(
          peerId: peerId,
          publicKey: 'public-key',
          rendezvous: '/dns4/example.com/tcp/4001',
          username: 'Alice',
          signature: 'signature',
          receivedAt: '2026-04-03T10:00:00.000Z',
        ),
      ]);
      await introRepo.saveIntroduction(
        const IntroductionModel(
          id: 'intro-notification-recovery',
          introducerId: 'peer-introducer',
          recipientId: 'own-peer',
          introducedId: peerId,
          recipientStatus: IntroductionStatus.accepted,
          introducedStatus: IntroductionStatus.pending,
          status: IntroductionOverallStatus.pending,
          createdAt: '2026-04-03T09:00:00.000Z',
          introducerUsername: 'Noor',
          recipientUsername: 'Receiver',
          introducedUsername: 'Alice',
          introducedPublicKey: 'public-key',
        ),
      );

      await recoverIntroContactRequest(
        introRepo: introRepo,
        requestRepo: requestRepository,
        contactRepo: contactRepository,
        ownPeerId: 'own-peer',
        request: const VerifiedContactRequestEnvelope(
          peerId: peerId,
          publicKey: 'public-key',
          rendezvous: '/dns4/example.com/tcp/4001',
          username: 'Alice',
          signature: 'signature',
        ),
        messageRepo: messageRepo,
      );

      final result = await resolveContactRequestNotificationTarget(
        peerId: peerId,
        requestRepository: requestRepository,
        contactRepository: contactRepository,
      );

      expect(result.state, ContactRequestNotificationTargetState.conversation);
      expect(result.request, isNull);
      expect(result.contact?.peerId, peerId);
    },
  );

  for (final hasPending in [true, false]) {
    test(
      'blocked contact never routes (pending request: $hasPending)',
      () async {
        if (hasPending) requestRepository.seed([_routeRequest]);
        contactRepository.seed([_routeRequest.toContactModel()]);
        await contactRepository.blockContact(_routeRequest.peerId);
        final result = await resolveContactRequestNotificationTarget(
          peerId: _routeRequest.peerId,
          requestRepository: requestRepository,
          contactRepository: contactRepository,
        );
        expect(result.state, ContactRequestNotificationTargetState.missing);
        expect(
          (await contactRepository.getContact(_routeRequest.peerId))!.isBlocked,
          isTrue,
        );
      },
    );
  }

  for (final change in ['removed', 'replaced', 'blocked']) {
    test('rechecks $change authority after an awaited request read', () async {
      final held = _HeldRequestRepository()
        ..contactRepository = contactRepository
        ..seed([_routeRequest]);
      requestRepository = held;
      final resolving = resolveContactRequestNotificationTarget(
        peerId: _routeRequest.peerId,
        requestRepository: held,
        contactRepository: contactRepository,
      );
      addTearDown(() {
        if (!held.releaseRead.isCompleted) held.releaseRead.complete();
      });
      await held.readStarted.future;
      switch (change) {
        case 'removed':
          await held.deleteRequest(_routeRequest.peerId);
          break;
        case 'replaced':
          await held.addRequest(
            _routeRequest.copyWith(
              signature: 'newer-signed-request',
              receivedAt: '2026-04-03T10:01:00.000Z',
            ),
          );
          break;
        case 'blocked':
          contactRepository.seed([_routeRequest.toContactModel()]);
          await contactRepository.blockContact(_routeRequest.peerId);
          break;
      }
      held.releaseRead.complete();
      final result = await resolving;
      expect(result.state, ContactRequestNotificationTargetState.missing);
      if (change == 'replaced') {
        final newer = (await held.getRequest(_routeRequest.peerId))!;
        expect(newer.signature, 'newer-signed-request');
        expect(newer.status, ContactRequestStatus.pending);
        expect(
          await contactRepository.contactExists(_routeRequest.peerId),
          isFalse,
        );
      }
    });
  }
}

const _routeRequest = ContactRequestModel(
  peerId: 'peer-request-123',
  publicKey: 'public-key',
  rendezvous: '/dns4/example.com/tcp/4001',
  username: 'Alice',
  signature: 'signature',
  receivedAt: '2026-04-03T10:00:00.000Z',
);

class _HeldRequestRepository extends FakeContactRequestRepository {
  final readStarted = Completer<void>();
  final releaseRead = Completer<void>();
  bool _holdRead = true;

  @override
  Future<ContactRequestModel?> getRequest(String peerId) async {
    final request = await super.getRequest(peerId);
    if (_holdRead) {
      _holdRead = false;
      readStarted.complete();
      await releaseRead.future;
    }
    return request;
  }
}
