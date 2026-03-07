import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/check_intro_banner_use_case.dart';
import 'package:flutter_app/features/introduction/application/handle_incoming_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/handle_mutual_acceptance_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';
import '../../../shared/fakes/intro_test_user.dart';

void main() {
  // ── Shared test users ──────────────────────────────────────────────
  late FakeP2PNetwork network;
  late IntroTestUser alice; // introducer
  late IntroTestUser bob; // recipient (User-B)
  late IntroTestUser carol; // introduced (User-C)

  setUp(() {
    network = FakeP2PNetwork();
    alice = IntroTestUser.create(
      peerId: 'peer-alice',
      username: 'Alice',
      network: network,
    );
    bob = IntroTestUser.create(
      peerId: 'peer-bob',
      username: 'Bob',
      network: network,
    );
    carol = IntroTestUser.create(
      peerId: 'peer-carol',
      username: 'Carol',
      network: network,
    );

    // Wire up contacts: Alice knows both Bob and Carol
    alice.addContact(bob);
    alice.addContact(carol);
  });

  tearDown(() {
    alice.dispose();
    bob.dispose();
    carol.dispose();
  });

  // Helper: create a standard introduction from Alice introducing Carol to Bob
  Future<String> createStandardIntro() async {
    final intros = await alice.sendIntroductions(
      recipientPeerId: bob.peerId,
      friends: [
        ContactModel(
          peerId: carol.peerId,
          publicKey: 'pk-${carol.peerId}',
          rendezvous: '',
          username: carol.username,
          signature: 'sig-${carol.peerId}',
          scannedAt: DateTime.now().toUtc().toIso8601String(),
          mlKemPublicKey: 'test-mlkem-pk-${carol.peerId}',
        ),
      ],
    );
    final introId = intros.first.id;

    // Seed the intro on Bob and Carol's repos
    final aliceIntro = await alice.introRepo.getIntroduction(introId);
    await bob.introRepo.saveIntroduction(aliceIntro!);
    await carol.introRepo.saveIntroduction(aliceIntro);

    return introId;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Area 1: Pass status
  // ═══════════════════════════════════════════════════════════════════
  group('Area 1: Pass status', () {
    test('introduced party passes → introducedStatus=passed, recipientStatus unchanged', () async {
      final introId = await createStandardIntro();

      // Carol passes
      await carol.introRepo.updateIntroducedStatus(introId, IntroductionStatus.passed);
      final newOverall = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.pending,
        introducedStatus: IntroductionStatus.passed,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      await carol.introRepo.updateOverallStatus(introId, newOverall);

      final updated = await carol.introRepo.getIntroduction(introId);
      expect(updated!.introducedStatus, IntroductionStatus.passed);
      expect(updated.recipientStatus, IntroductionStatus.pending);
      expect(updated.status, IntroductionOverallStatus.passed);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Area 2: Unknown responderId guard
  // ═══════════════════════════════════════════════════════════════════
  group('Area 2: Unknown responderId', () {
    test('responderId matching neither party → error, no state mutation', () async {
      final introId = await createStandardIntro();

      final (result, _) = await handleIncomingIntroduction(
        payload: IntroductionPayload(
          action: 'accept',
          introductionId: introId,
          responderId: 'peer-unknown',
          responderUsername: 'Unknown',
          timestamp: DateTime.now().toUtc().toIso8601String(),
        ),
        introRepo: bob.introRepo,
        contactRepo: bob.contactRepo,
        ownPeerId: bob.peerId,
      );

      expect(result, HandleIntroductionResult.error);

      // Verify no state mutation
      final intro = await bob.introRepo.getIntroduction(introId);
      expect(intro!.recipientStatus, IntroductionStatus.pending);
      expect(intro.introducedStatus, IntroductionStatus.pending);
      expect(intro.status, IntroductionOverallStatus.pending);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Area 3: Expired exclusion
  // ═══════════════════════════════════════════════════════════════════
  group('Area 3: Expired exclusion', () {
    test('expired intro excluded from countPendingIntroductions', () async {
      final introRepo = InMemoryIntroductionRepository();

      // Create an expired introduction
      final expiredIntro = IntroductionModel(
        id: 'intro-expired',
        introducerId: 'peer-alice',
        recipientId: 'peer-bob',
        introducedId: 'peer-carol',
        status: IntroductionOverallStatus.expired,
        createdAt: DateTime.now().subtract(const Duration(days: 31)).toUtc().toIso8601String(),
      );
      await introRepo.saveIntroduction(expiredIntro);

      // Create a pending introduction
      final pendingIntro = IntroductionModel(
        id: 'intro-pending',
        introducerId: 'peer-alice',
        recipientId: 'peer-bob',
        introducedId: 'peer-dave',
        status: IntroductionOverallStatus.pending,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      await introRepo.saveIntroduction(pendingIntro);

      final count = await introRepo.countPendingIntroductions('peer-bob');
      expect(count, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Area 4: Block/unblock banner
  // ═══════════════════════════════════════════════════════════════════
  group('Area 4: Block/unblock banner', () {
    test('block hides banner, unblock restores it', () async {
      final contactRepo = InMemoryContactRepository();
      final target = ContactModel(
        peerId: 'peer-target',
        publicKey: 'pk',
        rendezvous: '',
        username: 'Target',
        signature: 'sig',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      );
      contactRepo.addTestContact(target);

      // Add another friend so gate 5 passes
      contactRepo.addTestContact(ContactModel(
        peerId: 'peer-other',
        publicKey: 'pk2',
        rendezvous: '',
        username: 'Other',
        signature: 'sig2',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // Initially banner shows
      expect(
        await shouldShowIntroBanner(
          contactRepo: contactRepo,
          contact: target,
          messageCount: 0,
        ),
        isTrue,
      );

      // Block → banner hidden
      await contactRepo.blockContact('peer-target');
      final blockedContact = await contactRepo.getContact('peer-target');
      expect(
        await shouldShowIntroBanner(
          contactRepo: contactRepo,
          contact: blockedContact!,
          messageCount: 0,
        ),
        isFalse,
      );

      // Unblock → banner restored
      await contactRepo.unblockContact('peer-target');
      final unblockedContact = await contactRepo.getContact('peer-target');
      expect(
        await shouldShowIntroBanner(
          contactRepo: contactRepo,
          contact: unblockedContact!,
          messageCount: 0,
        ),
        isTrue,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Area 5: Concurrent idempotency
  // ═══════════════════════════════════════════════════════════════════
  group('Area 5: Concurrent idempotency', () {
    test('handleMutualAcceptance called twice → exactly 1 contact created', () async {
      final introId = await createStandardIntro();

      // Both accept
      await bob.introRepo.updateRecipientStatus(introId, IntroductionStatus.accepted);
      await bob.introRepo.updateIntroducedStatus(introId, IntroductionStatus.accepted);
      await bob.introRepo.updateOverallStatus(introId, IntroductionOverallStatus.mutualAccepted);

      final intro = await bob.introRepo.getIntroduction(introId);

      // Call handleMutualAcceptance twice
      final contact1 = await handleMutualAcceptance(
        introduction: intro!,
        contactRepo: bob.contactRepo,
        ownPeerId: bob.peerId,
      );
      final contact2 = await handleMutualAcceptance(
        introduction: intro,
        contactRepo: bob.contactRepo,
        ownPeerId: bob.peerId,
      );

      expect(contact1, isNotNull);
      expect(contact2, isNull); // Already exists → null

      final allContacts = await bob.contactRepo.getAllContacts();
      final carolContacts = allContacts.where((c) => c.peerId == carol.peerId);
      expect(carolContacts.length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Area 6: One-sided no contact
  // ═══════════════════════════════════════════════════════════════════
  group('Area 6: One-sided no contact', () {
    test('recipient accepts alone → no contact created for other party', () async {
      final introId = await createStandardIntro();

      // Only Bob accepts
      await bob.introRepo.updateRecipientStatus(introId, IntroductionStatus.accepted);
      final newOverall = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.accepted,
        introducedStatus: IntroductionStatus.pending,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      await bob.introRepo.updateOverallStatus(introId, newOverall);

      // Status should be pending (not mutualAccepted)
      expect(newOverall, IntroductionOverallStatus.pending);

      // Carol should not exist as a contact for Bob
      expect(await bob.contactRepo.contactExists(carol.peerId), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Area 7a & 7b: Key direction correctness
  // ═══════════════════════════════════════════════════════════════════
  group('Area 7: Key direction', () {
    test('7a: recipient (Bob) gets introduced party keys (Carol)', () async {
      final introId = await createStandardIntro();

      // Set up keys on introduction
      final intro = await bob.introRepo.getIntroduction(introId);
      final withKeys = intro!.copyWith(
        introducedPublicKey: 'pk-carol',
        introducedMlKemPublicKey: 'mlkem-carol',
        recipientPublicKey: 'pk-bob',
        recipientMlKemPublicKey: 'mlkem-bob',
        recipientStatus: IntroductionStatus.accepted,
        introducedStatus: IntroductionStatus.accepted,
        status: IntroductionOverallStatus.mutualAccepted,
      );
      await bob.introRepo.saveIntroduction(withKeys);

      final contact = await handleMutualAcceptance(
        introduction: withKeys,
        contactRepo: bob.contactRepo,
        ownPeerId: bob.peerId,
      );

      expect(contact, isNotNull);
      expect(contact!.publicKey, 'pk-carol');
      expect(contact.mlKemPublicKey, 'mlkem-carol');
    });

    test('7b: introduced party (Carol) gets recipient keys (Bob)', () async {
      final introId = await createStandardIntro();

      // Set up keys on introduction
      final intro = await carol.introRepo.getIntroduction(introId);
      final withKeys = intro!.copyWith(
        introducedPublicKey: 'pk-carol',
        introducedMlKemPublicKey: 'mlkem-carol',
        recipientPublicKey: 'pk-bob',
        recipientMlKemPublicKey: 'mlkem-bob',
        recipientStatus: IntroductionStatus.accepted,
        introducedStatus: IntroductionStatus.accepted,
        status: IntroductionOverallStatus.mutualAccepted,
      );
      await carol.introRepo.saveIntroduction(withKeys);

      final contact = await handleMutualAcceptance(
        introduction: withKeys,
        contactRepo: carol.contactRepo,
        ownPeerId: carol.peerId,
      );

      expect(contact, isNotNull);
      // Carol is introduced party → should get Bob's (recipient) keys
      expect(contact!.publicKey, 'pk-bob');
      expect(contact.mlKemPublicKey, 'mlkem-bob');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Area 8: Duplicate accept delivery
  // ═══════════════════════════════════════════════════════════════════
  group('Area 8: Duplicate accept delivery', () {
    test('same accept notification twice → no duplicate contacts', () async {
      final introId = await createStandardIntro();

      // Bob accepts first (local)
      await bob.introRepo.updateRecipientStatus(introId, IntroductionStatus.accepted);

      // Simulate receiving Carol's accept twice
      await bob.receiveAcceptNotification(
        introId: introId,
        responderId: carol.peerId,
        responderUsername: carol.username,
      );
      await bob.receiveAcceptNotification(
        introId: introId,
        responderId: carol.peerId,
        responderUsername: carol.username,
      );

      final allContacts = await bob.contactRepo.getAllContacts();
      final carolContacts = allContacts.where((c) => c.peerId == carol.peerId);
      expect(carolContacts.length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Area 9: Picker exclusion
  // ═══════════════════════════════════════════════════════════════════
  group('Area 9: Picker exclusion', () {
    test('recipient excluded from friend list', () async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(ContactModel(
        peerId: 'peer-bob',
        publicKey: 'pk',
        rendezvous: '',
        username: 'Bob',
        signature: 'sig',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ));
      contactRepo.addTestContact(ContactModel(
        peerId: 'peer-carol',
        publicKey: 'pk2',
        rendezvous: '',
        username: 'Carol',
        signature: 'sig2',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final contacts = await contactRepo.getActiveContacts();
      final recipientPeerId = 'peer-bob';
      final filtered = contacts.where((c) => c.peerId != recipientPeerId && !c.isBlocked).toList();

      expect(filtered.length, 1);
      expect(filtered.first.peerId, 'peer-carol');
    });

    test('blocked contacts excluded from friend list', () async {
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(ContactModel(
        peerId: 'peer-bob',
        publicKey: 'pk',
        rendezvous: '',
        username: 'Bob',
        signature: 'sig',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ));
      contactRepo.addTestContact(ContactModel(
        peerId: 'peer-carol',
        publicKey: 'pk2',
        rendezvous: '',
        username: 'Carol',
        signature: 'sig2',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        isBlocked: true,
        blockedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final contacts = await contactRepo.getActiveContacts();
      final recipientPeerId = 'peer-dave'; // not in list
      final filtered = contacts.where((c) => c.peerId != recipientPeerId && !c.isBlocked).toList();

      // Carol is blocked → excluded
      expect(filtered.length, 1);
      expect(filtered.first.peerId, 'peer-bob');
    });

    test('already-introduced contacts excluded from friend list', () async {
      final contactRepo = InMemoryContactRepository();
      final introRepo = InMemoryIntroductionRepository();
      final recipientPeerId = 'peer-bob';
      final introducerPeerId = 'peer-alice';

      contactRepo.addTestContact(ContactModel(
        peerId: 'peer-carol',
        publicKey: 'pk',
        rendezvous: '',
        username: 'Carol',
        signature: 'sig',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ));
      contactRepo.addTestContact(ContactModel(
        peerId: 'peer-dave',
        publicKey: 'pk2',
        rendezvous: '',
        username: 'Dave',
        signature: 'sig2',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // Carol was already introduced to Bob by Alice
      await introRepo.saveIntroduction(IntroductionModel(
        id: 'intro-existing',
        introducerId: introducerPeerId,
        recipientId: recipientPeerId,
        introducedId: 'peer-carol',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // Replicate picker logic
      final existingIntros = await introRepo.getIntroductionsByIntroducer(introducerPeerId);
      final alreadyIntroduced = <String>{};
      for (final intro in existingIntros) {
        if (intro.recipientId == recipientPeerId) {
          alreadyIntroduced.add(intro.introducedId);
        }
        if (intro.introducedId == recipientPeerId) {
          alreadyIntroduced.add(intro.recipientId);
        }
      }

      final contacts = await contactRepo.getActiveContacts();
      final filtered = contacts.where((c) {
        if (c.peerId == recipientPeerId) return false;
        if (c.isBlocked) return false;
        if (alreadyIntroduced.contains(c.peerId)) return false;
        return true;
      }).toList();

      expect(filtered.length, 1);
      expect(filtered.first.peerId, 'peer-dave');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Area 10: Banner full matrix
  // ═══════════════════════════════════════════════════════════════════
  group('Area 10: Banner full matrix', () {
    test('all 6 gates pass → true; flip each gate individually → false', () async {
      final contactRepo = InMemoryContactRepository();

      // The target contact (all gates pass)
      final baseContact = ContactModel(
        peerId: 'peer-target',
        publicKey: 'pk',
        rendezvous: '',
        username: 'Target',
        signature: 'sig',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      );
      contactRepo.addTestContact(baseContact);

      // Another friend (gate 5: at least 1 other active non-blocked contact)
      contactRepo.addTestContact(ContactModel(
        peerId: 'peer-friend',
        publicKey: 'pk2',
        rendezvous: '',
        username: 'Friend',
        signature: 'sig2',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // All gates pass
      expect(
        await shouldShowIntroBanner(
          contactRepo: contactRepo,
          contact: baseContact,
          messageCount: 0,
        ),
        isTrue,
      );

      // Gate 1: blocked → false
      expect(
        await shouldShowIntroBanner(
          contactRepo: contactRepo,
          contact: baseContact.copyWith(isBlocked: true),
          messageCount: 0,
        ),
        isFalse,
      );

      // Gate 2: archived → false
      expect(
        await shouldShowIntroBanner(
          contactRepo: contactRepo,
          contact: baseContact.copyWith(isArchived: true),
          messageCount: 0,
        ),
        isFalse,
      );

      // Gate 3: banner dismissed → false
      expect(
        await shouldShowIntroBanner(
          contactRepo: contactRepo,
          contact: baseContact.copyWith(introsBannerDismissed: true),
          messageCount: 0,
        ),
        isFalse,
      );

      // Gate 4: intros already sent → false
      expect(
        await shouldShowIntroBanner(
          contactRepo: contactRepo,
          contact: baseContact.copyWith(introsSentAt: '2025-01-01T00:00:00Z'),
          messageCount: 0,
        ),
        isFalse,
      );

      // Gate 5: no other friends (remove friend)
      final lonelyRepo = InMemoryContactRepository();
      lonelyRepo.addTestContact(baseContact);
      expect(
        await shouldShowIntroBanner(
          contactRepo: lonelyRepo,
          contact: baseContact,
          messageCount: 0,
        ),
        isFalse,
      );

      // Gate 6: too many messages → false
      expect(
        await shouldShowIntroBanner(
          contactRepo: contactRepo,
          contact: baseContact,
          messageCount: 3,
        ),
        isFalse,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Area 11: Encryption fallback
  // ═══════════════════════════════════════════════════════════════════
  group('Area 11: Encryption fallback', () {
    test('callEncryptMessage returns ok=false → v1 plaintext sent', () async {
      final failBridge = FakeBridge(
        initialResponses: {'message.encrypt': {'ok': false}},
      );
      final failNetwork = FakeP2PNetwork();
      final failAlice = IntroTestUser.create(
        peerId: 'peer-alice',
        username: 'Alice',
        network: failNetwork,
        bridge: failBridge,
      );
      final failBob = IntroTestUser.create(
        peerId: 'peer-bob',
        username: 'Bob',
        network: failNetwork,
      );
      final failCarol = IntroTestUser.create(
        peerId: 'peer-carol',
        username: 'Carol',
        network: failNetwork,
      );

      failAlice.addContact(failBob);
      failAlice.addContact(failCarol);

      // Collect sent messages
      final sentMessages = <ChatMessage>[];
      failBob.p2pService.messageStream.listen((m) => sentMessages.add(m));
      failCarol.p2pService.messageStream.listen((m) => sentMessages.add(m));

      await failAlice.sendIntroductions(
        recipientPeerId: failBob.peerId,
        friends: [
          ContactModel(
            peerId: failCarol.peerId,
            publicKey: 'pk-carol',
            rendezvous: '',
            username: 'Carol',
            signature: 'sig',
            scannedAt: DateTime.now().toUtc().toIso8601String(),
            mlKemPublicKey: 'mlkem-carol',
          ),
        ],
      );

      // Allow delivery
      await Future.delayed(const Duration(milliseconds: 50));

      // Both messages should be v1 (contain "version":"1")
      expect(sentMessages.length, 2);
      for (final msg in sentMessages) {
        final json = jsonDecode(msg.content) as Map<String, dynamic>;
        expect(json['version'], '1');
        expect(json['type'], 'introduction');
      }

      failAlice.dispose();
      failBob.dispose();
      failCarol.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Area 13: v1 fallback when intro record lacks ML-KEM key
  // ═══════════════════════════════════════════════════════════════════
  group('Area 13: v1 fallback preserved for pre-ML-KEM introductions', () {
    test('v1 fallback when intro record lacks ML-KEM key', () async {
      // Create intro WITHOUT any ML-KEM keys (pre-ML-KEM introduction)
      final introId = 'intro-no-mlkem';
      await bob.introRepo.saveIntroduction(IntroductionModel(
        id: introId,
        introducerId: alice.peerId,
        recipientId: bob.peerId,
        introducedId: carol.peerId,
        introducerUsername: 'Alice',
        recipientUsername: 'Bob',
        introducedUsername: 'Carol',
        // No ML-KEM keys on intro record
        recipientMlKemPublicKey: null,
        introducedMlKemPublicKey: null,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // Bob knows Alice (the introducer) but NOT Carol
      bob.addContact(alice);

      final bridgeBob = bob.bridge as PassthroughCryptoBridge;
      bridgeBob.commandLog.clear();

      await bob.acceptIntro(introId);

      // Should have 1 encrypt call (for Alice, who is a contact with ML-KEM key)
      // Carol's send should be v1 (no encrypt) because intro has no ML-KEM key for her
      final encryptCalls =
          bridgeBob.commandLog.where((c) => c == 'message.encrypt').length;
      expect(encryptCalls, 1,
          reason: 'only introducer encrypted, stranger gets v1 (no ML-KEM key on intro)');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Area 12: Listener resilience
  // ═══════════════════════════════════════════════════════════════════
  group('Area 12: Listener resilience', () {
    test('12a: completely malformed JSON → silently dropped, no crash', () async {
      alice.start();
      bob.start();

      final received = <IntroductionModel>[];
      bob.introListener.introReceivedStream.listen((m) => received.add(m));

      // Inject malformed JSON
      bob.p2pService.injectIncomingMessage(ChatMessage(
        from: alice.peerId,
        to: bob.peerId,
        content: 'this is not json at all!!!',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(received, isEmpty);
    });

    test('12b: valid envelope but missing required payload fields → dropped', () async {
      alice.start();
      bob.start();

      final received = <IntroductionModel>[];
      bob.introListener.introReceivedStream.listen((m) => received.add(m));

      // Valid envelope structure but missing action/introductionId/timestamp
      final incomplete = jsonEncode({
        'type': 'introduction',
        'version': '1',
        'payload': {'foo': 'bar'},
      });

      bob.p2pService.injectIncomingMessage(ChatMessage(
        from: alice.peerId,
        to: bob.peerId,
        content: incomplete,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(received, isEmpty);
    });

    test('12c: valid envelope with unknown action → no emissions', () async {
      alice.start();
      bob.start();

      final received = <IntroductionModel>[];
      final statusChanged = <IntroductionModel>[];
      bob.introListener.introReceivedStream.listen((m) => received.add(m));
      bob.introListener.introStatusChangedStream.listen((m) => statusChanged.add(m));

      final unknownAction = jsonEncode({
        'type': 'introduction',
        'version': '1',
        'payload': {
          'action': 'unknown',
          'introductionId': 'intro-123',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      });

      bob.p2pService.injectIncomingMessage(ChatMessage(
        from: alice.peerId,
        to: bob.peerId,
        content: unknownAction,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(received, isEmpty);
      expect(statusChanged, isEmpty);
    });
  });
}
