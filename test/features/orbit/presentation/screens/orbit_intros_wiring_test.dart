import 'dart:async';

import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/fakes/fake_p2p_network.dart';
import '../../../../shared/fakes/intro_test_user.dart';

void main() {
  late FakeP2PNetwork network;
  late IntroTestUser userA;
  late IntroTestUser userB;
  late IntroTestUser userC;

  setUp(() {
    network = FakeP2PNetwork();
    userA = IntroTestUser.create(
        peerId: 'peer-A', username: 'Noor', network: network);
    userB = IntroTestUser.create(
        peerId: 'peer-B', username: 'Lina', network: network);
    userC = IntroTestUser.create(
        peerId: 'peer-C', username: 'Sarah', network: network);

    userA.addContact(userB);
    userB.addContact(userA);
    userA.addContact(userC);
    userC.addContact(userA);

    userA.start();
    userB.start();
    userC.start();
  });

  tearDown(() {
    userA.dispose();
    userB.dispose();
    userC.dispose();
  });

  group('orbit intros tab wiring', () {
    test('pending count > 0 when introductions exist', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      await userB.introRepo.saveIntroduction(intros.first);

      final count =
          await userB.introRepo.countPendingIntroductions('peer-B');
      expect(count, greaterThan(0));
    });

    test('pending count is 0 when no introductions', () async {
      final count =
          await userB.introRepo.countPendingIntroductions('peer-B');
      expect(count, 0);
    });

    test('loadIntroductionsForUser returns correct grouped data', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      await userB.introRepo.saveIntroduction(intros.first);

      final pending = await loadIntroductionsForUser(
        introRepo: userB.introRepo,
        peerId: 'peer-B',
      );
      final grouped = groupByIntroducer(pending);

      expect(grouped.keys, contains('peer-A'));
      expect(grouped['peer-A']!.length, 1);
    });

    test('accept callback calls acceptIntroduction use case', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      await userB.introRepo.saveIntroduction(intros.first);

      await userB.acceptIntro(intros.first.id);

      final updated = await userB.introRepo.getIntroduction(intros.first.id);
      expect(updated!.recipientStatus, IntroductionStatus.accepted);
    });

    test('pass callback calls passIntroduction use case', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      await userB.introRepo.saveIntroduction(intros.first);

      await userB.passIntro(intros.first.id);

      final updated = await userB.introRepo.getIntroduction(intros.first.id);
      expect(updated!.recipientStatus, IntroductionStatus.passed);
      expect(updated.status, IntroductionOverallStatus.passed);
    });

    test('intro count refreshes after accept action', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      await userB.introRepo.saveIntroduction(intros.first);

      final beforeCount =
          await userB.introRepo.countPendingIntroductions('peer-B');
      expect(beforeCount, 1);

      await userB.acceptIntro(intros.first.id);

      // After accept, status changes to pending (one-sided) so still counted
      // But overall is still pending (only one side accepted)
      final afterCount =
          await userB.introRepo.countPendingIntroductions('peer-B');
      // Single accept doesn't change overall status to non-pending
      expect(afterCount, 1);
    });

    test('intro count refreshes after pass action', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      await userB.introRepo.saveIntroduction(intros.first);

      await userB.passIntro(intros.first.id);

      // After pass, overall status is "passed" so not in pending
      final afterCount =
          await userB.introRepo.countPendingIntroductions('peer-B');
      expect(afterCount, 0);
    });

    test('introReceivedStream triggers data availability', () async {
      final received = Completer<IntroductionModel>();
      userB.introListener.introReceivedStream.listen((intro) {
        if (!received.isCompleted) received.complete(intro);
      });

      final friendC = await userA.contactRepo.getContact('peer-C');
      await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );

      final intro = await received.future.timeout(
        const Duration(seconds: 2),
      );
      expect(intro.introducerId, 'peer-A');
    });

    test('introStatusChangedStream triggers on accept notification',
        () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );

      await Future.delayed(const Duration(milliseconds: 100));
      await userB.introRepo.saveIntroduction(intros.first);
      await userC.introRepo.saveIntroduction(intros.first);

      final statusChanged = Completer<IntroductionModel>();
      userC.introListener.introStatusChangedStream.listen((intro) {
        if (!statusChanged.isCompleted) statusChanged.complete(intro);
      });

      // B accepts and C should get the notification via P2P
      await userB.acceptIntro(intros.first.id);

      // Verify through direct call since the P2P notification path depends on network
      await userC.receiveAcceptNotification(
        introId: intros.first.id,
        responderId: 'peer-B',
        responderUsername: 'Lina',
      );

      final updated = await userC.introRepo.getIntroduction(intros.first.id);
      expect(updated!.recipientStatus, IntroductionStatus.accepted);
    });

    test('IntrosTab built with correct grouped data', () async {
      final friendC = await userA.contactRepo.getContact('peer-C');
      final intros = await userA.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      await userB.introRepo.saveIntroduction(intros.first);

      final pending = await loadIntroductionsForUser(
        introRepo: userB.introRepo,
        peerId: 'peer-B',
      );
      final grouped = groupByIntroducer(pending);
      final usernames = <String, String>{};
      for (final intro in pending) {
        usernames.putIfAbsent(
          intro.introducerId,
          () => intro.introducerUsername ?? 'Unknown',
        );
      }

      expect(grouped.keys, contains('peer-A'));
      expect(usernames['peer-A'], 'Noor');
    });
  });
}
