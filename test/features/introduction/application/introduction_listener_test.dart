import 'dart:async';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

void main() {
  late StreamController<ChatMessage> streamController;
  late InMemoryContactRepository contactRepo;
  late InMemoryIntroductionRepository introRepo;
  late IntroductionListener listener;

  setUp(() {
    streamController = StreamController<ChatMessage>.broadcast();
    contactRepo = InMemoryContactRepository();
    introRepo = InMemoryIntroductionRepository();

    listener = IntroductionListener(
      introductionStream: streamController.stream,
      introRepo: introRepo,
      contactRepo: contactRepo,
      bridge: PassthroughCryptoBridge(),
      getOwnMlKemSecretKey: () async => 'test-sk',
      getOwnPeerId: () async => 'own-peer',
    );
    listener.start();
  });

  tearDown(() {
    listener.dispose();
    streamController.close();
  });

  group('IntroductionListener', () {
    test('rejects messages from blocked senders', () async {
      contactRepo.addTestContact(ContactModel(
        peerId: 'blocked-peer',
        publicKey: 'pk',
        rendezvous: '/rv',
        username: 'Blocked',
        signature: 'sig',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        isBlocked: true,
        blockedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final received = <IntroductionModel>[];
      listener.introReceivedStream.listen(received.add);

      final payload = IntroductionPayload(
        action: 'send',
        introductionId: 'intro-blocked',
        introducerId: 'blocked-peer',
        recipientId: 'own-peer',
        introducedId: 'peer-C',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );

      streamController.add(ChatMessage(
        from: 'blocked-peer',
        to: 'own-peer',
        content: payload.toJson(),
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ));

      await Future.delayed(const Duration(milliseconds: 100));
      expect(received, isEmpty);
    });

    test('dispatches new intros to introReceivedStream', () async {
      final received = Completer<IntroductionModel>();
      listener.introReceivedStream.listen((intro) {
        if (!received.isCompleted) received.complete(intro);
      });

      final payload = IntroductionPayload(
        action: 'send',
        introductionId: 'intro-new',
        introducerId: 'peer-A',
        introducerUsername: 'Noor',
        recipientId: 'own-peer',
        recipientUsername: 'Me',
        introducedId: 'peer-C',
        introducedUsername: 'Sarah',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );

      streamController.add(ChatMessage(
        from: 'peer-A',
        to: 'own-peer',
        content: payload.toJson(),
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ));

      final intro = await received.future.timeout(
        const Duration(seconds: 2),
      );
      expect(intro.id, 'intro-new');
      expect(intro.introducerId, 'peer-A');
    });

    test('dispatches status changes to introStatusChangedStream', () async {
      // First save the intro
      await introRepo.saveIntroduction(IntroductionModel(
        id: 'intro-status',
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'own-peer',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final changed = Completer<IntroductionModel>();
      listener.introStatusChangedStream.listen((intro) {
        if (!changed.isCompleted) changed.complete(intro);
      });

      final payload = IntroductionPayload(
        action: 'accept',
        introductionId: 'intro-status',
        responderId: 'peer-B',
        responderUsername: 'Lina',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );

      streamController.add(ChatMessage(
        from: 'peer-B',
        to: 'own-peer',
        content: payload.toJson(),
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ));

      final updated = await changed.future.timeout(
        const Duration(seconds: 2),
      );
      expect(updated.id, 'intro-status');
      expect(updated.recipientStatus, IntroductionStatus.accepted);
    });
  });
}
