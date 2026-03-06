import 'package:flutter_app/features/introduction/application/check_intro_banner_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

ContactModel _makeContact({
  required String peerId,
  String username = 'User',
  bool isBlocked = false,
  bool isArchived = false,
  bool introsBannerDismissed = false,
  String? introsSentAt,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/ip4/127.0.0.1/tcp/0',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    isBlocked: isBlocked,
    isArchived: isArchived,
    introsBannerDismissed: introsBannerDismissed,
    introsSentAt: introsSentAt,
  );
}

void main() {
  group('edge cases', () {
    late InMemoryContactRepository contactRepo;
    late InMemoryIntroductionRepository introRepo;

    setUp(() {
      contactRepo = InMemoryContactRepository();
      introRepo = InMemoryIntroductionRepository();
    });

    test('0 friends shouldShowIntroBanner returns false', () async {
      final target = _makeContact(peerId: 'peer-1', username: 'Alice');
      contactRepo.addTestContact(target);
      // No other contacts added — only the target exists.

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: target,
        messageCount: 0,
      );

      expect(result, isFalse);
    });

    test('blocked contact hides banner', () async {
      final target =
          _makeContact(peerId: 'peer-1', username: 'Alice', isBlocked: true);
      contactRepo.addTestContact(target);
      contactRepo.addTestContact(
          _makeContact(peerId: 'peer-2', username: 'Bob'));

      final result = await shouldShowIntroBanner(
        contactRepo: contactRepo,
        contact: target,
        messageCount: 0,
      );

      expect(result, isFalse);
    });

    test('deriveStatus returns expired after 30 days', () {
      final createdAt = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 31))
          .toIso8601String();

      final status = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.pending,
        introducedStatus: IntroductionStatus.pending,
        createdAt: createdAt,
      );

      expect(status, IntroductionOverallStatus.expired);
    });

    test('deriveStatus returns pending within 30 days', () {
      final createdAt = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 29))
          .toIso8601String();

      final status = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.pending,
        introducedStatus: IntroductionStatus.pending,
        createdAt: createdAt,
      );

      expect(status, IntroductionOverallStatus.pending);
    });

    test('deriveStatus returns mutualAccepted when both accept', () {
      final createdAt = DateTime.now().toUtc().toIso8601String();

      final status = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.accepted,
        introducedStatus: IntroductionStatus.accepted,
        createdAt: createdAt,
      );

      expect(status, IntroductionOverallStatus.mutualAccepted);
    });

    test('deriveStatus returns passed when recipient passes', () {
      final createdAt = DateTime.now().toUtc().toIso8601String();

      final status = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.passed,
        introducedStatus: IntroductionStatus.pending,
        createdAt: createdAt,
      );

      expect(status, IntroductionOverallStatus.passed);
    });

    test('deriveStatus returns passed when introduced passes', () {
      final createdAt = DateTime.now().toUtc().toIso8601String();

      final status = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.pending,
        introducedStatus: IntroductionStatus.passed,
        createdAt: createdAt,
      );

      expect(status, IntroductionOverallStatus.passed);
    });

    test('deriveStatus returns passed when one passes after other accepts',
        () {
      final createdAt = DateTime.now().toUtc().toIso8601String();

      final status = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.accepted,
        introducedStatus: IntroductionStatus.passed,
        createdAt: createdAt,
      );

      expect(status, IntroductionOverallStatus.passed);
    });

    test('getPendingIntroductionsForUser filters by status', () async {
      final pendingIntro = IntroductionModel(
        id: 'intro-1',
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );

      final passedIntro = IntroductionModel(
        id: 'intro-2',
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-D',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        recipientStatus: IntroductionStatus.passed,
        status: IntroductionOverallStatus.passed,
      );

      await introRepo.saveIntroduction(pendingIntro);
      await introRepo.saveIntroduction(passedIntro);

      final pending =
          await introRepo.getPendingIntroductionsForUser('peer-B');

      expect(pending.length, equals(1));
      expect(pending.first.id, equals('intro-1'));
    });
  });
}
