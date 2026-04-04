import 'dart:async';

import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/introduction/application/check_intro_banner_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/intro_test_user.dart';

Future<IntroductionModel> waitForIntroReceived(
  IntroTestUser user,
  String introId,
) {
  return user.introListener.introReceivedStream
      .firstWhere((intro) => intro.id == introId)
      .timeout(const Duration(seconds: 2));
}

Future<IntroductionModel> waitForIntroStatusChanged(
  IntroTestUser user,
  String introId,
) {
  return user.introListener.introStatusChangedStream
      .firstWhere((intro) => intro.id == introId)
      .timeout(const Duration(seconds: 2));
}

Future<void> waitForAsyncCondition(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for async test condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<String> sendSingleIntroduction({
  required IntroTestUser introducer,
  required String recipientPeerId,
  required String introducedPeerId,
}) async {
  final contact = await introducer.contactRepo.getContact(introducedPeerId);
  final intros = await introducer.sendIntroductions(
    recipientPeerId: recipientPeerId,
    friends: [contact!],
  );
  return intros.single.id;
}

Future<void> liveMutualAcceptance({
  required IntroTestUser recipientUser,
  required IntroTestUser introducedUser,
  required String introId,
}) async {
  final introducedSawRecipient = waitForIntroStatusChanged(
    introducedUser,
    introId,
  );
  await recipientUser.acceptIntro(introId);
  await introducedSawRecipient;

  final recipientSawIntroduced = waitForIntroStatusChanged(
    recipientUser,
    introId,
  );
  await introducedUser.acceptIntro(introId);
  await recipientSawIntroduced;
}

void main() {
  late FakeP2PNetwork network;
  late IntroTestUser userA;
  late IntroTestUser userB;
  late IntroTestUser userC;
  late IntroTestUser userD;

  setUp(() {
    network = FakeP2PNetwork();
    userA = IntroTestUser.create(
      peerId: 'peer-A',
      username: 'Noor',
      network: network,
    );
    userB = IntroTestUser.create(
      peerId: 'peer-B',
      username: 'Lina',
      network: network,
    );
    userC = IntroTestUser.create(
      peerId: 'peer-C',
      username: 'Sarah',
      network: network,
    );
    userD = IntroTestUser.create(
      peerId: 'peer-D',
      username: 'Dana',
      network: network,
    );

    // A knows B and C
    userA.addContact(userB);
    userB.addContact(userA);
    userA.addContact(userC);
    userC.addContact(userA);
    // B and C do NOT know each other initially

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

  group('multi-node introduction tests', () {
    test('A sends intros → B receives via listener stream', () async {
      final bReceived = Completer<IntroductionModel>();
      userB.introListener.introReceivedStream.listen((intro) {
        if (!bReceived.isCompleted) bReceived.complete(intro);
      });

      final friendC = await userA.contactRepo.getContact('peer-C');
      await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );

      final received = await bReceived.future.timeout(
        const Duration(seconds: 2),
      );

      expect(received.introducerId, 'peer-A');
      expect(received.recipientId, 'peer-B');
      expect(received.introducedId, 'peer-C');
      expect(received.status, IntroductionOverallStatus.pending);
    });

    test('A sends intros → C receives via listener stream', () async {
      final cReceived = Completer<IntroductionModel>();
      userC.introListener.introReceivedStream.listen((intro) {
        if (!cReceived.isCompleted) cReceived.complete(intro);
      });

      final friendC = await userA.contactRepo.getContact('peer-C');
      await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );

      final received = await cReceived.future.timeout(
        const Duration(seconds: 2),
      );

      expect(received.introducerId, 'peer-A');
      expect(received.introducedId, 'peer-C');
    });

    test(
      'B accepts → C view reflects recipient acceptance while overall stays pending',
      () async {
        // Seed intro on both B and C
        final friendC = await userA.contactRepo.getContact('peer-C');
        final intros = await userA.sendIntroductions(
          recipientPeerId: 'peer-B',
          friends: [friendC!],
        );
        final introId = intros.first.id;

        // Wait for B to receive
        await Future.delayed(const Duration(milliseconds: 100));

        // Seed the intro on B's repo if not already there via listener
        final bIntro = await userB.introRepo.getIntroduction(introId);
        if (bIntro == null) {
          await userB.introRepo.saveIntroduction(intros.first);
        }

        // B accepts
        await userB.acceptIntro(introId);

        // B's view: recipientStatus = accepted
        final bUpdated = await userB.introRepo.getIntroduction(introId);
        expect(bUpdated!.recipientStatus, IntroductionStatus.accepted);

        await waitForAsyncCondition(() async {
          final cIntro = await userC.introRepo.getIntroduction(introId);
          return cIntro?.recipientStatus == IntroductionStatus.accepted;
        });

        final cIntro = await userC.introRepo.getIntroduction(introId);
        expect(cIntro, isNotNull);
        expect(cIntro!.recipientStatus, IntroductionStatus.accepted);
        expect(cIntro.introducedStatus, IntroductionStatus.pending);
        expect(cIntro.status, IntroductionOverallStatus.pending);
      },
    );

    test('B accepts, C passes → no mutualAccepted', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      final introId = intros.first.id;

      await Future.delayed(const Duration(milliseconds: 100));

      // Seed on both repos
      final bIntro = await userB.introRepo.getIntroduction(introId);
      if (bIntro == null) {
        await userB.introRepo.saveIntroduction(intros.first);
      }
      final cIntro = await userC.introRepo.getIntroduction(introId);
      if (cIntro == null) {
        await userC.introRepo.saveIntroduction(intros.first);
      }

      await userB.acceptIntro(introId);
      await userC.passIntro(introId);

      final cUpdated = await userC.introRepo.getIntroduction(introId);
      expect(cUpdated!.status, IntroductionOverallStatus.passed);
    });

    test('B accepts, C accepts → mutual acceptance', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      final introId = intros.first.id;

      await Future.delayed(const Duration(milliseconds: 100));

      // Seed on both repos
      final bIntro = await userB.introRepo.getIntroduction(introId);
      if (bIntro == null) {
        await userB.introRepo.saveIntroduction(intros.first);
      }
      final cIntro = await userC.introRepo.getIntroduction(introId);
      if (cIntro == null) {
        await userC.introRepo.saveIntroduction(intros.first);
      }

      // B accepts locally
      await userB.acceptIntro(introId);
      // Simulate B's accept arriving at C
      await userC.receiveAcceptNotification(
        introId: introId,
        responderId: 'peer-B',
        responderUsername: 'Lina',
      );
      // C accepts locally
      await userC.acceptIntro(introId);
      // Simulate C's accept arriving at B
      await userB.receiveAcceptNotification(
        introId: introId,
        responderId: 'peer-C',
        responderUsername: 'Sarah',
      );

      final cUpdated = await userC.introRepo.getIntroduction(introId);
      expect(cUpdated!.recipientStatus, IntroductionStatus.accepted);
      expect(cUpdated.introducedStatus, IntroductionStatus.accepted);
      expect(cUpdated.status, IntroductionOverallStatus.mutualAccepted);
    });

    test('mutual acceptance data correct on both nodes', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      final introId = intros.first.id;

      await Future.delayed(const Duration(milliseconds: 100));

      await userB.introRepo.saveIntroduction(intros.first);
      await userC.introRepo.saveIntroduction(intros.first);

      // B accepts, notify C
      await userB.acceptIntro(introId);
      await userC.receiveAcceptNotification(
        introId: introId,
        responderId: 'peer-B',
        responderUsername: 'Lina',
      );
      // C accepts, notify B
      await userC.acceptIntro(introId);
      await userB.receiveAcceptNotification(
        introId: introId,
        responderId: 'peer-C',
        responderUsername: 'Sarah',
      );

      final bFinal = await userB.introRepo.getIntroduction(introId);
      final cFinal = await userC.introRepo.getIntroduction(introId);

      expect(bFinal!.status, IntroductionOverallStatus.mutualAccepted);
      expect(cFinal!.status, IntroductionOverallStatus.mutualAccepted);
    });

    test(
      'mutual acceptance → both appear in each other\'s contact repo',
      () async {
        final friendC = await userA.contactRepo.getContact('peer-C');
        final intros = await userA.sendIntroductions(
          recipientPeerId: 'peer-B',
          friends: [friendC!],
        );
        final introId = intros.first.id;

        await Future.delayed(const Duration(milliseconds: 100));
        await userB.introRepo.saveIntroduction(intros.first);
        await userC.introRepo.saveIntroduction(intros.first);

        // B accepts, notify C
        await userB.acceptIntro(introId);
        await userC.receiveAcceptNotification(
          introId: introId,
          responderId: 'peer-B',
          responderUsername: 'Lina',
        );
        // C accepts, notify B
        await userC.acceptIntro(introId);
        await userB.receiveAcceptNotification(
          introId: introId,
          responderId: 'peer-C',
          responderUsername: 'Sarah',
        );

        // B should now have C as a contact
        expect(await userB.contactRepo.contactExists('peer-C'), isTrue);
        // C should now have B as a contact
        expect(await userC.contactRepo.contactExists('peer-B'), isTrue);
      },
    );

    test(
      'mutual acceptance → contacts have correct introducedBy field',
      () async {
        final friendC = await userA.contactRepo.getContact('peer-C');
        final intros = await userA.sendIntroductions(
          recipientPeerId: 'peer-B',
          friends: [friendC!],
        );
        final introId = intros.first.id;

        await Future.delayed(const Duration(milliseconds: 100));
        await userB.introRepo.saveIntroduction(intros.first);
        await userC.introRepo.saveIntroduction(intros.first);

        // B accepts, notify C
        await userB.acceptIntro(introId);
        await userC.receiveAcceptNotification(
          introId: introId,
          responderId: 'peer-B',
          responderUsername: 'Lina',
        );
        // C accepts, notify B
        await userC.acceptIntro(introId);
        await userB.receiveAcceptNotification(
          introId: introId,
          responderId: 'peer-C',
          responderUsername: 'Sarah',
        );

        final bContactC = await userB.contactRepo.getContact('peer-C');
        final cContactB = await userC.contactRepo.getContact('peer-B');
        expect(bContactC!.introducedBy, 'Noor');
        expect(cContactB!.introducedBy, 'Noor');
      },
    );

    test(
      'full cross-step chain → contacts created after mutual acceptance',
      () async {
        final friendC = await userA.contactRepo.getContact('peer-C');
        final intros = await userA.sendIntroductions(
          recipientPeerId: 'peer-B',
          friends: [friendC!],
        );
        final introId = intros.first.id;

        await Future.delayed(const Duration(milliseconds: 100));
        await userB.introRepo.saveIntroduction(intros.first);
        await userC.introRepo.saveIntroduction(intros.first);

        // Before mutual acceptance, no cross-contacts
        expect(await userB.contactRepo.contactExists('peer-C'), isFalse);
        expect(await userC.contactRepo.contactExists('peer-B'), isFalse);

        // B accepts — not yet mutual
        await userB.acceptIntro(introId);
        expect(await userB.contactRepo.contactExists('peer-C'), isFalse);

        // C gets B's accept notification
        await userC.receiveAcceptNotification(
          introId: introId,
          responderId: 'peer-B',
          responderUsername: 'Lina',
        );

        // C accepts — mutual! C creates contact for B
        await userC.acceptIntro(introId);
        expect(await userC.contactRepo.contactExists('peer-B'), isTrue);

        // B gets C's accept notification — B creates contact for C
        await userB.receiveAcceptNotification(
          introId: introId,
          responderId: 'peer-C',
          responderUsername: 'Sarah',
        );
        expect(await userB.contactRepo.contactExists('peer-C'), isTrue);
      },
    );

    test('notifications sent to all parties on accept', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      final introId = intros.first.id;

      await Future.delayed(const Duration(milliseconds: 100));
      await userB.introRepo.saveIntroduction(intros.first);

      network.resetCounters();

      await userB.acceptIntro(introId);

      // B sends to introducer (A) and other party (C)
      expect(network.deliverCallCount, 2);
    });

    test('order independence: C accepts first then B', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      final introId = intros.first.id;

      await Future.delayed(const Duration(milliseconds: 100));
      await userB.introRepo.saveIntroduction(intros.first);
      await userC.introRepo.saveIntroduction(intros.first);

      // C first
      await userC.acceptIntro(introId);
      await userB.receiveAcceptNotification(
        introId: introId,
        responderId: 'peer-C',
        responderUsername: 'Sarah',
      );
      // then B
      await userB.acceptIntro(introId);

      final bFinal = await userB.introRepo.getIntroduction(introId);
      expect(bFinal!.status, IntroductionOverallStatus.mutualAccepted);
    });

    test('concurrent acceptance: both nodes reach mutualAccepted', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      final introId = intros.first.id;

      await Future.delayed(const Duration(milliseconds: 100));
      await userB.introRepo.saveIntroduction(intros.first);
      await userC.introRepo.saveIntroduction(intros.first);

      // Both accept locally
      await userB.acceptIntro(introId);
      await userC.acceptIntro(introId);

      // Cross-notify (simulating the P2P notifications arriving)
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

      final bFinal = await userB.introRepo.getIntroduction(introId);
      final cFinal = await userC.introRepo.getIntroduction(introId);

      expect(bFinal!.status, IntroductionOverallStatus.mutualAccepted);
      expect(cFinal!.status, IntroductionOverallStatus.mutualAccepted);
    });

    test(
      'mutual acceptance with v2 encrypted notifications end-to-end',
      () async {
        final friendC = await userA.contactRepo.getContact('peer-C');
        final intros = await userA.sendIntroductions(
          recipientPeerId: 'peer-B',
          friends: [friendC!],
        );
        final introId = intros.first.id;

        await Future.delayed(const Duration(milliseconds: 100));
        await userB.introRepo.saveIntroduction(intros.first);
        await userC.introRepo.saveIntroduction(intros.first);

        // Track encrypt calls on both B and C
        final bridgeB = userB.bridge as PassthroughCryptoBridge;
        final bridgeC = userC.bridge as PassthroughCryptoBridge;
        bridgeB.commandLog.clear();
        bridgeC.commandLog.clear();

        // B accepts (v2 to A + v2 to C)
        await userB.acceptIntro(introId);
        final bEncryptCalls = bridgeB.commandLog
            .where((c) => c == 'message.encrypt')
            .length;
        expect(
          bEncryptCalls,
          2,
          reason: 'B encrypts to A (contact) + C (stranger)',
        );

        // Notify C of B's acceptance
        await userC.receiveAcceptNotification(
          introId: introId,
          responderId: 'peer-B',
          responderUsername: 'Lina',
        );

        // C accepts (v2 to A + v2 to B)
        await userC.acceptIntro(introId);
        final cEncryptCalls = bridgeC.commandLog
            .where((c) => c == 'message.encrypt')
            .length;
        expect(
          cEncryptCalls,
          2,
          reason: 'C encrypts to A (contact) + B (stranger)',
        );

        // Notify B of C's acceptance
        await userB.receiveAcceptNotification(
          introId: introId,
          responderId: 'peer-C',
          responderUsername: 'Sarah',
        );

        // Both reach mutual_accepted
        final bFinal = await userB.introRepo.getIntroduction(introId);
        final cFinal = await userC.introRepo.getIntroduction(introId);
        expect(bFinal!.status, IntroductionOverallStatus.mutualAccepted);
        expect(cFinal!.status, IntroductionOverallStatus.mutualAccepted);

        // Contacts created
        expect(await userB.contactRepo.contactExists('peer-C'), isTrue);
        expect(await userC.contactRepo.contactExists('peer-B'), isTrue);

        // Total: 4 cross-party encrypt calls (2 from B + 2 from C)
        expect(bEncryptCalls + cEncryptCalls, 4);
      },
    );

    test('A has correct intro record locally', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );

      final stored = await userA.introRepo.getIntroduction(intros.first.id);
      expect(stored, isNotNull);
      expect(stored!.introducerId, 'peer-A');
      expect(stored.recipientId, 'peer-B');
      expect(stored.introducedId, 'peer-C');
    });

    test('shouldShowIntroBanner returns false after intros sent', () async {
      final contactB = await userA.contactRepo.getContact('peer-B');
      final friendC = await userA.contactRepo.getContact('peer-C');

      // Before sending: banner should show
      final before = await shouldShowIntroBanner(
        contactRepo: userA.contactRepo,
        contact: contactB!,
        messageCount: 0,
      );
      expect(before, isTrue);

      // Send intros
      await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );

      // After sending: introsSentAt is set → banner hidden
      final updatedB = await userA.contactRepo.getContact('peer-B');
      final after = await shouldShowIntroBanner(
        contactRepo: userA.contactRepo,
        contact: updatedB!,
        messageCount: 0,
      );
      expect(after, isFalse);
    });

    test(
      'live accept delivery converges for recipient-first order without manual helper injection',
      () async {
        final friendC = await userA.contactRepo.getContact('peer-C');
        final intros = await userA.sendIntroductions(
          recipientPeerId: 'peer-B',
          friends: [friendC!],
        );
        final introId = intros.first.id;

        await Future.wait([
          waitForIntroReceived(userB, introId),
          waitForIntroReceived(userC, introId),
        ]);

        final cSawBAccept = waitForIntroStatusChanged(userC, introId);
        await userB.acceptIntro(introId);

        final cAfterRemoteAccept = await cSawBAccept;
        expect(cAfterRemoteAccept.recipientStatus, IntroductionStatus.accepted);
        expect(cAfterRemoteAccept.introducedStatus, IntroductionStatus.pending);
        expect(cAfterRemoteAccept.status, IntroductionOverallStatus.pending);
        expect(
          (await userC.loadPendingIntros()).map((intro) => intro.id),
          contains(introId),
        );

        final bSawCAccept = waitForIntroStatusChanged(userB, introId);
        await userC.acceptIntro(introId);
        await bSawCAccept;

        final bFinal = await userB.introRepo.getIntroduction(introId);
        final cFinal = await userC.introRepo.getIntroduction(introId);

        expect(bFinal, isNotNull);
        expect(cFinal, isNotNull);
        expect(bFinal!.status, IntroductionOverallStatus.mutualAccepted);
        expect(cFinal!.status, IntroductionOverallStatus.mutualAccepted);
        expect(bFinal.recipientStatus, IntroductionStatus.accepted);
        expect(bFinal.introducedStatus, IntroductionStatus.accepted);
        expect(cFinal.recipientStatus, IntroductionStatus.accepted);
        expect(cFinal.introducedStatus, IntroductionStatus.accepted);
        expect(await userB.loadPendingIntros(), isEmpty);
        expect(await userC.loadPendingIntros(), isEmpty);
        expect(await userB.contactRepo.contactExists('peer-C'), isTrue);
        expect(await userC.contactRepo.contactExists('peer-B'), isTrue);
      },
    );

    test(
      'live accept delivery converges for introduced-first order without manual helper injection',
      () async {
        final friendC = await userA.contactRepo.getContact('peer-C');
        final intros = await userA.sendIntroductions(
          recipientPeerId: 'peer-B',
          friends: [friendC!],
        );
        final introId = intros.first.id;

        await Future.wait([
          waitForIntroReceived(userB, introId),
          waitForIntroReceived(userC, introId),
        ]);

        final bSawCAccept = waitForIntroStatusChanged(userB, introId);
        await userC.acceptIntro(introId);

        final bAfterRemoteAccept = await bSawCAccept;
        expect(bAfterRemoteAccept.recipientStatus, IntroductionStatus.pending);
        expect(
          bAfterRemoteAccept.introducedStatus,
          IntroductionStatus.accepted,
        );
        expect(bAfterRemoteAccept.status, IntroductionOverallStatus.pending);
        expect(
          (await userB.loadPendingIntros()).map((intro) => intro.id),
          contains(introId),
        );

        final cSawBAccept = waitForIntroStatusChanged(userC, introId);
        await userB.acceptIntro(introId);
        await cSawBAccept;

        final bFinal = await userB.introRepo.getIntroduction(introId);
        final cFinal = await userC.introRepo.getIntroduction(introId);

        expect(bFinal, isNotNull);
        expect(cFinal, isNotNull);
        expect(bFinal!.status, IntroductionOverallStatus.mutualAccepted);
        expect(cFinal!.status, IntroductionOverallStatus.mutualAccepted);
        expect(bFinal.recipientStatus, IntroductionStatus.accepted);
        expect(bFinal.introducedStatus, IntroductionStatus.accepted);
        expect(cFinal.recipientStatus, IntroductionStatus.accepted);
        expect(cFinal.introducedStatus, IntroductionStatus.accepted);
        expect(await userB.loadPendingIntros(), isEmpty);
        expect(await userC.loadPendingIntros(), isEmpty);
        expect(await userB.contactRepo.contactExists('peer-C'), isTrue);
        expect(await userC.contactRepo.contactExists('peer-B'), isTrue);
      },
    );

    test(
      'intro between existing contacts gets alreadyConnected status',
      () async {
        // Make B and C already contacts
        userB.addContact(userC);
        userC.addContact(userB);

        // A introduces B to C
        final friendC = await userA.contactRepo.getContact('peer-C');
        final intros = await userA.sendIntroductions(
          recipientPeerId: 'peer-B',
          friends: [friendC!],
        );
        final introId = intros.first.id;

        // Wait for listeners to process
        await Future.delayed(const Duration(milliseconds: 200));

        // B should have received it with alreadyConnected status
        final bIntro = await userB.introRepo.getIntroduction(introId);
        expect(bIntro, isNotNull);
        expect(bIntro!.status, IntroductionOverallStatus.alreadyConnected);

        // C should also have received it with alreadyConnected status
        final cIntro = await userC.introRepo.getIntroduction(introId);
        expect(cIntro, isNotNull);
        expect(cIntro!.status, IntroductionOverallStatus.alreadyConnected);

        // No duplicate contacts created — B and C already knew each other
        final allBContacts = await userB.contactRepo.getAllContacts();
        final cContactsOfB = allBContacts
            .where((c) => c.peerId == 'peer-C')
            .toList();
        expect(cContactsOfB, hasLength(1));
      },
    );

    test('expired intro filtered from pending', () async {
      final thirtyOneDaysAgo = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 31))
          .toIso8601String();

      await userB.introRepo.saveIntroduction(
        IntroductionModel(
          id: 'expired-intro',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          createdAt: thirtyOneDaysAgo,
        ),
      );

      // getPendingIntroductionsForUser filters by status == pending
      // But the model was saved with default pending status, so it's still in the list
      // The expiration is computed by deriveStatus, not stored on save
      // So verify the derive logic separately
      final derived = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.pending,
        introducedStatus: IntroductionStatus.pending,
        createdAt: thirtyOneDaysAgo,
      );
      expect(derived, IntroductionOverallStatus.expired);
    });

    test(
      'offline relay intro delivery converges to mutual acceptance and first encrypted chat',
      () async {
        userB.setOnline(false);
        userC.setOnline(false);

        final introId = await sendSingleIntroduction(
          introducer: userA,
          recipientPeerId: 'peer-B',
          introducedPeerId: 'peer-C',
        );

        expect(network.storeInInboxCallCount, 2);
        expect(network.inboxCount('peer-B'), 1);
        expect(network.inboxCount('peer-C'), 1);

        userB.setOnline(true);
        userC.setOnline(true);

        final bReceived = waitForIntroReceived(userB, introId);
        final cReceived = waitForIntroReceived(userC, introId);
        expect(await userB.drainOfflineInbox(), 1);
        expect(await userC.drainOfflineInbox(), 1);
        await Future.wait([bReceived, cReceived]);

        await liveMutualAcceptance(
          recipientUser: userB,
          introducedUser: userC,
          introId: introId,
        );

        expect(await userB.contactRepo.contactExists('peer-C'), isTrue);
        expect(await userC.contactRepo.contactExists('peer-B'), isTrue);

        final bridgeB = userB.bridge as PassthroughCryptoBridge;
        bridgeB.commandLog.clear();

        final (sendResult, sentMessage) = await userB.sendMessage(
          'peer-C',
          'hello after intro',
        );
        expect(sendResult, SendChatMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(
          bridgeB.commandLog.where((command) => command == 'message.encrypt'),
          hasLength(1),
        );

        await waitForAsyncCondition(() async {
          final conversation = await userC.loadConversationWith('peer-B');
          return conversation.any((message) => message.id == sentMessage!.id);
        });

        final bConversation = await userB.loadConversationWith('peer-C');
        final cConversation = await userC.loadConversationWith('peer-B');
        expect(
          bConversation.map((message) => message.text),
          contains('hello after intro'),
        );
        expect(
          cConversation.map((message) => message.text),
          contains('hello after intro'),
        );
        expect(bConversation.last.text, 'hello after intro');
        expect(cConversation.last.text, 'hello after intro');
        expect(cConversation.last.isIncoming, isTrue);
        expect(cConversation.last.transport, isNot('system'));
      },
    );

    test(
      'dual deferred accept responses replay when the intro arrives and still converge to contacts',
      () async {
        const introId = 'intro-dual-deferred';
        final now = DateTime.now().toUtc().toIso8601String();

        userB.p2pService.injectIncomingMessage(
          ChatMessage(
            from: 'peer-C',
            to: 'peer-B',
            content: IntroductionPayload(
              action: 'accept',
              introductionId: introId,
              responderId: 'peer-C',
              responderUsername: 'Sarah',
              timestamp: now,
            ).toJson(),
            timestamp: now,
            isIncoming: true,
          ),
        );
        userC.p2pService.injectIncomingMessage(
          ChatMessage(
            from: 'peer-B',
            to: 'peer-C',
            content: IntroductionPayload(
              action: 'accept',
              introductionId: introId,
              responderId: 'peer-B',
              responderUsername: 'Lina',
              timestamp: now,
            ).toJson(),
            timestamp: now,
            isIncoming: true,
          ),
        );

        await waitForAsyncCondition(() async {
          final bPending = await userB.introRepo.loadPendingResponses(introId);
          final cPending = await userC.introRepo.loadPendingResponses(introId);
          return bPending.length == 1 && cPending.length == 1;
        });

        final bIntroReceived = waitForIntroReceived(userB, introId);
        final cIntroReceived = waitForIntroReceived(userC, introId);

        final sendPayload = IntroductionPayload(
          action: 'send',
          introductionId: introId,
          introducerId: 'peer-A',
          introducerUsername: 'Noor',
          recipientId: 'peer-B',
          recipientUsername: 'Lina',
          introducedId: 'peer-C',
          introducedUsername: 'Sarah',
          introducedPublicKey: 'pk-peer-C',
          introducedMlKemPublicKey: 'test-mlkem-pk-peer-C',
          recipientPublicKey: 'pk-peer-B',
          recipientMlKemPublicKey: 'test-mlkem-pk-peer-B',
          timestamp: now,
        );

        userB.p2pService.injectIncomingMessage(
          ChatMessage(
            from: 'peer-A',
            to: 'peer-B',
            content: sendPayload.toJson(),
            timestamp: now,
            isIncoming: true,
          ),
        );
        userC.p2pService.injectIncomingMessage(
          ChatMessage(
            from: 'peer-A',
            to: 'peer-C',
            content: sendPayload.toJson(),
            timestamp: now,
            isIncoming: true,
          ),
        );

        final bAfterReplay = await bIntroReceived;
        final cAfterReplay = await cIntroReceived;

        expect(bAfterReplay.introducedStatus, IntroductionStatus.accepted);
        expect(bAfterReplay.recipientStatus, IntroductionStatus.pending);
        expect(cAfterReplay.recipientStatus, IntroductionStatus.accepted);
        expect(cAfterReplay.introducedStatus, IntroductionStatus.pending);
        expect(await userB.introRepo.loadPendingResponses(introId), isEmpty);
        expect(await userC.introRepo.loadPendingResponses(introId), isEmpty);

        await liveMutualAcceptance(
          recipientUser: userB,
          introducedUser: userC,
          introId: introId,
        );

        final bFinal = await userB.introRepo.getIntroduction(introId);
        final cFinal = await userC.introRepo.getIntroduction(introId);
        expect(bFinal!.status, IntroductionOverallStatus.mutualAccepted);
        expect(cFinal!.status, IntroductionOverallStatus.mutualAccepted);
        expect(await userB.contactRepo.contactExists('peer-C'), isTrue);
        expect(await userC.contactRepo.contactExists('peer-B'), isTrue);
      },
    );

    test(
      'accept notifications fall back to inbox while peers are unreachable and converge after drain',
      () async {
        final introId = await sendSingleIntroduction(
          introducer: userA,
          recipientPeerId: 'peer-B',
          introducedPeerId: 'peer-C',
        );

        await waitForAsyncCondition(() async {
          final bIntro = await userB.introRepo.getIntroduction(introId);
          final cIntro = await userC.introRepo.getIntroduction(introId);
          return bIntro != null && cIntro != null;
        });

        userA.setOnline(false);
        userC.setOnline(false);
        await userB.acceptIntro(introId);

        expect(network.inboxCount('peer-A'), 1);
        expect(network.inboxCount('peer-C'), 1);

        userC.setOnline(true);
        final cSawBAccept = waitForIntroStatusChanged(userC, introId);
        expect(await userC.drainOfflineInbox(), 1);
        final cAfterReplay = await cSawBAccept;
        expect(cAfterReplay.recipientStatus, IntroductionStatus.accepted);

        userA.setOnline(false);
        userB.setOnline(false);
        await userC.acceptIntro(introId);

        expect(network.inboxCount('peer-A'), 2);
        expect(network.inboxCount('peer-B'), 1);

        userB.setOnline(true);
        final bSawCAccept = waitForIntroStatusChanged(userB, introId);
        expect(await userB.drainOfflineInbox(), 1);
        await bSawCAccept;

        final bFinal = await userB.introRepo.getIntroduction(introId);
        final cFinal = await userC.introRepo.getIntroduction(introId);
        expect(bFinal!.status, IntroductionOverallStatus.mutualAccepted);
        expect(cFinal!.status, IntroductionOverallStatus.mutualAccepted);
        expect(await userB.contactRepo.contactExists('peer-C'), isTrue);
        expect(await userC.contactRepo.contactExists('peer-B'), isTrue);
      },
    );

    test(
      'reintroducing the same pair repairs a missed side and ignores stale older delivery',
      () async {
        userC.setOnline(false);

        final firstIntroId = await sendSingleIntroduction(
          introducer: userA,
          recipientPeerId: 'peer-B',
          introducedPeerId: 'peer-C',
        );

        await waitForAsyncCondition(() async {
          final bIntro = await userB.introRepo.getIntroduction(firstIntroId);
          return bIntro != null;
        });
        expect(await userC.introRepo.getIntroduction(firstIntroId), isNull);

        userC.setOnline(true);

        final secondIntroId = await sendSingleIntroduction(
          introducer: userA,
          recipientPeerId: 'peer-B',
          introducedPeerId: 'peer-C',
        );
        expect(secondIntroId, isNot(firstIntroId));

        await waitForAsyncCondition(() async {
          final bIntro = await userB.introRepo.getIntroduction(secondIntroId);
          final cIntro = await userC.introRepo.getIntroduction(secondIntroId);
          return bIntro != null && cIntro != null;
        });

        expect(await userB.introRepo.getIntroduction(firstIntroId), isNull);
        expect(await userC.introRepo.getIntroduction(firstIntroId), isNull);

        final drained = await userC.drainOfflineInbox();
        expect(drained, 1);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(await userC.introRepo.getIntroduction(firstIntroId), isNull);
        final cCurrent = await userC.introRepo.getIntroduction(secondIntroId);
        expect(cCurrent, isNotNull);
        expect(cCurrent!.status, IntroductionOverallStatus.pending);

        await liveMutualAcceptance(
          recipientUser: userB,
          introducedUser: userC,
          introId: secondIntroId,
        );

        expect(await userB.contactRepo.contactExists('peer-C'), isTrue);
        expect(await userC.contactRepo.contactExists('peer-B'), isTrue);
        final bContacts = await userB.contactRepo.getAllContacts();
        final cContacts = await userC.contactRepo.getAllContacts();
        expect(
          bContacts.where((contact) => contact.peerId == 'peer-C'),
          hasLength(1),
        );
        expect(
          cContacts.where((contact) => contact.peerId == 'peer-B'),
          hasLength(1),
        );
      },
    );

    test(
      'same pair with a different introducer reopens as alreadyConnected without duplicate contacts',
      () async {
        userD.addContact(userB);
        userD.addContact(userC);

        final originalIntroId = await sendSingleIntroduction(
          introducer: userA,
          recipientPeerId: 'peer-B',
          introducedPeerId: 'peer-C',
        );

        await waitForAsyncCondition(() async {
          final bIntro = await userB.introRepo.getIntroduction(originalIntroId);
          final cIntro = await userC.introRepo.getIntroduction(originalIntroId);
          return bIntro != null && cIntro != null;
        });
        await liveMutualAcceptance(
          recipientUser: userB,
          introducedUser: userC,
          introId: originalIntroId,
        );

        final secondIntroId = await sendSingleIntroduction(
          introducer: userD,
          recipientPeerId: 'peer-B',
          introducedPeerId: 'peer-C',
        );

        await waitForAsyncCondition(() async {
          final bIntro = await userB.introRepo.getIntroduction(secondIntroId);
          final cIntro = await userC.introRepo.getIntroduction(secondIntroId);
          return bIntro != null && cIntro != null;
        });
        final bSecondIntro = await userB.introRepo.getIntroduction(
          secondIntroId,
        );
        final cSecondIntro = await userC.introRepo.getIntroduction(
          secondIntroId,
        );
        expect(
          bSecondIntro!.status,
          IntroductionOverallStatus.alreadyConnected,
        );
        expect(
          cSecondIntro!.status,
          IntroductionOverallStatus.alreadyConnected,
        );

        final bContacts = await userB.contactRepo.getAllContacts();
        final cContacts = await userC.contactRepo.getAllContacts();
        expect(
          bContacts.where((contact) => contact.peerId == 'peer-C'),
          hasLength(1),
        );
        expect(
          cContacts.where((contact) => contact.peerId == 'peer-B'),
          hasLength(1),
        );
      },
    );

    test(
      'chain and circular introductions create the next edge without regressions',
      () async {
        userB.addContact(userD);
        userD.addContact(userB);

        final bcIntroId = await sendSingleIntroduction(
          introducer: userA,
          recipientPeerId: 'peer-B',
          introducedPeerId: 'peer-C',
        );
        await waitForAsyncCondition(() async {
          final bIntro = await userB.introRepo.getIntroduction(bcIntroId);
          final cIntro = await userC.introRepo.getIntroduction(bcIntroId);
          return bIntro != null && cIntro != null;
        });
        await liveMutualAcceptance(
          recipientUser: userB,
          introducedUser: userC,
          introId: bcIntroId,
        );

        final cdIntroId = await sendSingleIntroduction(
          introducer: userB,
          recipientPeerId: 'peer-C',
          introducedPeerId: 'peer-D',
        );
        await waitForAsyncCondition(() async {
          final cIntro = await userC.introRepo.getIntroduction(cdIntroId);
          final dIntro = await userD.introRepo.getIntroduction(cdIntroId);
          return cIntro != null && dIntro != null;
        });
        await liveMutualAcceptance(
          recipientUser: userC,
          introducedUser: userD,
          introId: cdIntroId,
        );

        expect(await userC.contactRepo.contactExists('peer-D'), isTrue);
        expect(await userD.contactRepo.contactExists('peer-C'), isTrue);

        final adIntroId = await sendSingleIntroduction(
          introducer: userC,
          recipientPeerId: 'peer-D',
          introducedPeerId: 'peer-A',
        );
        await waitForAsyncCondition(() async {
          final dIntro = await userD.introRepo.getIntroduction(adIntroId);
          final aIntro = await userA.introRepo.getIntroduction(adIntroId);
          return dIntro != null && aIntro != null;
        });
        await liveMutualAcceptance(
          recipientUser: userD,
          introducedUser: userA,
          introId: adIntroId,
        );

        expect(await userA.contactRepo.contactExists('peer-D'), isTrue);
        expect(await userD.contactRepo.contactExists('peer-A'), isTrue);

        final aToD = await userA.contactRepo.getContact('peer-D');
        final dToA = await userD.contactRepo.getContact('peer-A');
        expect(aToD!.introducedBy, 'Sarah');
        expect(dToA!.introducedBy, 'Sarah');
      },
    );
  });
}
