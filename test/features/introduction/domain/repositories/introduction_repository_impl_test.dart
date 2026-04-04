import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/introduction/domain/models/pending_introduction_response.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository_impl.dart';

void main() {
  test(
    'deleteIntroduction clears staged responses before deleting intro row',
    () async {
      final operations = <String>[];

      final repo = IntroductionRepositoryImpl(
        dbInsertIntroduction: (_) async {},
        dbLoadIntroduction: (_) async => null,
        dbDeleteIntroduction: (id) async {
          operations.add('intro:$id');
        },
        dbLoadIntroductionsByRecipient: (_) async => const [],
        dbLoadIntroductionsByIntroduced: (_) async => const [],
        dbLoadIntroductionsByIntroducer: (_) async => const [],
        dbLoadIntroductionsForRecipientAndIntroducer: (_, __) async => const [],
        dbUpdateRecipientStatus: (_, __, ___) async {},
        dbUpdateIntroducedStatus: (_, __, ___) async {},
        dbUpdateOverallStatus: (_, __) async {},
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
