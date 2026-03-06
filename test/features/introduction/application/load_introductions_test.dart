import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_introduction_repository.dart';

void main() {
  late InMemoryIntroductionRepository introRepo;
  final now = DateTime.now().toUtc().toIso8601String();

  setUp(() {
    introRepo = InMemoryIntroductionRepository();
  });

  group('loadIntroductionsForUser', () {
    test('returns only pending intros for user', () async {
      await introRepo.saveIntroduction(IntroductionModel(
        id: 'i1',
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        createdAt: now,
      ));
      await introRepo.saveIntroduction(IntroductionModel(
        id: 'i2',
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-D',
        createdAt: now,
        status: IntroductionOverallStatus.passed,
      ));

      final result = await loadIntroductionsForUser(
        introRepo: introRepo,
        peerId: 'peer-B',
      );

      expect(result, hasLength(1));
      expect(result.first.id, 'i1');
    });

    test('returns intros where user is introduced party', () async {
      await introRepo.saveIntroduction(IntroductionModel(
        id: 'i1',
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        createdAt: now,
      ));

      final result = await loadIntroductionsForUser(
        introRepo: introRepo,
        peerId: 'peer-C',
      );

      expect(result, hasLength(1));
      expect(result.first.id, 'i1');
    });

    test('returns empty list when no intros exist', () async {
      final result = await loadIntroductionsForUser(
        introRepo: introRepo,
        peerId: 'peer-X',
      );

      expect(result, isEmpty);
    });
  });

  group('groupByIntroducer', () {
    test('groups correctly by introducer ID', () {
      final intros = [
        IntroductionModel(
          id: 'i1',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          createdAt: now,
        ),
        IntroductionModel(
          id: 'i2',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-D',
          createdAt: now,
        ),
        IntroductionModel(
          id: 'i3',
          introducerId: 'peer-X',
          recipientId: 'peer-B',
          introducedId: 'peer-E',
          createdAt: now,
        ),
      ];

      final grouped = groupByIntroducer(intros);

      expect(grouped.keys, hasLength(2));
      expect(grouped['peer-A'], hasLength(2));
      expect(grouped['peer-X'], hasLength(1));
    });

    test('empty list returns empty map', () {
      final grouped = groupByIntroducer([]);
      expect(grouped, isEmpty);
    });
  });
}
