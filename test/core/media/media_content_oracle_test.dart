import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/media_content_oracle.dart';
import '../../../integration_test/support/media_oracle_go_bridge_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File processed;
  late File cipher;
  late File received;
  late MediaEncryptionInputObserver observer;
  final identity = MediaWireIdentity(
    runId: 'fixture-run',
    owner: MediaOwnerLane.direct,
    messageId: 'fixture-message',
    attachmentId: 'fixture-attachment',
  );
  final imageBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAgCAIAAAAt/+nTAAAATklEQVR4nO3PUQkAIBTAwNfAfmY3jCH8OITBAtxm7fN1wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjx2AV3NKJdv7voVAAAAAElFTkSuQmCC',
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('media-oracle-');
    processed = File('${root.path}/processed.png')
      ..writeAsBytesSync(imageBytes);
    cipher = File('${root.path}/cipher.blob');
    received = File('${root.path}/received.png')..writeAsBytesSync(imageBytes);
    observer = MediaEncryptionInputObserver();
  });
  tearDown(() => root.deleteSync(recursive: true));

  String request() => jsonEncode({
    'cmd': 'blob:encrypt',
    'payload': {'filePath': processed.path, 'keyBase64': 'fixture-only-key'},
  });
  Future<String> encryptFixture() async {
    // Observer tests intentionally fake only native crypto; this is not AES.
    cipher.writeAsBytesSync([
      for (final b in processed.readAsBytesSync()) b ^ 0x5a,
      ...List.filled(16, 7),
    ]);
    return jsonEncode({
      'ok': true,
      'encryptedPath': cipher.path,
      'nonce': 'fixture-nonce',
    });
  }

  Future<SentMediaBinding> capture({String mime = 'image/png'}) async {
    await observer.observe(request(), encryptFixture);
    final cipherHash = (await fingerprintMediaFile(cipher)).sha256Hex;
    return observer.bindSentRow(
      MediaAttachment(
        id: identity.attachmentId,
        messageId: identity.messageId,
        ownerLane: identity.owner,
        mime: mime,
        size: imageBytes.length,
        mediaType: MediaAttachment.mediaTypeFromMime(mime),
        localPath: processed.path,
        contentHash: cipherHash,
        downloadStatus: 'done',
        createdAt: '2026-10-22T12:00:00Z',
      ),
      identity,
    );
  }

  MediaAttachment receiverRow(SentMediaBinding sent) => MediaAttachment(
    id: identity.attachmentId,
    messageId: identity.messageId,
    ownerLane: identity.owner,
    mime: sent.mime,
    size: imageBytes.length,
    mediaType: MediaAttachment.mediaTypeFromMime(sent.mime),
    localPath: received.path,
    contentHash: sent.source.ciphertext.sha256Hex,
    downloadStatus: 'done',
    createdAt: '2026-10-22T12:00:00Z',
  );
  Future<MediaByteEquality> compare(
    SentMediaBinding sent, {
    MediaAttachment? row,
    Future<MediaAttachment?> Function()? load,
    Future<void> Function(MediaAttachment)? authority,
  }) => verifyReceivedMediaBytes(
    sent: sent,
    loadCurrentReceivedRow: load ?? () async => row ?? receiverRow(sent),
    assertCurrentReadAuthority: authority ?? (_) async {},
    resolveStoredPath: (p) async => p,
  );
  Matcher code(String value) =>
      isA<MediaOracleFailure>().having((error) => error.code, 'code', value);

  test(
    'real bridge adapter observes processed native encryption input, never the raw camera file',
    () async {
      final camera = File('${root.path}/raw-camera.png')
        ..writeAsBytesSync([
          ...imageBytes,
          ...utf8.encode('unstripped-camera-metadata'),
        ]);
      const channel = MethodChannel('com.mknoon/go_bridge');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var nativeCalls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        nativeCalls++;
        expect(call.method, 'blobEncrypt');
        final args = jsonDecode(call.arguments as String) as Map;
        expect(args['filePath'], processed.path);
        return encryptFixture();
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final bridge = MediaOracleGoBridgeClient(mediaInputObserver: observer);
      addTearDown(bridge.dispose);
      final response = await bridge.send(request());
      expect(jsonDecode(response)['ok'], isTrue);
      expect(nativeCalls, 1);
      expect(observer.captureCount, 1);
      expect(observer.failures, isEmpty);
      final sent = observer.bindSentRow(
        receiverRowForHash(
          (await fingerprintMediaFile(cipher)).sha256Hex,
          imageBytes.length,
          processed.path,
          identity,
        ),
        identity,
      );
      var authorityCalls = 0;
      final proof = await compare(
        sent,
        authority: (_) async => authorityCalls++,
      );
      expect(authorityCalls, 2);
      expect(proof.receiver.sha256Hex, sent.source.plaintext.sha256Hex);
      expect(
        (await fingerprintMediaFile(camera)).sha256Hex,
        isNot(sent.source.plaintext.sha256Hex),
      );
      expect(
        sent.source.ciphertext.sha256Hex,
        isNot(sent.source.plaintext.sha256Hex),
      );
      final serialized = jsonEncode(proof.toJson());
      for (final forbidden in [
        root.path,
        'fixture-only-key',
        'fixture-nonce',
        identity.messageId,
        identity.attachmentId,
      ]) {
        expect(serialized, isNot(contains(forbidden)));
      }
      expect(proof.toJson()['byte_gate'], 'PASS');
      expect(proof.toJson()['native_gate'], 'NOT_RUN');
    },
  );

  for (final corruption in ['last-byte', 'prefix-only', 'raw-camera']) {
    test(
      'full-byte comparison rejects $corruption receiver despite matching row metadata',
      () async {
        final sent = await capture();
        final bytes = imageBytes.toList();
        if (corruption == 'last-byte') bytes[bytes.length - 1] ^= 1;
        if (corruption == 'prefix-only') bytes.removeRange(16, bytes.length);
        if (corruption == 'raw-camera') {
          bytes.addAll(utf8.encode('camera-metadata'));
        }
        received.writeAsBytesSync(bytes);
        await expectLater(
          compare(sent),
          throwsA(code('RECEIVER_PLAINTEXT_MISMATCH')),
        );
      },
    );
  }
  for (final change in ['id', 'owner', 'cipher-hash', 'mime', 'pending']) {
    test(
      'current received $change cannot borrow another complete file proof',
      () async {
        final sent = await capture();
        var row = receiverRow(sent);
        switch (change) {
          case 'id':
            row = row.copyWith(id: 'wrong-item');
          case 'owner':
            row = row.copyWith(ownerLane: MediaOwnerLane.group);
          case 'cipher-hash':
            row = row.copyWith(contentHash: 'f' * 64);
          case 'mime':
            row = row.copyWith(mime: 'video/mp4');
          case 'pending':
            row = row.copyWith(downloadStatus: 'downloading');
        }
        await expectLater(
          compare(sent, row: row),
          throwsA(
            code(
              change == 'id' || change == 'owner'
                  ? 'RECEIVER_IDENTITY_MISMATCH'
                  : 'RECEIVER_NOT_CURRENT_COMPLETE_FILE',
            ),
          ),
        );
      },
    );
  }
  test(
    'deletion or read-authority loss while hashing cannot publish equality',
    () async {
      final sent = await capture();
      var reads = 0;
      await expectLater(
        compare(
          sent,
          load: () async => ++reads == 1 ? receiverRow(sent) : null,
        ),
        throwsA(code('RECEIVER_IDENTITY_MISMATCH')),
      );
      received.deleteSync();
      await expectLater(
        compare(
          sent,
          authority: (_) async {
            throw const MediaOracleFailure('READ_AUTHORITY_DENIED');
          },
        ),
        throwsA(code('READ_AUTHORITY_DENIED')),
        reason: 'authority is checked before even attempting missing-file I/O',
      );
    },
  );
  test(
    'input mutation is an oracle gap while native response remains untouched',
    () async {
      var calls = 0;
      final original = await encryptFixture();
      final response = await observer.observe(request(), () async {
        calls++;
        processed.writeAsBytesSync([...imageBytes, 9]);
        return original;
      });
      expect(response, original);
      expect(calls, 1);
      expect(observer.captureCount, 0);
      expect(observer.failures, ['ENCRYPTION_INPUT_CHANGED']);
    },
  );
  test(
    'sender receipt crosses app processes with pinned identity and no path/key payload',
    () async {
      final sent = await capture();
      final wire = Map<String, Object?>.from(
        jsonDecode(jsonEncode(sent.toSenderReceipt())) as Map,
      );
      final pin = sent.senderReceiptSha256;
      // A receiver has no sender observer or native-key object in its process.
      observer = MediaEncryptionInputObserver();
      final imported = SentMediaBinding.fromSenderReceipt(
        receipt: Map.fromEntries(wire.entries.toList().reversed),
        expectedReceiptSha256: pin,
        expectedIdentity: identity,
      );
      expect(observer.captureCount, 0);
      final equality = await compare(imported);
      expect(equality.toJson()['sender_receipt_sha256'], pin);
      expect(equality.receiver.sha256Hex, sent.source.plaintext.sha256Hex);
    },
  );
  test(
    'altered sender receipt cannot reuse its producer-pinned digest',
    () async {
      final sent = await capture();
      final wire = Map<String, Object?>.from(sent.toSenderReceipt())
        ..['mime'] = 'video/mp4';
      expect(
        () => SentMediaBinding.fromSenderReceipt(
          receipt: wire,
          expectedReceiptSha256: sent.senderReceiptSha256,
          expectedIdentity: identity,
        ),
        throwsA(code('SENDER_RECEIPT_NOT_PINNED')),
      );
    },
  );
  test(
    'a valid source receipt cannot be relabeled for another owner/parent/item',
    () async {
      final sent = await capture();
      expect(
        () => SentMediaBinding.fromSenderReceipt(
          receipt: sent.toSenderReceipt(),
          expectedReceiptSha256: sent.senderReceiptSha256,
          expectedIdentity: MediaWireIdentity(
            runId: identity.runId,
            owner: MediaOwnerLane.group,
            messageId: identity.messageId,
            attachmentId: identity.attachmentId,
          ),
        ),
        throwsA(code('SENDER_RECEIPT_NOT_PINNED')),
      );
    },
  );
  test(
    'an earlier run cannot lend a receipt even when fixture IDs and bytes repeat',
    () async {
      final sent = await capture();
      expect(
        () => SentMediaBinding.fromSenderReceipt(
          receipt: sent.toSenderReceipt(),
          expectedReceiptSha256: sent.senderReceiptSha256,
          expectedIdentity: MediaWireIdentity(
            runId: 'another-run',
            owner: identity.owner,
            messageId: identity.messageId,
            attachmentId: identity.attachmentId,
          ),
        ),
        throwsA(code('SENDER_RECEIPT_NOT_PINNED')),
      );
    },
  );
  test(
    'conflicting same-cipher capture is poisoned without changing native response',
    () async {
      final sent = await capture();
      final originalResponse = jsonEncode({
        'ok': true,
        'encryptedPath': cipher.path,
      });
      final changed = imageBytes.toList()..[20] ^= 1;
      processed.writeAsBytesSync(changed);
      expect(
        await observer.observe(request(), () async => originalResponse),
        originalResponse,
      );
      expect(observer.captureCount, 0);
      expect(observer.failures, ['CONFLICTING_CIPHERTEXT_CAPTURE']);
      expect(
        () => observer.bindSentRow(receiverRow(sent), identity),
        throwsA(code('ACTUAL_SENT_SOURCE_NOT_CAPTURED')),
      );
    },
  );
  test(
    'file resolver changes while row identity stays stable cannot publish stale equality',
    () async {
      final sent = await capture();
      var resolutions = 0;
      await expectLater(
        verifyReceivedMediaBytes(
          sent: sent,
          loadCurrentReceivedRow: () async => receiverRow(sent),
          assertCurrentReadAuthority: (_) async {},
          resolveStoredPath: (p) async => ++resolutions == 1 ? p : '$p.moved',
        ),
        throwsA(code('RECEIVER_PATH_CHANGED')),
      );
    },
  );
  test(
    'image-shaped observation cannot stand in for the selected video',
    () async {
      final equality = await compare(await capture(mime: 'video/mp4'));
      expect(
        () => validateNativeMediaObservation(
          equality,
          NativeMediaOpenObservation(
            kind: NativeMediaOpenKind.decodedImage,
            identitySha256: identity.digest,
            plaintextSha256: equality.receiver.sha256Hex,
            nativeBackend: 'fixture-wrong-kind',
            proofArtifact: processed,
            width: 64,
            height: 32,
          ),
        ),
        throwsA(code('NATIVE_KIND_DOES_NOT_MATCH_MEDIA')),
      );
    },
  );

  test(
    'native failure, non-encrypt command and exceptions remain transparent once',
    () async {
      const failed = '{"ok":false,"errorCode":"fixture-failure"}';
      expect(await observer.observe(request(), () async => failed), failed);
      expect(
        await observer.observe('{"cmd":"fixture:ping"}', () async => failed),
        failed,
      );
      final error = StateError('fixture-only');
      await expectLater(
        observer.observe(request(), () async => throw error),
        throwsA(same(error)),
      );
      expect(observer.captureCount, 0);
    },
  );
  test(
    'host equality cannot invoke or stamp a native-open PASS',
    () async {
      final equality = await compare(await capture());
      var invoked = false;
      await expectLater(
        verifyNativeMediaOpen(
          equality: equality,
          observerCase: 'must-not-run-on-host',
          assertCurrentOpenAuthority: () async {},
          assertNativeOpen: (_) async {
            invoked = true;
            throw StateError('not a native probe');
          },
        ),
        throwsA(code('NATIVE_TARGET_REQUIRED')),
      );
      expect(invoked, isFalse);
    },
    skip: Platform.isAndroid || Platform.isIOS
        ? 'host-only guard assertion'
        : false,
  );
  for (final kind in [
    NativeMediaOpenKind.renderedVideo,
    NativeMediaOpenKind.playedAudio,
    NativeMediaOpenKind.renderedPdf,
  ]) {
    test(
      '$kind metadata-only observation cannot substitute for native playback/page',
      () async {
        final mime = kind == NativeMediaOpenKind.renderedPdf
            ? 'application/pdf'
            : kind == NativeMediaOpenKind.playedAudio
            ? 'audio/mp4'
            : 'video/mp4';
        final equality = await compare(await capture(mime: mime));
        final observation = NativeMediaOpenObservation(
          kind: kind,
          identitySha256: identity.digest,
          plaintextSha256: equality.receiver.sha256Hex,
          nativeBackend: 'fixture-metadata-only',
          proofArtifact: processed,
          width: 64,
          height: 32,
          durationMs: 1000,
          startPositionMs: 0,
          endPositionMs: 0,
        );
        expect(
          () => validateNativeMediaObservation(equality, observation),
          throwsA(
            code(
              kind == NativeMediaOpenKind.renderedPdf
                  ? 'NATIVE_PDF_PAGE_NOT_RENDERED'
                  : 'NATIVE_PLAYBACK_DID_NOT_ADVANCE',
            ),
          ),
        );
      },
    );
  }
}

MediaAttachment receiverRowForHash(
  String cipherHash,
  int size,
  String path,
  MediaWireIdentity identity,
) => MediaAttachment(
  id: identity.attachmentId,
  messageId: identity.messageId,
  ownerLane: identity.owner,
  mime: 'image/png',
  size: size,
  mediaType: 'image',
  localPath: path,
  contentHash: cipherHash,
  downloadStatus: 'done',
  createdAt: '2026-10-22T12:00:00Z',
);
