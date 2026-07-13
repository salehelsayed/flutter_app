import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../domain/repositories/fake_reaction_repository.dart';
import '../../../shared/fakes/fake_notification_service.dart';

const _senderPeerId = '12D3KooWSender';
const _ownMlKemSecretKey = 'own-secret-key';

class _BarrierReactionRepository extends FakeReactionRepository {
  final Completer<void> bothCallsArrived = Completer<void>();
  final Completer<void> release = Completer<void>();
  int applyCallCount = 0;

  @override
  Future<ReactionAddApplyResult> applyIncomingAdd(
    MessageReaction reaction,
  ) async {
    applyCallCount++;
    if (applyCallCount == 2 && !bothCallsArrived.isCompleted) {
      bothCallsArrived.complete();
    }
    await release.future;
    return super.applyIncomingAdd(reaction);
  }
}

ChatMessage _makeReactionMessage(String content) {
  return ChatMessage(
    from: _senderPeerId,
    to: 'my-peer',
    content: content,
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
  );
}

/// FDC-18 Prerequisite P0: capture the flow events emitted while [action] runs.
Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() action,
) async {
  final events = <Map<String, dynamic>>[];
  debugSetFlowEventSink((payload) => events.add(payload));
  try {
    await action();
  } finally {
    debugSetFlowEventSink(null);
  }
  return events;
}

Future<void> _expectCommittedNotificationClaim(File claim) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (await claim.exists()) {
      try {
        final decoded = jsonDecode(await claim.readAsString());
        if (decoded is Map && decoded['state'] == 'committed') return;
      } on FormatException {
        // The exclusive create may be visible before its JSON write settles.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('notification claim did not commit: ${claim.path}');
}

void main() {
  late FakeBridge bridge;
  late FakeContactRepository contactRepo;
  late FakeMessageRepository messageRepo;
  late FakeReactionRepository reactionRepo;

  setUp(() {
    bridge = FakeBridge(
      initialResponses: {
        'message.decrypt': {
          'ok': true,
          'plaintext': jsonEncode({
            'id': 'r1',
            'messageId': 'msg-1',
            'emoji': '👍',
            'action': 'add',
            'senderPeerId': _senderPeerId,
            'timestamp': '2026-02-27T10:00:00.000Z',
          }),
        },
      },
    );
    contactRepo = FakeContactRepository();
    contactRepo.seed([
      ContactModel(
        peerId: _senderPeerId,
        publicKey: 'pk',
        rendezvous: '/relay',
        username: 'Sender',
        signature: 'sig',
        scannedAt: '2026-01-01T00:00:00.000Z',
      ),
    ]);
    messageRepo = FakeMessageRepository()
      ..seed([
        const ConversationMessage(
          id: 'msg-1',
          contactPeerId: _senderPeerId,
          senderPeerId: 'my-peer',
          text: 'hello',
          timestamp: '2026-02-27T10:00:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-27T10:00:00.000Z',
        ),
      ]);
    reactionRepo = FakeReactionRepository();
  });

  group('handleIncomingReaction', () {
    test('rejects non-reaction envelope', () async {
      final (result, _) = await handleIncomingReaction(
        message: _makeReactionMessage(
          jsonEncode({'type': 'chat_message', 'version': '1', 'payload': {}}),
        ),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.notReaction);
    });

    test('rejects v1 reaction (encryption required)', () async {
      final v1 = const ReactionPayload(
        id: 'r1',
        messageId: 'msg-1',
        emoji: '👍',
        action: 'add',
        senderPeerId: _senderPeerId,
        timestamp: '2026-02-27T10:00:00.000Z',
      ).toJson();

      final (result, _) = await handleIncomingReaction(
        message: _makeReactionMessage(v1),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.notReaction);
    });

    test('returns decryptionFailed when no own key', () async {
      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, _) = await handleIncomingReaction(
        message: ChatMessage(
          from: 'unknown-peer',
          to: 'my-peer',
          content: v2,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: null,
      );

      expect(result, HandleReactionResult.decryptionFailed);
    });

    test('returns decryptionFailed when decrypt fails', () async {
      bridge.responses['message.decrypt'] = {'ok': false, 'errorCode': 'err'};

      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, _) = await handleIncomingReaction(
        message: ChatMessage(
          from: 'unknown-peer',
          to: 'my-peer',
          content: v2,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.decryptionFailed);
    });

    test('returns unknownSender when sender not in contacts', () async {
      // Use a different sender that's not in contacts
      bridge.responses['message.decrypt'] = {
        'ok': true,
        'plaintext': jsonEncode({
          'id': 'r1',
          'messageId': 'msg-1',
          'emoji': '👍',
          'action': 'add',
          'senderPeerId': 'unknown-peer',
          'timestamp': '2026-02-27T10:00:00.000Z',
        }),
      };

      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: 'unknown-peer',
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, _) = await handleIncomingReaction(
        message: ChatMessage(
          from: 'unknown-peer',
          to: 'my-peer',
          content: v2,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.unknownSender);
    });

    test(
      'returns senderMismatch when envelope sender disagrees with payload sender',
      () async {
        final v2 = ReactionPayload.buildEncryptedEnvelope(
          senderPeerId: _senderPeerId,
          kem: 'k',
          ciphertext: 'c',
          nonce: 'n',
        );

        final (result, change) = await handleIncomingReaction(
          message: ChatMessage(
            from: 'different-envelope-sender',
            to: 'my-peer',
            content: v2,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
          ),
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: _ownMlKemSecretKey,
        );

        expect(result, HandleReactionResult.senderMismatch);
        expect(change, isNull);
        expect(reactionRepo.saveReactionCallCount, 0);
      },
    );

    test(
      'rejects outer notification metadata that mismatches plaintext',
      () async {
        final v2 = ReactionPayload.buildEncryptedEnvelope(
          senderPeerId: _senderPeerId,
          eventId: 'different-event',
          action: 'add',
          targetMessageId: 'msg-1',
          kem: 'k',
          ciphertext: 'c',
          nonce: 'n',
        );

        final (result, change) = await handleIncomingReaction(
          message: _makeReactionMessage(v2),
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: _ownMlKemSecretKey,
        );

        expect(result, HandleReactionResult.metadataMismatch);
        expect(change, isNull);
        expect(reactionRepo.saveReactionCallCount, 0);
      },
    );

    group('127-Bug-C reaction notifications', () {
      String envelope() => ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      test('incoming ADD reaction notifies the recipient', () async {
        final notifications = FakeNotificationService();
        final (result, change) = await handleIncomingReaction(
          message: _makeReactionMessage(envelope()),
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: _ownMlKemSecretKey,
          notificationService: notifications,
          conversationTracker: ActiveConversationTracker(),
          getAppLifecycleState: () => AppLifecycleState.resumed,
        );
        await Future<void>.delayed(Duration.zero);

        expect(result, HandleReactionResult.success);
        expect(change?.type, ReactionChangeType.upserted);
        expect(notifications.shown, hasLength(1));
        expect(notifications.shown.single.senderUsername, 'Sender');
        expect(notifications.shown.single.messageText, contains('👍'));
        expect(notifications.shown.single.contactPeerId, _senderPeerId);
      });

      test(
        'only target author is notified while both target directions persist',
        () async {
          Future<({ReactionChange? change, int notifications, int stored})>
          deliver({required bool targetIsIncoming}) async {
            final localMessages = FakeMessageRepository()
              ..seed([
                ConversationMessage(
                  id: 'msg-1',
                  contactPeerId: _senderPeerId,
                  senderPeerId: targetIsIncoming ? _senderPeerId : 'my-peer',
                  text: 'target',
                  timestamp: '2026-02-27T09:59:00.000Z',
                  status: 'delivered',
                  isIncoming: targetIsIncoming,
                  createdAt: '2026-02-27T09:59:00.000Z',
                ),
              ]);
            final localReactions = FakeReactionRepository();
            final notifications = FakeNotificationService();
            final (_, change) = await handleIncomingReaction(
              message: _makeReactionMessage(envelope()),
              messageRepo: localMessages,
              reactionRepo: localReactions,
              contactRepo: contactRepo,
              bridge: bridge,
              ownMlKemSecretKey: _ownMlKemSecretKey,
              notificationService: notifications,
              conversationTracker: ActiveConversationTracker(),
              getAppLifecycleState: () => AppLifecycleState.resumed,
            );
            await Future<void>.delayed(Duration.zero);
            return (
              change: change,
              notifications: notifications.shown.length,
              stored: localReactions.reactions.length,
            );
          }

          final authored = await deliver(targetIsIncoming: false);
          final received = await deliver(targetIsIncoming: true);

          expect(authored.change?.type, ReactionChangeType.upserted);
          expect(received.change?.type, ReactionChangeType.upserted);
          expect(authored.stored, 1);
          expect(received.stored, 1);
          expect(authored.notifications, 1);
          expect(received.notifications, 0);
        },
      );

      test(
        'missing local identity persists but fails notification closed',
        () async {
          final notifications = FakeNotificationService();
          final original = _makeReactionMessage(envelope());
          final (result, change) = await handleIncomingReaction(
            message: ChatMessage(
              from: original.from,
              to: '',
              content: original.content,
              timestamp: original.timestamp,
              isIncoming: true,
            ),
            messageRepo: messageRepo,
            reactionRepo: reactionRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownMlKemSecretKey: _ownMlKemSecretKey,
            notificationService: notifications,
            conversationTracker: ActiveConversationTracker(),
            getAppLifecycleState: () => AppLifecycleState.resumed,
          );
          await Future<void>.delayed(Duration.zero);

          expect(result, HandleReactionResult.success);
          expect(change?.type, ReactionChangeType.upserted);
          expect(reactionRepo.reactions, hasLength(1));
          expect(notifications.shown, isEmpty);
        },
      );

      test(
        'concurrent exact ADD has one change and one notification',
        () async {
          final barrierRepo = _BarrierReactionRepository();
          final notifications = FakeNotificationService();

          Future<(HandleReactionResult, ReactionChange?)> deliver() {
            return handleIncomingReaction(
              message: _makeReactionMessage(envelope()),
              messageRepo: messageRepo,
              reactionRepo: barrierRepo,
              contactRepo: contactRepo,
              bridge: bridge,
              ownMlKemSecretKey: _ownMlKemSecretKey,
              notificationService: notifications,
              conversationTracker: ActiveConversationTracker(),
              getAppLifecycleState: () => AppLifecycleState.resumed,
            );
          }

          final first = deliver();
          final second = deliver();
          await barrierRepo.bothCallsArrived.future;
          barrierRepo.release.complete();
          final results = await Future.wait([first, second]);
          await Future<void>.delayed(Duration.zero);

          expect(results.where((result) => result.$2 != null), hasLength(1));
          expect(barrierRepo.reactions, hasLength(1));
          expect(barrierRepo.saveReactionCallCount, 1);
          expect(notifications.shown, hasLength(1));
        },
      );

      test('incoming REMOVE reaction does NOT notify', () async {
        bridge.responses['message.decrypt'] = {
          'ok': true,
          'plaintext': jsonEncode({
            'id': 'r1',
            'messageId': 'msg-1',
            'emoji': '👍',
            'action': 'remove',
            'senderPeerId': _senderPeerId,
            'timestamp': '2026-02-27T10:05:00.000Z',
          }),
        };
        final notifications = FakeNotificationService();
        final (result, change) = await handleIncomingReaction(
          message: _makeReactionMessage(envelope()),
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: _ownMlKemSecretKey,
          notificationService: notifications,
          conversationTracker: ActiveConversationTracker(),
          getAppLifecycleState: () => AppLifecycleState.resumed,
        );
        await Future<void>.delayed(Duration.zero);

        expect(result, HandleReactionResult.success);
        expect(change?.type, ReactionChangeType.removed);
        expect(notifications.shown, isEmpty);
      });

      test(
        'ADD reaction is suppressed while viewing that conversation',
        () async {
          final notifications = FakeNotificationService();
          final tracker = ActiveConversationTracker()..setActive(_senderPeerId);
          await handleIncomingReaction(
            message: _makeReactionMessage(envelope()),
            messageRepo: messageRepo,
            reactionRepo: reactionRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownMlKemSecretKey: _ownMlKemSecretKey,
            notificationService: notifications,
            conversationTracker: tracker,
            getAppLifecycleState: () => AppLifecycleState.resumed,
          );
          await Future<void>.delayed(Duration.zero);

          expect(notifications.shown, isEmpty);
        },
      );

      test(
        'explicit suppressReactionNotification suppresses the notification',
        () async {
          final notifications = FakeNotificationService();
          await handleIncomingReaction(
            message: _makeReactionMessage(envelope()),
            messageRepo: messageRepo,
            reactionRepo: reactionRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownMlKemSecretKey: _ownMlKemSecretKey,
            notificationService: notifications,
            conversationTracker: ActiveConversationTracker(),
            getAppLifecycleState: () => AppLifecycleState.resumed,
            suppressReactionNotification: true,
          );
          await Future<void>.delayed(Duration.zero);

          expect(notifications.shown, isEmpty);
        },
      );

      test('no notification deps -> reaction still stored, no throw', () async {
        final (result, change) = await handleIncomingReaction(
          message: _makeReactionMessage(envelope()),
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: _ownMlKemSecretKey,
        );

        expect(result, HandleReactionResult.success);
        expect(change?.type, ReactionChangeType.upserted);
      });

      test(
        'rapid reactions debounce the tone — the second notification is silent',
        () async {
          final notifications = FakeNotificationService();
          final tracker = ActiveConversationTracker();
          final toneTracker = NotificationToneTracker();
          final directory = await Directory.systemTemp.createTemp(
            'direct-reaction-tone-burst-',
          );
          addTearDown(() => directory.delete(recursive: true));
          final coordinator = DurableNotificationToneLease(
            directory: directory,
          );

          Future<void> deliver(String id, String timestamp) async {
            bridge.responses['message.decrypt'] = {
              'ok': true,
              'plaintext': jsonEncode({
                'id': id,
                'messageId': 'msg-1',
                'emoji': '👍',
                'action': 'add',
                'senderPeerId': _senderPeerId,
                'timestamp': timestamp,
              }),
            };
            await handleIncomingReaction(
              message: _makeReactionMessage(envelope()),
              messageRepo: messageRepo,
              reactionRepo: reactionRepo,
              contactRepo: contactRepo,
              bridge: bridge,
              ownMlKemSecretKey: _ownMlKemSecretKey,
              notificationService: notifications,
              conversationTracker: tracker,
              getAppLifecycleState: () => AppLifecycleState.resumed,
              notificationToneTracker: toneTracker,
              durableNotificationCoordinatorResolver: () async => coordinator,
            );
            await Future<void>.delayed(Duration.zero);
          }

          await deliver('rxn-a', '2026-02-27T10:00:00.000Z');
          await deliver('rxn-b', '2026-02-27T10:00:01.000Z');
          final deadline = DateTime.now().add(const Duration(seconds: 2));
          while (notifications.shown.length < 2 &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }

          // Both notify, but the per-conversation tone debounce silences the
          // second so a burst of reactions never spams a sound.
          expect(notifications.shown, hasLength(2));
          expect(notifications.shown[0].silent, isFalse);
          expect(notifications.shown[1].silent, isTrue);
          for (final id in const <String>['rxn-a', 'rxn-b']) {
            final claimFile = File(
              '${directory.path}/'
              '${DurableNotificationToneLease.eventClaimsDirectoryName}/'
              '${DurableNotificationToneLease.messageEventClaimFileName(type: 'message_reaction', eventIdentity: boundedReactionEventIdentity(id))}',
            );
            await _expectCommittedNotificationClaim(claimFile);
          }
          final toneEntries = await Directory(
            '${directory.path}/'
            '${DurableNotificationToneLease.toneLeasesDirectoryName}',
          ).list().where((entity) => entity is File).cast<File>().toList();
          final committedToneLeases = toneEntries
              .where((file) => file.path.endsWith('.lease'))
              .toList();
          expect(committedToneLeases, hasLength(1));
          expect(
            num.tryParse(await committedToneLeases.single.readAsString()),
            isNotNull,
          );
          expect(
            toneEntries.where(
              (file) => file.path.endsWith(
                DurableNotificationToneLease.tonePendingReservationFileSuffix,
              ),
            ),
            isEmpty,
          );
        },
      );
    });

    test(
      'returns senderMismatch when encrypted envelope sender disagrees with payload sender',
      () async {
        final v2 = ReactionPayload.buildEncryptedEnvelope(
          senderPeerId: 'different-envelope-sender',
          kem: 'k',
          ciphertext: 'c',
          nonce: 'n',
        );

        final (result, change) = await handleIncomingReaction(
          message: _makeReactionMessage(v2),
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: _ownMlKemSecretKey,
        );

        expect(result, HandleReactionResult.senderMismatch);
        expect(change, isNull);
        expect(reactionRepo.saveReactionCallCount, 0);
      },
    );

    test('add action — decrypts and persists reaction', () async {
      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, change) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.success);
      expect(change, isNotNull);
      expect(change!.type, ReactionChangeType.upserted);
      expect(change.reaction!.emoji, '👍');
      expect(change.messageId, 'msg-1');
      expect(reactionRepo.saveReactionCallCount, 1);
    });

    test('duplicate add deliveries stay idempotent', () async {
      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final first = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );
      final second = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(first.$1, HandleReactionResult.success);
      expect(second.$1, HandleReactionResult.success);
      expect(first.$2, isNotNull);
      expect(second.$2, isNull);
      expect(reactionRepo.saveReactionCallCount, 1);

      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));
      expect(stored.single.senderPeerId, _senderPeerId);
      expect(stored.single.emoji, '👍');
    });

    test('remove action — decrypts and deletes reaction', () async {
      // Pre-populate
      await reactionRepo.saveReaction(
        const MessageReaction(
          id: 'r1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: _senderPeerId,
          timestamp: '2026-02-27T10:00:00.000Z',
          createdAt: '2026-02-27T10:00:01.000Z',
        ),
      );

      bridge.responses['message.decrypt'] = {
        'ok': true,
        'plaintext': jsonEncode({
          'id': 'r2',
          'messageId': 'msg-1',
          'emoji': '👍',
          'action': 'remove',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-02-27T10:01:00.000Z',
        }),
      };

      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, change) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.success);
      expect(change, isNotNull);
      expect(change!.type, ReactionChangeType.removed);
      expect(change.messageId, 'msg-1');
      expect(change.senderPeerId, _senderPeerId);
      expect(change.reaction, isNull);
      expect(reactionRepo.removeReactionCallCount, 1);

      final remaining = await reactionRepo.getReactionsForMessage('msg-1');
      expect(remaining, isEmpty);
    });

    test('duplicate remove deliveries stay idempotent', () async {
      await reactionRepo.saveReaction(
        const MessageReaction(
          id: 'r1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: _senderPeerId,
          timestamp: '2026-02-27T10:00:00.000Z',
          createdAt: '2026-02-27T10:00:01.000Z',
        ),
      );

      bridge.responses['message.decrypt'] = {
        'ok': true,
        'plaintext': jsonEncode({
          'id': 'r2',
          'messageId': 'msg-1',
          'emoji': '👍',
          'action': 'remove',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-02-27T10:01:00.000Z',
        }),
      };

      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final first = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );
      final second = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(first.$1, HandleReactionResult.success);
      expect(second.$1, HandleReactionResult.success);
      expect(reactionRepo.removeReactionCallCount, 2);
      expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
    });

    test('stale remove does not erase a newer stored reaction', () async {
      await reactionRepo.saveReaction(
        const MessageReaction(
          id: 'r-newer',
          messageId: 'msg-1',
          emoji: '❤️',
          senderPeerId: _senderPeerId,
          timestamp: '2026-02-27T10:02:00.000Z',
          createdAt: '2026-02-27T10:02:01.000Z',
        ),
      );

      bridge.responses['message.decrypt'] = {
        'ok': true,
        'plaintext': jsonEncode({
          'id': 'r-older-remove',
          'messageId': 'msg-1',
          'emoji': '❤️',
          'action': 'remove',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-02-27T10:01:00.000Z',
        }),
      };

      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, change) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.success);
      expect(change, isNull);
      expect(reactionRepo.removeReactionCallCount, 0);

      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));
      expect(stored.single.emoji, '❤️');
      expect(stored.single.timestamp, '2026-02-27T10:02:00.000Z');
    });

    test(
      'INV-T2 remove-then-stale-add stays removed (tombstone closes residual)',
      () async {
        // 1. Seed an active add at T1.
        await reactionRepo.saveReaction(
          const MessageReaction(
            id: 'r-add',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: _senderPeerId,
            timestamp: '2026-02-27T10:00:00.000Z',
            createdAt: '2026-02-27T10:00:01.000Z',
          ),
        );

        final v2 = ReactionPayload.buildEncryptedEnvelope(
          senderPeerId: _senderPeerId,
          kem: 'k',
          ciphertext: 'c',
          nonce: 'n',
        );

        // 2. Apply a remove at T2 > T1 → tombstone.
        bridge.responses['message.decrypt'] = {
          'ok': true,
          'plaintext': jsonEncode({
            'id': 'r-remove',
            'messageId': 'msg-1',
            'emoji': '👍',
            'action': 'remove',
            'senderPeerId': _senderPeerId,
            'timestamp': '2026-02-27T10:01:00.000Z',
          }),
        };
        await handleIncomingReaction(
          message: _makeReactionMessage(v2),
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: _ownMlKemSecretKey,
        );
        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);

        // 3. A STALE re-delivered add (T1 < T2) must NOT resurrect it.
        bridge.responses['message.decrypt'] = {
          'ok': true,
          'plaintext': jsonEncode({
            'id': 'r-add',
            'messageId': 'msg-1',
            'emoji': '👍',
            'action': 'add',
            'senderPeerId': _senderPeerId,
            'timestamp': '2026-02-27T10:00:00.000Z',
          }),
        };
        final (result, change) = await handleIncomingReaction(
          message: _makeReactionMessage(v2),
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: _ownMlKemSecretKey,
        );

        expect(result, HandleReactionResult.success);
        expect(change, isNull);
        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
      },
    );

    test('stale add does not replace a newer stored reaction', () async {
      await reactionRepo.saveReaction(
        const MessageReaction(
          id: 'r-newer',
          messageId: 'msg-1',
          emoji: '❤️',
          senderPeerId: _senderPeerId,
          timestamp: '2026-02-27T10:02:00.000Z',
          createdAt: '2026-02-27T10:02:01.000Z',
        ),
      );

      bridge.responses['message.decrypt'] = {
        'ok': true,
        'plaintext': jsonEncode({
          'id': 'r-older-add',
          'messageId': 'msg-1',
          'emoji': '👍',
          'action': 'add',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-02-27T10:01:00.000Z',
        }),
      };

      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, change) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.success);
      expect(change, isNull);
      expect(reactionRepo.saveReactionCallCount, 1);
      expect(reactionRepo.lastSavedReaction?.emoji, '❤️');

      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));
      expect(stored.single.emoji, '❤️');
      expect(stored.single.timestamp, '2026-02-27T10:02:00.000Z');
    });

    test(
      'FDC-18-06 a stale duplicate reaction (older than the current tombstone) '
      'is ignored under the raised concurrent-inbox duplicate pressure',
      () async {
        // FDC-18 fires the durable inbox copy CONCURRENTLY for unknown-presence
        // toggles, so a drained OLD copy can arrive AFTER a newer remove. The
        // receive last-writer-wins tombstone must still win — receive path is
        // unedited; this pins it under the new duplicate pressure (M6 weakens
        // _isStaleComparedToCurrent -> the stale add resurrects -> RED).

        // 1. Active add at T1.
        await reactionRepo.saveReaction(
          const MessageReaction(
            id: 'r-add',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: _senderPeerId,
            timestamp: '2026-02-27T10:00:00.000Z',
            createdAt: '2026-02-27T10:00:01.000Z',
          ),
        );

        final v2 = ReactionPayload.buildEncryptedEnvelope(
          senderPeerId: _senderPeerId,
          kem: 'k',
          ciphertext: 'c',
          nonce: 'n',
        );

        // 2. Remove at T2 > T1 → tombstone.
        bridge.responses['message.decrypt'] = {
          'ok': true,
          'plaintext': jsonEncode({
            'id': 'r-remove',
            'messageId': 'msg-1',
            'emoji': '👍',
            'action': 'remove',
            'senderPeerId': _senderPeerId,
            'timestamp': '2026-02-27T10:01:00.000Z',
          }),
        };
        await handleIncomingReaction(
          message: _makeReactionMessage(v2),
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: _ownMlKemSecretKey,
        );
        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);

        // 3. A STALE drained add (T1 < T2) must be ignored, not resurrect.
        bridge.responses['message.decrypt'] = {
          'ok': true,
          'plaintext': jsonEncode({
            'id': 'r-add',
            'messageId': 'msg-1',
            'emoji': '👍',
            'action': 'add',
            'senderPeerId': _senderPeerId,
            'timestamp': '2026-02-27T10:00:00.000Z',
          }),
        };
        late HandleReactionResult result;
        ReactionChange? change;
        final events = await _captureFlowEvents(() async {
          final (r, c) = await handleIncomingReaction(
            message: _makeReactionMessage(v2),
            messageRepo: messageRepo,
            reactionRepo: reactionRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownMlKemSecretKey: _ownMlKemSecretKey,
          );
          result = r;
          change = c;
        });

        expect(result, HandleReactionResult.success);
        expect(change, isNull);
        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
        expect(
          events.map((e) => e['event']),
          contains('REACTION_RECEIVE_STALE_IGNORED'),
        );
      },
    );

    test('ignores add action when the target message is missing', () async {
      bridge.responses['message.decrypt'] = {
        'ok': true,
        'plaintext': jsonEncode({
          'id': 'r1',
          'messageId': 'missing-msg',
          'emoji': '👍',
          'action': 'add',
          'senderPeerId': _senderPeerId,
          'timestamp': '2026-02-27T10:00:00.000Z',
        }),
      };

      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, change) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.targetUnavailable);
      expect(change, isNull);
      expect(reactionRepo.saveReactionCallCount, 0);
      expect(await reactionRepo.getReactionsForMessage('missing-msg'), isEmpty);
    });

    test('ignores add action when the target message is deleted', () async {
      messageRepo.seed([
        const ConversationMessage(
          id: 'msg-1',
          contactPeerId: _senderPeerId,
          senderPeerId: _senderPeerId,
          text: 'deleted',
          timestamp: '2026-02-27T10:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-27T10:00:00.000Z',
          deletedAt: '2026-02-27T10:05:00.000Z',
          deletedByPeerId: _senderPeerId,
        ),
      ]);

      final v2 = ReactionPayload.buildEncryptedEnvelope(
        senderPeerId: _senderPeerId,
        kem: 'k',
        ciphertext: 'c',
        nonce: 'n',
      );

      final (result, change) = await handleIncomingReaction(
        message: _makeReactionMessage(v2),
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: _ownMlKemSecretKey,
      );

      expect(result, HandleReactionResult.targetUnavailable);
      expect(change, isNull);
      expect(reactionRepo.saveReactionCallCount, 0);
      expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
    });
  });
}
