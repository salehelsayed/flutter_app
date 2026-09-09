import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_sibling_dispositions.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../domain/repositories/fake_reaction_repository.dart';
import '../../../shared/fakes/in_memory_inbox_staging_repository.dart';

const _senderPeerId = '12D3KooWSender';

class _UnavailableInboxStagingRepository
    extends InMemoryInboxStagingRepository {
  @override
  Future<List<String>> stageEntries(List<InboxStagingEntry> entries) async {
    throw StateError('isolated staging unavailable');
  }
}

ChatMessage _makeV2ReactionMessage({
  String action = 'add',
  String senderPeerId = _senderPeerId,
}) {
  return ChatMessage(
    from: senderPeerId,
    to: 'my-peer',
    content: ReactionPayload.buildEncryptedEnvelope(
      senderPeerId: senderPeerId,
      kem: 'k',
      ciphertext: 'c',
      nonce: 'n',
    ),
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
  );
}

void main() {
  late StreamController<ChatMessage> reactionStreamController;
  late FakeBridge bridge;
  late FakeContactRepository contactRepo;
  late FakeMessageRepository messageRepo;
  late FakeReactionRepository reactionRepo;
  late ReactionListener listener;

  setUp(() {
    reactionStreamController = StreamController<ChatMessage>.broadcast();
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
          senderPeerId: _senderPeerId,
          text: 'hello',
          timestamp: '2026-02-27T10:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-27T10:00:00.000Z',
        ),
      ]);
    reactionRepo = FakeReactionRepository();

    listener = ReactionListener(
      reactionStream: reactionStreamController.stream,
      messageRepo: messageRepo,
      reactionRepo: reactionRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => 'own-secret-key',
    );
  });

  tearDown(() {
    listener.dispose();
    reactionStreamController.close();
  });

  test('TC-361-03a the reaction listener applies the blocked policy to the '
      'RESOLVED logical contact before decrypt', () async {
    const linkedTransport = 'peer-linked-transport';
    contactRepo.seed([
      ContactModel(
        peerId: _senderPeerId,
        publicKey: 'pk',
        rendezvous: '/relay',
        username: 'Sender',
        signature: 'sig',
        scannedAt: '2026-01-01T00:00:00.000Z',
        isBlocked: true,
        blockedAt: '2026-08-11T12:00:00.000Z',
      ),
    ]);
    final blockedStream = StreamController<ChatMessage>.broadcast();
    addTearDown(blockedStream.close);
    final blockedListener = ReactionListener(
      reactionStream: blockedStream.stream,
      messageRepo: messageRepo,
      reactionRepo: reactionRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => 'own-secret-key',
      transportAuthority: _FakeTransportAuthority({
        linkedTransport: const DirectTransportAuthorityResolution.authorized(
          kind: DirectTransportAuthorityKind.linked,
          contactAccountPeerId: _senderPeerId,
          contactIsBlocked: true,
        ),
      }),
    );
    addTearDown(blockedListener.dispose);
    blockedListener.start();

    final envelope = ReactionPayload.buildEncryptedEnvelope(
      senderPeerId: linkedTransport,
      eventId: 'r-linked-blocked',
      action: ReactionPayload.addAction,
      targetMessageId: 'msg-1',
      kem: 'k',
      ciphertext: 'c',
      nonce: 'n',
    );
    blockedStream.add(
      ChatMessage(
        from: linkedTransport,
        to: 'my-peer',
        content: envelope,
        timestamp: '2026-08-11T12:00:00.000Z',
        isIncoming: true,
      ),
    );
    await Future.delayed(const Duration(milliseconds: 100));
    expect(
      reactionRepo.linkedApplyTransports,
      isEmpty,
      reason: 'a blocked logical contact never reaches the handler apply',
    );
    expect(bridge.sendCallCount, 0, reason: 'blocked precedes decrypt');
  });

  group('ReactionListener', () {
    test(
      'processes add reaction and broadcasts to incomingReactionStream',
      () async {
        final received = <MessageReaction>[];
        listener.incomingReactionStream.listen(received.add);
        listener.start();

        reactionStreamController.add(_makeV2ReactionMessage());
        await Future.delayed(const Duration(milliseconds: 100));

        expect(received.length, 1);
        expect(received[0].emoji, '👍');
        expect(received[0].messageId, 'msg-1');
        expect(reactionRepo.saveReactionCallCount, 1);
      },
    );

    for (final failure in ['synchronous', 'asynchronous', 'pending']) {
      test(
        'publishes committed reaction despite $failure display retry',
        () async {
          listener.dispose();
          final retryStarted = Completer<void>();
          final releaseRetry = Completer<void>();
          addTearDown(() {
            if (!releaseRetry.isCompleted) releaseRetry.complete();
          });
          listener = ReactionListener(
            reactionStream: reactionStreamController.stream,
            messageRepo: messageRepo,
            reactionRepo: reactionRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            getOwnMlKemSecretKey: () async => 'own-secret-key',
            retryNotificationDisplays: () {
              retryStarted.complete();
              if (failure == 'synchronous') {
                throw StateError('isolated notification sink failure');
              }
              if (failure == 'asynchronous') {
                return Future<void>.error(
                  StateError('isolated notification sink failure'),
                );
              }
              return releaseRetry.future;
            },
          );
          final changes = <ReactionChange>[];
          listener.incomingReactionChangeStream.listen(changes.add);
          listener.start();
          reactionStreamController.add(_makeV2ReactionMessage());
          await retryStarted.future;
          await pumpEventQueue();

          expect(reactionRepo.reactions, hasLength(1));
          expect(
            changes,
            hasLength(1),
            reason: 'display cannot hide a durable reaction',
          );
          expect(changes.single.type, ReactionChangeType.upserted);
          expect(changes.single.reaction?.id, 'r1');
          releaseRetry.complete();
          await pumpEventQueue();
          expect(changes, hasLength(1));
        },
      );
    }

    for (final stageFails in [false, true]) {
      for (final failure in ['synchronous', 'asynchronous', 'pending']) {
        test(
          'direct reaction ACK and UI survive $failure display with staging failure=$stageFails',
          () async {
            final retryStarted = Completer<void>();
            final releaseRetry = Completer<void>();
            addTearDown(() {
              if (!releaseRetry.isCompleted) releaseRetry.complete();
            });
            final changes = <ReactionChange>[];
            listener.incomingReactionChangeStream.listen(changes.add);
            final staging = stageFails
                ? _UnavailableInboxStagingRepository()
                : InMemoryInboxStagingRepository();
            final service = P2PServiceImpl(
              bridge: bridge,
              inboxStagingRepository: staging,
              replayRecoveredInboxReaction:
                  (message, {String? stagedEntryId}) async {
                    final (result, change) = await handleIncomingReaction(
                      message: message,
                      messageRepo: messageRepo,
                      reactionRepo: reactionRepo,
                      contactRepo: contactRepo,
                      bridge: bridge,
                      ownMlKemSecretKey: 'own-secret-key',
                      retryNotificationDisplays: () {
                        retryStarted.complete();
                        if (failure == 'synchronous') {
                          throw StateError(
                            'isolated notification sink failure',
                          );
                        }
                        if (failure == 'asynchronous') {
                          return Future<void>.error(
                            StateError('isolated notification sink failure'),
                          );
                        }
                        return releaseRetry.future;
                      },
                    );
                    if (result == HandleReactionResult.success &&
                        change != null) {
                      listener.publishPersistedChange(change);
                    }
                    return mapReactionReplayResultToDisposition(result);
                  },
            );
            addTearDown(service.dispose);
            final envelope = _makeV2ReactionMessage();
            bridge.onMessageReceived?.call(
              ChatMessage(
                from: envelope.from,
                to: envelope.to,
                content: envelope.content,
                timestamp: envelope.timestamp,
                isIncoming: true,
                transport: 'direct',
                confirmNonce: 'isolated-reaction-receipt',
              ),
            );
            await retryStarted.future;
            await pumpEventQueue();
            expect(reactionRepo.reactions, hasLength(1));
            expect(
              bridge.sentMessages
                  .map(jsonDecode)
                  .where((request) => request['cmd'] == 'message:confirm')
                  .map((request) => request['payload']),
              [
                {'nonce': 'isolated-reaction-receipt', 'ok': true},
              ],
            );
            expect(changes, hasLength(1));
            expect(changes.single.reaction?.id, 'r1');
            expect(staging.entry('direct:isolated-reaction-receipt'), isNull);
            releaseRetry.complete();
            await pumpEventQueue();
            expect(changes, hasLength(1));
          },
        );
      }
    }

    test(
      'failed notification custody keeps stage-error reaction unacknowledged',
      () async {
        final custodyAttempted = Completer<void>();
        var displayRetries = 0;
        final changes = <ReactionChange>[];
        listener.incomingReactionChangeStream.listen(changes.add);
        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: _UnavailableInboxStagingRepository(),
          replayRecoveredInboxReaction:
              (message, {String? stagedEntryId}) async {
                final (result, change) = await handleIncomingReaction(
                  message: message,
                  messageRepo: messageRepo,
                  reactionRepo: reactionRepo,
                  contactRepo: contactRepo,
                  bridge: bridge,
                  ownMlKemSecretKey: 'own-secret-key',
                  stageNotificationDisplayCustody:
                      ({required payload, required targetMessage}) async {
                        custodyAttempted.complete();
                        throw StateError(
                          'isolated notification custody unavailable',
                        );
                      },
                  retryNotificationDisplays: () async => displayRetries++,
                );
                if (result == HandleReactionResult.success && change != null) {
                  listener.publishPersistedChange(change);
                }
                return mapReactionReplayResultToDisposition(result);
              },
        );
        addTearDown(service.dispose);
        // Display custody is staged only for a locally authored target.
        messageRepo.seed([
          const ConversationMessage(
            id: 'msg-1',
            contactPeerId: _senderPeerId,
            senderPeerId: 'my-peer',
            text: 'isolated target',
            timestamp: '2026-02-27T10:00:00.000Z',
            status: 'delivered',
            isIncoming: false,
            createdAt: '2026-02-27T10:00:00.000Z',
          ),
        ]);
        final envelope = _makeV2ReactionMessage();
        bridge.onMessageReceived?.call(
          ChatMessage(
            from: envelope.from,
            to: envelope.to,
            content: envelope.content,
            timestamp: envelope.timestamp,
            isIncoming: true,
            transport: 'direct',
            confirmNonce: 'isolated-reaction-custody-failure',
          ),
        );
        await custodyAttempted.future;
        await pumpEventQueue();
        expect(reactionRepo.reactions, isEmpty);
        expect(changes, isEmpty);
        expect(displayRetries, 0);
        expect(bridge.commandLog, isNot(contains('message:confirm')));
      },
    );

    test(
      'publishes an already-persisted replay change without persisting again',
      () async {
        final reactions = <MessageReaction>[];
        final changes = <ReactionChange>[];
        listener.incomingReactionStream.listen(reactions.add);
        listener.incomingReactionChangeStream.listen(changes.add);

        const reaction = MessageReaction(
          id: 'replayed-r1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: _senderPeerId,
          timestamp: '2026-02-27T10:00:00.000Z',
          createdAt: '2026-02-27T10:00:01.000Z',
        );
        listener.publishPersistedChange(ReactionChange.upsert(reaction));
        await Future<void>.delayed(Duration.zero);

        expect(reactions, [reaction]);
        expect(changes, hasLength(1));
        expect(changes.single.reaction, reaction);
        expect(reactionRepo.saveReactionCallCount, 0);
      },
    );

    test(
      'processes remove reaction and broadcasts a removal change event',
      () async {
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

        final received = <ReactionChange>[];
        listener.incomingReactionChangeStream.listen(received.add);
        listener.start();

        reactionStreamController.add(_makeV2ReactionMessage(action: 'remove'));
        await Future.delayed(const Duration(milliseconds: 100));

        expect(received, hasLength(1));
        expect(received.single.type, ReactionChangeType.removed);
        expect(received.single.messageId, 'msg-1');
        expect(received.single.senderPeerId, _senderPeerId);
        expect(reactionRepo.removeReactionCallCount, 1);
      },
    );

    test('remove action does not emit to incomingReactionStream', () async {
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

      final received = <MessageReaction>[];
      listener.incomingReactionStream.listen(received.add);
      listener.start();

      reactionStreamController.add(_makeV2ReactionMessage(action: 'remove'));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isEmpty);
    });

    test('rejects blocked senders', () async {
      // Block the sender
      await contactRepo.blockContact(_senderPeerId);

      final received = <MessageReaction>[];
      listener.incomingReactionStream.listen(received.add);
      listener.start();

      reactionStreamController.add(_makeV2ReactionMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isEmpty);
      expect(reactionRepo.saveReactionCallCount, 0);
    });

    test('does not broadcast for decryption failure', () async {
      bridge.responses['message.decrypt'] = {'ok': false, 'errorCode': 'err'};

      final received = <MessageReaction>[];
      listener.incomingReactionStream.listen(received.add);
      listener.start();

      reactionStreamController.add(_makeV2ReactionMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isEmpty);
    });

    test('does not broadcast for unknown sender', () async {
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

      final received = <MessageReaction>[];
      listener.incomingReactionStream.listen(received.add);
      listener.start();

      reactionStreamController.add(
        ChatMessage(
          from: 'unknown-peer',
          to: 'my-peer',
          content: ReactionPayload.buildEncryptedEnvelope(
            senderPeerId: 'unknown-peer',
            kem: 'k',
            ciphertext: 'c',
            nonce: 'n',
          ),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isEmpty);
    });

    test('does not broadcast when the target message is missing', () async {
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

      final received = <MessageReaction>[];
      final changes = <ReactionChange>[];
      listener.incomingReactionStream.listen(received.add);
      listener.incomingReactionChangeStream.listen(changes.add);
      listener.start();

      reactionStreamController.add(_makeV2ReactionMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isEmpty);
      expect(changes, isEmpty);
      expect(reactionRepo.saveReactionCallCount, 0);
    });

    test('start is idempotent', () {
      listener.start();
      listener.start(); // no error
    });

    test('stop cancels subscription', () async {
      final received = <MessageReaction>[];
      listener.incomingReactionStream.listen(received.add);
      listener.start();
      listener.stop();

      reactionStreamController.add(_makeV2ReactionMessage());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(received, isEmpty);
    });

    test('dispose closes stream', () {
      listener.start();
      listener.dispose();
      // No error on dispose
    });
  });
}

class _FakeTransportAuthority implements DirectTransportAuthorityResolver {
  _FakeTransportAuthority(this.byTransport);

  final Map<String, DirectTransportAuthorityResolution> byTransport;

  @override
  Future<DirectTransportAuthorityResolution> resolveDirectTransportAuthority(
    String transportPeerId,
  ) async =>
      byTransport[transportPeerId] ??
      const DirectTransportAuthorityResolution.refused('unknown_transport');
}
