import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const request = ContactRequestModel(
    peerId: 'request-peer',
    publicKey: 'request-key',
    rendezvous: '/rendezvous/request-peer',
    username: 'Requester',
    signature: 'request-signature',
    receivedAt: '2026-11-01T01:00:00.000Z',
  );

  for (final decision in [
    ContactRequestDecisionResult.accepted,
    ContactRequestDecisionResult.alreadyAccepted,
    ContactRequestDecisionResult.declined,
  ]) {
    test(
      'CR-008 ${decision.name} retires only the committed request card',
      () async {
        final retired = <ContactRequestModel>[];
        var committed = false;
        final repository = ContactRequestRepositoryImpl(
          dbLoadPendingRequests: () async => [request.toMap()],
          dbLoadRequest: (_) async => request.toMap(),
          dbUpsertRequest: (_) async {},
          dbUpdateRequestStatus: (_, _) async {},
          dbDeleteRequest: (_) async {},
          dbRequestExists: (_) async => true,
          dbDecideRequest: (expected, accept, existingOnly, before) async {
            expect(expected, request.toMap());
            committed = true;
            return decision;
          },
          onRequestDecided: (settled) async {
            expect(committed, isTrue);
            retired.add(settled);
          },
        );

        expect(
          await repository.decideRequest(
            expectedRequest: request,
            accept: decision != ContactRequestDecisionResult.declined,
          ),
          decision,
        );
        expect(retired, hasLength(1));
        expect(retired.single, same(request));
      },
    );
  }

  test('CR-008 retirement failure preserves the committed decision', () async {
    var retirementAttempted = false;
    final repository = ContactRequestRepositoryImpl(
      dbLoadPendingRequests: () async => [],
      dbLoadRequest: (_) async => request.toMap(),
      dbUpsertRequest: (_) async {},
      dbUpdateRequestStatus: (_, _) async {},
      dbDeleteRequest: (_) async {},
      dbRequestExists: (_) async => true,
      dbDecideRequest: (_, _, _, _) async =>
          ContactRequestDecisionResult.declined,
      onRequestDecided: (_) async {
        retirementAttempted = true;
        throw StateError('notification center unavailable');
      },
    );

    expect(
      await repository.decideRequest(expectedRequest: request, accept: false),
      ContactRequestDecisionResult.declined,
    );
    expect(retirementAttempted, isTrue);
  });

  for (final decision in [
    ContactRequestDecisionResult.notPending,
    ContactRequestDecisionResult.blocked,
    ContactRequestDecisionResult.updateStatusError,
  ]) {
    test(
      'CR-008 ${decision.name} preserves the unresolved request card',
      () async {
        var retirementCount = 0;
        final repository = ContactRequestRepositoryImpl(
          dbLoadPendingRequests: () async => [request.toMap()],
          dbLoadRequest: (_) async => request.toMap(),
          dbUpsertRequest: (_) async {},
          dbUpdateRequestStatus: (_, _) async {},
          dbDeleteRequest: (_) async {},
          dbRequestExists: (_) async => true,
          dbDecideRequest: (_, _, _, _) async => decision,
          onRequestDecided: (_) async {
            retirementCount++;
          },
        );

        expect(
          await repository.decideRequest(
            expectedRequest: request,
            accept: false,
          ),
          decision,
        );
        expect(retirementCount, 0);
      },
    );
  }
}
