import 'dart:convert';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';

void main() {
  const testPayload = MessagePayload(
    id: 'msg-uuid-001',
    text: 'Hello! This is my first letter.',
    senderPeerId: '12D3KooWSender123',
    senderUsername: 'Alice',
    timestamp: '2026-02-09T15:30:00.000Z',
  );

  group('MessagePayload', () {
    test('TC-345-01c wire payload cannot mint local media custody intent', () {
      const injectedIntent = '0123456789abcdef0123456789abcdef';
      final v1Envelope =
          jsonDecode(testPayload.toJson()) as Map<String, dynamic>;
      final v1Payload = v1Envelope['payload'] as Map<String, dynamic>;
      v1Payload['directMediaCustodyIntentId'] = injectedIntent;
      v1Payload['direct_media_custody_intent_id'] = injectedIntent;

      final inner =
          jsonDecode(testPayload.toInnerJson()) as Map<String, dynamic>
            ..['directMediaCustodyIntentId'] = injectedIntent
            ..['direct_media_custody_intent_id'] = injectedIntent;
      final fromV1 = MessagePayload.fromJson(
        jsonEncode(v1Envelope),
      )!.toConversationMessage(contactPeerId: 'sender', isIncoming: true);
      final fromV2 = MessagePayload.fromDecryptedJson(
        jsonEncode(inner),
      )!.toConversationMessage(contactPeerId: 'sender', isIncoming: true);

      expect(fromV1.directMediaCustodyIntentId, isNull);
      expect(fromV2.directMediaCustodyIntentId, isNull);
      expect(testPayload.toJson(), isNot(contains('CustodyIntent')));
      expect(testPayload.toJson(), isNot(contains('custody_intent')));
      expect(testPayload.toInnerJson(), isNot(contains('CustodyIntent')));
      expect(testPayload.toInnerJson(), isNot(contains('custody_intent')));
    });

    test(
      'forward marker is legacy-safe inner-only and carries media plus dedup',
      () {
        const forwarded = MessagePayload(
          id: 'forwarded-1',
          text: 'caption',
          senderPeerId: 'sender',
          senderUsername: 'Sender',
          timestamp: '2026-07-10T00:00:00.000Z',
          dedupKey: 'operation-token',
          isForwarded: true,
          media: [
            {'id': 'attachment-1', 'mime': 'image/jpeg', 'mediaType': 'image'},
          ],
        );

        final v1 = MessagePayload.fromJson(forwarded.toJson())!;
        final v2 = MessagePayload.fromDecryptedJson(forwarded.toInnerJson())!;
        expect(v1.isForwarded, isTrue);
        expect(v2.isForwarded, isTrue);
        expect(v2.dedupKey, 'operation-token');
        expect(v2.media, hasLength(1));
        expect(
          MessagePayload.fromJson(testPayload.toJson())!.isForwarded,
          isFalse,
        );

        final outer =
            jsonDecode(
                  MessagePayload.buildEncryptedEnvelope(
                    id: forwarded.id,
                    senderPeerId: forwarded.senderPeerId,
                    senderUsername: forwarded.senderUsername,
                    kem: 'kem',
                    ciphertext: forwarded.toInnerJson(),
                    nonce: 'nonce',
                  ),
                )
                as Map<String, dynamic>;
        expect(outer.keys, isNot(contains('isForwarded')));
        expect(outer.keys, isNot(contains('dedupKey')));
      },
    );

    group('toJson / fromJson round-trip', () {
      test('round-trips correctly', () {
        final jsonString = testPayload.toJson();
        final restored = MessagePayload.fromJson(jsonString);

        expect(restored, isNotNull);
        expect(restored!.id, testPayload.id);
        expect(restored.text, testPayload.text);
        expect(restored.senderPeerId, testPayload.senderPeerId);
        expect(restored.senderUsername, testPayload.senderUsername);
        expect(restored.timestamp, testPayload.timestamp);
      });

      test('toJson produces correct envelope structure', () {
        final jsonString = testPayload.toJson();
        final parsed = jsonDecode(jsonString) as Map<String, dynamic>;

        expect(parsed['type'], 'chat_message');
        expect(parsed['version'], '1');
        expect(parsed['payload'], isA<Map<String, dynamic>>());

        final payload = parsed['payload'] as Map<String, dynamic>;
        expect(payload['id'], 'msg-uuid-001');
        expect(payload['text'], 'Hello! This is my first letter.');
        expect(payload['senderPeerId'], '12D3KooWSender123');
        expect(payload['senderUsername'], 'Alice');
        expect(payload['timestamp'], '2026-02-09T15:30:00.000Z');
        expect(payload.containsKey('action'), isFalse);
        expect(payload.containsKey('editedAt'), isFalse);
      });

      test('round-trips edit metadata when present', () {
        const editPayload = MessagePayload(
          id: 'msg-edit-001',
          text: 'Updated text',
          senderPeerId: '12D3KooWSender123',
          senderUsername: 'Alice',
          timestamp: '2026-02-09T15:30:00.000Z',
          action: MessagePayload.actionEdit,
          editedAt: '2026-02-09T16:00:00.000Z',
        );

        final jsonString = editPayload.toJson();
        final restored = MessagePayload.fromJson(jsonString);
        final parsed = jsonDecode(jsonString) as Map<String, dynamic>;

        expect(restored, isNotNull);
        expect(restored!.action, MessagePayload.actionEdit);
        expect(restored.editedAt, '2026-02-09T16:00:00.000Z');
        expect(parsed['payload']['action'], MessagePayload.actionEdit);
        expect(parsed['payload']['editedAt'], '2026-02-09T16:00:00.000Z');
      });
    });

    group('edit event identity', () {
      const editPayload = MessagePayload(
        id: 'msg-edit-target-001',
        text: 'Updated text',
        senderPeerId: '12D3KooWSender123',
        senderUsername: 'Alice',
        timestamp: '2026-02-09T15:30:00.000Z',
        action: MessagePayload.actionEdit,
        eventId: 'edit-event-001',
        editedAt: '2026-02-09T16:00:00.000Z',
      );

      test('round-trips through v1 and encrypted inner payloads', () {
        final v1 = MessagePayload.fromJson(editPayload.toJson());
        final inner = MessagePayload.fromDecryptedJson(
          editPayload.toInnerJson(),
        );

        expect(v1, isNotNull);
        expect(v1!.id, editPayload.id);
        expect(v1.eventId, editPayload.eventId);
        expect(v1.action, MessagePayload.actionEdit);
        expect(inner, isNotNull);
        expect(inner!.id, editPayload.id);
        expect(inner.eventId, editPayload.eventId);
        expect(inner.action, MessagePayload.actionEdit);
      });

      test('encrypted outer builder keeps target id and stamps event id', () {
        final envelope =
            jsonDecode(
                  MessagePayload.buildEncryptedEnvelope(
                    id: editPayload.id,
                    senderPeerId: editPayload.senderPeerId,
                    senderUsername: editPayload.senderUsername,
                    kem: 'kem',
                    ciphertext: 'ciphertext',
                    nonce: 'nonce',
                    eventId: editPayload.eventId,
                  ),
                )
                as Map<String, dynamic>;

        expect(envelope['id'], editPayload.id);
        expect(envelope['eventId'], editPayload.eventId);
        expect(envelope['id'], isNot(envelope['eventId']));
      });
    });

    group('dedupKey (F8 tier-2)', () {
      MessagePayload keyed({
        String dedupKey = 'src-1',
        List<Map<String, dynamic>>? media,
      }) => MessagePayload(
        id: 'msg-002',
        text: 'Hello!',
        senderPeerId: '12D3KooWSender123',
        senderUsername: 'Alice',
        timestamp: '2026-02-09T15:30:00.000Z',
        dedupKey: dedupKey,
        media: media,
      );

      test('round-trips through v1 toJson/fromJson', () {
        expect(MessagePayload.fromJson(keyed().toJson())!.dedupKey, 'src-1');
        // No key on the wire → null (legacy sender).
        expect(MessagePayload.fromJson(testPayload.toJson())!.dedupKey, isNull);
      });

      test(
        'round-trips through v2 inner (toInnerJson/fromDecryptedJson) — PROD-CRITICAL',
        () {
          final inner = keyed().toInnerJson();
          expect(inner, contains('"dedupKey":"src-1"'));
          expect(MessagePayload.fromDecryptedJson(inner)!.dedupKey, 'src-1');
        },
      );

      test('survives the v2 inner leg alongside media (M3 media forward)', () {
        final inner = keyed(
          media: [
            {
              'id': 'm1',
              'mime': 'image/jpeg',
              'size': 10,
              'mediaType': 'image',
            },
          ],
        ).toInnerJson();
        final restored = MessagePayload.fromDecryptedJson(inner)!;
        expect(restored.dedupKey, 'src-1');
        expect(restored.media!.single['mime'], 'image/jpeg');
      });
    });

    group('fromJson invalid input', () {
      test('returns null for non-JSON string', () {
        expect(MessagePayload.fromJson('not json'), isNull);
      });

      test('returns null for wrong type', () {
        final json = jsonEncode({
          'type': 'contact_request',
          'version': '1',
          'payload': {
            'id': '1',
            'text': 'hi',
            'senderPeerId': 'peer',
            'senderUsername': 'user',
            'timestamp': '2026-01-01T00:00:00.000Z',
          },
        });
        expect(MessagePayload.fromJson(json), isNull);
      });

      test('returns null for missing payload', () {
        final json = jsonEncode({'type': 'chat_message', 'version': '1'});
        expect(MessagePayload.fromJson(json), isNull);
      });

      test('returns null for missing required fields', () {
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {
            'id': '1',
            'text': 'hi',
            // missing senderPeerId, senderUsername, timestamp
          },
        });
        expect(MessagePayload.fromJson(json), isNull);
      });

      test('returns null for empty string', () {
        expect(MessagePayload.fromJson(''), isNull);
      });

      test('returns null when payload has null fields', () {
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {
            'id': null,
            'text': 'hi',
            'senderPeerId': 'peer',
            'senderUsername': 'user',
            'timestamp': '2026-01-01T00:00:00.000Z',
          },
        });
        expect(MessagePayload.fromJson(json), isNull);
      });
    });

    group('toConversationMessage', () {
      test('converts to incoming ConversationMessage correctly', () {
        final message = testPayload.toConversationMessage(
          contactPeerId: '12D3KooWSender123',
          isIncoming: true,
          status: 'delivered',
        );

        expect(message.id, testPayload.id);
        expect(message.contactPeerId, '12D3KooWSender123');
        expect(message.senderPeerId, testPayload.senderPeerId);
        expect(message.text, testPayload.text);
        expect(message.timestamp, testPayload.timestamp);
        expect(message.status, 'delivered');
        expect(message.isIncoming, true);
        expect(message.createdAt, isNotEmpty);
      });

      test('converts to outgoing ConversationMessage correctly', () {
        final message = testPayload.toConversationMessage(
          contactPeerId: 'target-peer',
          isIncoming: false,
          status: 'sent',
        );

        expect(message.isIncoming, false);
        expect(message.status, 'sent');
        expect(message.contactPeerId, 'target-peer');
      });

      test('uses default status of sent', () {
        final message = testPayload.toConversationMessage(
          contactPeerId: 'peer',
          isIncoming: false,
        );

        expect(message.status, 'sent');
      });
    });

    group('v2 encrypted envelope', () {
      const kem = 'base64kem==';
      const ciphertext = 'base64ct==';
      const nonce = 'base64nonce==';
      const messageId = 'msg-123';
      const senderPeerId = '12D3KooWSender123';
      const senderUsername = 'Alice';

      test('buildEncryptedEnvelope produces correct structure', () {
        final envelope = MessagePayload.buildEncryptedEnvelope(
          id: messageId,
          senderPeerId: senderPeerId,
          senderUsername: senderUsername,
          kem: kem,
          ciphertext: ciphertext,
          nonce: nonce,
        );

        final parsed = jsonDecode(envelope) as Map<String, dynamic>;
        expect(parsed['type'], 'chat_message');
        expect(parsed['version'], '2');
        expect(parsed['id'], messageId);
        expect(parsed['senderPeerId'], senderPeerId);
        expect(parsed.containsKey('senderUsername'), isFalse);
        expect(parsed['encrypted']['kem'], kem);
        expect(parsed['encrypted']['ciphertext'], ciphertext);
        expect(parsed['encrypted']['nonce'], nonce);
      });

      test('parseEncryptedEnvelope returns map for valid v2', () {
        final envelope = MessagePayload.buildEncryptedEnvelope(
          id: messageId,
          senderPeerId: senderPeerId,
          senderUsername: senderUsername,
          kem: kem,
          ciphertext: ciphertext,
          nonce: nonce,
        );

        final result = MessagePayload.parseEncryptedEnvelope(envelope);
        expect(result, isNotNull);
        expect(result!['version'], '2');
        expect(result['encrypted']['kem'], kem);
      });

      test('parseEncryptedEnvelope returns null for v1 envelope', () {
        expect(
          MessagePayload.parseEncryptedEnvelope(testPayload.toJson()),
          isNull,
        );
      });

      test('parseEncryptedEnvelope returns null for non-chat_message', () {
        final json = jsonEncode({
          'type': 'contact_request',
          'version': '2',
          'encrypted': {'kem': 'x', 'ciphertext': 'y', 'nonce': 'z'},
        });
        expect(MessagePayload.parseEncryptedEnvelope(json), isNull);
      });

      test(
        'parseEncryptedEnvelope returns null for missing encrypted fields',
        () {
          final json = jsonEncode({
            'type': 'chat_message',
            'version': '2',
            'encrypted': {'kem': 'x'},
          });
          expect(MessagePayload.parseEncryptedEnvelope(json), isNull);
        },
      );

      test(
        'parseEncryptedEnvelope returns null for missing encrypted block',
        () {
          final json = jsonEncode({
            'type': 'chat_message',
            'version': '2',
            'senderPeerId': senderPeerId,
          });
          expect(MessagePayload.parseEncryptedEnvelope(json), isNull);
        },
      );

      test('parseEncryptedEnvelope returns null for invalid JSON', () {
        expect(MessagePayload.parseEncryptedEnvelope('not json'), isNull);
      });
    });

    group('fromDecryptedJson', () {
      test('parses inner payload JSON', () {
        final inner = testPayload.toInnerJson();
        final parsed = MessagePayload.fromDecryptedJson(inner);

        expect(parsed, isNotNull);
        expect(parsed!.id, testPayload.id);
        expect(parsed.text, testPayload.text);
        expect(parsed.senderPeerId, testPayload.senderPeerId);
        expect(parsed.senderUsername, testPayload.senderUsername);
        expect(parsed.timestamp, testPayload.timestamp);
        expect(parsed.action, MessagePayload.actionSend);
      });

      test('returns null for missing fields', () {
        final json = jsonEncode({'id': 'x', 'text': 'y'});
        expect(MessagePayload.fromDecryptedJson(json), isNull);
      });

      test('returns null for invalid JSON', () {
        expect(MessagePayload.fromDecryptedJson('not json'), isNull);
      });
    });

    group('toInnerJson', () {
      test('produces JSON without envelope wrapper', () {
        final inner =
            jsonDecode(testPayload.toInnerJson()) as Map<String, dynamic>;

        expect(inner.containsKey('type'), isFalse);
        expect(inner.containsKey('version'), isFalse);
        expect(inner.containsKey('payload'), isFalse);
        expect(inner['id'], testPayload.id);
        expect(inner['text'], testPayload.text);
        expect(inner['senderPeerId'], testPayload.senderPeerId);
        expect(inner['senderUsername'], testPayload.senderUsername);
        expect(inner['timestamp'], testPayload.timestamp);
        expect(inner.containsKey('action'), isFalse);
      });

      test('includes edit metadata for edit payloads', () {
        const editPayload = MessagePayload(
          id: 'msg-edit-002',
          text: 'Inner edit',
          senderPeerId: '12D3KooWSender123',
          senderUsername: 'Alice',
          timestamp: '2026-02-09T15:30:00.000Z',
          action: MessagePayload.actionEdit,
          editedAt: '2026-02-09T16:30:00.000Z',
        );

        final inner =
            jsonDecode(editPayload.toInnerJson()) as Map<String, dynamic>;
        expect(inner['action'], MessagePayload.actionEdit);
        expect(inner['editedAt'], '2026-02-09T16:30:00.000Z');
      });
    });

    group('quotedMessageId', () {
      const payloadWithQuote = MessagePayload(
        id: 'msg-q1',
        text: 'This is a reply',
        senderPeerId: '12D3KooWSender123',
        senderUsername: 'Alice',
        timestamp: '2026-02-20T10:00:00.000Z',
        quotedMessageId: 'original-msg-001',
      );

      test('v1 round-trip preserves quotedMessageId', () {
        final jsonString = payloadWithQuote.toJson();
        final restored = MessagePayload.fromJson(jsonString);

        expect(restored, isNotNull);
        expect(restored!.quotedMessageId, 'original-msg-001');
      });

      test('v1 toJson includes quotedMessageId in payload', () {
        final jsonString = payloadWithQuote.toJson();
        final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
        final payload = parsed['payload'] as Map<String, dynamic>;

        expect(payload['quotedMessageId'], 'original-msg-001');
      });

      test('v1 toJson omits quotedMessageId when null', () {
        final jsonString = testPayload.toJson();
        final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
        final payload = parsed['payload'] as Map<String, dynamic>;

        expect(payload.containsKey('quotedMessageId'), isFalse);
      });

      test(
        'v1 fromJson reads null when quotedMessageId absent (backward compat)',
        () {
          final json = jsonEncode({
            'type': 'chat_message',
            'version': '1',
            'payload': {
              'id': 'old-msg',
              'text': 'old message',
              'senderPeerId': 'peer',
              'senderUsername': 'user',
              'timestamp': '2026-01-01T00:00:00.000Z',
            },
          });
          final restored = MessagePayload.fromJson(json);
          expect(restored, isNotNull);
          expect(restored!.quotedMessageId, isNull);
        },
      );

      test('v2 inner round-trip preserves quotedMessageId', () {
        final innerJson = payloadWithQuote.toInnerJson();
        final restored = MessagePayload.fromDecryptedJson(innerJson);

        expect(restored, isNotNull);
        expect(restored!.quotedMessageId, 'original-msg-001');
      });

      test('v2 toInnerJson includes quotedMessageId', () {
        final inner =
            jsonDecode(payloadWithQuote.toInnerJson()) as Map<String, dynamic>;
        expect(inner['quotedMessageId'], 'original-msg-001');
      });

      test('v2 toInnerJson omits quotedMessageId when null', () {
        final inner =
            jsonDecode(testPayload.toInnerJson()) as Map<String, dynamic>;
        expect(inner.containsKey('quotedMessageId'), isFalse);
      });

      test('toConversationMessage passes quotedMessageId', () {
        final msg = payloadWithQuote.toConversationMessage(
          contactPeerId: 'target',
          isIncoming: false,
        );
        expect(msg.quotedMessageId, 'original-msg-001');
      });

      test('toConversationMessage passes null when no quote', () {
        final msg = testPayload.toConversationMessage(
          contactPeerId: 'target',
          isIncoming: false,
        );
        expect(msg.quotedMessageId, isNull);
      });
    });

    group('media', () {
      test('TC-347-04 blob custody canonical wire and manifest hash', () {
        final a = DirectMediaBlobCustodyCommitment(
          contentHash: 'a' * 64,
          ciphertextSize: 101,
          expiresAtMs: 2000,
        );
        final b = DirectMediaBlobCustodyCommitment(
          contentHash: 'b' * 64,
          ciphertextSize: 202,
          expiresAtMs: 3000,
        );
        final attachment = MediaAttachment(
          id: 'blob-a',
          messageId: 'message-347',
          mime: 'image/jpeg',
          size: 7,
          mediaType: 'image',
          localPath: '/private/path-that-must-not-be-public',
          downloadStatus: 'done',
          createdAt: '2026-08-08T00:00:00.000Z',
          encryptionKeyBase64: 'secret-key',
          encryptionNonce: 'secret-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.direct,
          blobCustody: a,
        );

        final wire = attachment.toJson();
        expect(wire['size'], 7, reason: 'plaintext size remains unchanged');
        expect(wire['blobCustody'], <String, Object>{
          'kind': kDirectMediaBlobCustodyKind,
          'contract': kDirectMediaBlobCustodyContract,
          'contentHash': 'a' * 64,
          'ciphertextSize': 101,
          'transportMime': kDirectMediaBlobTransportMime,
          'expiresAtMs': 2000,
        });
        expect(jsonEncode(wire), isNot(contains('/private/path')));
        expect(jsonEncode(wire), isNot(contains('relay')));
        expect(
          MediaAttachment.fromJson(wire).blobCustody!.contentHash,
          'a' * 64,
        );

        final reverseOrder = <DirectMediaBlobManifestProjection>[
          DirectMediaBlobManifestProjection(
            attachmentId: 'blob-b',
            commitment: b,
          ),
          DirectMediaBlobManifestProjection(
            attachmentId: 'blob-a',
            commitment: a,
          ),
        ];
        final forwardOrder = reverseOrder.reversed.toList(growable: false);
        const expected =
            'a0e9b0a829a33d4298f90f3e067e1bd5ee9c2d6e5f4452225c197f4ca653fab2';
        expect(computeDirectMediaBlobManifestHash(reverseOrder), expected);
        expect(computeDirectMediaBlobManifestHash(forwardOrder), expected);
        expect(earliestDirectMediaBlobExpiryMs(reverseOrder), 2000);

        final injected = Map<String, Object?>.from(wire['blobCustody']! as Map)
          ..['relayPeerId'] = 'must-not-be-accepted';
        expect(
          () => DirectMediaBlobCustodyCommitment.fromJson(injected),
          throwsFormatException,
        );
        expect(
          () => computeDirectMediaBlobManifestHash(
            <DirectMediaBlobManifestProjection>[
              DirectMediaBlobManifestProjection(
                attachmentId: 'blob-a',
                commitment: a,
              ),
              DirectMediaBlobManifestProjection(
                attachmentId: 'blob-a',
                commitment: b,
              ),
            ],
          ),
          throwsFormatException,
        );
      });

      final mediaArray = [
        {
          'id': 'blob-001',
          'mime': 'image/jpeg',
          'size': 245000,
          'mediaType': 'image',
          'width': 1920,
          'height': 1080,
        },
        {
          'id': 'blob-002',
          'mime': 'audio/mp3',
          'size': 50000,
          'mediaType': 'audio',
          'durationMs': 30000,
        },
      ];

      final payloadWithMedia = MessagePayload(
        id: 'msg-media-001',
        text: 'Check this out',
        senderPeerId: '12D3KooWSender123',
        senderUsername: 'Alice',
        timestamp: '2026-02-20T10:00:00.000Z',
        media: mediaArray,
      );

      test('v1 round-trip preserves media array', () {
        final jsonString = payloadWithMedia.toJson();
        final restored = MessagePayload.fromJson(jsonString);

        expect(restored, isNotNull);
        expect(restored!.media, isNotNull);
        expect(restored.media!.length, 2);
        expect(restored.media![0]['id'], 'blob-001');
        expect(restored.media![0]['mime'], 'image/jpeg');
        expect(restored.media![0]['width'], 1920);
        expect(restored.media![1]['id'], 'blob-002');
        expect(restored.media![1]['durationMs'], 30000);
      });

      test('v1 toJson includes media in payload', () {
        final jsonString = payloadWithMedia.toJson();
        final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
        final payload = parsed['payload'] as Map<String, dynamic>;

        expect(payload['media'], isNotNull);
        expect(payload['media'], isList);
        expect((payload['media'] as List).length, 2);
      });

      test('v1 toJson omits media when null', () {
        final jsonString = testPayload.toJson();
        final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
        final payload = parsed['payload'] as Map<String, dynamic>;

        expect(payload.containsKey('media'), isFalse);
      });

      test('v1 toJson omits media when empty list', () {
        const emptyMedia = MessagePayload(
          id: 'msg-empty-media',
          text: 'No attachments',
          senderPeerId: '12D3KooWSender123',
          senderUsername: 'Alice',
          timestamp: '2026-02-20T10:00:00.000Z',
          media: [],
        );
        final jsonString = emptyMedia.toJson();
        final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
        final payload = parsed['payload'] as Map<String, dynamic>;

        expect(payload.containsKey('media'), isFalse);
      });

      test('v1 fromJson reads null when media absent (backward compat)', () {
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {
            'id': 'old-msg',
            'text': 'old message without media',
            'senderPeerId': 'peer',
            'senderUsername': 'user',
            'timestamp': '2026-01-01T00:00:00.000Z',
          },
        });
        final restored = MessagePayload.fromJson(json);
        expect(restored, isNotNull);
        expect(restored!.media, isNull);
      });

      test('v2 inner round-trip preserves media', () {
        final innerJson = payloadWithMedia.toInnerJson();
        final restored = MessagePayload.fromDecryptedJson(innerJson);

        expect(restored, isNotNull);
        expect(restored!.media, isNotNull);
        expect(restored.media!.length, 2);
        expect(restored.media![0]['id'], 'blob-001');
        expect(restored.media![1]['id'], 'blob-002');
      });

      test('v2 toInnerJson includes media', () {
        final inner =
            jsonDecode(payloadWithMedia.toInnerJson()) as Map<String, dynamic>;
        expect(inner['media'], isNotNull);
        expect((inner['media'] as List).length, 2);
      });

      test('v2 toInnerJson omits media when null', () {
        final inner =
            jsonDecode(testPayload.toInnerJson()) as Map<String, dynamic>;
        expect(inner.containsKey('media'), isFalse);
      });

      test('toConversationMessage does not include media (transient)', () {
        final msg = payloadWithMedia.toConversationMessage(
          contactPeerId: 'target',
          isIncoming: true,
          status: 'delivered',
        );
        // media is a transient field on ConversationMessage, not set by toConversationMessage
        expect(msg.media, isEmpty);
      });
    });

    group('private media encrypted-inner codec', () {
      MessagePayload privatePayload(PrivateMediaPolicy policy) =>
          MessagePayload(
            id: 'private-1',
            text: '',
            senderPeerId: 'sender',
            senderUsername: 'Sender',
            timestamp: '2026-07-11T00:00:00.000Z',
            media: const [
              {
                'id': 'attachment-1',
                'mime': 'image/jpeg',
                'mediaType': 'image',
              },
            ],
            privateMediaPolicy: policy,
          );

      test('valid policy round-trips only through encrypted inner JSON', () {
        final policy = PrivateMediaPolicy.fromJson({
          'version': 1,
          'mode': 'disappearing',
          'durationSeconds': 604800,
        });
        final payload = privatePayload(policy);

        final inner = jsonDecode(payload.toInnerJson()) as Map<String, dynamic>;
        expect(inner['privateMedia'], {
          'version': 1,
          'mode': 'disappearing',
          'durationSeconds': 604800,
        });
        final restored = MessagePayload.fromDecryptedJson(
          payload.toInnerJson(),
        );
        expect(restored, isNotNull);
        expect(restored!.privateMediaPolicy, policy);

        final message = restored.toConversationMessage(
          contactPeerId: 'sender',
          isIncoming: true,
          status: 'delivered',
        );
        expect(message.privateMediaPolicyVersion, 1);
        expect(message.privateMediaMode, PrivateMediaMode.disappearing);
        expect(message.privateMediaDurationSeconds, 604800);
        expect(message.privateMediaState, PrivateMediaLifecycleState.available);
      });

      test(
        'legacy private GIF inner policy remains private and never becomes ordinary',
        () {
          const policy = PrivateMediaPolicy.protected();
          const payload = MessagePayload(
            id: 'legacy-private-gif',
            text: '',
            senderPeerId: 'sender',
            senderUsername: 'Sender',
            timestamp: '2026-07-11T00:00:00.000Z',
            media: [
              {
                'id': 'legacy-gif-attachment',
                'mime': 'image/gif',
                'mediaType': 'image',
              },
            ],
            privateMediaPolicy: policy,
          );

          final inner =
              jsonDecode(payload.toInnerJson()) as Map<String, dynamic>;
          expect(inner['privateMedia'], {'version': 1, 'mode': 'protected'});
          expect(
            (inner['media'] as List<dynamic>).single,
            containsPair('mime', 'image/gif'),
          );

          final restored = MessagePayload.fromDecryptedJson(
            payload.toInnerJson(),
          );
          expect(restored, isNotNull);
          expect(restored!.privateMediaPolicy, policy);
          expect(restored.privateMediaPolicy.isUnsupported, isFalse);
          expect(
            restored.privateMediaPolicy,
            isNot(const PrivateMediaPolicy.ordinary()),
          );

          final message = restored.toConversationMessage(
            contactPeerId: 'sender',
            isIncoming: true,
            status: 'delivered',
          );
          expect(message.privateMediaPolicy, policy);
          expect(
            message.privateMediaState,
            PrivateMediaLifecycleState.available,
          );
        },
      );

      test('clear v2 envelope and v1 writer never contain privateMedia', () {
        final payload = privatePayload(
          PrivateMediaPolicy.fromJson({'version': 1, 'mode': 'protected'}),
        );

        final v1 = payload.toJson();
        expect(v1, isNot(contains('privateMedia')));
        expect(
          MessagePayload.fromJson(v1)!.privateMediaPolicy,
          const PrivateMediaPolicy.ordinary(),
        );

        final outer = MessagePayload.buildEncryptedEnvelope(
          id: payload.id,
          senderPeerId: payload.senderPeerId,
          senderUsername: payload.senderUsername,
          kem: 'kem',
          ciphertext: 'ciphertext',
          nonce: 'nonce',
        );
        expect(outer, isNot(contains('privateMedia')));
      });

      test(
        'missing policy keeps legacy inner bytes and behavior compatible',
        () {
          expect(
            testPayload.toInnerJson(),
            '{"id":"msg-uuid-001","text":"Hello! This is my first letter.",'
            '"senderPeerId":"12D3KooWSender123","senderUsername":"Alice",'
            '"timestamp":"2026-02-09T15:30:00.000Z"}',
          );
          final restored = MessagePayload.fromDecryptedJson(
            testPayload.toInnerJson(),
          );
          expect(
            restored!.privateMediaPolicy,
            const PrivateMediaPolicy.ordinary(),
          );
        },
      );

      test(
        'malformed unknown and ineligible private policy is unsupported',
        () {
          Map<String, dynamic> base() => {
            'id': 'private-bad',
            'text': '',
            'senderPeerId': 'sender',
            'senderUsername': 'Sender',
            'timestamp': '2026-07-11T00:00:00.000Z',
            'media': [
              {'id': 'a1', 'mime': 'image/jpeg', 'mediaType': 'image'},
            ],
          };

          for (final invalidPolicy in <Object?>[
            'protected',
            {'version': 2, 'mode': 'protected'},
            {'version': 1, 'mode': 'future'},
            {'version': 1, 'mode': 'disappearing', 'durationSeconds': 60},
          ]) {
            final inner = base()..['privateMedia'] = invalidPolicy;
            final parsed = MessagePayload.fromDecryptedJson(jsonEncode(inner));
            expect(parsed, isNotNull);
            expect(parsed!.privateMediaPolicy.isUnsupported, isTrue);
          }

          final captioned = base()
            ..['text'] = 'caption'
            ..['privateMedia'] = {'version': 1, 'mode': 'view_once'};
          expect(
            MessagePayload.fromDecryptedJson(
              jsonEncode(captioned),
            )!.privateMediaPolicy.isUnsupported,
            isTrue,
          );
        },
      );

      test('unknown additive v1 fields are ignored during inner decode', () {
        final inner =
            jsonDecode(
                  privatePayload(
                    PrivateMediaPolicy.fromJson({
                      'version': 1,
                      'mode': 'protected',
                    }),
                  ).toInnerJson(),
                )
                as Map<String, dynamic>;
        (inner['privateMedia'] as Map<String, dynamic>)['futureField'] = true;

        final restored = MessagePayload.fromDecryptedJson(jsonEncode(inner));
        expect(restored!.privateMediaPolicy.isUnsupported, isFalse);
        expect(restored.privateMediaPolicy.mode, PrivateMediaMode.protected);
        expect(restored.privateMediaPolicy.toJson(), {
          'version': 1,
          'mode': 'protected',
        });
      });
    });
  });
}
