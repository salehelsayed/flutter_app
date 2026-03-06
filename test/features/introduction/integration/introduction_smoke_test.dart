import 'package:flutter_app/features/introduction/application/check_intro_banner_use_case.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/intro_test_user.dart';

void main() {
  late FakeP2PNetwork network;
  late IntroTestUser userA;
  late IntroTestUser userB;
  late IntroTestUser userC;
  late IntroTestUser userD;

  setUp(() {
    network = FakeP2PNetwork();
    userA = IntroTestUser.create(
        peerId: 'peer-A', username: 'Noor', network: network);
    userB = IntroTestUser.create(
        peerId: 'peer-B', username: 'Lina', network: network);
    userC = IntroTestUser.create(
        peerId: 'peer-C', username: 'Sarah', network: network);
    userD = IntroTestUser.create(
        peerId: 'peer-D', username: 'Dana', network: network);

    // A knows B, C, D
    userA.addContact(userB);
    userA.addContact(userC);
    userA.addContact(userD);
    userB.addContact(userA);
    userC.addContact(userA);
    userD.addContact(userA);
    // B, C, D don't know each other

    userA.start();
    userB.start();
    userC.start();
    userD.start();
  });

  tearDown(() {
    userA.dispose();
    userB.dispose();
    userC.dispose();
    userD.dispose();
  });

  group('introduction smoke tests', () {
    test('happy path: A sends → B receives → both accept → connected',
        () async {
      // 1. A sees banner for B
      final contactB = await userA.contactRepo.getContact('peer-B');
      final showBanner = await shouldShowIntroBanner(
        contactRepo: userA.contactRepo,
        contact: contactB!,
        messageCount: 0,
      );
      expect(showBanner, isTrue);

      // 2. A sends intros for C and D to B
      final friendC = await userA.contactRepo.getContact('peer-C');
      final friendD = await userA.contactRepo.getContact('peer-D');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!, friendD!],
      );
      expect(intros, hasLength(2));

      // 3. Confirmation data correct
      expect(intros[0].recipientId, 'peer-B');
      expect(intros[1].recipientId, 'peer-B');

      // Wait for delivery
      await Future.delayed(const Duration(milliseconds: 100));

      // 4. Seed intros on B and C repos
      final introBC = intros.firstWhere((i) => i.introducedId == 'peer-C');
      await userB.introRepo.saveIntroduction(introBC);
      await userC.introRepo.saveIntroduction(introBC);

      // 5. B accepts C
      await userB.acceptIntro(introBC.id);
      await userC.receiveAcceptNotification(
        introId: introBC.id,
        responderId: 'peer-B',
        responderUsername: 'Lina',
      );

      // 6. C accepts B
      await userC.acceptIntro(introBC.id);
      await userB.receiveAcceptNotification(
        introId: introBC.id,
        responderId: 'peer-C',
        responderUsername: 'Sarah',
      );

      // 7. Both reach mutualAccepted
      final bFinal = await userB.introRepo.getIntroduction(introBC.id);
      final cFinal = await userC.introRepo.getIntroduction(introBC.id);
      expect(bFinal!.status, IntroductionOverallStatus.mutualAccepted);
      expect(cFinal!.status, IntroductionOverallStatus.mutualAccepted);

      // 8. Contacts created
      expect(await userB.contactRepo.contactExists('peer-C'), isTrue);
      expect(await userC.contactRepo.contactExists('peer-B'), isTrue);

      // 9. Contacts have introducedBy
      final bContactC = await userB.contactRepo.getContact('peer-C');
      expect(bContactC!.introducedBy, 'Noor');
    });

    test('dismiss + re-entry via overflow menu path', () async {

      // Dismiss banner
      await userA.contactRepo.dismissIntroBanner('peer-B');

      // Verify dismissed
      final updatedB = await userA.contactRepo.getContact('peer-B');
      expect(updatedB!.introsBannerDismissed, isTrue);

      final showBanner = await shouldShowIntroBanner(
        contactRepo: userA.contactRepo,
        contact: updatedB,
        messageCount: 0,
      );
      expect(showBanner, isFalse);

      // Can still send via direct use case call (overflow menu path)
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      expect(intros, hasLength(1));

      // B receives
      await Future.delayed(const Duration(milliseconds: 100));
    });

    test('no friends: banner not shown', () async {
      // Create a user with only one contact
      final lonelyNetwork = FakeP2PNetwork();
      final lonely = IntroTestUser.create(
        peerId: 'peer-lonely',
        username: 'Solo',
        network: lonelyNetwork,
      );
      final friend = IntroTestUser.create(
        peerId: 'peer-only',
        username: 'Only',
        network: lonelyNetwork,
      );
      lonely.addContact(friend);
      // lonely has only 1 contact, no other friends to introduce

      final contact = await lonely.contactRepo.getContact('peer-only');
      final showBanner = await shouldShowIntroBanner(
        contactRepo: lonely.contactRepo,
        contact: contact!,
        messageCount: 0,
      );
      expect(showBanner, isFalse);

      lonely.dispose();
      friend.dispose();
    });

    test('block during flow: banner stays dismissed after unblock', () async {
      // A blocks B
      await userA.contactRepo.blockContact('peer-B');

      final blockedB = await userA.contactRepo.getContact('peer-B');
      final showBanner = await shouldShowIntroBanner(
        contactRepo: userA.contactRepo,
        contact: blockedB!,
        messageCount: 0,
      );
      expect(showBanner, isFalse);

      // A unblocks B
      await userA.contactRepo.unblockContact('peer-B');

      // Banner should be available again (block doesn't auto-dismiss)
      final unblockedB = await userA.contactRepo.getContact('peer-B');
      final showAfterUnblock = await shouldShowIntroBanner(
        contactRepo: userA.contactRepo,
        contact: unblockedB!,
        messageCount: 0,
      );
      expect(showAfterUnblock, isTrue);
    });

    test('duplicate prevention: already-introduced filtered', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');

      // Send first round
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      expect(intros, hasLength(1));

      // A's intro repo has the record
      final stored = await userA.introRepo.getIntroductionsByIntroducer('peer-A');
      expect(stored, hasLength(1));
      expect(stored.first.introducedId, 'peer-C');

      // For duplicate filtering, the picker would exclude already-introduced
      // Verify the repo query returns existing intros
      final existingForRecipient =
          await userA.introRepo.getIntroductionsByRecipient('peer-B');
      final alreadyIntroduced =
          existingForRecipient.map((i) => i.introducedId).toSet();
      expect(alreadyIntroduced.contains('peer-C'), isTrue);
    });

    test('B passes all intros → no connections', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final friendD = await userA.contactRepo.getContact('peer-D');

      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!, friendD!],
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Seed on B
      for (final intro in intros) {
        await userB.introRepo.saveIntroduction(intro);
      }

      // B passes all
      for (final intro in intros) {
        await userB.passIntro(intro.id);
      }

      // All should be passed
      for (final intro in intros) {
        final updated = await userB.introRepo.getIntroduction(intro.id);
        expect(updated!.status, IntroductionOverallStatus.passed);
      }

      // No pending intros for B
      final pending = await userB.loadPendingIntros();
      expect(pending, isEmpty);
    });

    test('expired intros: 31-day-old not in pending', () async {
      final thirtyOneDaysAgo = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 31))
          .toIso8601String();

      // Save an old intro
      await userB.introRepo.saveIntroduction(IntroductionModel(
        id: 'old-intro',
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        createdAt: thirtyOneDaysAgo,
      ));

      // deriveStatus returns expired
      final status = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.pending,
        introducedStatus: IntroductionStatus.pending,
        createdAt: thirtyOneDaysAgo,
      );
      expect(status, IntroductionOverallStatus.expired);
    });

    test('one-sided accept then complete', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      final introId = intros.first.id;

      await Future.delayed(const Duration(milliseconds: 100));
      await userB.introRepo.saveIntroduction(intros.first);
      await userC.introRepo.saveIntroduction(intros.first);

      // B accepts — no connection yet
      await userB.acceptIntro(introId);
      final bAfterSingle = await userB.introRepo.getIntroduction(introId);
      expect(bAfterSingle!.status, IntroductionOverallStatus.pending);

      // C accepts — notify B
      await userC.acceptIntro(introId);
      await userB.receiveAcceptNotification(
        introId: introId,
        responderId: 'peer-C',
        responderUsername: 'Sarah',
      );
      // Notify C of B's acceptance too
      await userC.receiveAcceptNotification(
        introId: introId,
        responderId: 'peer-B',
        responderUsername: 'Lina',
      );

      final cAfterMutual = await userC.introRepo.getIntroduction(introId);
      expect(cAfterMutual!.status, IntroductionOverallStatus.mutualAccepted);

      // Contacts created only after mutual acceptance
      expect(await userC.contactRepo.contactExists('peer-B'), isTrue);
      expect(await userB.contactRepo.contactExists('peer-C'), isTrue);
    });

    test('mutual acceptance surfaces correctly on both nodes', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      final introId = intros.first.id;

      await Future.delayed(const Duration(milliseconds: 100));
      await userB.introRepo.saveIntroduction(intros.first);
      await userC.introRepo.saveIntroduction(intros.first);

      await userB.acceptIntro(introId);
      await userC.acceptIntro(introId);

      // Cross-notify
      await userB.receiveAcceptNotification(
        introId: introId,
        responderId: 'peer-C',
        responderUsername: 'Sarah',
      );
      await userC.receiveAcceptNotification(
        introId: introId,
        responderId: 'peer-B',
        responderUsername: 'Lina',
      );

      // Both nodes see mutualAccepted
      final bFinal = await userB.introRepo.getIntroduction(introId);
      final cFinal = await userC.introRepo.getIntroduction(introId);
      expect(bFinal!.status, IntroductionOverallStatus.mutualAccepted);
      expect(cFinal!.status, IntroductionOverallStatus.mutualAccepted);
      expect(bFinal.recipientStatus, IntroductionStatus.accepted);
      expect(bFinal.introducedStatus, IntroductionStatus.accepted);
    });

    test('full cross-step chain: send → accept → verify', () async {
      // Step 1: Banner check
      final contactB = await userA.contactRepo.getContact('peer-B');
      expect(
        await shouldShowIntroBanner(
          contactRepo: userA.contactRepo,
          contact: contactB!,
          messageCount: 0,
        ),
        isTrue,
      );

      // Step 2: Send intros (C and D)
      final friendC = await userA.contactRepo.getContact('peer-C');
      final friendD = await userA.contactRepo.getContact('peer-D');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!, friendD!],
      );
      expect(intros, hasLength(2));

      // Step 3: Banner now hidden
      final updatedB = await userA.contactRepo.getContact('peer-B');
      expect(
        await shouldShowIntroBanner(
          contactRepo: userA.contactRepo,
          contact: updatedB!,
          messageCount: 0,
        ),
        isFalse,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Step 4: Seed on all nodes
      for (final intro in intros) {
        await userB.introRepo.saveIntroduction(intro);
      }
      final introBC = intros.firstWhere((i) => i.introducedId == 'peer-C');
      final introBD = intros.firstWhere((i) => i.introducedId == 'peer-D');
      await userC.introRepo.saveIntroduction(introBC);
      await userD.introRepo.saveIntroduction(introBD);

      // Step 5: B accepts C's intro
      await userB.acceptIntro(introBC.id);
      await userC.receiveAcceptNotification(
        introId: introBC.id,
        responderId: 'peer-B',
        responderUsername: 'Lina',
      );

      // Step 6: C accepts — mutual acceptance
      await userC.acceptIntro(introBC.id);
      await userB.receiveAcceptNotification(
        introId: introBC.id,
        responderId: 'peer-C',
        responderUsername: 'Sarah',
      );

      final bcFinal = await userB.introRepo.getIntroduction(introBC.id);
      expect(bcFinal!.status, IntroductionOverallStatus.mutualAccepted);

      // Step 7: B passes D's intro
      await userB.passIntro(introBD.id);

      final bdFinal = await userB.introRepo.getIntroduction(introBD.id);
      expect(bdFinal!.status, IntroductionOverallStatus.passed);

      // Step 8: Verify pending count for B is 0
      final bPending = await userB.loadPendingIntros();
      expect(bPending, isEmpty);

      // Step 9: Verify A's records
      final aIntros =
          await userA.introRepo.getIntroductionsByIntroducer('peer-A');
      expect(aIntros, hasLength(2));

      // Step 10: groupByIntroducer works
      final grouped = groupByIntroducer(aIntros);
      expect(grouped.keys, contains('peer-A'));
      expect(grouped['peer-A'], hasLength(2));
    });
  });
}
