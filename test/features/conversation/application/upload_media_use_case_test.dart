import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';

/// Fake bridge that responds to media:upload commands.
class _FakeBridge implements Bridge {
  Map<String, dynamic> uploadResponse = {'ok': true};
  Map<String, dynamic>? keygenResponse;
  Map<String, dynamic>? encryptResponse;
  Object? mediaUploadError;
  Map<String, dynamic>? lastRequest;
  final List<Map<String, dynamic>> requests = [];
  final List<String> commandLog = [];
  final List<String> generatedKeys = [];
  final Map<String, String> uploadedContentHashes = {};
  int sendCallCount = 0;

  @override
  Future<String> send(String message) async {
    sendCallCount++;
    lastRequest = jsonDecode(message) as Map<String, dynamic>;
    requests.add(lastRequest!);
    final cmd = lastRequest!['cmd'] as String?;
    if (cmd != null) commandLog.add(cmd);
    if (cmd == 'blob:keygen') {
      if (keygenResponse != null) {
        return jsonEncode(keygenResponse);
      }
      final key = 'group-test-key-${generatedKeys.length + 1}';
      generatedKeys.add(key);
      return jsonEncode({'ok': true, 'keyBase64': key});
    }
    if (cmd == 'blob:encrypt' && encryptResponse != null) {
      return jsonEncode(encryptResponse);
    }
    if (cmd == 'blob:encrypt') {
      final payload = lastRequest!['payload'] as Map<String, dynamic>;
      final sourcePath = payload['filePath'] as String;
      final keyBase64 = payload['keyBase64'] as String;
      final encryptedPath = '$sourcePath.${generatedKeys.length}.enc';
      final sourceBytes = await File(sourcePath).readAsBytes();
      await File(encryptedPath).writeAsBytes([
        ...'cipher:$keyBase64:'.codeUnits,
        ...sourceBytes.reversed,
      ]);
      return jsonEncode({
        'ok': true,
        'encryptedPath': encryptedPath,
        'nonce': 'nonce-${generatedKeys.length}',
      });
    }
    if (cmd == 'media:upload') {
      final error = mediaUploadError;
      if (error != null) {
        throw error;
      }
      final payload = lastRequest!['payload'] as Map<String, dynamic>;
      final filePath = payload['filePath'] as String?;
      if (filePath != null && File(filePath).existsSync()) {
        uploadedContentHashes[filePath] =
            await GroupMediaIntegrityPolicy.computeFileSha256Hex(filePath);
      }
    }
    return jsonEncode(uploadResponse);
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}
  @override
  bool get isInitialized => true;
  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
  onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

Future<MediaAttachment?> _legacyUploadMedia({
  required Bridge bridge,
  required String localFilePath,
  required String mime,
  required String recipientPeerId,
  MediaFileManager? mediaFileManager,
  int? width,
  int? height,
  int? durationMs,
  List<double>? waveform,
  List<String>? allowedPeers,
  String? blobId,
  bool deleteSourceWhenDone = false,
  EncryptedMediaArtifact? preparedArtifact,
  int? groupMediaPerAttachmentLimitBytes,
  Duration? transferStallTimeout,
  Duration? transferMaxTimeout,
}) async => (await uploadMedia(
  bridge: bridge,
  localFilePath: localFilePath,
  mime: mime,
  recipientPeerId: recipientPeerId,
  mediaFileManager: mediaFileManager,
  width: width,
  height: height,
  durationMs: durationMs,
  waveform: waveform,
  allowedPeers: allowedPeers,
  blobId: blobId,
  deleteSourceWhenDone: deleteSourceWhenDone,
  preparedArtifact: preparedArtifact,
  groupMediaPerAttachmentLimitBytes: groupMediaPerAttachmentLimitBytes,
  transferStallTimeout: transferStallTimeout,
  transferMaxTimeout: transferMaxTimeout,
)).attachmentOrNull;

Future<void> _waitForCapturedFlowEvent(
  List<Map<String, dynamic>> events,
  String eventName,
) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (events.any((event) => event['event'] == eventName)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  late _FakeBridge bridge;
  late Directory tempDir;
  late File tempFile;
  late File gifFile;

  setUp(() async {
    debugGroupMediaUploadPostCommitProbeDelays = const [];
    bridge = _FakeBridge();
    tempDir = await Directory.systemTemp.createTemp('upload_test_');
    tempFile = File('${tempDir.path}/test_image.jpg');
    await tempFile.writeAsBytes(List.filled(1024, 0xFF)); // 1KB dummy file
    gifFile = File('${tempDir.path}/test_animation.gif');
    await gifFile.writeAsBytes(List.filled(512, 0x47));
  });

  tearDown(() async {
    debugGroupMediaUploadPostCommitProbeDelays = const [
      Duration(milliseconds: 250),
      Duration(seconds: 1),
    ];
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('UploadMedia failure contract', () {
    test('classifies every transport error family without relay state', () {
      final cases =
          <({String code, String message, UploadMediaDisposition disposition})>[
            (
              code: 'MEDIA_ERROR',
              message: 'relay unreachable while dialing peer',
              disposition: UploadMediaDisposition.connectivityRetryable,
            ),
            (
              code: 'MEDIA_ERROR',
              message: 'failed to open stream for media protocol',
              disposition: UploadMediaDisposition.connectivityRetryable,
            ),
            (
              code: 'MEDIA_ERROR',
              message: 'size 42 exceeds max 20',
              disposition: UploadMediaDisposition.terminal,
            ),
            (
              code: 'MEDIA_ERROR',
              message: 'open file: permission denied',
              disposition: UploadMediaDisposition.terminal,
            ),
            (
              code: 'MEDIA_ERROR',
              message: 'unrecognized native media failure',
              disposition: UploadMediaDisposition.boundedRetryable,
            ),
            (
              code: 'NOT_INITIALIZED',
              message: '',
              disposition: UploadMediaDisposition.connectivityRetryable,
            ),
            (
              code: 'NULL_RESPONSE',
              message: '',
              disposition: UploadMediaDisposition.connectivityRetryable,
            ),
            (
              code: 'INVALID_INPUT',
              message: '',
              disposition: UploadMediaDisposition.terminal,
            ),
            (
              code: 'UNKNOWN_COMMAND',
              message: '',
              disposition: UploadMediaDisposition.terminal,
            ),
            (
              code: 'MISSING_PLUGIN',
              message: '',
              disposition: UploadMediaDisposition.terminal,
            ),
            (
              code: 'MALFORMED_RESPONSE',
              message: '',
              disposition: UploadMediaDisposition.terminal,
            ),
            (
              code: 'PLATFORM_ERROR',
              message: '',
              disposition: UploadMediaDisposition.boundedRetryable,
            ),
            (
              code: 'INTERNAL_ERROR',
              message: '',
              disposition: UploadMediaDisposition.boundedRetryable,
            ),
            (
              code: 'FUTURE_NATIVE_CODE',
              message: '',
              disposition: UploadMediaDisposition.boundedRetryable,
            ),
          ];

      for (final testCase in cases) {
        final failure = classifyUploadMediaTransportFailure(
          errorCode: testCase.code,
          errorMessage: testCase.message,
        );
        expect(failure.stage, UploadMediaStage.transport);
        expect(
          failure.disposition,
          testCase.disposition,
          reason: '${testCase.code}: ${testCase.message}',
        );
        expect(failure.errorCode, testCase.code);
      }
    });

    test(
      'normalizes an injected throw at the shared consumer boundary',
      () async {
        final outcome = await runUploadMedia(
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                blobId,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async => throw StateError('injected seam failure'),
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'recipient',
        );

        expect(
          outcome,
          isA<UploadMediaFailed>()
              .having(
                (failure) => failure.stage,
                'stage',
                UploadMediaStage.consumerBoundary,
              )
              .having(
                (failure) => failure.disposition,
                'disposition',
                UploadMediaDisposition.terminal,
              )
              .having(
                (failure) => failure.errorCode,
                'errorCode',
                'UNEXPECTED_CONSUMER_THROW',
              ),
        );
      },
    );

    test(
      'classifies local, encryption, and transport throws by stage',
      () async {
        final invalidMime = await uploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'not-a-mime',
          recipientPeerId: 'recipient',
        );
        expect(
          invalidMime,
          isA<UploadMediaFailed>()
              .having(
                (failure) => failure.stage,
                'stage',
                UploadMediaStage.validation,
              )
              .having(
                (failure) => failure.disposition,
                'disposition',
                UploadMediaDisposition.terminal,
              ),
        );

        final missingSource = await uploadMedia(
          bridge: bridge,
          localFilePath: '${tempDir.path}/missing.jpg',
          mime: 'image/jpeg',
          recipientPeerId: 'recipient',
        );
        expect(
          missingSource,
          isA<UploadMediaFailed>()
              .having(
                (failure) => failure.stage,
                'stage',
                UploadMediaStage.localSource,
              )
              .having(
                (failure) => failure.disposition,
                'disposition',
                UploadMediaDisposition.terminal,
              ),
        );

        final missingGroupSource = await uploadMedia(
          bridge: bridge,
          localFilePath: '${tempDir.path}/missing-group.jpg',
          mime: 'image/jpeg',
          recipientPeerId: 'group-1',
          allowedPeers: const ['peer-2'],
        );
        expect(
          missingGroupSource,
          isA<UploadMediaFailed>().having(
            (failure) => failure.stage,
            'stage',
            UploadMediaStage.localSource,
          ),
        );

        bridge.keygenResponse = {
          'ok': false,
          'errorCode': 'INTERNAL_ERROR',
          'errorMessage': 'key generation failed',
        };
        final encryptionFailure = await uploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'recipient',
        );
        expect(
          encryptionFailure,
          isA<UploadMediaFailed>()
              .having(
                (failure) => failure.stage,
                'stage',
                UploadMediaStage.encryption,
              )
              .having(
                (failure) => failure.disposition,
                'disposition',
                UploadMediaDisposition.boundedRetryable,
              ),
        );

        bridge.keygenResponse = null;
        bridge.mediaUploadError = TimeoutException('issued request timed out');
        final transportTimeout = await uploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'recipient',
        );
        expect(
          transportTimeout,
          isA<UploadMediaFailed>()
              .having(
                (failure) => failure.stage,
                'stage',
                UploadMediaStage.transport,
              )
              .having(
                (failure) => failure.disposition,
                'disposition',
                UploadMediaDisposition.connectivityRetryable,
              )
              .having(
                (failure) => failure.errorCode,
                'errorCode',
                'TIMEOUT_EXCEPTION',
              ),
        );
      },
    );

    test(
      'MEDIA_ENCRYPTION_PREPARED exposes only safe attachment correlation',
      () async {
        final events = await captureFlowEvents(() async {
          await uploadMedia(
            bridge: bridge,
            localFilePath: tempFile.path,
            mime: 'image/jpeg',
            recipientPeerId: 'recipient-secret',
            blobId: 'blob-secret',
          );
        });

        final prepared = events.singleWhere(
          (event) => event['event'] == 'MEDIA_ENCRYPTION_PREPARED',
        );
        final details = prepared['details'] as Map<String, dynamic>;
        final expectedHash = sha256
            .convert(utf8.encode('blob-secret'))
            .toString();
        expect(details, {
          'recipientClass': 'direct',
          'mime': 'image/jpeg',
          'attachmentSha256': expectedHash,
        });
        expect(details.keys, isNot(contains('blobId')));
        expect(details.keys, isNot(contains('path')));
        expect(details.keys, isNot(contains('contentHash')));
        expect(details.keys, isNot(contains('key')));
        expect(details.keys, isNot(contains('nonce')));
      },
    );

    test('issued upload start follows encryption preparation', () async {
      final events = await captureFlowEvents(() async {
        await uploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'recipient-secret',
          blobId: 'blob-secret',
        );
      });

      final names = events.map((event) => event['event']).toList();
      final preparedIndex = names.indexOf('MEDIA_ENCRYPTION_PREPARED');
      final issuedIndex = names.indexOf('MEDIA_UPLOAD_START');
      expect(preparedIndex, greaterThanOrEqualTo(0));
      expect(issuedIndex, greaterThan(preparedIndex));
      final issued = events[issuedIndex]['details'] as Map<String, dynamic>;
      expect(issued, {
        'recipientClass': 'direct',
        'mime': 'image/jpeg',
        'attachmentSha256': sha256
            .convert(utf8.encode('blob-secret'))
            .toString(),
      });
      expect(names.where((name) => name == 'MEDIA_UPLOAD_START'), hasLength(1));
    });
  });

  group('uploadMedia', () {
    test('returns MediaAttachment on success', () async {
      final result = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'image/jpeg',
        recipientPeerId: '12D3KooWRecipient123',
        width: 1920,
        height: 1080,
      );

      expect(result, isNotNull);
      expect(result!.mime, 'image/jpeg');
      expect(result.size, 1024); // plaintext size on wire/DB (group convention)
      expect(result.mediaType, 'image');
      expect(result.width, 1920);
      expect(result.height, 1080);
      expect(result.localPath, tempFile.path);
      expect(result.downloadStatus, 'done');
      expect(result.messageId, ''); // set by caller
      expect(result.id, isNotEmpty);
      expect(result.createdAt, isNotEmpty);
      // 112: every 1:1 attachment carries the full blob-encryption
      // metadata; contentHash is the hash of the ENCRYPTED artifact.
      expect(result.encryptionKeyBase64, isNotNull);
      expect(result.encryptionNonce, isNotNull);
      expect(
        result.encryptionScheme,
        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
      final uploadRequest = bridge.requests.lastWhere(
        (request) => request['cmd'] == 'media:upload',
      );
      final uploadPayload = uploadRequest['payload'] as Map<String, dynamic>;
      expect(
        result.contentHash,
        bridge.uploadedContentHashes[uploadPayload['filePath'] as String],
      );
      expect(
        result.contentHash,
        isNot(
          await GroupMediaIntegrityPolicy.computeFileSha256Hex(tempFile.path),
        ),
      );
    });

    test('sends correct command to bridge', () async {
      await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'image/jpeg',
        recipientPeerId: '12D3KooWRecipient123',
      );

      // 112: 1:1 uploads are encrypted before the relay ever sees bytes.
      expect(
        bridge.commandLog,
        containsAllInOrder(['blob:keygen', 'blob:encrypt', 'media:upload']),
      );
      expect(bridge.lastRequest, isNotNull);
      expect(bridge.lastRequest!['cmd'], 'media:upload');
      final payload = bridge.lastRequest!['payload'] as Map<String, dynamic>;
      expect(payload['to'], '12D3KooWRecipient123');
      expect(payload['filePath'], endsWith('.enc'));
      expect(payload['filePath'], isNot(tempFile.path));
      expect(payload['id'], isNotEmpty);
    });

    test('distinct key, nonce, and contentHash per 1:1 object', () async {
      final first = File('${tempDir.path}/direct_first.jpg');
      final second = File('${tempDir.path}/direct_second.jpg');
      await first.writeAsBytes(List<int>.filled(64, 0x11));
      await second.writeAsBytes(List<int>.filled(64, 0x22));

      final firstResult = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: first.path,
        mime: 'image/jpeg',
        recipientPeerId: 'contact-A',
      );
      final secondResult = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: second.path,
        mime: 'image/jpeg',
        recipientPeerId: 'contact-A',
      );

      expect(firstResult, isNotNull);
      expect(secondResult, isNotNull);
      expect(
        firstResult!.encryptionKeyBase64,
        isNot(secondResult!.encryptionKeyBase64),
      );
      expect(firstResult.encryptionNonce, isNot(secondResult.encryptionNonce));
      expect(firstResult.contentHash, isNot(secondResult.contentHash));
    });

    test(
      '1:1 encrypted upload advertises opaque mime to the transport',
      () async {
        // G7a: the relay's plaintext metadata sidecar must not learn the
        // real content type; it travels only inside the ML-KEM envelope.
        final result = await _legacyUploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'contact-A',
        );

        expect(result, isNotNull);
        expect(result!.mime, 'image/jpeg');
        final payload = bridge.lastRequest!['payload'] as Map<String, dynamic>;
        expect(payload['mime'], kOpaqueMediaTransportMime);
      },
    );

    test('group upload still advertises the real mime to the relay', () async {
      // Green pin protecting the group relay_mime_mismatch cross-check
      // (Alternatives rejected #7): opaque mime is 1:1-ONLY.
      final validJpegFile = File('${tempDir.path}/group_real_mime.jpg');
      await validJpegFile.writeAsBytes([
        0xff,
        0xd8,
        0xff,
        ...List<int>.filled(32, 0xff),
      ]);

      final result = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: validJpegFile.path,
        mime: 'image/jpeg',
        recipientPeerId: 'group-1',
        allowedPeers: const ['peer-2'],
      );

      expect(result, isNotNull);
      final payload = bridge.lastRequest!['payload'] as Map<String, dynamic>;
      expect(payload['mime'], 'image/jpeg');
    });

    test('1:1 upload skips group mime/size policy', () async {
      // Green pin guarding the crypto-block hoist: encryption became
      // unconditional but GroupMediaMimePolicy/GroupMediaSizePolicy stay
      // group-gated (application/pdf is group-rejected, 1:1-allowed).
      final pdfFile = File('${tempDir.path}/doc.pdf');
      await pdfFile.writeAsBytes(List<int>.filled(2048, 0x25));

      final result = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: pdfFile.path,
        mime: 'application/pdf',
        recipientPeerId: 'contact-A',
        groupMediaPerAttachmentLimitBytes: 512,
      );

      expect(result, isNotNull);
      expect(result!.mediaType, 'file');
    });

    test(
      'encrypted temp deleted after successful 1:1 upload; plaintext durable '
      'copy retained',
      () async {
        final mediaFileManager = FakeMediaFileManager();
        const blobId = 'blob-enc-temp-cleanup';

        final result = await _legacyUploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'contact-A',
          mediaFileManager: mediaFileManager,
          blobId: blobId,
        );

        expect(result, isNotNull);
        final uploadRequest = bridge.requests.lastWhere(
          (request) => request['cmd'] == 'media:upload',
        );
        final uploadedPath =
            (uploadRequest['payload'] as Map<String, dynamic>)['filePath']
                as String;
        expect(File(uploadedPath).existsSync(), isFalse);
        // The durable copy is the PLAINTEXT render source for the sender.
        final resolvedPath = await mediaFileManager.resolveStoredPath(
          result!.localPath!,
        );
        expect(File(resolvedPath).existsSync(), isTrue);
        expect(File(resolvedPath).lengthSync(), tempFile.lengthSync());
      },
    );

    test('transient source file deleted after durable copy and successful '
        'upload when deleteSourceWhenDone', () async {
      final mediaFileManager = FakeMediaFileManager();
      final pickerTemp = File('${tempDir.path}/picker_temp.jpg');
      await pickerTemp.writeAsBytes(List<int>.filled(128, 0x33));

      final result = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: pickerTemp.path,
        mime: 'image/jpeg',
        recipientPeerId: 'contact-A',
        mediaFileManager: mediaFileManager,
        deleteSourceWhenDone: true,
      );

      expect(result, isNotNull);
      // Best-effort unlink only — secure-delete/overwrite is not
      // meaningfully achievable on flash/APFS.
      expect(pickerTemp.existsSync(), isFalse);
      final resolvedPath = await mediaFileManager.resolveStoredPath(
        result!.localPath!,
      );
      expect(File(resolvedPath).existsSync(), isTrue);
    });

    test(
      'deleteSourceWhenDone without durable copy keeps the source',
      () async {
        // Without a mediaFileManager the source IS the sender's only
        // render copy — it must never be deleted.
        final result = await _legacyUploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'contact-A',
          deleteSourceWhenDone: true,
        );

        expect(result, isNotNull);
        expect(tempFile.existsSync(), isTrue);
        expect(result!.localPath, tempFile.path);
      },
    );

    test('1:1 upload fails closed when blob keygen/encrypt fails', () async {
      bridge.keygenResponse = {'ok': false, 'errorMessage': 'keygen broken'};

      final result = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'image/jpeg',
        recipientPeerId: 'contact-A',
      );

      expect(result, isNull);
      // No plaintext fallback: media:upload must never be issued.
      expect(bridge.commandLog, isNot(contains('media:upload')));

      bridge.keygenResponse = null;
      bridge.encryptResponse = {'ok': false, 'errorMessage': 'encrypt broken'};

      final encryptFailResult = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'image/jpeg',
        recipientPeerId: 'contact-A',
      );

      expect(encryptFailResult, isNull);
      expect(bridge.commandLog, isNot(contains('media:upload')));
    });

    test('returns null when bridge returns error', () async {
      bridge.uploadResponse = {
        'ok': false,
        'errorCode': 'UPLOAD_FAILED',
        'errorMessage': 'Relay unavailable',
      };

      final result = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'image/jpeg',
        recipientPeerId: '12D3KooWRecipient123',
      );

      expect(result, isNull);
    });

    test('returns null when file does not exist', () async {
      final result = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: '/nonexistent/path/file.jpg',
        mime: 'image/jpeg',
        recipientPeerId: '12D3KooWRecipient123',
      );

      expect(result, isNull);
    });

    test('returns null when bridge throws exception', () async {
      final throwBridge = _ThrowingBridge();

      final result = await _legacyUploadMedia(
        bridge: throwBridge,
        localFilePath: tempFile.path,
        mime: 'image/jpeg',
        recipientPeerId: '12D3KooWRecipient123',
      );

      expect(result, isNull);
    });

    test(
      'emits MEDIA_UPLOAD_TIMING with blob, mime, and size metadata',
      () async {
        final events = await captureFlowEvents(() async {
          await _legacyUploadMedia(
            bridge: bridge,
            localFilePath: tempFile.path,
            mime: 'image/jpeg',
            recipientPeerId: '12D3KooWRecipient123',
          );
        });

        final timing = events.lastWhere(
          (event) => event['event'] == 'MEDIA_UPLOAD_TIMING',
        );
        expect(timing['details']['outcome'], 'success');
        expect(timing['details']['blobId'], isA<String>());
        expect(timing['details']['mime'], 'image/jpeg');
        expect(timing['details']['sizeBytes'], 1024);
        expect(timing['details']['elapsedMs'], isA<int>());
      },
    );

    test(
      'copies successful uploads into owned media storage with durability telemetry',
      () async {
        final mediaFileManager = FakeMediaFileManager();
        const blobId = 'blob-owned-copy-test';
        const recipientPeerId = 'peer-owned-copy-test';

        final events = await captureFlowEvents(() async {
          final result = await _legacyUploadMedia(
            bridge: bridge,
            localFilePath: tempFile.path,
            mime: 'image/jpeg',
            recipientPeerId: recipientPeerId,
            mediaFileManager: mediaFileManager,
            blobId: blobId,
          );

          expect(result, isNotNull);
          expect(result!.localPath, 'media/$recipientPeerId/$blobId.jpg');
          final resolvedPath = await mediaFileManager.resolveStoredPath(
            result.localPath!,
          );
          expect(File(resolvedPath).existsSync(), isTrue);
          expect(File(resolvedPath).lengthSync(), tempFile.lengthSync());
        });

        final durability = events.singleWhere(
          (event) => event['event'] == 'MEDIA_UPLOAD_DURABLE_COPY_COMMITTED',
        );
        expect(
          durability['details'],
          allOf(
            containsPair('blobId', 'blob-own'),
            containsPair('storedPath', 'media/$recipientPeerId/$blobId.jpg'),
            containsPair('fileExists', true),
            containsPair('fileBytes', tempFile.lengthSync()),
            containsPair('expectedBytes', tempFile.lengthSync()),
          ),
        );
      },
    );

    test(
      'group durable copy emits delayed post-commit existence probe',
      () async {
        debugGroupMediaUploadPostCommitProbeDelays = const [Duration.zero];
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final validJpegFile = File('${tempDir.path}/valid_group_probe.jpg');
        await validJpegFile.writeAsBytes([
          0xff,
          0xd8,
          0xff,
          ...List<int>.filled(32, 0xff),
        ]);
        final mediaFileManager = FakeMediaFileManager();
        const blobId = 'blob-group-probe';

        final result = await _legacyUploadMedia(
          bridge: bridge,
          localFilePath: validJpegFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'group-1',
          allowedPeers: const ['peer-2'],
          mediaFileManager: mediaFileManager,
          blobId: blobId,
        );

        expect(result, isNotNull);
        expect(result!.localPath, 'media/group-1/$blobId.jpg');
        await _waitForCapturedFlowEvent(
          events,
          'MEDIA_GROUP_UPLOAD_DURABLE_COPY_DELAYED_PROBE',
        );

        final probe = events.singleWhere(
          (event) =>
              event['event'] == 'MEDIA_GROUP_UPLOAD_DURABLE_COPY_DELAYED_PROBE',
        );
        expect(
          probe['details'],
          allOf(
            containsPair('blobId', 'blob-gro'),
            containsPair('recipientClass', 'group'),
            containsPair('storedPath', 'media/group-1/$blobId.jpg'),
            containsPair('fileExists', true),
            containsPair('fileBytes', validJpegFile.lengthSync()),
            containsPair('expectedBytes', validJpegFile.lengthSync()),
          ),
        );
        expect(
          events.map((event) => event['event']),
          isNot(
            contains('MEDIA_GROUP_UPLOAD_DURABLE_COPY_DELAYED_PROBE_MISSING'),
          ),
        );
      },
    );

    test('infers mediaType from mime', () async {
      final cases = {
        'video/mp4': 'video',
        'audio/mpeg': 'audio',
        'application/pdf': 'file',
        'image/png': 'image',
      };

      for (final entry in cases.entries) {
        final result = await _legacyUploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: entry.key,
          recipientPeerId: 'recipient',
        );
        expect(result, isNotNull, reason: 'Should succeed for ${entry.key}');
        expect(
          result!.mediaType,
          entry.value,
          reason: 'mediaType for ${entry.key}',
        );
      }
    });

    test('passes optional dimensions and duration', () async {
      final result = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'video/mp4',
        recipientPeerId: 'recipient',
        width: 1280,
        height: 720,
        durationMs: 30000,
      );

      expect(result, isNotNull);
      expect(result!.width, 1280);
      expect(result.height, 720);
      expect(result.durationMs, 30000);
    });

    test(
      'uploads GIF with mime image/gif and preserves animated metadata',
      () async {
        final result = await _legacyUploadMedia(
          bridge: bridge,
          localFilePath: gifFile.path,
          mime: 'image/gif',
          recipientPeerId: 'recipient',
        );

        expect(result, isNotNull);
        expect(result!.mime, 'image/gif');
        expect(result.mediaType, 'image');
        expect(result.isAnimated, isTrue);

        // 112: animated metadata survives on the attachment while the
        // transport sees only opaque ciphertext.
        final payload = bridge.lastRequest!['payload'] as Map<String, dynamic>;
        expect(payload['mime'], kOpaqueMediaTransportMime);
        expect(payload['filePath'], endsWith('.enc'));
      },
    );

    test('rejects dangerous group MIME before bridge upload', () async {
      final result = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'application/pdf',
        recipientPeerId: 'group-1',
        allowedPeers: const ['peer-2'],
      );

      expect(result, isNull);
      expect(bridge.sendCallCount, 0);
      expect(bridge.lastRequest, isNull);
    });

    test('group upload computes content hash for uploaded bytes', () async {
      final validJpegFile = File('${tempDir.path}/valid_image.jpg');
      await validJpegFile.writeAsBytes([
        0xff,
        0xd8,
        0xff,
        ...List<int>.filled(1021, 0xff),
      ]);

      final result = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: validJpegFile.path,
        mime: 'image/jpeg',
        recipientPeerId: 'group-1',
        allowedPeers: const ['peer-2'],
      );

      expect(result, isNotNull);
      expect(
        result!.contentHash,
        isNot(
          await GroupMediaIntegrityPolicy.computeFileSha256Hex(
            validJpegFile.path,
          ),
        ),
      );
      final uploadRequest = bridge.requests.lastWhere(
        (request) => request['cmd'] == 'media:upload',
      );
      final uploadPayload = uploadRequest['payload'] as Map<String, dynamic>;
      expect(
        result.contentHash,
        bridge.uploadedContentHashes[uploadPayload['filePath'] as String],
      );
    });

    test(
      'group uploads encrypt each media object with distinct object metadata',
      () async {
        final first = File('${tempDir.path}/first.jpg');
        final second = File('${tempDir.path}/second.jpg');
        await first.writeAsBytes([
          0xff,
          0xd8,
          0xff,
          ...List<int>.filled(32, 0x11),
        ]);
        await second.writeAsBytes([
          0xff,
          0xd8,
          0xff,
          ...List<int>.filled(32, 0x22),
        ]);

        final firstResult = await _legacyUploadMedia(
          bridge: bridge,
          localFilePath: first.path,
          mime: 'image/jpeg',
          recipientPeerId: 'group-1',
          allowedPeers: const ['peer-2'],
        );
        final secondResult = await _legacyUploadMedia(
          bridge: bridge,
          localFilePath: second.path,
          mime: 'image/jpeg',
          recipientPeerId: 'group-1',
          allowedPeers: const ['peer-2'],
        );

        expect(firstResult, isNotNull);
        expect(secondResult, isNotNull);
        expect(
          bridge.commandLog,
          containsAllInOrder([
            'blob:keygen',
            'blob:encrypt',
            'media:upload',
            'blob:keygen',
            'blob:encrypt',
            'media:upload',
          ]),
        );

        final uploadRequests = bridge.requests
            .where((request) => request['cmd'] == 'media:upload')
            .toList(growable: false);
        expect(uploadRequests, hasLength(2));
        final firstUpload =
            uploadRequests[0]['payload'] as Map<String, dynamic>;
        final secondUpload =
            uploadRequests[1]['payload'] as Map<String, dynamic>;
        expect(firstUpload['filePath'], isNot(first.path));
        expect(secondUpload['filePath'], isNot(second.path));
        expect(firstUpload['filePath'], endsWith('.enc'));
        expect(secondUpload['filePath'], endsWith('.enc'));
        expect(firstResult!.encryptionKeyBase64, isNotNull);
        expect(secondResult!.encryptionKeyBase64, isNotNull);
        expect(
          firstResult.encryptionKeyBase64,
          isNot(secondResult.encryptionKeyBase64),
        );
        expect(firstResult.encryptionNonce, isNotNull);
        expect(secondResult.encryptionNonce, isNotNull);
        expect(
          firstResult.encryptionNonce,
          isNot(secondResult.encryptionNonce),
        );
        expect(firstResult.contentHash, isNot(secondResult.contentHash));
      },
    );

    test('rejects spoofed group media bytes before bridge upload', () async {
      final spoofedFile = File('${tempDir.path}/spoofed.jpg')
        ..writeAsStringSync('<script>alert(1)</script>');

      final result = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: spoofedFile.path,
        mime: 'image/jpeg',
        recipientPeerId: 'group-1',
        allowedPeers: const ['peer-2'],
      );

      expect(result, isNull);
      expect(bridge.sendCallCount, 0);
      expect(bridge.lastRequest, isNull);
    });

    test('rejects oversized group upload before bridge upload', () async {
      final oversizedFile = File('${tempDir.path}/oversized.jpg')
        ..writeAsBytesSync(List.filled(1024, 0x01));

      final result = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: oversizedFile.path,
        mime: 'image/jpeg',
        recipientPeerId: 'group-1',
        allowedPeers: const ['peer-2'],
        groupMediaPerAttachmentLimitBytes: 512,
      );

      expect(result, isNull);
      expect(bridge.sendCallCount, 0);
      expect(bridge.lastRequest, isNull);

      final boundaryResult = await GroupMediaSizePolicy.validateLocalFile(
        path: oversizedFile.path,
        mime: 'image/jpeg',
        perMediaLimitBytes: 1024,
      );
      expect(boundaryResult.isValid, isTrue);
    });

    test('null dimensions when not provided', () async {
      final result = await _legacyUploadMedia(
        bridge: bridge,
        localFilePath: tempFile.path,
        mime: 'audio/mpeg',
        recipientPeerId: 'recipient',
      );

      expect(result, isNotNull);
      expect(result!.width, isNull);
      expect(result.height, isNull);
      expect(result.durationMs, isNull);
    });

    group('with mediaFileManager', () {
      late _FakeMediaFileManager fakeFileManager;

      setUp(() {
        fakeFileManager = _FakeMediaFileManager(tempDir.path);
      });

      test('returns relative path in localPath for DB storage', () async {
        final result = await _legacyUploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'contact-A',
          mediaFileManager: fakeFileManager,
        );

        expect(result, isNotNull);
        // localPath should be relative (for DB storage)
        expect(result!.localPath, startsWith('media/'));
        expect(result.localPath, contains('contact-A'));
        expect(result.localPath, endsWith('.jpg'));
        // Should NOT be an absolute path
        expect(result.localPath, isNot(startsWith('/')));
      });

      test('copies file to persistent absolute path', () async {
        final result = await _legacyUploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'contact-A',
          mediaFileManager: fakeFileManager,
        );

        expect(result, isNotNull);
        // The file should be copied to the absolute path
        final absolutePath = '${tempDir.path}/contact-A/${result!.id}.jpg';
        expect(await File(absolutePath).exists(), isTrue);
        expect(await File(absolutePath).length(), 1024);
      });

      test('without mediaFileManager returns original absolute path', () async {
        final result = await _legacyUploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'contact-A',
        );

        expect(result, isNotNull);
        // Without mediaFileManager, localPath is the original file path
        expect(result!.localPath, tempFile.path);
      });
    });
  });
}

/// Fake media file manager that uses a temp directory as base path.
class _FakeMediaFileManager extends MediaFileManager {
  final String basePath;

  _FakeMediaFileManager(this.basePath);

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final ext = _extFromMime(mime);
    final dir = Directory('$basePath/$contactPeerId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return '$basePath/$contactPeerId/$blobId$ext';
  }

  static String _extFromMime(String mime) {
    const m = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'video/mp4': '.mp4',
      'audio/mpeg': '.mp3',
    };
    return m[mime] ?? '';
  }
}

class _ThrowingBridge implements Bridge {
  @override
  Future<String> send(String message) async =>
      throw Exception('Bridge exploded');
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}
  @override
  bool get isInitialized => true;
  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
  onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}
