import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

ContactModel _contact(String peerId) => ContactModel(
  peerId: peerId,
  publicKey: 'pk-$peerId',
  rendezvous: 'rendezvous',
  username: peerId,
  signature: 'signature',
  scannedAt: '2026-11-04T10:00:00.000Z',
  mlKemPublicKey: 'mlkem-$peerId',
);

Map<String, dynamic> _voiceJson({Object? caption, bool withCaption = true}) =>
    <String, dynamic>{
      'media_id': 'media-1',
      'blob_id': 'blob-1',
      'kind': 'voice',
      'mime': 'audio/mp4',
      'size_bytes': 12,
      'duration_ms': 4000,
      if (withCaption) 'caption': caption,
    };

PostMediaAttachmentModel _parse(Map<String, dynamic> json) =>
    PostMediaAttachmentModel.fromRenderableJson(
      json,
      postId: 'thought',
      position: 0,
    );

void main() {
  group('wire', () {
    test('a caption round-trips through the media item', () {
      final parsed = _parse(_voiceJson(caption: 'what I think so far'));
      expect(parsed.toMap()['caption'], 'what I think so far');
      expect(parsed.toRenderableJson()['caption'], 'what I think so far');
    });

    test('a payload without a caption parses and writes no caption key', () {
      final parsed = _parse(_voiceJson(withCaption: false));
      expect(parsed.toMap()['caption'], isNull);
      expect(parsed.toRenderableJson().containsKey('caption'), isFalse);
    });

    test('a non-string caption is dropped', () {
      for (final bad in <Object?>[
        42,
        true,
        <String>['x'],
        null,
      ]) {
        final parsed = _parse(_voiceJson(caption: bad));
        expect(parsed.toMap()['caption'], isNull, reason: '$bad');
        expect(parsed.toRenderableJson().containsKey('caption'), isFalse);
      }
    });

    test('a blank caption is trimmed away and never written', () {
      final parsed = _parse(_voiceJson(caption: '   \n '));
      expect(parsed.toMap()['caption'], isNull);
      expect(parsed.toRenderableJson().containsKey('caption'), isFalse);
    });

    test('a received caption is trimmed and capped at 140 characters', () {
      final long = '  ${'🙂' * 150}  ';
      final parsed = _parse(_voiceJson(caption: long));
      expect(parsed.toMap()['caption'], '🙂' * 140);
    });
  });

  group('end to end', () {
    late InMemoryPostRepository posts;
    late InMemoryContactRepository contacts;
    late Directory temp;

    setUp(() async {
      posts = InMemoryPostRepository();
      contacts = InMemoryContactRepository();
      temp = await Directory.systemTemp.createTemp('voice-caption');
    });

    tearDown(() async {
      posts.dispose();
      await temp.delete(recursive: true);
    });

    test(
      'a voice draft caption is stored trimmed and reaches the sent attachment',
      () async {
        contacts.addTestContact(_contact('friend'));
        final source = File('${temp.path}/voice.m4a');
        await source.writeAsString('voice bytes');

        final (_, created) = await createLocalPost(
          postRepo: posts,
          contactRepo: contacts,
          senderPeerId: 'author',
          senderUsername: 'Author',
          text: '',
          audience: PostAudience.allFriends(),
          mediaDrafts: [
            PostMediaDraft(
              localFilePath: source.path,
              mime: 'audio/mp4',
              durationMs: 4000,
              caption: '  what I think so far ',
            ),
          ],
        );
        final recovery = await posts.loadPostMediaUploadRecoveryItems(
          created!.post.id,
        );
        expect(recovery.single.toMap()['caption'], 'what I think so far');

        // A restart: the recovery row, not the in-memory draft, drives upload.
        final (_, prepared) = await prepareCreatedLocalPostMedia(
          created: created.copyWith(mediaDrafts: const <PostMediaDraft>[]),
          postRepo: posts,
          secureKeyStore: FakeSecureKeyStore(),
          imageProcessor: ImageProcessor(),
          uploadPostMediaFn:
              ({
                required postId,
                required localFilePath,
                required mime,
                required allowedPeers,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
              }) async => PostMediaAttachmentModel(
                mediaId: 'media-1',
                postId: postId,
                blobId: 'blob-1',
                kind: 'voice',
                mime: mime,
                sizeBytes: 11,
                durationMs: durationMs,
                createdAt: '2026-11-04T10:00:00.000Z',
              ),
        );
        final saved = await posts.loadPostMediaAttachments(created.post.id);
        expect(saved.single.toMap()['caption'], 'what I think so far');
        final wireMedia =
            (jsonDecode(
                      PostCreateEnvelope.fromPost(prepared!.post).toInnerJson(),
                    )
                    as Map<String, dynamic>)['snapshot']['media']
                as List<dynamic>;
        expect(
          (wireMedia.single as Map<String, dynamic>)['caption'],
          'what I think so far',
        );
      },
    );

    test('a received voice caption is saved on the attachment', () async {
      final now = DateTime.now().toUtc();
      contacts.addTestContact(_contact('author'));
      final createdAt = now.subtract(const Duration(minutes: 5));
      final post = PostModel(
        id: 'thought',
        eventId: 'event',
        senderPeerId: 'author',
        authorPeerId: 'author',
        authorUsername: 'Author',
        text: '',
        audience: PostAudience.allFriends(),
        createdAt: createdAt.toIso8601String(),
        visibleAt: createdAt.toIso8601String(),
        expiresAt: '2099-01-01T00:00:00.000Z',
        mediaKind: 'voice',
        media: [_parse(_voiceJson(withCaption: false))],
        isIncoming: false,
      );
      final raw =
          jsonDecode(PostCreateEnvelope.fromPost(post).toJson())
              as Map<String, dynamic>;
      final media =
          (raw['payload']['snapshot'] as Map<String, dynamic>)['media']
              as List<dynamic>;
      (media.single as Map<String, dynamic>)['caption'] = ' heard it today ';

      final (result, _) = await handleIncomingPost(
        message: ChatMessage(
          from: 'author',
          to: 'receiver',
          content: jsonEncode(raw),
          timestamp: now.toIso8601String(),
          isIncoming: true,
        ),
        postRepo: posts,
        contactRepo: contacts,
        nowProvider: () => now,
      );

      expect(result, HandleIncomingPostResult.postCreated);
      final saved = await posts.loadPostMediaAttachments('thought');
      expect(saved.single.toMap()['caption'], 'heard it today');
    });
  });
}
