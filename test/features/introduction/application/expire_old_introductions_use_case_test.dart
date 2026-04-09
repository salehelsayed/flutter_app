import 'package:flutter_app/features/introduction/application/expire_old_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';

void main() {
  late InMemoryIntroductionRepository introRepo;
  late InMemoryContactRepository contactRepo;
  late InMemoryMessageRepository messageRepo;

  setUp(() {
    introRepo = InMemoryIntroductionRepository();
    contactRepo = InMemoryContactRepository();
    messageRepo = InMemoryMessageRepository();
  });

  group('expireOldIntroductions', () {
    test('repairs stale pending mutual acceptance rows and recreates contact',
        () async {
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'intro-stale-mutual',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          introducerUsername: 'Noor',
          recipientUsername: 'Lina',
          introducedUsername: 'Sarah',
          recipientPublicKey: 'pk-peer-B',
          recipientMlKemPublicKey: 'mlkem-pk-peer-B',
          introducedPublicKey: 'pk-peer-C',
          introducedMlKemPublicKey: 'mlkem-pk-peer-C',
          recipientStatus: IntroductionStatus.accepted,
          introducedStatus: IntroductionStatus.accepted,
          status: IntroductionOverallStatus.pending,
          createdAt: '2026-03-25T12:00:00.000Z',
        ),
      );

      final repaired = await expireOldIntroductions(
        introRepo: introRepo,
        peerId: 'peer-B',
        contactRepo: contactRepo,
        messageRepo: messageRepo,
      );

      expect(repaired, 1);

      final updated = await introRepo.getIntroduction('intro-stale-mutual');
      expect(updated, isNotNull);
      expect(updated!.status, IntroductionOverallStatus.mutualAccepted);
      expect(await contactRepo.contactExists('peer-C'), isTrue);

      final messages = await messageRepo.getMessagesForContact('peer-C');
      expect(messages, hasLength(1));
      expect(
        messages.single.text,
        'You and Sarah are now connected — introduced by Noor',
      );
    });

    test('repairs stale pending passed rows without creating a contact',
        () async {
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'intro-stale-passed',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          recipientStatus: IntroductionStatus.passed,
          introducedStatus: IntroductionStatus.pending,
          status: IntroductionOverallStatus.pending,
          createdAt: '2026-03-25T12:00:00.000Z',
        ),
      );

      final repaired = await expireOldIntroductions(
        introRepo: introRepo,
        peerId: 'peer-B',
        contactRepo: contactRepo,
        messageRepo: messageRepo,
      );

      expect(repaired, 1);

      final updated = await introRepo.getIntroduction('intro-stale-passed');
      expect(updated, isNotNull);
      expect(updated!.status, IntroductionOverallStatus.passed);
      expect(await contactRepo.contactExists('peer-C'), isFalse);
      expect(await messageRepo.getMessagesForContact('peer-C'), isEmpty);
    });

    test('repairs stale pending expired rows without creating a contact',
        () async {
      final thirtyOneDaysAgo = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 31))
          .toIso8601String();

      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'intro-stale-expired',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          recipientStatus: IntroductionStatus.pending,
          introducedStatus: IntroductionStatus.pending,
          status: IntroductionOverallStatus.pending,
          createdAt: thirtyOneDaysAgo,
        ),
      );

      final repaired = await expireOldIntroductions(
        introRepo: introRepo,
        peerId: 'peer-B',
        contactRepo: contactRepo,
        messageRepo: messageRepo,
      );

      expect(repaired, 1);

      final updated = await introRepo.getIntroduction('intro-stale-expired');
      expect(updated, isNotNull);
      expect(updated!.status, IntroductionOverallStatus.expired);
      expect(await contactRepo.contactExists('peer-C'), isFalse);
      expect(await messageRepo.getMessagesForContact('peer-C'), isEmpty);
    });

    test('leaves alreadyConnected rows untouched during startup repair',
        () async {
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'intro-already-connected',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          status: IntroductionOverallStatus.alreadyConnected,
          createdAt: '2026-01-01T12:00:00.000Z',
        ),
      );

      final repaired = await expireOldIntroductions(
        introRepo: introRepo,
        peerId: 'peer-B',
        contactRepo: contactRepo,
      );

      expect(repaired, 0);

      final updated = await introRepo.getIntroduction('intro-already-connected');
      expect(updated, isNotNull);
      expect(updated!.status, IntroductionOverallStatus.alreadyConnected);
    });
  });
}
