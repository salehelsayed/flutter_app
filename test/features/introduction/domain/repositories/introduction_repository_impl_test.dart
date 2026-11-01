import '../../../../core/secure_storage/fake_secure_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/introduction/domain/models/pending_introduction_response.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/data/repositories/introduction_repository_impl.dart';

void main() {
  for (final response in [
    IntroductionStatus.accepted,
    IntroductionStatus.passed,
  ]) {
    test(
      'IN-008 committed ${response.name} retires the existing intro offer card',
      () async {
        final retired = <String>[];
        var committed = false;
        final repo = _responseRepository(
          saveResponse: () async {
            committed = true;
            return true;
          },
          onResponseSaved: (introId) async {
            expect(committed, isTrue);
            retired.add(introId);
          },
        );

        expect(
          await repo.saveIntroductionResponseWithOutboxDeliveries(
            introductionId: 'intro-1',
            isRecipient: true,
            responseStatus: response,
            overallStatus: response == IntroductionStatus.passed
                ? IntroductionOverallStatus.passed
                : IntroductionOverallStatus.pending,
            respondedAt: '2026-11-01T01:00:00.000Z',
            deliveries: const [],
          ),
          isTrue,
        );
        expect(retired, ['intro-1']);
      },
    );
  }

  test('IN-008 rejected response preserves the pending intro card', () async {
    final retired = <String>[];
    final repo = _responseRepository(
      saveResponse: () async => false,
      onResponseSaved: (id) async => retired.add(id),
    );
    expect(
      await repo.saveIntroductionResponseWithOutboxDeliveries(
        introductionId: 'intro-1',
        isRecipient: true,
        responseStatus: IntroductionStatus.passed,
        overallStatus: IntroductionOverallStatus.passed,
        respondedAt: '2026-11-01T01:00:00.000Z',
        deliveries: const [],
      ),
      isFalse,
    );
    expect(retired, isEmpty);
  });

  test('IN-008 retirement failure preserves the committed response', () async {
    var retirementAttempted = false;
    final repo = _responseRepository(
      saveResponse: () async => true,
      onResponseSaved: (_) async {
        retirementAttempted = true;
        throw StateError('notification center unavailable');
      },
    );
    expect(
      await repo.saveIntroductionResponseWithOutboxDeliveries(
        introductionId: 'intro-1',
        isRecipient: true,
        responseStatus: IntroductionStatus.accepted,
        overallStatus: IntroductionOverallStatus.pending,
        respondedAt: '2026-11-01T01:00:00.000Z',
        deliveries: const [],
      ),
      isTrue,
    );
    expect(retirementAttempted, isTrue);
  });

  test(
    'deleteIntroduction clears staged responses before deleting intro row',
    () async {
      final operations = <String>[];

      final repo = IntroductionRepositoryImpl(
        secureKeyStore: FakeSecureKeyStore(),
        dbInsertIntroduction: (_) async {},
        dbLoadIntroduction: (_) async => null,
        dbDeleteIntroduction: (id) async {
          operations.add('intro:$id');
        },
        dbLoadIntroductionsByRecipient: (_) async => const [],
        dbLoadIntroductionsByIntroduced: (_) async => const [],
        dbLoadIntroductionsByIntroducer: (_) async => const [],
        dbLoadIntroductionsForRecipientAndIntroducer: (_, _) async => const [],
        dbUpdateRecipientStatus: (_, _, _) async => true,
        dbUpdateIntroducedStatus: (_, _, _) async => true,
        dbUpdateOverallStatus: (_, _) async {},
        dbLoadPendingIntroductionsForUser: (_) async => const [],
        dbCountPendingIntroductions: (_) async => 0,
        dbUpsertPendingIntroductionResponse: (_) async {},
        dbLoadPendingIntroductionResponses: (introductionId) async {
          operations.add('load:$introductionId');
          return [
            const PendingIntroductionResponse(
              responseKey: 'response-a',
              introductionId: 'intro-1',
              action: 'accept',
              responderId: 'peer-a',
              createdAt: '2026-04-01T00:00:00.000Z',
            ).toMap(),
            const PendingIntroductionResponse(
              responseKey: 'response-b',
              introductionId: 'intro-1',
              action: 'pass',
              responderId: 'peer-b',
              createdAt: '2026-04-01T00:01:00.000Z',
            ).toMap(),
          ];
        },
        dbDeletePendingIntroductionResponse: (responseKey) async {
          operations.add('response:$responseKey');
        },
        dbUpsertIntroductionOutboxDelivery: (_) async {},
        dbSaveIntroductionWithOutboxDeliveries:
            (introductionRow, deliveryRows) async {},
        dbReplaceIntroductionWithPendingResponseMigration:
            ({
              required introductionRow,
              required deliveryRows,
              required replacedIntroductionIds,
            }) async {},
        dbSaveIntroductionResponseWithOutboxDeliveries:
            ({
              required introductionId,
              required isRecipient,
              required responseStatus,
              required respondedAt,
              required overallStatus,
              required deliveryRows,
            }) async => true,
        dbLoadIntroductionOutboxDeliveriesForIntroduction: (_) async =>
            const [],
        dbLoadRetryableIntroductionOutboxDeliveries:
            ({required olderThan, limit = 100}) async => const [],
        dbDeleteIntroductionOutboxDelivery: (_) async {},
        dbDeleteIntroductionOutboxDeliveriesForIntroduction:
            (introductionId) async {
              operations.add('outbox:$introductionId');
            },
      );

      await repo.deleteIntroduction('intro-1');

      expect(operations, [
        'load:intro-1',
        'response:response-a',
        'response:response-b',
        'outbox:intro-1',
        'intro:intro-1',
      ]);
    },
  );
}

IntroductionRepositoryImpl _responseRepository({
  required Future<bool> Function() saveResponse,
  required Future<void> Function(String) onResponseSaved,
}) => IntroductionRepositoryImpl(
  secureKeyStore: FakeSecureKeyStore(),
  dbInsertIntroduction: (_) async {},
  dbLoadIntroduction: (_) async => null,
  dbDeleteIntroduction: (_) async {},
  dbLoadIntroductionsByRecipient: (_) async => const [],
  dbLoadIntroductionsByIntroduced: (_) async => const [],
  dbLoadIntroductionsByIntroducer: (_) async => const [],
  dbLoadIntroductionsForRecipientAndIntroducer: (_, _) async => const [],
  dbUpdateRecipientStatus: (_, _, _) async => true,
  dbUpdateIntroducedStatus: (_, _, _) async => true,
  dbUpdateOverallStatus: (_, _) async {},
  dbLoadPendingIntroductionsForUser: (_) async => const [],
  dbCountPendingIntroductions: (_) async => 0,
  dbUpsertPendingIntroductionResponse: (_) async {},
  dbLoadPendingIntroductionResponses: (_) async => const [],
  dbDeletePendingIntroductionResponse: (_) async {},
  dbUpsertIntroductionOutboxDelivery: (_) async {},
  dbSaveIntroductionWithOutboxDeliveries: (_, _) async {},
  dbReplaceIntroductionWithPendingResponseMigration:
      ({
        required introductionRow,
        required deliveryRows,
        required replacedIntroductionIds,
      }) async {},
  dbSaveIntroductionResponseWithOutboxDeliveries:
      ({
        required introductionId,
        required isRecipient,
        required responseStatus,
        required respondedAt,
        required overallStatus,
        required deliveryRows,
      }) => saveResponse(),
  dbLoadIntroductionOutboxDeliveriesForIntroduction: (_) async => const [],
  dbLoadRetryableIntroductionOutboxDeliveries:
      ({required olderThan, limit = 100}) async => const [],
  dbDeleteIntroductionOutboxDelivery: (_) async {},
  dbDeleteIntroductionOutboxDeliveriesForIntroduction: (_) async {},
  onResponseSaved: onResponseSaved,
);
