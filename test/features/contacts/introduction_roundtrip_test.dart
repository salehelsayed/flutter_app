import 'package:flutter_app/features/introduction/application/resolve_unknown_inbox_sender_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/fake_p2p_network.dart';
import '../../shared/fakes/intro_test_user.dart';

/// 124 Phase 8 — introduction_roundtrip coverage closer.
///
/// Exercises the full introduction round-trip end-to-end through the live
/// harness — `sendIntroductions` (SendIntroduction) →
/// `handleIncomingIntroduction` on both peers reaching mutual acceptance →
/// then `resolveUnknownInboxSender` resolving the introduced peer when a
/// later inbox chat arrives. The unit suites cover each leg in isolation;
/// this binds the send leg, the live accept leg, and the unknown-sender
/// resolver leg together so a regression in any wiring point is caught.
Future<IntroductionModel> _waitForIntroReceived(
  IntroTestUser user,
  String introId,
) {
  return user.introListener.introReceivedStream
      .firstWhere((intro) => intro.id == introId)
      .timeout(const Duration(seconds: 2));
}

Future<IntroductionModel> _waitForIntroStatusChanged(
  IntroTestUser user,
  String introId,
) {
  return user.introListener.introStatusChangedStream
      .firstWhere((intro) => intro.id == introId)
      .timeout(const Duration(seconds: 2));
}

void main() {
  late FakeP2PNetwork network;
  late IntroTestUser introducer; // A — Noor, knows B and C
  late IntroTestUser recipient; // B — Lina
  late IntroTestUser introduced; // C — Sarah

  setUp(() {
    network = FakeP2PNetwork();
    introducer = IntroTestUser.create(
      peerId: 'peer-A',
      username: 'Noor',
      network: network,
    );
    recipient = IntroTestUser.create(
      peerId: 'peer-B',
      username: 'Lina',
      network: network,
    );
    introduced = IntroTestUser.create(
      peerId: 'peer-C',
      username: 'Sarah',
      network: network,
    );

    // A knows both B and C. B and C do NOT know each other yet.
    introducer.addContact(recipient);
    recipient.addContact(introducer);
    introducer.addContact(introduced);
    introduced.addContact(introducer);

    introducer.start();
    recipient.start();
    introduced.start();
  });

  tearDown(() {
    introducer.dispose();
    recipient.dispose();
    introduced.dispose();
  });

  test(
    'send → mutual acceptance → resolveUnknownInboxSender recovers the '
    'introduced peer end-to-end',
    () async {
      // 1) SendIntroduction: A introduces C to B. Both B and C receive the
      //    intro live via handleIncomingIntroduction on the listener stream.
      final friendC = await introducer.contactRepo.getContact('peer-C');
      final intros = await introducer.sendIntroductions(
        recipientPeerId: 'peer-B',
        friends: [friendC!],
      );
      final introId = intros.single.id;

      final received = await Future.wait([
        _waitForIntroReceived(recipient, introId),
        _waitForIntroReceived(introduced, introId),
      ]);
      // Both sides see the same pending introduction wired to the right peers.
      for (final intro in received) {
        expect(intro.introducerId, 'peer-A');
        expect(intro.recipientId, 'peer-B');
        expect(intro.introducedId, 'peer-C');
        expect(intro.status, IntroductionOverallStatus.pending);
      }

      // 2) Mutual acceptance via the live accept notifications, each consumed
      //    by the other peer's handleIncomingIntroduction.
      final introducedSawRecipientAccept = _waitForIntroStatusChanged(
        introduced,
        introId,
      );
      await recipient.acceptIntro(introId);
      await introducedSawRecipientAccept;

      final recipientSawIntroducedAccept = _waitForIntroStatusChanged(
        recipient,
        introId,
      );
      await introduced.acceptIntro(introId);
      await recipientSawIntroducedAccept;

      // Both reach mutualAccepted and create the cross contact.
      final recipientIntro = await recipient.introRepo.getIntroduction(introId);
      final introducedIntro = await introduced.introRepo.getIntroduction(
        introId,
      );
      expect(recipientIntro!.status, IntroductionOverallStatus.mutualAccepted);
      expect(introducedIntro!.status, IntroductionOverallStatus.mutualAccepted);
      expect(await recipient.contactRepo.contactExists('peer-C'), isTrue);
      expect(await introduced.contactRepo.contactExists('peer-B'), isTrue);

      // 3) Simulate the local contact for the introduced peer going missing on
      //    B (e.g. it was never persisted / got purged) while the mutually
      //    accepted introduction row survives. An inbox chat from C is now an
      //    "unknown sender" — resolveUnknownInboxSender must recreate it.
      await recipient.contactRepo.deleteContact('peer-C');
      expect(await recipient.contactRepo.contactExists('peer-C'), isFalse);

      final resolution = await resolveUnknownInboxSender(
        introRepo: recipient.introRepo,
        contactRepo: recipient.contactRepo,
        ownPeerId: 'peer-B',
        senderPeerId: 'peer-C',
      );

      // The introduced peer is resolved and the contact is recreated from the
      // mutually accepted introduction record.
      expect(resolution, UnknownInboxSenderResolution.contactRecovered);
      final recovered = await recipient.contactRepo.getContact('peer-C');
      expect(recovered, isNotNull);
      expect(recovered!.peerId, 'peer-C');
      expect(recovered.username, 'Sarah');
      expect(recovered.introducedBy, 'Noor');

      // A true stranger with no introduction is still rejected.
      final strangerResolution = await resolveUnknownInboxSender(
        introRepo: recipient.introRepo,
        contactRepo: recipient.contactRepo,
        ownPeerId: 'peer-B',
        senderPeerId: 'peer-stranger',
      );
      expect(strangerResolution, UnknownInboxSenderResolution.rejected);
    },
  );
}
