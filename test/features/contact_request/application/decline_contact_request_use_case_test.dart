import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';

import '../../contact_request/domain/repositories/fake_contact_request_repository.dart';

const _pendingRequest = ContactRequestModel(
  peerId: 'peer-decline-001',
  publicKey: 'pk-base64',
  rendezvous: '/dns4/relay',
  username: 'Bob',
  signature: 'sig-base64',
  receivedAt: '2026-01-01T00:00:00.000Z',
  status: ContactRequestStatus.pending,
  mlKemPublicKey: 'mlkem-pk',
);

void main() {
  late FakeContactRequestRepository requestRepo;

  setUp(() {
    requestRepo = FakeContactRequestRepository();
  });

  group('declineContactRequest', () {
    test('returns notFound when request does not exist', () async {
      final result = await declineContactRequest(
        requestRepo: requestRepo,
        peerId: 'nonexistent-peer',
      );

      expect(result, DeclineContactRequestResult.notFound);
    });

    test('returns success when request exists', () async {
      requestRepo.seed([_pendingRequest]);

      final result = await declineContactRequest(
        requestRepo: requestRepo,
        peerId: _pendingRequest.peerId,
      );

      expect(result, DeclineContactRequestResult.success);
    });

    test('status is updated to declined', () async {
      requestRepo.seed([_pendingRequest]);

      await declineContactRequest(
        requestRepo: requestRepo,
        peerId: _pendingRequest.peerId,
      );

      expect(requestRepo.updateStatusCallCount, 1);
      expect(requestRepo.lastUpdateStatusPeerId, _pendingRequest.peerId);
      expect(requestRepo.lastUpdateStatus, ContactRequestStatus.declined);

      final updated = await requestRepo.getRequest(_pendingRequest.peerId);
      expect(updated!.status, ContactRequestStatus.declined);
    });

    test('returns updateError when updateStatus throws', () async {
      requestRepo.seed([_pendingRequest]);
      requestRepo.throwOnUpdateStatus = true;

      final result = await declineContactRequest(
        requestRepo: requestRepo,
        peerId: _pendingRequest.peerId,
      );

      expect(result, DeclineContactRequestResult.updateError);
    });

    test('works for already-accepted requests (still declines)', () async {
      requestRepo.seed([
        _pendingRequest.copyWith(status: ContactRequestStatus.accepted),
      ]);

      final result = await declineContactRequest(
        requestRepo: requestRepo,
        peerId: _pendingRequest.peerId,
      );

      // The use case does not check current status -- it just updates
      expect(result, DeclineContactRequestResult.success);

      final updated = await requestRepo.getRequest(_pendingRequest.peerId);
      expect(updated!.status, ContactRequestStatus.declined);
    });
  });
}
