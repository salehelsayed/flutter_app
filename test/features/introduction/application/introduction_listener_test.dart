import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';

void main() {
  late StreamController<ChatMessage> streamController;
  late InMemoryContactRepository contactRepo;
  late InMemoryIntroductionRepository introRepo;
  late InMemoryMessageRepository messageRepo;
  late FakeNotificationService notificationService;
  late IntroductionListener listener;
  late PassthroughCryptoBridge bridge;

  setUp(() {
    streamController = StreamController<ChatMessage>.broadcast();
    contactRepo = InMemoryContactRepository();
    introRepo = InMemoryIntroductionRepository();
    messageRepo = InMemoryMessageRepository();
    notificationService = FakeNotificationService();
    bridge = PassthroughCryptoBridge();

    listener = IntroductionListener(
      introductionStream: streamController.stream,
      introRepo: introRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => 'test-sk',
      getOwnPeerId: () async => 'own-peer',
      messageRepo: messageRepo,
      notificationService: notificationService,
    );
    listener.start();
  });

  tearDown(() {
    listener.dispose();
    streamController.close();
  });

  Future<List<Map<String, dynamic>>> captureFlowEvents(
    Future<void> Function() action,
  ) async {
    final originalDebugPrint = debugPrint;
    final originalFlowLogging = flowEventLoggingEnabled;
    final lines = <String>[];

    flowEventLoggingEnabled = true;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        lines.add(message);
      }
    };

    try {
      await action();
    } finally {
      flowEventLoggingEnabled = originalFlowLogging;
      debugPrint = originalDebugPrint;
    }

    return lines
        .where((line) => line.startsWith('[FLOW] '))
        .map(
          (line) =>
              jsonDecode(line.substring('[FLOW] '.length))
                  as Map<String, dynamic>,
        )
        .toList(growable: false);
  }

  group('IntroductionListener', () {
    test('rejects send messages from blocked senders', () async {
      contactRepo.addTestContact(
        ContactModel(
          peerId: 'blocked-peer',
          publicKey: 'pk',
          rendezvous: '/rv',
          username: 'Blocked',
          signature: 'sig',
          scannedAt: DateTime.now().toUtc().toIso8601String(),
          isBlocked: true,
          blockedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

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

      streamController.add(
        ChatMessage(
          from: 'blocked-peer',
          to: 'own-peer',
          content: payload.toJson(),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));
      expect(received, isEmpty);
    });

    test('allows accept from blocked sender to complete handshake', () async {
      // Pre-save an introduction where own-peer (recipient) already accepted
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'intro-blocked-accept',
          introducerId: 'peer-A',
          recipientId: 'own-peer',
          introducedId: 'blocked-peer',
          recipientStatus: IntroductionStatus.accepted,
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      // Add sender as a blocked contact
      contactRepo.addTestContact(
        ContactModel(
          peerId: 'blocked-peer',
          publicKey: 'pk',
          rendezvous: '/rv',
          username: 'Blocked',
          signature: 'sig',
          scannedAt: DateTime.now().toUtc().toIso8601String(),
          isBlocked: true,
          blockedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      final changed = Completer<IntroductionModel>();
      listener.introStatusChangedStream.listen((intro) {
        if (!changed.isCompleted) changed.complete(intro);
      });

      // Send accept from the blocked contact
      final payload = IntroductionPayload(
        action: 'accept',
        introductionId: 'intro-blocked-accept',
        responderId: 'blocked-peer',
        responderUsername: 'Blocked',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );

      streamController.add(
        ChatMessage(
          from: 'blocked-peer',
          to: 'own-peer',
          content: payload.toJson(),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      // Accept should NOT be dropped — it should complete the handshake
      final updated = await changed.future.timeout(const Duration(seconds: 2));
      expect(updated.id, 'intro-blocked-accept');
      expect(updated.introducedStatus, IntroductionStatus.accepted);
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

      streamController.add(
        ChatMessage(
          from: 'peer-A',
          to: 'own-peer',
          content: payload.toJson(),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      final intro = await received.future.timeout(const Duration(seconds: 2));
      expect(intro.id, 'intro-new');
      expect(intro.introducerId, 'peer-A');
    });

    test(
      'successful intro receipt emits flow events, stores a system message, and shows a local notification',
      () async {
        late IntroductionMessageProcessOutcome outcome;
        final events = await captureFlowEvents(() async {
          outcome = await listener.processIncomingMessage(
            ChatMessage(
              from: 'peer-A',
              to: 'own-peer',
              content: IntroductionPayload(
                action: 'send',
                introductionId: 'intro-flow',
                introducerId: 'peer-A',
                introducerUsername: 'Noor',
                recipientId: 'own-peer',
                recipientUsername: 'Me',
                introducedId: 'peer-C',
                introducedUsername: 'Sarah',
                timestamp: DateTime.now().toUtc().toIso8601String(),
              ).toJson(),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isIncoming: true,
            ),
          );
        });

        expect(outcome.state, IntroductionMessageProcessState.stored);

        final systemMessages = await messageRepo.getMessagesForContact(
          'peer-A',
        );
        expect(systemMessages, hasLength(1));
        expect(systemMessages.single.transport, 'system');
        expect(systemMessages.single.text, 'Noor introduced Sarah to you');

        expect(notificationService.shownGeneric, hasLength(1));
        expect(
          notificationService.shownGeneric.single.title,
          'New Introduction',
        );
        expect(
          notificationService.shownGeneric.single.body,
          'Noor introduced Sarah to you',
        );
        expect(notificationService.shownGeneric.single.payload, 'intros');

        final eventNames = events
            .map((event) => event['event'] as String)
            .toList(growable: false);
        expect(
          eventNames,
          containsAll(<String>[
            'INTRO_LISTENER_MESSAGE_RECEIVED',
            'HANDLE_INCOMING_INTRO_START',
            'HANDLE_INCOMING_INTRO_SAVED',
            'INSERT_INTRO_SYSTEM_MESSAGE',
            'INTRO_LISTENER_NEW_INTRO',
          ]),
        );
      },
    );

    test('dispatches status changes to introStatusChangedStream', () async {
      // First save the intro
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'intro-status',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'own-peer',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

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

      streamController.add(
        ChatMessage(
          from: 'peer-B',
          to: 'own-peer',
          content: payload.toJson(),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      final updated = await changed.future.timeout(const Duration(seconds: 2));
      expect(updated.id, 'intro-status');
      expect(updated.recipientStatus, IntroductionStatus.accepted);
    });

    test(
      'introduced-side receipt uses introduced perspective in system message and notification',
      () async {
        final outcome = await listener.processIncomingMessage(
          ChatMessage(
            from: 'peer-A',
            to: 'own-peer',
            content: IntroductionPayload(
              action: 'send',
              introductionId: 'intro-introduced',
              introducerId: 'peer-A',
              introducerUsername: 'Noor',
              recipientId: 'peer-B',
              recipientUsername: 'Lina',
              introducedId: 'own-peer',
              introducedUsername: 'Me',
              timestamp: DateTime.now().toUtc().toIso8601String(),
            ).toJson(),
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
          ),
        );

        expect(outcome.state, IntroductionMessageProcessState.stored);

        final systemMessages = await messageRepo.getMessagesForContact(
          'peer-A',
        );
        expect(systemMessages, hasLength(1));
        expect(systemMessages.single.text, 'Noor introduced you to Lina');

        expect(notificationService.shownGeneric, hasLength(1));
        expect(
          notificationService.shownGeneric.single.body,
          'Noor introduced you to Lina',
        );
      },
    );

    test(
      'mutual acceptance shows a local new-connection notification',
      () async {
        await introRepo.saveIntroduction(
          IntroductionModel(
            id: 'intro-mutual-notification',
            introducerId: 'peer-A',
            introducerUsername: 'Noor',
            recipientId: 'own-peer',
            recipientUsername: 'Me',
            introducedId: 'peer-C',
            introducedUsername: 'Sarah',
            recipientStatus: IntroductionStatus.accepted,
            introducedStatus: IntroductionStatus.pending,
            status: IntroductionOverallStatus.pending,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        final outcome = await listener.processIncomingMessage(
          ChatMessage(
            from: 'peer-C',
            to: 'own-peer',
            content: IntroductionPayload(
              action: 'accept',
              introductionId: 'intro-mutual-notification',
              responderId: 'peer-C',
              responderUsername: 'Sarah',
              timestamp: DateTime.now().toUtc().toIso8601String(),
            ).toJson(),
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
          ),
        );

        expect(outcome.state, IntroductionMessageProcessState.stored);
        expect(notificationService.shownGeneric, hasLength(1));
        expect(notificationService.shownGeneric.single.title, 'New Connection');
        expect(
          notificationService.shownGeneric.single.body,
          'Sarah also accepted! You\'re now connected.',
        );
        expect(notificationService.shownGeneric.single.payload, 'intros');
      },
    );

    test(
      'multiple incoming intros produce stacked local notifications',
      () async {
        await listener.processIncomingMessage(
          ChatMessage(
            from: 'peer-A',
            to: 'own-peer',
            content: IntroductionPayload(
              action: 'send',
              introductionId: 'intro-stack-1',
              introducerId: 'peer-A',
              introducerUsername: 'Noor',
              recipientId: 'own-peer',
              recipientUsername: 'Me',
              introducedId: 'peer-C',
              introducedUsername: 'Sarah',
              timestamp: DateTime.now().toUtc().toIso8601String(),
            ).toJson(),
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
          ),
        );
        await listener.processIncomingMessage(
          ChatMessage(
            from: 'peer-D',
            to: 'own-peer',
            content: IntroductionPayload(
              action: 'send',
              introductionId: 'intro-stack-2',
              introducerId: 'peer-D',
              introducerUsername: 'Dana',
              recipientId: 'own-peer',
              recipientUsername: 'Me',
              introducedId: 'peer-E',
              introducedUsername: 'Yara',
              timestamp: DateTime.now().toUtc().toIso8601String(),
            ).toJson(),
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
          ),
        );

        expect(notificationService.shownGeneric, hasLength(2));
        expect(
          notificationService.shownGeneric.map((item) => item.body).toList(),
          <String>[
            'Noor introduced Sarah to you',
            'Dana introduced Yara to you',
          ],
        );
      },
    );

    test(
      'defers out-of-order accept and confirms direct delivery positively',
      () async {
        final outcome = await listener.processIncomingMessage(
          ChatMessage(
            from: 'peer-B',
            to: 'own-peer',
            content: IntroductionPayload(
              action: 'accept',
              introductionId: 'intro-out-of-order',
              responderId: 'peer-B',
              responderUsername: 'Bob',
              timestamp: DateTime.now().toUtc().toIso8601String(),
            ).toJson(),
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
            confirmNonce: 'nonce-intro-1',
          ),
        );

        expect(outcome.state, IntroductionMessageProcessState.deferred);
        expect(
          await introRepo.loadPendingResponses('intro-out-of-order'),
          hasLength(1),
        );

        final confirmRequest =
            jsonDecode(bridge.sentMessages.last) as Map<String, dynamic>;
        expect(confirmRequest['cmd'], 'message:confirm');
        expect(confirmRequest['payload'], {
          'nonce': 'nonce-intro-1',
          'ok': true,
        });
      },
    );

    test('send after deferred accept replays staged response', () async {
      await listener.processIncomingMessage(
        ChatMessage(
          from: 'peer-B',
          to: 'own-peer',
          content: IntroductionPayload(
            action: 'accept',
            introductionId: 'intro-replay',
            responderId: 'peer-B',
            responderUsername: 'Bob',
            timestamp: DateTime.now().toUtc().toIso8601String(),
          ).toJson(),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      final outcome = await listener.processIncomingMessage(
        ChatMessage(
          from: 'peer-A',
          to: 'own-peer',
          content: IntroductionPayload(
            action: 'send',
            introductionId: 'intro-replay',
            introducerId: 'peer-A',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            timestamp: DateTime.now().toUtc().toIso8601String(),
          ).toJson(),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );

      expect(outcome.state, IntroductionMessageProcessState.stored);
      final intro = await introRepo.getIntroduction('intro-replay');
      expect(intro, isNotNull);
      expect(intro!.recipientStatus, IntroductionStatus.accepted);
      expect(intro.introducedStatus, IntroductionStatus.pending);
      expect(await introRepo.loadPendingResponses('intro-replay'), isEmpty);
    });

    test(
      'v2 key mismatch rejects intro, stores nothing, and logs failure',
      () async {
        final mismatchBridge = FakeBridge(
          initialResponses: {
            'message.decrypt': {
              'ok': false,
              'errorCode': 'KEY_MISMATCH',
              'errorMessage': 'ciphertext cannot be decrypted by this key',
            },
          },
        );
        final mismatchListener = IntroductionListener(
          introductionStream: const Stream<ChatMessage>.empty(),
          introRepo: introRepo,
          contactRepo: contactRepo,
          bridge: mismatchBridge,
          getOwnMlKemSecretKey: () async => 'test-sk',
          getOwnPeerId: () async => 'own-peer',
          messageRepo: messageRepo,
          notificationService: notificationService,
        );

        addTearDown(mismatchListener.dispose);

        late IntroductionMessageProcessOutcome outcome;
        final events = await captureFlowEvents(() async {
          outcome = await mismatchListener.processIncomingMessage(
            ChatMessage(
              from: 'peer-A',
              to: 'own-peer',
              content: IntroductionPayload.buildEncryptedEnvelope(
                introductionId: 'intro-v2-mismatch',
                senderPeerId: 'peer-A',
                kem: 'old-kem',
                ciphertext: jsonEncode({
                  'action': 'send',
                  'introductionId': 'intro-v2-mismatch',
                  'timestamp': '2026-04-03T00:00:00.000Z',
                }),
                nonce: 'old-nonce',
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isIncoming: true,
            ),
          );
        });

        expect(outcome.state, IntroductionMessageProcessState.rejected);
        expect(outcome.reasonCode, 'decryption_failed');
        expect(await introRepo.countPendingIntroductions('own-peer'), 0);
        expect(notificationService.shownGeneric, isEmpty);
        expect(await messageRepo.getTotalUnreadCount(), 0);

        final decryptFailedEvents = events.where(
          (event) => event['event'] == 'INTRO_LISTENER_DECRYPT_FAILED',
        );
        expect(decryptFailedEvents, hasLength(1));
        expect(
          decryptFailedEvents.single['details'],
          containsPair('errorCode', 'KEY_MISMATCH'),
        );
      },
    );
  });
}
