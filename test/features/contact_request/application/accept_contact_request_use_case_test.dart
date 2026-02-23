import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';

import '../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';

const testRequest = ContactRequestModel(
  peerId: 'peer-accept-001',
  publicKey: 'pk-base64',
  rendezvous: '/dns4/relay',
  username: 'Alice',
  signature: 'sig-base64',
  receivedAt: '2026-01-01T00:00:00.000Z',
  status: ContactRequestStatus.pending,
  mlKemPublicKey: 'mlkem-pk',
);

void main() {
  late FakeContactRequestRepository requestRepo;
  late FakeContactRepository contactRepo;

  setUp(() {
    requestRepo = FakeContactRequestRepository();
    contactRepo = FakeContactRepository();
  });

  group('acceptContactRequest', () {
    test('returns notFound when request does not exist', () async {
      // No requests seeded -- repo is empty
      final result = await acceptContactRequest(
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        peerId: 'nonexistent-peer',
      );

      expect(result, AcceptContactRequestResult.notFound);
    });

    test('returns notPending when request is already accepted', () async {
      requestRepo.seed([
        testRequest.copyWith(status: ContactRequestStatus.accepted),
      ]);

      final result = await acceptContactRequest(
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        peerId: testRequest.peerId,
      );

      expect(result, AcceptContactRequestResult.notPending);
    });

    test('returns notPending when request is declined', () async {
      requestRepo.seed([
        testRequest.copyWith(status: ContactRequestStatus.declined),
      ]);

      final result = await acceptContactRequest(
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        peerId: testRequest.peerId,
      );

      expect(result, AcceptContactRequestResult.notPending);
    });

    test('returns success and adds contact when request is pending', () async {
      requestRepo.seed([testRequest]);

      final result = await acceptContactRequest(
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        peerId: testRequest.peerId,
      );

      expect(result, AcceptContactRequestResult.success);
      expect(contactRepo.addContactCallCount, 1);
    });

    test('added contact has correct peerId and username from request',
        () async {
      requestRepo.seed([testRequest]);

      await acceptContactRequest(
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        peerId: testRequest.peerId,
      );

      final addedContact = contactRepo.lastAddedContact;
      expect(addedContact, isNotNull);
      expect(addedContact!.peerId, testRequest.peerId);
      expect(addedContact.username, testRequest.username);
      expect(addedContact.publicKey, testRequest.publicKey);
      expect(addedContact.rendezvous, testRequest.rendezvous);
      expect(addedContact.mlKemPublicKey, testRequest.mlKemPublicKey);
    });

    test('returns addContactError when contactRepo throws', () async {
      requestRepo.seed([testRequest]);
      contactRepo.throwOnAddContact = true;

      final result = await acceptContactRequest(
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        peerId: testRequest.peerId,
      );

      expect(result, AcceptContactRequestResult.addContactError);
    });

    test('returns updateStatusError when requestRepo.updateStatus throws',
        () async {
      requestRepo.seed([testRequest]);
      requestRepo.throwOnUpdateStatus = true;

      final result = await acceptContactRequest(
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        peerId: testRequest.peerId,
      );

      expect(result, AcceptContactRequestResult.updateStatusError);
      // Contact should still have been added before the status update failed
      expect(contactRepo.addContactCallCount, 1);
    });

    test('status is updated to accepted on success', () async {
      requestRepo.seed([testRequest]);

      await acceptContactRequest(
        requestRepo: requestRepo,
        contactRepo: contactRepo,
        peerId: testRequest.peerId,
      );

      expect(requestRepo.updateStatusCallCount, 1);
      expect(requestRepo.lastUpdateStatusPeerId, testRequest.peerId);
      expect(requestRepo.lastUpdateStatus, ContactRequestStatus.accepted);

      // Verify the stored request also reflects the update
      final updated = await requestRepo.getRequest(testRequest.peerId);
      expect(updated!.status, ContactRequestStatus.accepted);
    });
  });
}
