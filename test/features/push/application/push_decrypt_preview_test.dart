import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/group_reaction_notification_copy.dart';
import 'package:flutter_app/features/push/application/push_decrypt_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveBackgroundPushNotification', () {
    test(
      'authenticated inner id anchors test-mutated missing outer id',
      () async {
        final directMessage = await resolveBackgroundPushNotification(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-alice',
              'kem': 'kem',
              'ciphertext': 'ciphertext',
              'nonce': 'direct-message-nonce',
            },
          ),
          directMessageContext: const DirectMessageNotificationContext(
            senderPeerId: 'peer-alice',
            senderUsername: 'Alice',
            expectedMessageId: null,
          ),
          decryptOneToOne:
              ({required kem, required ciphertext, required nonce}) async =>
                  const MessagePayload(
                    id: 'direct-inner-message',
                    text: 'hello',
                    senderPeerId: 'peer-alice',
                    senderUsername: 'Alice',
                    timestamp: '2026-08-03T10:00:00.000Z',
                  ).toInnerJson(),
        );
        expect(
          directMessage.resolvedEventIdentity,
          const ResolvedPushEventIdentity.authenticatedInner(
            kind: ConversationNotificationContentKind.message,
            canonicalEventId: 'direct-inner-message',
          ),
        );

        final groupMessage = await resolveBackgroundPushNotification(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'sender_id': 'peer-alice',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'group-message-nonce',
            },
          ),
          groupMessageContext: const GroupMessageNotificationContext(
            groupId: 'group-team',
            groupName: 'Team',
            localPeerId: 'peer-local',
            senderPeerId: 'peer-alice',
            senderUsername: 'Alice',
            expectedMessageId: null,
          ),
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => jsonEncode(<String, Object?>{
                'groupId': 'group-team',
                'messageId': 'group-inner-message',
                'senderId': 'peer-alice',
                'text': 'hello group',
              }),
        );
        expect(
          groupMessage.resolvedEventIdentity,
          const ResolvedPushEventIdentity.authenticatedInner(
            kind: ConversationNotificationContentKind.message,
            canonicalEventId: 'group-inner-message',
          ),
        );
        expect(
          (groupMessage.groupComparand
                  as BackgroundGroupMessageNotificationComparand)
              .messageId,
          'group-inner-message',
        );

        final directReaction = await resolveBackgroundPushNotification(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'message_reaction',
              'sender_id': 'peer-alice',
              'target_message_id': 'direct-target',
              'action': 'add',
              'kem': 'kem',
              'ciphertext': 'ciphertext',
              'nonce': 'direct-reaction-nonce',
            },
          ),
          directReactionContext: const DirectReactionNotificationContext(
            actorPeerId: 'peer-alice',
            actorUsername: 'Alice',
            targetMessageId: 'direct-target',
          ),
          decryptOneToOne:
              ({required kem, required ciphertext, required nonce}) async =>
                  jsonEncode(<String, Object?>{
                    'id': 'direct-inner-reaction',
                    'messageId': 'direct-target',
                    'emoji': '👍',
                    'action': 'add',
                    'senderPeerId': 'peer-alice',
                    'timestamp': '2026-08-03T10:01:00.000Z',
                  }),
        );
        expect(
          directReaction.resolvedEventIdentity,
          const ResolvedPushEventIdentity.authenticatedInner(
            kind: ConversationNotificationContentKind.reaction,
            canonicalEventId: 'direct-inner-reaction',
            targetMessageId: 'direct-target',
            action: 'add',
          ),
        );

        final groupReaction = await resolveBackgroundPushNotification(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_reaction',
              'groupId': 'group-team',
              'reactor_peer_id': 'peer-alice',
              'target_message_id': 'group-target',
              'action': 'add',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'group-reaction-nonce',
            },
          ),
          groupReactionContext: const GroupReactionNotificationContext(
            groupId: 'group-team',
            groupName: 'Team',
            actorPeerId: 'peer-alice',
            actorUsername: 'Alice',
            targetMessageId: 'group-target',
          ),
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => jsonEncode(<String, Object?>{
                'id': 'group-reaction-state',
                'messageId': 'group-target',
                'emoji': '👍',
                'action': 'add',
                'senderPeerId': 'peer-alice',
                'timestamp': '2026-08-03T10:02:00.000Z',
                'eventId': 'group-inner-transition',
              }),
        );
        expect(
          groupReaction.resolvedEventIdentity,
          const ResolvedPushEventIdentity.authenticatedInner(
            kind: ConversationNotificationContentKind.reaction,
            canonicalEventId: 'group-inner-transition',
            targetMessageId: 'group-target',
            action: 'add',
          ),
        );
      },
    );

    test('reaction preview uses validated actor and semantic body', () async {
      const message = RemoteMessage(
        data: {
          'type': 'message_reaction',
          'sender_id': 'peer-alice',
          'event_id': 'reaction-1',
          'target_message_id': 'message-owned-by-bob',
          'action': 'add',
          'kem': 'kem',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      );

      final resolved = await resolveBackgroundPushNotification(
        message,
        directReactionContext: const DirectReactionNotificationContext(
          actorPeerId: 'peer-alice',
          actorUsername: 'Alice',
          targetMessageId: 'message-owned-by-bob',
        ),
        decryptOneToOne:
            ({required kem, required ciphertext, required nonce}) async {
              return jsonEncode({
                'id': 'reaction-1',
                'messageId': 'message-owned-by-bob',
                'emoji': '👍',
                'action': 'add',
                'senderPeerId': 'peer-alice',
                'timestamp': '2026-07-12T09:00:00.000Z',
              });
            },
      );

      expect(resolved.title, 'Alice');
      expect(resolved.body, 'Reacted 👍 to your message');
      expect(resolved.payload, 'peer-alice');
    });

    test('direct reaction authenticated inner mismatch fails closed', () async {
      await expectLater(
        resolveBackgroundPushNotification(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'message_reaction',
              'sender_id': 'peer-alice',
              'event_id': 'reaction-outer',
              'target_message_id': 'message-owned-by-bob',
              'action': 'add',
              'kem': 'kem',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
          directReactionContext: const DirectReactionNotificationContext(
            actorPeerId: 'peer-alice',
            actorUsername: 'Alice',
            targetMessageId: 'message-owned-by-bob',
          ),
          decryptOneToOne:
              ({required kem, required ciphertext, required nonce}) async =>
                  jsonEncode(<String, Object?>{
                    'id': 'reaction-authenticated-inner',
                    'messageId': 'message-owned-by-bob',
                    'emoji': '👍',
                    'action': 'add',
                    'senderPeerId': 'peer-alice',
                    'timestamp': '2026-08-03T10:00:00.000Z',
                  }),
        ),
        throwsA(
          isA<DirectReactionNotificationIntegrityException>().having(
            (error) => error.reason,
            'reason',
            'direct_reaction_parity_mismatch',
          ),
        ),
      );
    });

    test(
      'group reaction preview uses local actor and kind without emoji or target text',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_reaction',
            'groupId': 'group-team',
            'reactor_peer_id': 'peer-alice',
            'event_id': 'transition-1',
            'target_message_id': 'message-owned-by-bob',
            'action': 'add',
            'keyEpoch': '7',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );

        final resolved = await resolveBackgroundPushNotification(
          message,
          groupReactionContext: const GroupReactionNotificationContext(
            groupId: 'group-team',
            groupName: 'Team Chat',
            actorPeerId: 'peer-alice',
            actorUsername: 'Alice',
            targetMessageId: 'message-owned-by-bob',
            targetKind: GroupReactionTargetKind.voiceMessage,
          ),
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async {
                expect(groupId, 'group-team');
                expect(keyEpoch, 7);
                return jsonEncode({
                  'id': 'deterministic-reaction-state',
                  'messageId': 'message-owned-by-bob',
                  'emoji': '👍',
                  'action': 'add',
                  'senderPeerId': 'peer-alice',
                  'timestamp': '2026-07-12T09:00:00.000Z',
                  'eventId': 'transition-1',
                });
              },
        );

        expect(resolved.title, 'Team Chat');
        expect(resolved.body, 'Alice reacted to your voice message');
        expect(resolved.body, isNot(contains('👍')));
        expect(
          resolved.payload,
          'group:group-team|message:message-owned-by-bob',
        );
        final comparand =
            resolved.groupComparand
                as BackgroundGroupReactionNotificationComparand;
        expect(comparand.reactionId, 'deterministic-reaction-state');
        expect(comparand.messageId, 'message-owned-by-bob');
        expect(comparand.senderPeerId, 'peer-alice');
        expect(comparand.timestamp, '2026-07-12T09:00:00.000Z');
        expect(
          comparand.notificationEventIdentity,
          boundedReactionEventIdentity('transition-1'),
        );
      },
    );

    test(
      'group reaction decrypt or input failure keeps a provisional fence scope',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_reaction',
            'groupId': 'group-team',
            'reactor_peer_id': 'peer-alice',
            'event_id': 'transition-1',
            'target_message_id': 'message-owned-by-bob',
            'action': 'add',
            'keyEpoch': '7',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );
        const context = GroupReactionNotificationContext(
          groupId: 'group-team',
          groupName: 'Team Chat',
          actorPeerId: 'peer-alice',
          actorUsername: 'Alice',
          targetMessageId: 'message-owned-by-bob',
          targetKind: GroupReactionTargetKind.photo,
        );

        final resolved = await resolveBackgroundPushNotification(
          message,
          groupReactionContext: context,
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => throw StateError('crypto unavailable'),
        );

        expect(resolved.title, 'Team Chat');
        expect(resolved.body, 'Alice reacted to your photo');
        expect(resolved.title, isNot(backgroundPushDefaultTitle));
        expect(resolved.body, isNot(backgroundPushDefaultBody));
        final comparand =
            resolved.groupComparand
                as BackgroundProvisionalGroupReactionNotificationComparand;
        expect(comparand.groupId, 'group-team');
        expect(comparand.messageId, 'message-owned-by-bob');
        expect(comparand.senderPeerId, 'peer-alice');
        expect(
          comparand.notificationEventIdentity,
          boundedReactionEventIdentity('transition-1'),
        );

        final inputUnavailable = await resolveBackgroundPushNotification(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_reaction',
              'groupId': 'group-team',
              'reactor_peer_id': 'peer-alice',
              'event_id': 'transition-1',
              'target_message_id': 'message-owned-by-bob',
              'action': 'add',
            },
          ),
          groupReactionContext: context,
        );
        expect(
          inputUnavailable.groupComparand,
          isA<BackgroundProvisionalGroupReactionNotificationComparand>(),
        );
      },
    );

    test(
      'group reaction invalid scope and unorderable outage fail closed',
      () async {
        const validData = <String, dynamic>{
          'type': 'group_reaction',
          'groupId': 'group-team',
          'reactor_peer_id': 'peer-alice',
          'event_id': 'transition-1',
          'target_message_id': 'message-owned-by-bob',
          'action': 'add',
          'keyEpoch': '7',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        };
        const context = GroupReactionNotificationContext(
          groupId: 'group-team',
          groupName: 'Team Chat',
          actorPeerId: 'peer-alice',
          actorUsername: 'Alice',
          targetMessageId: 'message-owned-by-bob',
        );

        Future<void> expectIntegrityFailure(
          Map<String, dynamic> data,
          GroupReactionNotificationContext? localContext,
        ) async {
          await expectLater(
            resolveBackgroundPushNotification(
              RemoteMessage(data: data),
              groupReactionContext: localContext,
              decryptGroup:
                  ({
                    required groupId,
                    required keyEpoch,
                    required ciphertext,
                    required nonce,
                  }) async => throw StateError('must not decrypt'),
            ),
            throwsA(isA<GroupReactionNotificationIntegrityException>()),
          );
        }

        await expectIntegrityFailure(validData, null);
        await expectIntegrityFailure(<String, dynamic>{
          ...validData,
          'reactor_peer_id': 'peer-mismatch',
        }, context);
        await expectIntegrityFailure(<String, dynamic>{
          ...validData,
          'action': 'remove',
        }, context);
        final missingEvent = <String, dynamic>{...validData}
          ..remove('event_id');
        await expectIntegrityFailure(missingEvent, context);

        await expectLater(
          resolveBackgroundPushNotification(
            const RemoteMessage(
              data: <String, dynamic>{
                'type': 'group_reaction',
                'groupId': 'group-team',
                'reactor_peer_id': 'peer-alice',
                'event_id': 'transition-1',
                'target_message_id': 'message-owned-by-bob',
                'action': 'add',
              },
            ),
            groupReactionContext: const GroupReactionNotificationContext(
              groupId: 'group-team',
              groupName: 'Team Chat',
              actorPeerId: 'peer-alice',
              actorUsername: 'Alice',
              targetMessageId: 'message-owned-by-bob',
              currentReactionTimestamp: '2026-08-03T00:00:00.000Z',
            ),
          ),
          throwsA(isA<GroupReactionNotificationIntegrityException>()),
        );
      },
    );

    test(
      'group reaction decrypted parity mismatch suppresses instead of displaying fallback',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_reaction',
            'groupId': 'group-team',
            'reactor_peer_id': 'peer-alice',
            'event_id': 'transition-1',
            'target_message_id': 'message-owned-by-bob',
            'action': 'add',
            'keyEpoch': '7',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );

        await expectLater(
          resolveBackgroundPushNotification(
            message,
            groupReactionContext: const GroupReactionNotificationContext(
              groupId: 'group-team',
              groupName: 'Team Chat',
              actorPeerId: 'peer-alice',
              actorUsername: 'Alice',
              targetMessageId: 'message-owned-by-bob',
            ),
            decryptGroup:
                ({
                  required groupId,
                  required keyEpoch,
                  required ciphertext,
                  required nonce,
                }) async => jsonEncode(<String, Object?>{
                  'id': 'deterministic-reaction-state',
                  'messageId': 'different-target',
                  'emoji': '👍',
                  'action': 'add',
                  'senderPeerId': 'peer-alice',
                  'timestamp': '2026-07-12T09:00:00.000Z',
                  'eventId': 'transition-1',
                }),
          ),
          throwsA(
            isA<GroupReactionNotificationIntegrityException>().having(
              (error) => error.reason,
              'reason',
              'group_reaction_parity_mismatch',
            ),
          ),
        );
      },
    );

    test('delayed ADD older than a REMOVE tombstone is suppressed', () async {
      const message = RemoteMessage(
        data: {
          'type': 'group_reaction',
          'groupId': 'group-team',
          'reactor_peer_id': 'peer-alice',
          'event_id': 'transition-old-add',
          'target_message_id': 'message-owned-by-bob',
          'action': 'add',
          'keyEpoch': '7',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      );

      await expectLater(
        resolveBackgroundPushNotification(
          message,
          groupReactionContext: const GroupReactionNotificationContext(
            groupId: 'group-team',
            groupName: 'Team Chat',
            actorPeerId: 'peer-alice',
            actorUsername: 'Alice',
            targetMessageId: 'message-owned-by-bob',
            currentReactionTimestamp: '2026-07-12T09:00:00.000Z',
            currentReactionRemovedAt: '2026-07-12T09:05:00.000Z',
          ),
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => jsonEncode(<String, Object?>{
                'id': 'deterministic-reaction-state',
                'messageId': 'message-owned-by-bob',
                'emoji': '👍',
                'action': 'add',
                'senderPeerId': 'peer-alice',
                'timestamp': '2026-07-12T09:01:00.000Z',
                'eventId': 'transition-old-add',
              }),
        ),
        throwsA(
          isA<GroupReactionNotificationIntegrityException>().having(
            (error) => error.reason,
            'reason',
            'group_reaction_stale_local_state',
          ),
        ),
      );
    });

    test(
      'acknowledged exact ADD replay is suppressed before show but a later ADD survives',
      () async {
        const context = GroupReactionNotificationContext(
          groupId: 'group-team',
          groupName: 'Team Chat',
          actorPeerId: 'peer-alice',
          actorUsername: 'Alice',
          targetMessageId: 'message-owned-by-bob',
          currentReactionId: 'reaction-a',
          currentReactionTimestamp: '2026-07-12T09:00:00.000Z',
          currentReactionAcknowledged: true,
        );

        Future<BackgroundPushNotificationFallback> resolve({
          required String eventId,
          required String reactionId,
          required String timestamp,
        }) => resolveBackgroundPushNotification(
          RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_reaction',
              'groupId': 'group-team',
              'reactor_peer_id': 'peer-alice',
              'event_id': eventId,
              'target_message_id': 'message-owned-by-bob',
              'action': 'add',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
          groupReactionContext: context,
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => jsonEncode(<String, Object?>{
                'id': reactionId,
                'messageId': 'message-owned-by-bob',
                'emoji': '👍',
                'action': 'add',
                'senderPeerId': 'peer-alice',
                'timestamp': timestamp,
                'eventId': eventId,
              }),
        );

        await expectLater(
          resolve(
            eventId: 'transition-a-replay',
            reactionId: 'reaction-a',
            timestamp: '2026-07-12T09:00:00.000Z',
          ),
          throwsA(
            isA<GroupReactionNotificationIntegrityException>().having(
              (error) => error.reason,
              'reason',
              'group_reaction_stale_local_state',
            ),
          ),
        );

        final later = await resolve(
          eventId: 'transition-b',
          reactionId: 'reaction-b',
          timestamp: '2026-07-12T09:00:02.000Z',
        );
        expect(
          later.groupComparand,
          isA<BackgroundGroupReactionNotificationComparand>(),
        );
      },
    );

    test(
      'signed group reaction nomination binds this exact transport installation',
      () async {
        final data = _signedGroupReactionPushData(
          notificationRecipients: const <String>[
            'transport-author-one',
            'transport-author-two',
          ],
        );
        final verificationCalls = <Map<String, String>>[];

        final verified = await verifyGroupReactionNotificationNomination(
          data: data,
          localTransportPeerId: 'transport-author-two',
          verifySignature:
              ({
                required publicKey,
                required signedPayload,
                required signature,
              }) async {
                verificationCalls.add(<String, String>{
                  'publicKey': publicKey,
                  'signedPayload': signedPayload,
                  'signature': signature,
                });
                return true;
              },
        );

        expect(verified?.reactorTransportPeerId, 'transport-reactor');
        expect(verified?.senderPublicKey, 'reactor-device-key');
        expect(verified?.transitionId, 'transition-signed-1');
        expect(verificationCalls, hasLength(1));
        final missingOuterTransition = <String, dynamic>{...data}
          ..remove('event_id');
        expect(
          (await verifyGroupReactionNotificationNomination(
            data: missingOuterTransition,
            localTransportPeerId: 'transport-author-two',
            verifySignature:
                ({
                  required publicKey,
                  required signedPayload,
                  required signature,
                }) async => true,
          ))?.transitionId,
          'transition-signed-1',
          reason:
              'the signed nomination retains identity when its duplicate outer field is absent',
        );
        expect(
          await verifyGroupReactionNotificationNomination(
            data: data,
            localTransportPeerId: 'transport-bystander',
            verifySignature:
                ({
                  required publicKey,
                  required signedPayload,
                  required signature,
                }) async => true,
          ),
          isNull,
          reason: 'account ownership does not replace exact signed nomination',
        );
        expect(
          await verifyGroupReactionNotificationNomination(
            data: data,
            localTransportPeerId: 'transport-author-one',
            verifySignature:
                ({
                  required publicKey,
                  required signedPayload,
                  required signature,
                }) async => false,
          ),
          isNull,
          reason: 'a nominated transport still needs a valid signature',
        );
      },
    );

    test('decrypts private 1:1 payload with generated en/de/ar copy', () async {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': 'peer-alice',
          'message_id': 'msg-private-localized',
          'kem': 'kem',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      );
      final policy = PrivateMediaPolicy.fromJson(const {
        'version': 1,
        'mode': 'protected',
      });

      for (final testCase in const [
        (Locale('en'), 'Private media'),
        (Locale('de'), 'Private Medien'),
        (Locale('ar'), 'وسائط خاصة'),
      ]) {
        final resolved = await resolveBackgroundPushNotification(
          message,
          locale: testCase.$1,
          decryptOneToOne:
              ({required kem, required ciphertext, required nonce}) async {
                return MessagePayload(
                  id: 'msg-private-localized',
                  text: 'caption-canary',
                  senderPeerId: 'peer-alice',
                  senderUsername: 'Alice',
                  timestamp: '2026-07-11T09:00:00.000Z',
                  media: const [
                    {
                      'id': 'private-blob-canary',
                      'mime': 'image/jpeg',
                      'mediaType': 'image',
                    },
                  ],
                  privateMediaPolicy: policy,
                ).toInnerJson();
              },
        );

        expect(resolved.body, testCase.$2, reason: testCase.$1.languageCode);
        expect(resolved.payload, 'peer-alice');
        for (final forbidden in [
          'caption-canary',
          'private-blob-canary',
          'image/jpeg',
        ]) {
          expect(resolved.body, isNot(contains(forbidden)));
          expect(resolved.payload, isNot(contains(forbidden)));
        }
      }
    });

    test('decrypts private 1:1 payload to a generic leak-free body', () async {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': 'peer-alice',
          'message_id': 'msg-private-1',
          'kem': 'kem',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      );
      final policy = PrivateMediaPolicy.fromJson(const {
        'version': 1,
        'mode': 'protected',
      });

      final resolved = await resolveBackgroundPushNotification(
        message,
        decryptOneToOne:
            ({required kem, required ciphertext, required nonce}) async {
              return MessagePayload(
                id: 'msg-private-1',
                text: '',
                senderPeerId: 'peer-alice',
                senderUsername: 'Alice',
                timestamp: '2026-07-11T09:00:00.000Z',
                media: const [
                  {
                    'id': 'private-blob',
                    'mime': 'image/jpeg',
                    'mediaType': 'image',
                  },
                ],
                privateMediaPolicy: policy,
              ).toInnerJson();
            },
      );

      expect(resolved.title, 'Alice');
      expect(resolved.body, 'Private media');
      expect(resolved.payload, 'peer-alice');
      final route = resolved.payload ?? '';
      for (final forbidden in ['protected', 'private-blob', 'image/jpeg']) {
        expect(route, isNot(contains(forbidden)));
      }
    });

    test('redacts view-once, disappearing, and unsupported variants', () async {
      final policies = <Map<String, Object>>[
        {'version': 1, 'mode': 'view_once'},
        {'version': 1, 'mode': 'disappearing', 'durationSeconds': 3600},
        {'version': 9, 'mode': 'future-mode'},
      ];

      for (var index = 0; index < policies.length; index++) {
        final message = RemoteMessage(
          data: {
            'type': 'new_message',
            'sender_id': 'peer-alice',
            'message_id': 'msg-private-variant-$index',
            'kem': 'kem',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );
        final resolved = await resolveBackgroundPushNotification(
          message,
          decryptOneToOne:
              ({required kem, required ciphertext, required nonce}) async =>
                  jsonEncode({
                    'id': 'msg-private-variant-$index',
                    'text': index == 2 ? 'future private caption' : '',
                    'senderPeerId': 'peer-alice',
                    'senderUsername': 'Alice',
                    'timestamp': '2026-07-11T09:00:00.000Z',
                    'media': const [
                      {
                        'id': 'private-variant-blob',
                        'mime': 'image/jpeg',
                        'mediaType': 'image',
                      },
                    ],
                    'privateMedia': policies[index],
                  }),
        );

        expect(
          resolved.body,
          'Private media',
          reason: policies[index].toString(),
        );
        expect(resolved.payload, 'peer-alice');
        for (final forbidden in [
          'view_once',
          'disappearing',
          'durationSeconds',
          'future-mode',
          'future private caption',
          'private-variant-blob',
          'image/jpeg',
        ]) {
          expect(resolved.body, isNot(contains(forbidden)));
          expect(resolved.payload, isNot(contains(forbidden)));
        }
      }
    });

    test('fixture route data keeps plaintext preview fields encrypted', () {
      final fixtureFiles = <File>[
        ...Directory('test/features/push/fixtures')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json')),
        ...Directory(
          'test/features/push/frozen_payloads',
        ).listSync().whereType<File>().where(
          (file) =>
              file.path.endsWith('.json') &&
              file.uri.pathSegments.last.startsWith('post_phase1_'),
        ),
      ];
      const forbiddenRouteFields = <String>{
        'title',
        'body',
        'pushTitle',
        'pushBody',
        'senderUsername',
        'groupName',
        'messageText',
        'text',
        'media',
      };

      for (final file in fixtureFiles) {
        final decoded = jsonDecode(file.readAsStringSync());
        final routeDataItems = <Map<String, dynamic>>[];
        if (decoded is Map<String, dynamic>) {
          final routeData = decoded['routeData'];
          if (routeData is Map<String, dynamic>) {
            routeDataItems.add(routeData);
          }
          final cases = decoded['cases'];
          if (cases is List) {
            for (final item in cases) {
              if (item is Map<String, dynamic> &&
                  item['routeData'] is Map<String, dynamic>) {
                routeDataItems.add(item['routeData'] as Map<String, dynamic>);
              }
            }
          }
        }
        expect(routeDataItems, isNotEmpty, reason: file.path);
        for (final routeData in routeDataItems) {
          expect(
            routeData.keys.toSet().intersection(forbiddenRouteFields),
            isEmpty,
            reason: file.path,
          );
        }
      }
    });

    test('decrypts 1:1 ciphertext preview with sender title', () async {
      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': 'peer-alice',
          'message_id': 'msg-chat-1',
          'kem': 'kem',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      );

      final resolved = await resolveBackgroundPushNotification(
        message,
        decryptOneToOne:
            ({required kem, required ciphertext, required nonce}) async {
              expect(kem, 'kem');
              expect(ciphertext, 'ciphertext');
              expect(nonce, 'nonce');
              return const MessagePayload(
                id: 'msg-chat-1',
                text: 'Hello secret',
                senderPeerId: 'peer-alice',
                senderUsername: 'Alice',
                timestamp: '2026-04-24T12:00:00.000Z',
              ).toInnerJson();
            },
      );

      expect(resolved.title, 'Alice');
      expect(resolved.body, 'Hello secret');
      expect(resolved.payload, 'peer-alice');
    });

    test(
      'recipient-owned direct context replaces malicious names and enforces sender/message parity',
      () async {
        const message = RemoteMessage(
          data: <String, dynamic>{
            'type': 'new_message',
            'sender_id': 'peer-alice',
            'message_id': 'msg-trusted-direct',
            'kem': 'kem',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );
        const context = DirectMessageNotificationContext(
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice from contacts DB',
          expectedMessageId: 'msg-trusted-direct',
        );

        final resolved = await resolveBackgroundPushNotification(
          message,
          directMessageContext: context,
          decryptOneToOne:
              ({required kem, required ciphertext, required nonce}) async {
                return const MessagePayload(
                  id: 'msg-trusted-direct',
                  text: 'Trusted encrypted content',
                  senderPeerId: 'peer-alice',
                  senderUsername: 'ATTACKER DECRYPTED NAME',
                  timestamp: '2026-07-12T09:00:00.000Z',
                ).toInnerJson();
              },
        );
        expect(resolved.title, 'Alice from contacts DB');
        expect(resolved.body, 'Trusted encrypted content');

        for (final mismatch in const <({String sender, String messageId})>[
          (sender: 'peer-attacker', messageId: 'msg-trusted-direct'),
          (sender: 'peer-alice', messageId: 'msg-attacker'),
        ]) {
          await expectLater(
            resolveBackgroundPushNotification(
              message,
              directMessageContext: context,
              decryptOneToOne:
                  ({required kem, required ciphertext, required nonce}) async {
                    return MessagePayload(
                      id: mismatch.messageId,
                      text: 'must stay silent',
                      senderPeerId: mismatch.sender,
                      senderUsername: 'attacker',
                      timestamp: '2026-07-12T09:00:00.000Z',
                    ).toInnerJson();
                  },
            ),
            throwsA(isA<OrdinaryMessageNotificationIntegrityException>()),
          );
        }
      },
    );

    test(
      'trusted direct context with no local name never promotes decrypted copy',
      () async {
        final resolved = await resolveBackgroundPushNotification(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-alice',
              'message_id': 'msg-null-local-name',
              'kem': 'kem',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
          directMessageContext: const DirectMessageNotificationContext(
            senderPeerId: 'peer-alice',
            senderUsername: null,
            expectedMessageId: 'msg-null-local-name',
          ),
          locale: const Locale('de'),
          decryptOneToOne:
              ({required kem, required ciphertext, required nonce}) async {
                return const MessagePayload(
                  id: 'msg-null-local-name',
                  text: 'ATTACKER DECRYPTED CONTENT',
                  senderPeerId: 'peer-alice',
                  senderUsername: 'ATTACKER DECRYPTED NAME',
                  timestamp: '2026-07-12T09:00:00.000Z',
                ).toInnerJson();
              },
        );

        expect(resolved.title, 'Mknoon');
        expect(resolved.body, 'Nachricht');
        expect(
          '${resolved.title}|${resolved.body}',
          isNot(contains('ATTACKER')),
        );
      },
    );

    test(
      'authorized direct crypto outage returns localized content-free trusted fallback',
      () async {
        final resolved = await resolveBackgroundPushNotification(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'new_message',
              'sender_id': 'peer-alice',
              'message_id': 'msg-outage',
              'kem': 'SECRET-kem',
              'ciphertext': 'SECRET-ciphertext',
              'nonce': 'SECRET-nonce',
            },
          ),
          directMessageContext: const DirectMessageNotificationContext(
            senderPeerId: 'peer-alice',
            senderUsername: 'Trusted Alice',
            expectedMessageId: 'msg-outage',
          ),
          locale: const Locale('de'),
          decryptOneToOne:
              ({required kem, required ciphertext, required nonce}) async =>
                  throw StateError('plugin unavailable'),
        );

        expect(resolved.title, 'Trusted Alice');
        expect(resolved.body, 'Nachricht');
        expect('${resolved.title}|${resolved.body}', isNot(contains('SECRET')));
      },
    );

    test('emits leak-safe Android decrypt telemetry', () async {
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));

      const message = RemoteMessage(
        data: {
          'type': 'new_message',
          'sender_id': 'peer-alice',
          'message_id': 'msg-chat-1',
          'kem': 'kem',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      );

      final resolved = await resolveBackgroundPushNotification(
        message,
        decryptOneToOne:
            ({required kem, required ciphertext, required nonce}) async {
              return const MessagePayload(
                id: 'msg-chat-1',
                text: 'UltraSecretCanary',
                senderPeerId: 'peer-alice',
                senderUsername: 'Alice',
                timestamp: '2026-04-24T12:00:00.000Z',
              ).toInnerJson();
            },
      );

      expect(resolved.title, 'Alice');
      expect(resolved.body, 'UltraSecretCanary');
      expect(events, hasLength(1));
      expect(events.single['event'], 'PUSH_ANDROID_DATA_DECRYPT_OK');
      expect(events.single['details'], {'kind': 'chat'});

      final encodedEvents = jsonEncode(events);
      expect(encodedEvents, isNot(contains('UltraSecretCanary')));
      expect(encodedEvents, isNot(contains('Alice')));
    });

    test(
      'decrypts group ciphertext preview with sender-prefixed body',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-team',
            'message_id': 'msg-group-1',
            'keyEpoch': '7',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );

        final resolved = await resolveBackgroundPushNotification(
          message,
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async {
                expect(groupId, 'group-team');
                expect(keyEpoch, 7);
                expect(ciphertext, 'ciphertext');
                expect(nonce, 'nonce');
                return jsonEncode({
                  'messageId': 'msg-group-1',
                  'groupName': 'Team Chat',
                  'senderUsername': 'Alice',
                  'text': 'Hello group',
                });
              },
        );

        expect(resolved.title, 'Team Chat');
        expect(resolved.body, 'Alice: Hello group');
        expect(resolved.payload, 'group:group-team|message:msg-group-1');
      },
    );

    test(
      'recipient-owned group context enforces group/message/sender/self parity',
      () async {
        const message = RemoteMessage(
          data: <String, dynamic>{
            'type': 'group_message',
            'groupId': 'group-team',
            'sender_id': 'peer-admin',
            'sender_transport_peer_id': 'transport-admin-phone',
            'message_id': 'msg-trusted-group',
            'keyEpoch': '7',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );
        const context = GroupMessageNotificationContext(
          groupId: 'group-team',
          groupName: 'Team from groups DB',
          localPeerId: 'peer-local',
          senderPeerId: 'peer-admin',
          senderTransportPeerId: 'transport-admin-phone',
          senderUsername: 'Admin from members DB',
          expectedMessageId: 'msg-trusted-group',
        );
        final resolved = await resolveBackgroundPushNotification(
          message,
          groupMessageContext: context,
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => jsonEncode(<String, Object?>{
                'groupId': 'group-team',
                'messageId': 'msg-trusted-group',
                'senderId': 'peer-admin',
                'groupName': 'ATTACKER GROUP',
                'senderUsername': 'ATTACKER ACTOR',
                'text': 'Hello trusted group',
              }),
        );
        expect(resolved.title, 'Team from groups DB');
        expect(resolved.body, 'Admin from members DB: Hello trusted group');
        final comparand =
            resolved.groupComparand
                as BackgroundGroupMessageNotificationComparand;
        expect(comparand.groupId, 'group-team');
        expect(comparand.messageId, 'msg-trusted-group');
        expect(comparand.senderPeerId, 'peer-admin');
        expect(comparand.senderTransportPeerId, 'transport-admin-phone');

        await expectLater(
          resolveBackgroundPushNotification(
            const RemoteMessage(
              data: <String, dynamic>{
                'type': 'group_message',
                'groupId': 'group-team',
                'sender_id': 'peer-admin',
                'sender_transport_peer_id': 'transport-attacker-phone',
                'message_id': 'msg-trusted-group',
                'keyEpoch': '7',
                'ciphertext': 'ciphertext',
                'nonce': 'nonce',
              },
            ),
            groupMessageContext: context,
            decryptGroup:
                ({
                  required groupId,
                  required keyEpoch,
                  required ciphertext,
                  required nonce,
                }) async => throw StateError('must not decrypt'),
          ),
          throwsA(isA<OrdinaryMessageNotificationIntegrityException>()),
        );

        for (final mismatch
            in const <({String groupId, String messageId, String sender})>[
              (
                groupId: 'group-attacker',
                messageId: 'msg-trusted-group',
                sender: 'peer-admin',
              ),
              (
                groupId: 'group-team',
                messageId: 'msg-attacker',
                sender: 'peer-admin',
              ),
              (
                groupId: 'group-team',
                messageId: 'msg-trusted-group',
                sender: 'peer-attacker',
              ),
              (
                groupId: 'group-team',
                messageId: 'msg-trusted-group',
                sender: 'peer-local',
              ),
            ]) {
          await expectLater(
            resolveBackgroundPushNotification(
              message,
              groupMessageContext: context,
              decryptGroup:
                  ({
                    required groupId,
                    required keyEpoch,
                    required ciphertext,
                    required nonce,
                  }) async => jsonEncode(<String, Object?>{
                    'groupId': mismatch.groupId,
                    'messageId': mismatch.messageId,
                    'senderId': mismatch.sender,
                    'text': 'must stay silent',
                  }),
            ),
            throwsA(isA<OrdinaryMessageNotificationIntegrityException>()),
          );
        }
      },
    );

    // ------------------------------------------------------------------
    // 384/G19: the DEFAULT group send lane never pushes the Dart replay
    // envelope. `sendGroupMessage` -> `callGroupSendReliable` reaches the Go
    // producer, which stores a LIVE envelope whose encrypted
    // `GroupMessagePayload` is `{text, timestamp, username, extra}` — no
    // `senderId`/`senderPeerId`/`sender_id`, and no `groupId` key anywhere.
    // Byte-shape anchors (re-derive these if the Go side moves):
    //   payload struct        go-mknoon/internal/group_envelope.go:42-47
    //   extra builder         go-mknoon/node/pubsub.go:1860-1876
    //                         (+ :496 publishedAtNano, :1874 messageId)
    //   opts source           go-mknoon/bridge/bridge.go:2698-2741
    //   relay data mapping    go-relay-server/inbox.go:854-899,:1221-1256
    // Every other context-bearing fixture in this file uses the Dart
    // `inboxPayload` shape, which is id-complete. That is exactly why the
    // null-`decodedSender` arm of the parity check had zero coverage and
    // shipped a false positive that killed every killed-app group card.
    // ------------------------------------------------------------------

    /// The 9 FCM data keys the relay emits for a live Go group envelope.
    ///
    /// No `kind` (the live envelope carries no such field) and no outer
    /// sender-ACCOUNT key — `sender_transport_peer_id` is the only sender
    /// fact on the wire, and it is what resolves the context that arms the
    /// sender parity clause.
    Map<String, dynamic> liveEnvelopeOuterData({
      String messageId = 'msg-live-envelope',
    }) => <String, dynamic>{
      'type': 'group_message',
      'groupId': 'group-team',
      'sender_transport_peer_id': 'transport-admin-phone',
      'message_id': messageId,
      'envelope_version': '3',
      'payloadType': 'group_message',
      'keyEpoch': '7',
      'ciphertext': 'ciphertext',
      'nonce': 'nonce',
    };

    /// The decrypted live-envelope plaintext, with the full default-lane
    /// `extra` key set (bridge opts minus `timestamp`, plus the producer's
    /// `messageId` overwrite and `publishedAtNano`).
    String liveEnvelopePlaintext({
      String messageId = 'msg-live-envelope',
      String text = 'Ready for the standup?',
      List<Object?>? media,
    }) => jsonEncode(<String, Object?>{
      'text': text,
      'timestamp': '2026-08-18T09:41:12.481931Z',
      // Sender-authored display name. The copy path must refuse it whenever
      // a recipient-owned context exists.
      'username': 'Admin from the sender device',
      'extra': <String, Object?>{
        'senderDeviceId': 'device-admin-phone',
        'senderTransportPeerId': 'transport-admin-phone',
        'senderDevicePublicKey': 'device-public-key-base64',
        'senderKeyPackageId': 'key-package-admin-1',
        'logicalDeliveryId': 'logical-delivery-live-envelope',
        // Sender-authored group name. The trusted context name must win.
        'groupName': 'ATTACKER GROUP',
        'recipientPeerIds': const <String>['peer-local', 'peer-admin'],
        'preserveRecipientPeerIds': true,
        'media': ?media,
        'messageId': messageId,
        'publishedAtNano': '1787053468061245000',
      },
    });

    const liveEnvelopeContext = GroupMessageNotificationContext(
      groupId: 'group-team',
      groupName: 'Team from groups DB',
      localPeerId: 'peer-local',
      senderPeerId: 'peer-admin',
      senderTransportPeerId: 'transport-admin-phone',
      senderUsername: 'Admin from members DB',
      expectedMessageId: 'msg-live-envelope',
    );

    List<Map<String, dynamic>> captureFlowEvents() {
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));
      return events;
    }

    Iterable<Map<String, dynamic>> eventsNamed(
      List<Map<String, dynamic>> events,
      String name,
    ) => events.where((event) => event['event'] == name);

    test(
      'live Go envelope without inner sender key renders the trusted group card',
      () async {
        final events = captureFlowEvents();
        final resolved = await resolveBackgroundPushNotification(
          RemoteMessage(data: liveEnvelopeOuterData()),
          groupMessageContext: liveEnvelopeContext,
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => liveEnvelopePlaintext(),
        );

        expect(resolved.title, 'Team from groups DB');
        expect(resolved.body, 'Admin from members DB: Ready for the standup?');

        // The card must bind to the TRUSTED comparand: with the inner sender
        // absent there is nothing to promote, so the context facts stand.
        final comparand =
            resolved.groupComparand
                as BackgroundGroupMessageNotificationComparand;
        expect(comparand.groupId, 'group-team');
        expect(comparand.messageId, 'msg-live-envelope');
        expect(comparand.senderPeerId, 'peer-admin');
        expect(comparand.senderTransportPeerId, 'transport-admin-phone');

        expect(
          eventsNamed(
            events,
            'PUSH_ANDROID_DATA_DECRYPT_OK',
          ).map((event) => event['details']).toList(),
          contains(containsPair('kind', 'group')),
        );
        // A fix that keeps the clause firing and merely skips the THROW would
        // still emit the failure. It must not fire at all.
        expect(eventsNamed(events, 'PUSH_ANDROID_DATA_DECRYPT_FAIL'), isEmpty);
      },
    );

    test(
      'live Go envelope media flavor renders a card instead of throwing',
      () async {
        final events = captureFlowEvents();
        const media = <Object?>[
          <String, Object?>{
            'mediaType': 'image',
            'mediaId': 'media-live-envelope-1',
            'mimeType': 'image/jpeg',
          },
        ];
        final resolved = await resolveBackgroundPushNotification(
          RemoteMessage(data: liveEnvelopeOuterData()),
          groupMessageContext: liveEnvelopeContext,
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => liveEnvelopePlaintext(text: '', media: media),
        );

        expect(resolved.title, 'Team from groups DB');
        // Typed media copy, sender-prefixed from the roster. Bound to the shared
        // preview helper rather than a copy literal.
        expect(
          resolved.body,
          'Admin from members DB: ${pushPreviewBody('', media)}',
        );
        expect(resolved.body, isNot(endsWith(': ')));
        expect(eventsNamed(events, 'PUSH_ANDROID_DATA_DECRYPT_FAIL'), isEmpty);
      },
    );

    // Per-clause discriminator rows. `reason` stays byte-identical; `clause`
    // names the FIRST true clause in evaluation order so the next parity red
    // is diagnosable from one log line.
    Future<Map<String, dynamic>> captureParityFailure({
      required Map<String, dynamic> data,
      required GroupMessageNotificationContext? context,
      required String plaintext,
    }) async {
      final events = captureFlowEvents();
      await expectLater(
        resolveBackgroundPushNotification(
          RemoteMessage(data: data),
          groupMessageContext: context,
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => plaintext,
        ),
        throwsA(isA<OrdinaryMessageNotificationIntegrityException>()),
      );
      final failures = eventsNamed(
        events,
        'PUSH_ANDROID_DATA_DECRYPT_FAIL',
      ).toList(growable: false);
      expect(failures, hasLength(1));
      final details = Map<String, dynamic>.from(
        failures.single['details'] as Map,
      );
      expect(details['kind'], 'group');
      expect(details['reason'], 'group_parity_mismatch');
      return details;
    }

    test('parity mismatch reports inner_message_id_missing clause', () async {
      // Sender-ABSENT on purpose: a field-complete payload here would let a
      // guard hoisted above the whole clause chain pass this row.
      final details = await captureParityFailure(
        data: liveEnvelopeOuterData(),
        context: liveEnvelopeContext,
        plaintext: jsonEncode(<String, Object?>{
          'text': 'no ids anywhere',
          'timestamp': '2026-08-18T09:41:12.481931Z',
          'extra': <String, Object?>{'groupName': 'Team'},
        }),
      );
      expect(details['clause'], 'inner_message_id_missing');
    });

    test('parity mismatch reports inner_id_outer_mismatch clause', () async {
      // The no-context protection arm: without a recipient-owned context the
      // inner/outer id agreement is the only thing standing.
      final details = await captureParityFailure(
        data: liveEnvelopeOuterData(),
        context: null,
        plaintext: liveEnvelopePlaintext(messageId: 'msg-other-envelope'),
      );
      expect(details['clause'], 'inner_id_outer_mismatch');
    });

    test('parity mismatch reports inner_group_id_mismatch clause', () async {
      // Sender-ABSENT live-envelope shape with a tampered inner group id.
      // This is the row that kills a hoisted `decodedSender != null` guard:
      // under any hoist the tamper check is skipped and the push CARDS.
      final details = await captureParityFailure(
        data: liveEnvelopeOuterData(),
        context: liveEnvelopeContext,
        plaintext: jsonEncode(<String, Object?>{
          'text': 'must stay silent',
          'timestamp': '2026-08-18T09:41:12.481931Z',
          'extra': <String, Object?>{
            'groupId': 'group-attacker',
            'messageId': 'msg-live-envelope',
          },
        }),
      );
      expect(details['clause'], 'inner_group_id_mismatch');
    });

    test('parity mismatch reports inner_sender_is_local clause', () async {
      // `senderPeerId == localPeerId` is unreachable through the production
      // context builder (`background_message_handler.dart:3061` rejects a
      // self-sender). The row pins the predicate, not a production state —
      // and the equality is what keeps the sender-context clause quiet so
      // this stays a UNIQUE pin for the self-sender clause.
      const selfSenderContext = GroupMessageNotificationContext(
        groupId: 'group-team',
        groupName: 'Team from groups DB',
        localPeerId: 'peer-local',
        senderPeerId: 'peer-local',
        senderTransportPeerId: 'transport-admin-phone',
        senderUsername: 'Admin from members DB',
        expectedMessageId: 'msg-live-envelope',
      );
      final details = await captureParityFailure(
        data: liveEnvelopeOuterData(),
        context: selfSenderContext,
        plaintext: jsonEncode(<String, Object?>{
          'text': 'must stay silent',
          'timestamp': '2026-08-18T09:41:12.481931Z',
          'senderId': 'peer-local',
          'extra': <String, Object?>{'messageId': 'msg-live-envelope'},
        }),
      );
      expect(details['clause'], 'inner_sender_is_local');
    });

    test(
      'parity mismatch reports inner_sender_context_mismatch clause',
      () async {
        // Present-but-wrong inner sender: genuine tamper, still throws.
        final details = await captureParityFailure(
          data: liveEnvelopeOuterData(),
          context: liveEnvelopeContext,
          plaintext: jsonEncode(<String, Object?>{
            'text': 'must stay silent',
            'timestamp': '2026-08-18T09:41:12.481931Z',
            'senderId': 'peer-attacker',
            'extra': <String, Object?>{'messageId': 'msg-live-envelope'},
          }),
        );
        expect(details['clause'], 'inner_sender_context_mismatch');
      },
    );

    // ------------------------------------------------------------------
    // G26: the STRICT-authority group lane never reaches the Go group
    // topic. It signs one `group_offline_replay` envelope per recipient
    // into the DIRECT inbox under `group_content_v1` custody, and the relay
    // used to store it without ever pushing — §1.3's killed-path row was
    // unreachable on that lane by construction.
    //
    // The relay now routes it through the SAME `buildGroupPushMessage` the
    // topic lane uses (`go-relay-server/group_content_push.go`), so the
    // recipient needs no change. This row is the proof of that claim: it
    // feeds the exact 10 data keys the relay emits and the exact plaintext
    // the strict sender encrypts, and asserts a real card comes back.
    //
    // Byte-shape anchors (re-derive if either side moves):
    //   outer keys     go-relay-server/inbox.go:854-899,:1221-1256
    //   inner payload  send_group_message_use_case.dart:2567-2589
    //                  (`inboxPayload`, also the strict replay plaintext)
    // Unlike the default lane's Go LIVE envelope, this plaintext IS
    // id-complete — which is why the sender clause agrees rather than
    // needing 384's null guard. Both shapes now card.
    // ------------------------------------------------------------------
    test(
      'strict-lane group content push renders the trusted group card',
      () async {
        final events = captureFlowEvents();
        final resolved = await resolveBackgroundPushNotification(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'sender_transport_peer_id': 'transport-admin-phone',
              'message_id': 'msg-strict-content',
              'kind': 'group_offline_replay',
              'envelope_version': '1',
              'payloadType': 'group_message',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
          groupMessageContext: const GroupMessageNotificationContext(
            groupId: 'group-team',
            groupName: 'Team from groups DB',
            localPeerId: 'peer-local',
            senderPeerId: 'peer-admin',
            senderTransportPeerId: 'transport-admin-phone',
            senderUsername: 'Admin from members DB',
            expectedMessageId: 'msg-strict-content',
          ),
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => jsonEncode(<String, Object?>{
                'groupId': 'group-team',
                'groupName': 'ATTACKER GROUP',
                'senderId': 'peer-admin',
                'senderDeviceId': 'device-admin-phone',
                'transportPeerId': 'transport-admin-phone',
                'senderUsername': 'ATTACKER ACTOR',
                'keyEpoch': 7,
                'text': 'Strict group standup',
                'timestamp': '2026-08-19T09:41:12.481931Z',
                'messageId': 'msg-strict-content',
                'logicalDeliveryId': 'logical-delivery-strict',
              }),
        );

        expect(resolved.title, 'Team from groups DB');
        expect(resolved.body, 'Admin from members DB: Strict group standup');
        final comparand =
            resolved.groupComparand
                as BackgroundGroupMessageNotificationComparand;
        expect(comparand.groupId, 'group-team');
        expect(comparand.messageId, 'msg-strict-content');
        expect(comparand.senderPeerId, 'peer-admin');
        expect(eventsNamed(events, 'PUSH_ANDROID_DATA_DECRYPT_FAIL'), isEmpty);
      },
    );

    // The relay degrades an unusable epoch to a routing-only push rather than
    // dropping the wake. The recipient must still card, generically.
    test(
      'strict-lane routing-only fallback still returns a trusted card',
      () async {
        final events = captureFlowEvents();
        final resolved = await resolveBackgroundPushNotification(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'sender_transport_peer_id': 'transport-admin-phone',
              'message_id': 'msg-strict-fallback',
              'preview_unavailable': '1',
            },
          ),
          groupMessageContext: const GroupMessageNotificationContext(
            groupId: 'group-team',
            groupName: 'Team from groups DB',
            localPeerId: 'peer-local',
            senderPeerId: 'peer-admin',
            senderTransportPeerId: 'transport-admin-phone',
            senderUsername: 'Admin from members DB',
            expectedMessageId: 'msg-strict-fallback',
          ),
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => throw StateError('must not decrypt a stripped push'),
        );

        expect(resolved.title, 'Team from groups DB');
        expect(resolved.body, isNotEmpty);
        expect(resolved.body, isNot(contains('ATTACKER')));
        expect(
          eventsNamed(
            events,
            'PUSH_ANDROID_DATA_DECRYPT_FAIL',
          ).map((event) => (event['details']! as Map)['reason']).toList(),
          contains('missing_group_decrypt_input'),
        );
      },
    );

    test(
      'trusted group context with no local group name stays generic',
      () async {
        final resolved = await resolveBackgroundPushNotification(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'sender_id': 'peer-alice',
              'sender_transport_peer_id': 'transport-alice-phone',
              'message_id': 'msg-null-group-name',
              'keyEpoch': '7',
              'ciphertext': 'ciphertext',
              'nonce': 'nonce',
            },
          ),
          groupMessageContext: const GroupMessageNotificationContext(
            groupId: 'group-team',
            groupName: null,
            localPeerId: 'peer-local',
            senderPeerId: 'peer-alice',
            senderTransportPeerId: 'transport-alice-phone',
            senderUsername: 'Alice from members DB',
            expectedMessageId: 'msg-null-group-name',
          ),
          locale: const Locale('ar'),
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => jsonEncode(<String, Object?>{
                'groupId': 'group-team',
                'messageId': 'msg-null-group-name',
                'senderId': 'peer-alice',
                'senderUsername': 'UNTRUSTED ALICE',
                'groupName': 'UNTRUSTED GROUP',
                'text': 'UNTRUSTED CONTENT',
                'media': <Map<String, Object?>>[
                  <String, Object?>{'mediaType': 'video'},
                ],
              }),
        );

        expect(resolved.title, 'Mknoon');
        expect(resolved.body, 'رسالة');
        expect(
          '${resolved.title}|${resolved.body}',
          isNot(contains('UNTRUSTED')),
        );
      },
    );

    test('threads locale through decrypted group media previews', () async {
      const message = RemoteMessage(
        data: {
          'type': 'group_message',
          'groupId': 'group-team',
          'message_id': 'msg-group-voice-de',
          'keyEpoch': '7',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      );

      final resolved = await resolveBackgroundPushNotification(
        message,
        locale: const Locale('de'),
        decryptGroup:
            ({
              required groupId,
              required keyEpoch,
              required ciphertext,
              required nonce,
            }) async => jsonEncode({
              'messageId': 'msg-group-voice-de',
              'groupName': 'Team Chat',
              'senderUsername': 'Alice',
              'text': '',
              'media': [
                {'mediaType': 'audio', 'mime': 'audio/aac'},
              ],
            }),
      );

      expect(resolved.title, 'Team Chat');
      expect(resolved.body, 'Alice: Sprachnachricht');
      expect(resolved.payload, 'group:group-team|message:msg-group-voice-de');
    });

    test(
      'decrypts native v3 group preview from encrypted extra metadata',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-team',
            'message_id': 'native-msg-1',
            'keyEpoch': '7',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );

        final resolved = await resolveBackgroundPushNotification(
          message,
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async {
                return jsonEncode({
                  'text': 'Hello native',
                  'timestamp': '2026-06-05T19:33:38.064850Z',
                  'username': 'Alice',
                  'extra': {
                    'groupName': 'Team Chat',
                    'messageId': 'native-msg-1',
                  },
                });
              },
        );

        expect(resolved.title, 'Team Chat');
        expect(resolved.body, 'Alice: Hello native');
        expect(resolved.payload, 'group:group-team|message:native-msg-1');
      },
    );

    test(
      'group private policy at decrypted top level emits only generic localized copy',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-team',
            'message_id': 'private-top-level',
            'keyEpoch': '7',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );

        final resolved = await resolveBackgroundPushNotification(
          message,
          locale: const Locale('en'),
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => jsonEncode(<String, Object?>{
                'messageId': 'private-top-level',
                'groupName': 'SECRET group title',
                'senderUsername': 'SECRET sender name',
                'text': 'SECRET private caption',
                'media': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'SECRET-private-blob',
                    'mime': 'image/jpeg',
                    'mediaType': 'image',
                  },
                ],
                'mediaPolicyVersion': 1,
                'mediaLifecycle': 'viewOnce',
                'mediaDurationSeconds': null,
                'mediaProtected': true,
              }),
        );

        expect(resolved.title, 'Mknoon');
        expect(resolved.body, 'New private media');
        expect(resolved.payload, 'group:group-team|message:private-top-level');
        final visibleCopy = '${resolved.title}|${resolved.body}';
        for (final forbidden in const <String>[
          'SECRET',
          'group title',
          'sender name',
          'caption',
          'image',
          'viewOnce',
          'private-blob',
        ]) {
          expect(visibleCopy, isNot(contains(forbidden)));
        }
      },
    );

    test(
      'group private policy in native encrypted extra emits only generic localized copy',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-team',
            'message_id': 'private-native-extra',
            'keyEpoch': '7',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );

        final resolved = await resolveBackgroundPushNotification(
          message,
          locale: const Locale('en'),
          decryptGroup:
              ({
                required groupId,
                required keyEpoch,
                required ciphertext,
                required nonce,
              }) async => jsonEncode(<String, Object?>{
                'text': 'SECRET disappearing caption',
                'username': 'SECRET native sender',
                'extra': <String, Object?>{
                  'groupName': 'SECRET native group',
                  'messageId': 'private-native-extra',
                  'media': <Map<String, Object?>>[
                    <String, Object?>{
                      'id': 'SECRET-native-video',
                      'mime': 'video/mp4',
                      'mediaType': 'video',
                    },
                  ],
                  'mediaPolicyVersion': 1,
                  'mediaLifecycle': 'disappearing',
                  'mediaDurationSeconds': 3600,
                  'mediaProtected': true,
                },
              }),
        );

        expect(resolved.title, 'Mknoon');
        expect(resolved.body, 'New private media');
        expect(
          resolved.payload,
          'group:group-team|message:private-native-extra',
        );
        final visibleCopy = '${resolved.title}|${resolved.body}';
        for (final forbidden in const <String>[
          'SECRET',
          'native group',
          'native sender',
          'caption',
          'video',
          'disappearing',
          '3600',
        ]) {
          expect(visibleCopy, isNot(contains(forbidden)));
        }
      },
    );

    test(
      'malformed or unsupported explicit group private tuple fails closed to generic copy',
      () async {
        final plaintexts = <Map<String, Object?>>[
          <String, Object?>{
            'groupName': 'SECRET partial group',
            'senderUsername': 'SECRET partial sender',
            'text': 'SECRET partial caption',
            'mediaPolicyVersion': 1,
          },
          <String, Object?>{
            'text': 'SECRET future caption',
            'username': 'SECRET future sender',
            'extra': <String, Object?>{
              'groupName': 'SECRET future group',
              'mediaPolicyVersion': 9,
              'mediaLifecycle': 'futureMode',
              'mediaDurationSeconds': null,
              'mediaProtected': true,
            },
          },
          <String, Object?>{
            'groupName': 'SECRET wrong-type group',
            'senderUsername': 'SECRET wrong-type sender',
            'text': 'SECRET wrong-type caption',
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'viewOnce',
            'mediaDurationSeconds': null,
            'mediaProtected': 'true',
          },
        ];

        for (var index = 0; index < plaintexts.length; index++) {
          final resolved = await resolveBackgroundPushNotification(
            RemoteMessage(
              data: <String, String>{
                'type': 'group_message',
                'groupId': 'group-team',
                'message_id': 'private-malformed-$index',
                'keyEpoch': '7',
                'ciphertext': 'ciphertext',
                'nonce': 'nonce',
              },
            ),
            locale: const Locale('en'),
            decryptGroup:
                ({
                  required groupId,
                  required keyEpoch,
                  required ciphertext,
                  required nonce,
                }) async => jsonEncode(plaintexts[index]),
          );

          expect(resolved.title, 'Mknoon', reason: 'fixture $index');
          expect(resolved.body, 'New private media', reason: 'fixture $index');
          final visibleCopy = '${resolved.title}|${resolved.body}';
          expect(visibleCopy, isNot(contains('SECRET')));
          expect(visibleCopy, isNot(contains('futureMode')));
          expect(visibleCopy, isNot(contains('viewOnce')));
        }
      },
    );

    test('sanitizes group member_joined system preview', () async {
      const message = RemoteMessage(
        data: {
          'type': 'group_message',
          'groupId': 'group-team',
          'message_id': 'msg-group-join',
          'keyEpoch': '7',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      );

      final resolved = await resolveBackgroundPushNotification(
        message,
        decryptGroup:
            ({
              required groupId,
              required keyEpoch,
              required ciphertext,
              required nonce,
            }) async {
              return jsonEncode({
                'messageId': 'msg-group-join',
                'senderUsername': 'Rasha',
                'text': jsonEncode({
                  '__sys': 'member_joined',
                  'member': {
                    'peerId': '12D3KooWRawPeerId',
                    'username': 'Rasha',
                  },
                }),
              });
            },
      );

      expect(resolved.title, backgroundPushDefaultTitle);
      expect(resolved.body, 'Rasha joined the group');
      expect(resolved.payload, 'group:group-team|message:msg-group-join');
      for (final forbidden in ['{', '}', '__sys', 'peerId', '12D3']) {
        expect(resolved.body, isNot(contains(forbidden)));
      }
    });

    test('sanitizes unknown group system preview', () async {
      const message = RemoteMessage(
        data: {
          'type': 'group_message',
          'groupId': 'group-team',
          'message_id': 'msg-group-role',
          'keyEpoch': '7',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      );

      final resolved = await resolveBackgroundPushNotification(
        message,
        decryptGroup:
            ({
              required groupId,
              required keyEpoch,
              required ciphertext,
              required nonce,
            }) async {
              return jsonEncode({
                'messageId': 'msg-group-role',
                'senderUsername': 'Rasha',
                'text': jsonEncode({
                  '__sys': 'member_role_changed',
                  'member': {'peerId': '12D3KooWRawPeerId'},
                }),
              });
            },
      );

      expect(resolved.title, backgroundPushDefaultTitle);
      expect(resolved.body, 'Group update');
      expect(resolved.payload, 'group:group-team|message:msg-group-role');
      for (final forbidden in ['{', '}', '__sys', 'peerId', '12D3']) {
        expect(resolved.body, isNot(contains(forbidden)));
      }
    });

    test('degrades to fallback when decrypt input is missing', () async {
      const message = RemoteMessage(
        data: {'type': 'new_message', 'sender_id': 'peer-alice'},
      );

      final resolved = await resolveBackgroundPushNotification(
        message,
        decryptOneToOne:
            ({required kem, required ciphertext, required nonce}) async =>
                throw StateError('should not decrypt'),
      );

      expect(resolved.title, backgroundPushDefaultTitle);
      expect(resolved.body, backgroundPushDefaultBody);
      expect(resolved.payload, 'peer-alice');
    });

    test(
      'ordinary group decrypt failure without relay fallback flag fails closed',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'group_message',
            'groupId': 'group-team',
            'message_id': 'msg-group-1',
            'keyEpoch': '7',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );

        await expectLater(
          resolveBackgroundPushNotification(
            message,
            decryptGroup:
                ({
                  required groupId,
                  required keyEpoch,
                  required ciphertext,
                  required nonce,
                }) async => throw StateError('invalid cipher or missing key'),
          ),
          throwsA(isA<OrdinaryMessageNotificationIntegrityException>()),
        );
      },
    );

    test(
      'authorized preview_unavailable group wake returns localized generic copy',
      () async {
        final resolved = await resolveBackgroundPushNotification(
          const RemoteMessage(
            data: <String, dynamic>{
              'type': 'group_message',
              'groupId': 'group-team',
              'sender_transport_peer_id': 'transport-admin-phone',
              'message_id': 'msg-oversized-group',
              'preview_unavailable': '1',
            },
          ),
          groupMessageContext: const GroupMessageNotificationContext(
            groupId: 'group-team',
            groupName: 'Trusted Team',
            localPeerId: 'peer-local',
            senderPeerId: 'peer-admin',
            senderTransportPeerId: 'transport-admin-phone',
            senderUsername: 'Trusted Admin',
            expectedMessageId: 'msg-oversized-group',
          ),
          locale: const Locale('de'),
        );

        expect(resolved.title, 'Trusted Team');
        expect(resolved.body, 'Trusted Admin: Nachricht');
        expect(
          resolved.payload,
          'group:group-team|message:msg-oversized-group',
        );

        await expectLater(
          resolveBackgroundPushNotification(
            const RemoteMessage(
              data: <String, dynamic>{
                'type': 'group_message',
                'groupId': 'group-team',
                'sender_transport_peer_id': 'transport-admin-phone',
                'message_id': 'msg-oversized-group',
                'preview_unavailable': '1',
                'keyEpoch': '7',
                'ciphertext': 'invalid-ciphertext',
                'nonce': 'nonce',
              },
            ),
            groupMessageContext: const GroupMessageNotificationContext(
              groupId: 'group-team',
              groupName: 'Trusted Team',
              localPeerId: 'peer-local',
              senderPeerId: 'peer-admin',
              senderTransportPeerId: 'transport-admin-phone',
              senderUsername: 'Trusted Admin',
              expectedMessageId: 'msg-oversized-group',
            ),
            decryptGroup:
                ({
                  required groupId,
                  required keyEpoch,
                  required ciphertext,
                  required nonce,
                }) async => throw StateError('invalid ciphertext'),
          ),
          throwsA(isA<OrdinaryMessageNotificationIntegrityException>()),
          reason: 'the relay flag cannot launder an invalid provided cipher',
        );
      },
    );
  });

  group('pushPreviewBody', () {
    test('caps long text previews at 140 scalar values', () {
      final body = pushPreviewBody('a' * 180, null);

      expect(body.length, 140);
    });

    test('renders typed media descriptors', () {
      expect(
        pushPreviewBody('', [
          {'mediaType': 'audio'},
        ]),
        'Voice message',
      );
      expect(
        pushPreviewBody('', [
          {'mediaType': 'image'},
        ]),
        'Photo',
      );
    });

    test('localizes typed media descriptors for German and Arabic', () {
      expect(
        pushPreviewBody('', [
          {'mediaType': 'image'},
        ], locale: const Locale('de')),
        'Foto',
      );
      expect(
        pushPreviewBody('', [
          {'mediaType': 'audio'},
        ], locale: const Locale('de')),
        'Sprachnachricht',
      );
      expect(
        pushPreviewBody('', [
          {'mediaType': 'video'},
        ], locale: const Locale('ar')),
        'فيديو',
      );
      expect(
        pushPreviewBody('', [
          {'mediaType': 'audio'},
        ], locale: const Locale('ar')),
        'رسالة صوتية',
      );
      expect(pushPreviewBody('', null, locale: const Locale('ar')), 'رسالة');
    });
  });
}

Map<String, dynamic> _signedGroupReactionPushData({
  required List<String> notificationRecipients,
}) {
  final signedPayload = canonicalizeGroupEventLogPayload(<String, Object?>{
    'kind': 'group_reaction_notification',
    'version': 1,
    'transitionId': 'transition-signed-1',
    'action': 'add',
    'targetMessageId': 'message-owned-by-local',
    'reactorPeerId': 'peer-reactor',
    'reactorTransportPeerId': 'transport-reactor',
    'replayRecipientSetHash': 'replay-set-hash',
    'notificationRecipientTransportPeerIds': notificationRecipients,
    'baseEnvelopeHash': 'base-envelope-hash',
  });
  final extension = <String, Object?>{
    'version': 1,
    'transitionId': 'transition-signed-1',
    'action': 'add',
    'targetMessageId': 'message-owned-by-local',
    'reactorPeerId': 'peer-reactor',
    'reactorTransportPeerId': 'transport-reactor',
    'replayRecipientSetHash': 'replay-set-hash',
    'notificationRecipientTransportPeerIds': notificationRecipients,
    'baseEnvelopeHash': 'base-envelope-hash',
    'signatureAlgorithm': 'ed25519',
    'signedPayload': signedPayload,
    'signature': 'signature',
  };
  return <String, dynamic>{
    'type': 'group_reaction',
    'groupId': 'group-team',
    'event_id': 'transition-signed-1',
    'target_message_id': 'message-owned-by-local',
    'action': 'add',
    'reactor_peer_id': 'peer-reactor',
    'reactor_transport_peer_id': 'transport-reactor',
    'base_envelope_hash': 'base-envelope-hash',
    'notification_extension': jsonEncode(extension),
    'sender_public_key': 'reactor-device-key',
    'capability_version': 'group_reaction_v1',
    'envelope_version': '1',
  };
}
