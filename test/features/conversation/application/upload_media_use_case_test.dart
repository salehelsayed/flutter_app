import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/group_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_media_blob_generation_result.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/prepared_group_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

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
  final List<List<int>> uploadedBodies = <List<int>>[];
  Map<String, dynamic> Function(Map<String, dynamic> payload)?
  mediaUploadResponseBuilder;
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
        uploadedBodies.add(await File(filePath).readAsBytes());
        uploadedContentHashes[filePath] =
            await GroupMediaIntegrityPolicy.computeFileSha256Hex(filePath);
      }
      final responseBuilder = mediaUploadResponseBuilder;
      if (responseBuilder != null) {
        return jsonEncode(responseBuilder(payload));
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

    test(
      'P269 explicit empty group ACL fails closed before encryption or bridge upload',
      () async {
        final validJpegFile = File('${tempDir.path}/p269_empty_acl.jpg');
        final sourceBytes = <int>[
          0xff,
          0xd8,
          0xff,
          ...List<int>.filled(32, 0x7a),
        ];
        await validJpegFile.writeAsBytes(sourceBytes);

        final invalidGroupAcls = <List<String>>[
          const <String>[],
          const <String>[' ', '\t', '\n'],
        ];
        for (var index = 0; index < invalidGroupAcls.length; index += 1) {
          bridge = _FakeBridge();
          final outcome = await uploadMedia(
            bridge: bridge,
            localFilePath: validJpegFile.path,
            mime: 'image/jpeg',
            recipientPeerId: 'group-1',
            allowedPeers: invalidGroupAcls[index],
            blobId: 'p269-empty-group-acl-$index',
          );

          expect(
            bridge.commandLog,
            isEmpty,
            reason: 'empty group ACL must stop before blob:keygen',
          );
          expect(bridge.generatedKeys, isEmpty);
          expect(bridge.requests, isEmpty);
          expect(bridge.sendCallCount, 0);
          expect(
            outcome,
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
                )
                .having(
                  (failure) => failure.errorCode,
                  'errorCode',
                  'EMPTY_GROUP_MEDIA_ACL',
                ),
          );
          expect(await validJpegFile.readAsBytes(), sourceBytes);
        }

        // Null remains the explicit direct-mode discriminator and must retain
        // its existing encrypted upload behavior.
        bridge = _FakeBridge();
        final directOutcome = await uploadMedia(
          bridge: bridge,
          localFilePath: validJpegFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'direct-transport-peer',
          allowedPeers: null,
          blobId: 'p269-null-direct-acl',
        );
        expect(directOutcome, isA<UploadMediaSucceeded>());
        expect(bridge.commandLog, [
          'blob:keygen',
          'blob:encrypt',
          'media:upload',
        ]);
        final directPayload =
            bridge.lastRequest!['payload'] as Map<String, dynamic>;
        expect(directPayload, isNot(contains('allowedPeers')));
        expect(directPayload['mime'], kOpaqueMediaTransportMime);
      },
    );

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

    test(
      'TC-347-02b prepared LAN and strict relay bytes are identical',
      () async {
        final repository = _StrictBlobRepository();
        final store = DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => tempDir,
        );
        final parent = _strictParent('lan-relay');
        final attachment = _strictPendingAttachment('lan-relay');
        final networkOrder = <String>[];
        List<int>? lanBytes;
        bridge.mediaUploadResponseBuilder = (payload) {
          networkOrder.add('relay');
          return _exactStrictReceipt(payload);
        };

        final result =
            await PreparedDirectMediaBlobCustodyCoordinator(
              repository: repository,
              artifactStore: store,
            ).prepareAndUploadFresh(
              bridge: bridge,
              identityPeerId: parent.senderPeerId,
              recipientPeerId: parent.contactPeerId,
              expectedParent: parent,
              sources: <PreparedDirectMediaBlobSource>[
                PreparedDirectMediaBlobSource(
                  attachment: attachment,
                  plaintextPath: tempFile.path,
                ),
              ],
              onGenerationReady: (artifacts) async {
                networkOrder.add('lan');
                expect(repository.rows, hasLength(1));
                lanBytes = await File(
                  artifacts.single.absoluteCiphertextPath,
                ).readAsBytes();
              },
            );

        expect(result.isComplete, isTrue);
        expect(networkOrder, <String>['lan', 'relay']);
        expect(bridge.uploadedBodies, hasLength(1));
        expect(lanBytes, bridge.uploadedBodies.single);
        expect(
          sha256.convert(lanBytes!).toString(),
          result.attachments.single.blobCustody!.contentHash,
        );
      },
    );

    test(
      'TC-347-03 strict prepared direct upload accepts exact relay proof',
      () async {
        Future<PreparedDirectMediaBlobUploadResult> runCase(
          String suffix,
          Map<String, dynamic> Function(Map<String, dynamic>) response,
        ) async {
          final source = File('${tempDir.path}/strict-$suffix.jpg');
          await source.writeAsBytes(<int>[1, 3, 4, 7, 11, suffix.length]);
          final caseBridge = _FakeBridge()
            ..mediaUploadResponseBuilder = response;
          return PreparedDirectMediaBlobCustodyCoordinator(
            repository: _StrictBlobRepository(),
            artifactStore: DirectMediaBlobArtifactStore(
              documentsDirectoryProvider: () async => tempDir,
            ),
          ).prepareAndUploadFresh(
            bridge: caseBridge,
            identityPeerId: 'sender-347',
            recipientPeerId: 'recipient-347',
            expectedParent: _strictParent(suffix),
            sources: <PreparedDirectMediaBlobSource>[
              PreparedDirectMediaBlobSource(
                attachment: _strictPendingAttachment(suffix),
                plaintextPath: source.path,
              ),
            ],
          );
        }

        Map<String, dynamic> exact(Map<String, dynamic> payload) {
          expect(payload.keys.toSet(), <String>{
            'id',
            'to',
            'mime',
            'filePath',
            'custodyContract',
            'custodyKind',
            'contentHash',
          });
          expect(payload['mime'], 'application/octet-stream');
          expect(payload['custodyKind'], 'direct_media_blob_v1');
          expect(payload['custodyContract'], 'ack_or_expiry_v1');
          expect(
            payload['contentHash'],
            sha256
                .convert(File(payload['filePath'] as String).readAsBytesSync())
                .toString(),
          );
          return _exactStrictReceipt(payload);
        }

        final accepted = await runCase('exact', exact);
        expect(accepted.isComplete, isTrue);
        expect(accepted.attachments.single.downloadStatus, 'done');
        expect(accepted.attachments.single.blobCustody!.isValid, isTrue);

        final invalidMutations = <String, void Function(Map<String, dynamic>)>{
          'broad-ok': (receipt) => receipt.remove('storeStatus'),
          'wrong-id': (receipt) => receipt['id'] = 'crossed',
          'wrong-kind': (receipt) => receipt['custodyKind'] = 'other',
          'wrong-contract': (receipt) => receipt['custodyContract'] = 'other',
          'wrong-hash': (receipt) => receipt['contentHash'] = '0' * 64,
          'plaintext-size': (receipt) => receipt['size'] = 6,
          'real-mime': (receipt) => receipt['mime'] = 'image/jpeg',
          'missing-expiry': (receipt) => receipt.remove('expiresAtMs'),
          'missing-relay': (receipt) => receipt.remove('custodyRelayPeerId'),
        };
        for (final entry in invalidMutations.entries) {
          final retained = await runCase(entry.key, (payload) {
            final receipt = _exactStrictReceipt(payload);
            entry.value(receipt);
            return receipt;
          });
          expect(
            retained.state,
            PreparedDirectMediaBlobUploadState.retained,
            reason: entry.key,
          );
        }
      },
    );

    test(
      'TC-347-08e disabled and excluded callers preserve legacy bytes',
      () async {
        final direct = await _legacyUploadMedia(
          bridge: bridge,
          localFilePath: tempFile.path,
          mime: 'image/jpeg',
          recipientPeerId: 'direct-peer',
          blobId: 'legacy-direct-347',
        );
        final directUpload = bridge.requests.singleWhere(
          (request) => request['cmd'] == 'media:upload',
        );
        final directPayload = directUpload['payload'] as Map<String, dynamic>;
        expect(direct, isNotNull);
        expect(directPayload['mime'], 'application/octet-stream');
        expect(directPayload, isNot(contains('custodyKind')));
        expect(directPayload, isNot(contains('custodyContract')));
        expect(directPayload, isNot(contains('contentHash')));

        final excludedBridge = _FakeBridge();
        final excludedSource = File('${tempDir.path}/excluded-group.jpg');
        await excludedSource.writeAsBytes(<int>[
          0xff,
          0xd8,
          0xff,
          ...List<int>.filled(32, 0x7a),
        ]);
        final group = await _legacyUploadMedia(
          bridge: excludedBridge,
          localFilePath: excludedSource.path,
          mime: 'image/jpeg',
          recipientPeerId: 'group-347',
          allowedPeers: const <String>['peer-a', 'peer-b'],
          blobId: 'legacy-group-347',
        );
        final groupUpload = excludedBridge.requests.singleWhere(
          (request) => request['cmd'] == 'media:upload',
        );
        final groupPayload = groupUpload['payload'] as Map<String, dynamic>;
        expect(group, isNotNull);
        expect(groupPayload['mime'], 'image/jpeg');
        expect(groupPayload['allowedPeers'], <String>['peer-a', 'peer-b']);
        expect(groupPayload, isNot(contains('custodyKind')));
        expect(groupPayload, isNot(contains('custodyContract')));
      },
    );

    test(
      'TC-366-00a Dart group manifest scheme matches the relay validator',
      () {
        final manifest = ProtectedGroupMediaManifest(
          groupId: 'group-366-parity',
          messageId: 'message-366-parity',
          attachments: <ProtectedGroupMediaAttachmentCommitment>[
            ProtectedGroupMediaAttachmentCommitment(
              attachmentId: 'attachment-366-parity',
              custodyBlobId: 'group-blob-366-parity',
              ciphertextSha256: 'a' * 64,
              ciphertextSize: 64,
              mime: 'image/jpeg',
              mediaType: 'image',
              encryptionKeyBase64: 'a2V5LTM2Ng==',
              encryptionNonce: 'bm9uY2UtMzY2',
              targets: <GroupMediaBlobTargetCommitment>[
                GroupMediaBlobTargetCommitment(
                  recipientPeerId: 'transport-366',
                  expiresAtMs: 2_000_000_000_000,
                ),
              ],
            ),
          ],
        );
        final wire = jsonDecode(manifest.encode()) as Map<String, dynamic>;
        final attachment =
            (wire['attachments'] as List<dynamic>).single
                as Map<String, dynamic>;

        expect(groupMediaBlobEncryptionScheme, 'blob_aes_256_gcm_v1');
        expect(attachment['encryptionScheme'], 'blob_aes_256_gcm_v1');
        expect(
          () => ProtectedGroupMediaAttachmentCommitment(
            attachmentId: 'attachment-obsolete',
            custodyBlobId: 'group-blob-obsolete',
            ciphertextSha256: 'b' * 64,
            ciphertextSize: 64,
            mime: 'image/jpeg',
            mediaType: 'image',
            encryptionScheme: 'blob_aes_gcm_v1',
            encryptionKeyBase64: 'a2V5LW9ic29sZXRl',
            encryptionNonce: 'bm9uY2Utb2Jzb2xldGU=',
            targets: <GroupMediaBlobTargetCommitment>[
              GroupMediaBlobTargetCommitment(
                recipientPeerId: 'transport-366',
                expiresAtMs: 2_000_000_000_000,
              ),
            ],
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'TC-365-02a strict group upload stores exact recipient custody without allowedPeers',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'tc365-group-upload-',
        );
        addTearDown(() => root.delete(recursive: true));
        final plaintext = File('${root.path}/source.jpg');
        await plaintext.writeAsBytes(<int>[
          0xff,
          0xd8,
          0xff,
          ...List<int>.generate(61, (index) => index),
        ]);
        final ciphertextBytes = <int>[
          ...List<int>.filled(16, 0xa5),
          ...await plaintext.readAsBytes(),
        ];
        final ciphertext = File('${root.path}/ciphertext.bin');
        await ciphertext.writeAsBytes(ciphertextBytes);
        final ciphertextHash = sha256.convert(ciphertextBytes).toString();

        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(
          GroupModel(
            id: 'group-365',
            name: 'Plan 365',
            type: GroupType.chat,
            topicName: 'group-365-topic',
            createdAt: DateTime.utc(2026, 8, 14, 9),
            createdBy: 'account-local',
            myRole: GroupRole.member,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-365',
            keyGeneration: 7,
            encryptedKey: 'group-key-365',
            createdAt: DateTime.utc(2026, 8, 14, 9),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-365',
            peerId: 'account-local',
            role: MemberRole.writer,
            publicKey: 'account-public-key',
            devices: const <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'device-current',
                transportPeerId: 'transport-current',
                deviceSigningPublicKey: 'device-current-key',
              ),
              GroupMemberDeviceIdentity(
                deviceId: 'device-sibling',
                transportPeerId: 'transport-sibling',
                deviceSigningPublicKey: 'device-sibling-key',
              ),
            ],
            joinedAt: DateTime.utc(2026, 8, 14, 9),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-365',
            peerId: 'account-remote',
            role: MemberRole.writer,
            publicKey: 'remote-account-key',
            devices: const <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'device-remote',
                transportPeerId: 'transport-remote',
                deviceSigningPublicKey: 'device-remote-key',
              ),
            ],
            joinedAt: DateTime.utc(2026, 8, 14, 9),
          ),
        );

        final repository = _StrictGroupBlobRepository();
        final uploadedBodies = <List<int>>[];
        final uploadedRecipients = <String>[];
        final artifactStore = GroupMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => root,
        );
        final coordinator = PreparedGroupMediaBlobCustodyCoordinator(
          artifactStore: artifactStore,
          clock: () => DateTime.utc(2026, 8, 14, 10),
          strictUpload:
              ({
                required bridge,
                required custodyBlobId,
                required recipientPeerId,
                required ciphertextPath,
                required contentHash,
                required ciphertextSize,
              }) async {
                expect(
                  repository.stageCompleted,
                  isTrue,
                  reason: 'every target row must exist before network',
                );
                final bytes = await File(ciphertextPath).readAsBytes();
                uploadedBodies.add(bytes);
                uploadedRecipients.add(recipientPeerId);
                final expiresAtMs = recipientPeerId == 'transport-remote'
                    ? DateTime.utc(2026, 8, 20).millisecondsSinceEpoch
                    : DateTime.utc(2026, 8, 21).millisecondsSinceEpoch;
                return <String, dynamic>{
                  'ok': true,
                  'id': custodyBlobId,
                  'storeStatus': 'stored',
                  'custodyKind': groupMediaBlobCustodyKind,
                  'custodyContract': groupMediaBlobCustodyContract,
                  'contentHash': contentHash,
                  'size': ciphertextSize,
                  'mime': groupMediaBlobTransportMime,
                  'expiresAtMs': expiresAtMs,
                  'custodyRelayPeerId': 'relay-$recipientPeerId',
                };
              },
        );
        final parent = GroupMessage(
          id: 'message-365',
          groupId: 'group-365',
          senderPeerId: 'account-local',
          senderUsername: 'Local',
          text: 'caption',
          timestamp: DateTime.utc(2026, 8, 14, 10),
          status: GroupMessage.statusQueuedOffline,
          isIncoming: false,
          createdAt: DateTime.utc(2026, 8, 14, 10),
        );
        final attachment = MediaAttachment(
          id: 'attachment-365',
          messageId: parent.id,
          mime: 'image/jpeg',
          size: await plaintext.length(),
          mediaType: 'image',
          width: 8,
          height: 8,
          localPath: plaintext.path,
          downloadStatus: 'upload_pending',
          createdAt: parent.createdAt.toIso8601String(),
          ownerLane: MediaOwnerLane.group,
        );
        final authoringContext = GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 14, 9, 30),
            eventId: 'authority-365',
            keyEpoch: 7,
          ),
          inboxStore: _NoopAckCustodyInboxStore(),
        );

        final result = await coordinator.prepareAndUploadFresh(
          bridge: _FakeBridge(),
          groupRepository: groupRepo,
          mediaAttachmentRepository: repository,
          identityPeerId: 'account-local',
          senderPublicKey: 'device-current-key',
          senderDeviceId: 'device-current',
          senderTransportPeerId: 'transport-current',
          parent: parent,
          sources: <PreparedGroupMediaBlobSource>[
            PreparedGroupMediaBlobSource(
              attachment: attachment,
              plaintextPath: plaintext.path,
              preparedArtifact: EncryptedMediaArtifact(
                encryptedPath: ciphertext.path,
                keyBase64: 'group-media-key',
                nonce: 'group-media-nonce',
                scheme: groupMediaBlobEncryptionScheme,
                contentHash: ciphertextHash,
                plaintextSize: await plaintext.length(),
              ),
            ),
          ],
          groupContentAuthoring: authoringContext,
        );

        expect(result.isComplete, isTrue);
        expect(uploadedRecipients, <String>[
          'transport-remote',
          'transport-sibling',
        ]);
        expect(uploadedBodies, hasLength(2));
        expect(uploadedBodies[0], uploadedBodies[1]);
        expect(uploadedBodies.singleOrNull, isNull);
        expect(repository.rows, hasLength(2));
        expect(
          repository.rows.map((row) => row.state).toSet(),
          <DirectMediaBlobCustodyState>{
            DirectMediaBlobCustodyState.outgoingStored,
          },
        );
        expect(
          repository.rows.map((row) => row.recipientPeerId).toSet(),
          <String>{'transport-remote', 'transport-sibling'},
        );
        expect(
          result.preparedManifest!.manifest.recipientPeerIds,
          <String>['transport-remote', 'transport-sibling'],
          reason:
              'the current authoring transport is excluded, not its sibling',
        );
        final files = await root
            .list(recursive: true)
            .where((entry) => entry is File && entry.path.endsWith('.blob'))
            .toList();
        expect(files, hasLength(1), reason: 'one ciphertext owns both targets');

        // A refused atomic stage owns no DB reference. The just-published
        // candidate must be removed without touching the surviving generation.
        final refusedCiphertext = File('${root.path}/refused-ciphertext.bin');
        await refusedCiphertext.writeAsBytes(ciphertextBytes);
        final refusedParent = parent.copyWith(id: 'message-365-refused');
        final refusedAttachment = attachment.copyWith(
          id: 'attachment-365-refused',
          messageId: refusedParent.id,
        );
        final refused = await coordinator.prepareAndUploadFresh(
          bridge: _FakeBridge(),
          groupRepository: groupRepo,
          mediaAttachmentRepository: repository,
          identityPeerId: 'account-local',
          senderPublicKey: 'device-current-key',
          senderDeviceId: 'device-current',
          senderTransportPeerId: 'transport-current',
          parent: refusedParent,
          sources: <PreparedGroupMediaBlobSource>[
            PreparedGroupMediaBlobSource(
              attachment: refusedAttachment,
              plaintextPath: plaintext.path,
              preparedArtifact: EncryptedMediaArtifact(
                encryptedPath: refusedCiphertext.path,
                keyBase64: 'group-media-key-refused',
                nonce: 'group-media-nonce-refused',
                scheme: groupMediaBlobEncryptionScheme,
                contentHash: ciphertextHash,
                plaintextSize: await plaintext.length(),
              ),
            ),
          ],
          groupContentAuthoring: authoringContext,
        );
        expect(refused.state, PreparedGroupMediaBlobState.refused);
        expect(
          await root
              .list(recursive: true)
              .where((entry) => entry is File && entry.path.endsWith('.blob'))
              .length,
          1,
          reason: 'stage refusal must delete only its unreferenced candidate',
        );

        // Content completion leaves exact cleanup rows. The same lifecycle
        // owner retires them and also sweeps crash artifacts with no DB owner.
        for (var index = 0; index < repository.rows.length; index++) {
          repository.rows[index] = repository.rows[index].copyWith(
            state: DirectMediaBlobCustodyState.outgoingCleanupPending,
            updatedAt: '2026-08-14T11:00:00.000Z',
          );
        }
        final orphanCiphertext = File('${root.path}/orphan-ciphertext.bin');
        await orphanCiphertext.writeAsBytes(ciphertextBytes);
        await artifactStore.persistCandidate(
          identityPeerId: 'account-local',
          groupId: 'group-365',
          attachmentId: 'attachment-365-orphan',
          encryptedSourcePath: orphanCiphertext.path,
          expectedContentHash: ciphertextHash,
        );
        final cleanupProgress = await coordinator
            .drainOutgoingCleanupAndOrphans(
              mediaAttachmentRepository: repository,
              identityPeerId: 'account-local',
            );
        expect(cleanupProgress, greaterThanOrEqualTo(4));
        expect(repository.rows, isEmpty);
        expect(
          await root
              .list(recursive: true)
              .where((entry) => entry is File && entry.path.endsWith('.blob'))
              .toList(),
          isEmpty,
        );

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-365',
            peerId: 'account-remote',
            role: MemberRole.writer,
            publicKey: 'remote-account-key',
            devices: List<GroupMemberDeviceIdentity>.generate(
              protectedGroupMediaMaxPhysicalRecipients,
              (index) => GroupMemberDeviceIdentity(
                deviceId: 'device-overflow-$index',
                transportPeerId: 'transport-overflow-$index',
                deviceSigningPublicKey: 'device-overflow-key-$index',
              ),
              growable: false,
            ),
            joinedAt: DateTime.utc(2026, 8, 14, 9),
          ),
        );
        final overLimitRepository = _StrictGroupBlobRepository();
        var overLimitPrepareCalls = 0;
        final overLimitCoordinator = PreparedGroupMediaBlobCustodyCoordinator(
          artifactStore: artifactStore,
          prepareArtifact: ({required bridge, required localFilePath}) async {
            overLimitPrepareCalls++;
            throw StateError('over-limit ACL must refuse before preprocessing');
          },
        );
        final overLimitParent = parent.copyWith(id: 'message-365-over-limit');
        final overLimit = await overLimitCoordinator.prepareAndUploadFresh(
          bridge: _FakeBridge(),
          groupRepository: groupRepo,
          mediaAttachmentRepository: overLimitRepository,
          identityPeerId: 'account-local',
          senderPublicKey: 'device-current-key',
          senderDeviceId: 'device-current',
          senderTransportPeerId: 'transport-current',
          parent: overLimitParent,
          sources: <PreparedGroupMediaBlobSource>[
            PreparedGroupMediaBlobSource(
              attachment: attachment.copyWith(
                id: 'attachment-365-over-limit',
                messageId: overLimitParent.id,
              ),
              plaintextPath: plaintext.path,
            ),
          ],
          groupContentAuthoring: authoringContext,
        );
        expect(overLimit.state, PreparedGroupMediaBlobState.refused);
        expect(overLimit.hasDurableAuthority, isFalse);
        expect(overLimitPrepareCalls, 0);
        expect(overLimitRepository.stageCalls, 0);
        expect(overLimitRepository.rows, isEmpty);
      },
    );

    test(
      'TC-365-02a strict group authoring preserves GIF video audio and voice descriptors across discussion and admin policy',
      () async {
        final cases =
            <
              ({
                String label,
                GroupType groupType,
                GroupRole groupRole,
                MemberRole senderRole,
                String mime,
                String mediaType,
                List<int> bytes,
                int? width,
                int? height,
                int? durationMs,
                List<double>? waveform,
              })
            >[
              (
                label: 'discussion-gif',
                groupType: GroupType.chat,
                groupRole: GroupRole.member,
                senderRole: MemberRole.writer,
                mime: 'image/gif',
                mediaType: 'image',
                bytes: <int>[
                  ...utf8.encode('GIF89a'),
                  ...List<int>.filled(40, 1),
                ],
                width: 24,
                height: 18,
                durationMs: null,
                waveform: null,
              ),
              (
                label: 'announcement-admin-video',
                groupType: GroupType.announcement,
                groupRole: GroupRole.admin,
                senderRole: MemberRole.admin,
                mime: 'video/mp4',
                mediaType: 'video',
                bytes: <int>[
                  0,
                  0,
                  0,
                  24,
                  ...utf8.encode('ftypisom'),
                  ...List<int>.filled(40, 2),
                ],
                width: 640,
                height: 360,
                durationMs: 12_500,
                waveform: null,
              ),
              (
                label: 'discussion-audio',
                groupType: GroupType.chat,
                groupRole: GroupRole.member,
                senderRole: MemberRole.writer,
                mime: 'audio/mpeg',
                mediaType: 'audio',
                bytes: <int>[...utf8.encode('ID3'), ...List<int>.filled(40, 3)],
                width: null,
                height: null,
                durationMs: 48_000,
                waveform: null,
              ),
              (
                label: 'announcement-admin-voice',
                groupType: GroupType.announcement,
                groupRole: GroupRole.admin,
                senderRole: MemberRole.admin,
                mime: 'audio/mp4',
                mediaType: 'audio',
                bytes: <int>[
                  0,
                  0,
                  0,
                  24,
                  ...utf8.encode('ftypM4A '),
                  ...List<int>.filled(40, 4),
                ],
                width: null,
                height: null,
                durationMs: 3200,
                waveform: const <double>[0.1, 0.55, 0.9, 0.25],
              ),
            ];

        for (final testCase in cases) {
          final root = await Directory.systemTemp.createTemp(
            'tc365-${testCase.label}-',
          );
          addTearDown(() async {
            if (await root.exists()) await root.delete(recursive: true);
          });
          final groupId = 'group-${testCase.label}';
          final messageId = 'message-${testCase.label}';
          final attachmentId = 'attachment-${testCase.label}';
          final plaintext = File('${root.path}/source.bin');
          await plaintext.writeAsBytes(testCase.bytes);
          final ciphertextBytes = <int>[
            ...List<int>.filled(16, 0xa5),
            ...testCase.bytes,
          ];
          final ciphertext = File('${root.path}/ciphertext.bin');
          await ciphertext.writeAsBytes(ciphertextBytes);
          final ciphertextHash = sha256.convert(ciphertextBytes).toString();

          final groupRepo = InMemoryGroupRepository();
          await groupRepo.saveGroup(
            GroupModel(
              id: groupId,
              name: testCase.label,
              type: testCase.groupType,
              topicName: '$groupId-topic',
              createdAt: DateTime.utc(2026, 8, 14, 9),
              createdBy: 'account-local',
              myRole: testCase.groupRole,
            ),
          );
          await groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 7,
              encryptedKey: 'group-key-${testCase.label}',
              createdAt: DateTime.utc(2026, 8, 14, 9),
            ),
          );
          await groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: 'account-local',
              role: testCase.senderRole,
              publicKey: 'account-public-key',
              devices: const <GroupMemberDeviceIdentity>[
                GroupMemberDeviceIdentity(
                  deviceId: 'device-current',
                  transportPeerId: 'transport-current',
                  deviceSigningPublicKey: 'device-current-key',
                ),
                GroupMemberDeviceIdentity(
                  deviceId: 'device-sibling',
                  transportPeerId: 'transport-sibling',
                  deviceSigningPublicKey: 'device-sibling-key',
                ),
              ],
              joinedAt: DateTime.utc(2026, 8, 14, 9),
            ),
          );
          await groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: 'account-remote',
              role: MemberRole.writer,
              publicKey: 'remote-account-key',
              devices: const <GroupMemberDeviceIdentity>[
                GroupMemberDeviceIdentity(
                  deviceId: 'device-remote',
                  transportPeerId: 'transport-remote',
                  deviceSigningPublicKey: 'device-remote-key',
                ),
              ],
              joinedAt: DateTime.utc(2026, 8, 14, 9, 0, 1),
            ),
          );

          final repository = _StrictGroupBlobRepository();
          final uploadedRecipients = <String>[];
          final coordinator = PreparedGroupMediaBlobCustodyCoordinator(
            artifactStore: GroupMediaBlobArtifactStore(
              documentsDirectoryProvider: () async => root,
            ),
            clock: () => DateTime.utc(2026, 8, 14, 10),
            strictUpload:
                ({
                  required bridge,
                  required custodyBlobId,
                  required recipientPeerId,
                  required ciphertextPath,
                  required contentHash,
                  required ciphertextSize,
                }) async {
                  expect(repository.stageCompleted, isTrue);
                  expect(contentHash, ciphertextHash);
                  expect(ciphertextSize, ciphertextBytes.length);
                  expect(
                    await File(ciphertextPath).readAsBytes(),
                    ciphertextBytes,
                  );
                  uploadedRecipients.add(recipientPeerId);
                  return <String, dynamic>{
                    'ok': true,
                    'id': custodyBlobId,
                    'storeStatus': 'stored',
                    'custodyKind': groupMediaBlobCustodyKind,
                    'custodyContract': groupMediaBlobCustodyContract,
                    'contentHash': contentHash,
                    'size': ciphertextSize,
                    'mime': groupMediaBlobTransportMime,
                    'expiresAtMs': recipientPeerId == 'transport-remote'
                        ? DateTime.utc(2026, 8, 20).millisecondsSinceEpoch
                        : DateTime.utc(2026, 8, 21).millisecondsSinceEpoch,
                    'custodyRelayPeerId': 'relay-$recipientPeerId',
                  };
                },
          );
          final parent = GroupMessage(
            id: messageId,
            groupId: groupId,
            senderPeerId: 'account-local',
            senderUsername: 'Local',
            text: 'caption ${testCase.label}',
            timestamp: DateTime.utc(2026, 8, 14, 10),
            status: GroupMessage.statusQueuedOffline,
            isIncoming: false,
            createdAt: DateTime.utc(2026, 8, 14, 10),
          );
          final attachment = MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: testCase.mime,
            size: testCase.bytes.length,
            mediaType: testCase.mediaType,
            width: testCase.width,
            height: testCase.height,
            durationMs: testCase.durationMs,
            waveform: testCase.waveform,
            localPath: plaintext.path,
            downloadStatus: 'upload_pending',
            createdAt: parent.createdAt.toIso8601String(),
            ownerLane: MediaOwnerLane.group,
          );
          final result = await coordinator.prepareAndUploadFresh(
            bridge: _FakeBridge(),
            groupRepository: groupRepo,
            mediaAttachmentRepository: repository,
            identityPeerId: 'account-local',
            senderPublicKey: 'device-current-key',
            senderDeviceId: 'device-current',
            senderTransportPeerId: 'transport-current',
            parent: parent,
            sources: <PreparedGroupMediaBlobSource>[
              PreparedGroupMediaBlobSource(
                attachment: attachment,
                plaintextPath: plaintext.path,
                preparedArtifact: EncryptedMediaArtifact(
                  encryptedPath: ciphertext.path,
                  keyBase64: 'key-${testCase.label}',
                  nonce: 'nonce-${testCase.label}',
                  scheme: groupMediaBlobEncryptionScheme,
                  contentHash: ciphertextHash,
                  plaintextSize: testCase.bytes.length,
                ),
              ),
            ],
            groupContentAuthoring: GroupContentAuthoringContext(
              directLinkedDeviceSelector:
                  const DirectLinkedDeviceSelector.enabled(),
              multiDeviceSyncEnabled: true,
              authorityVersion: GroupContentAuthorityVersion(
                eventAt: DateTime.utc(2026, 8, 14, 9, 30),
                eventId: 'authority-${testCase.label}',
                keyEpoch: 7,
              ),
              inboxStore: _NoopAckCustodyInboxStore(),
            ),
          );

          expect(result.isComplete, isTrue, reason: testCase.label);
          expect(uploadedRecipients, <String>[
            'transport-remote',
            'transport-sibling',
          ], reason: testCase.label);
          expect(repository.rows, hasLength(2), reason: testCase.label);
          expect(
            repository.rows.map((row) => row.recipientPeerId).toSet(),
            <String>{'transport-remote', 'transport-sibling'},
            reason:
                '${testCase.label}: strict custody targets physical recipients only',
          );
          expect(
            repository.rows.every(
              (row) =>
                  row.ownerLane == MediaBlobCustodyOwnerLane.group &&
                  row.direction == DirectMediaBlobCustodyDirection.outgoing &&
                  row.state == DirectMediaBlobCustodyState.outgoingStored &&
                  row.custodyKind == groupMediaBlobCustodyKind &&
                  row.custodyContract == groupMediaBlobCustodyContract,
            ),
            isTrue,
            reason: testCase.label,
          );
          final completed = result.attachments.single;
          final commitment =
              result.preparedManifest!.manifest.attachments.single;
          expect(completed.mime, testCase.mime, reason: testCase.label);
          expect(
            completed.mediaType,
            testCase.mediaType,
            reason: testCase.label,
          );
          expect(completed.width, testCase.width, reason: testCase.label);
          expect(completed.height, testCase.height, reason: testCase.label);
          expect(
            completed.durationMs,
            testCase.durationMs,
            reason: testCase.label,
          );
          expect(completed.waveform, testCase.waveform, reason: testCase.label);
          expect(commitment.mime, testCase.mime, reason: testCase.label);
          expect(
            commitment.mediaType,
            testCase.mediaType,
            reason: testCase.label,
          );
          expect(commitment.width, testCase.width, reason: testCase.label);
          expect(commitment.height, testCase.height, reason: testCase.label);
          expect(
            commitment.durationMs,
            testCase.durationMs,
            reason: testCase.label,
          );
          expect(
            commitment.waveform,
            testCase.waveform ?? const <double>[],
            reason: testCase.label,
          );
          expect(commitment.recipientPeerIds, <String>{
            'transport-remote',
            'transport-sibling',
          }, reason: testCase.label);
        }
      },
    );

    test(
      'TC-365-02a initialized private group media refuses before preprocessing',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'tc365-group-exclusions-',
        );
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });
        final groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(
          GroupModel(
            id: 'group-365-exclusions',
            name: 'Plan 365 exclusions',
            type: GroupType.chat,
            topicName: 'group-365-exclusions-topic',
            createdAt: DateTime.utc(2026, 8, 14, 9),
            createdBy: 'account-local',
            myRole: GroupRole.member,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-365-exclusions',
            keyGeneration: 7,
            encryptedKey: 'group-key-365-exclusions',
            createdAt: DateTime.utc(2026, 8, 14, 9),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-365-exclusions',
            peerId: 'account-local',
            role: MemberRole.writer,
            publicKey: 'account-public-key',
            devices: const <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'device-current',
                transportPeerId: 'transport-current',
                deviceSigningPublicKey: 'device-current-key',
              ),
              GroupMemberDeviceIdentity(
                deviceId: 'device-sibling',
                transportPeerId: 'transport-sibling',
                deviceSigningPublicKey: 'device-sibling-key',
              ),
            ],
            joinedAt: DateTime.utc(2026, 8, 14, 9),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-365-exclusions',
            peerId: 'account-remote',
            role: MemberRole.writer,
            publicKey: 'remote-account-key',
            devices: const <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'device-remote',
                transportPeerId: 'transport-remote',
                deviceSigningPublicKey: 'device-remote-key',
              ),
            ],
            joinedAt: DateTime.utc(2026, 8, 14, 9, 0, 1),
          ),
        );
        final authoringContext = GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 14, 9, 30),
            eventId: 'authority-365-exclusions',
            keyEpoch: 7,
          ),
          inboxStore: _NoopAckCustodyInboxStore(),
        );

        for (final exclusion
            in <({String label, GroupMessage Function(GroupMessage) mutate})>[
              (
                label: 'private',
                mutate: (parent) => parent.copyWith(
                  privateMediaPolicy: const GroupPrivateMediaPolicy.protected(),
                ),
              ),
            ]) {
          final source = File('${root.path}/${exclusion.label}.jpg');
          await source.writeAsBytes(<int>[
            0xff,
            0xd8,
            0xff,
            ...List<int>.filled(40, 0x36),
          ]);
          final bridge = _FakeBridge();
          final repository = _StrictGroupBlobRepository();
          var prepareCalls = 0;
          var uploadCalls = 0;
          final coordinator = PreparedGroupMediaBlobCustodyCoordinator(
            artifactStore: GroupMediaBlobArtifactStore(
              documentsDirectoryProvider: () async => root,
            ),
            prepareArtifact: ({required bridge, required localFilePath}) async {
              prepareCalls += 1;
              throw StateError('excluded media must not preprocess');
            },
            strictUpload:
                ({
                  required bridge,
                  required custodyBlobId,
                  required recipientPeerId,
                  required ciphertextPath,
                  required contentHash,
                  required ciphertextSize,
                }) async {
                  uploadCalls += 1;
                  throw StateError('excluded media must not upload');
                },
          );
          final baseParent = GroupMessage(
            id: 'message-365-${exclusion.label}',
            groupId: 'group-365-exclusions',
            senderPeerId: 'account-local',
            text: '',
            timestamp: DateTime.utc(2026, 8, 14, 10),
            status: GroupMessage.statusQueuedOffline,
            isIncoming: false,
            createdAt: DateTime.utc(2026, 8, 14, 10),
          );
          final parent = exclusion.mutate(baseParent);
          final result = await coordinator.prepareAndUploadFresh(
            bridge: bridge,
            groupRepository: groupRepo,
            mediaAttachmentRepository: repository,
            identityPeerId: 'account-local',
            senderPublicKey: 'device-current-key',
            senderDeviceId: 'device-current',
            senderTransportPeerId: 'transport-current',
            parent: parent,
            sources: <PreparedGroupMediaBlobSource>[
              PreparedGroupMediaBlobSource(
                attachment: MediaAttachment(
                  id: 'attachment-365-${exclusion.label}',
                  messageId: parent.id,
                  mime: 'image/jpeg',
                  size: await source.length(),
                  mediaType: 'image',
                  width: 8,
                  height: 8,
                  localPath: source.path,
                  downloadStatus: 'upload_pending',
                  createdAt: parent.createdAt.toIso8601String(),
                  ownerLane: MediaOwnerLane.group,
                ),
                plaintextPath: source.path,
              ),
            ],
            groupContentAuthoring: authoringContext,
          );

          expect(
            result.state,
            PreparedGroupMediaBlobState.refused,
            reason: exclusion.label,
          );
          expect(prepareCalls, 0, reason: exclusion.label);
          expect(uploadCalls, 0, reason: exclusion.label);
          expect(bridge.sendCallCount, 0, reason: exclusion.label);
          expect(repository.stageCompleted, isFalse, reason: exclusion.label);
          expect(repository.rows, isEmpty, reason: exclusion.label);
          expect(
            await repository.getAttachmentsForMessage(
              parent.id,
              owner: MediaOwnerLane.group,
            ),
            isEmpty,
            reason: exclusion.label,
          );
          expect(await source.exists(), isTrue, reason: exclusion.label);
        }
        expect(
          await root
              .list(recursive: true)
              .where((entry) => entry is File && entry.path.endsWith('.blob'))
              .toList(),
          isEmpty,
        );
      },
    );
  });
}

ConversationMessage _strictParent(String suffix) => ConversationMessage(
  id: 'message-$suffix',
  contactPeerId: 'recipient-347',
  senderPeerId: 'sender-347',
  text: '',
  timestamp: '2026-08-08T12:00:00.000Z',
  status: 'sending',
  isIncoming: false,
  createdAt: '2026-08-08T12:00:00.000Z',
  directMediaCustodyIntentId: 'intent-$suffix',
);

MediaAttachment _strictPendingAttachment(String suffix) => MediaAttachment(
  id: 'attachment-$suffix',
  messageId: 'message-$suffix',
  mime: 'image/jpeg',
  size: 6,
  mediaType: 'image',
  localPath: MediaFilePathConvention.relativePathForPendingUpload(
    messageId: 'message-$suffix',
    attachmentId: 'attachment-$suffix',
    mime: 'image/jpeg',
  ),
  downloadStatus: 'upload_pending',
  createdAt: '2026-08-08T12:00:00.000Z',
  ownerLane: MediaOwnerLane.direct,
);

Map<String, dynamic> _exactStrictReceipt(Map<String, dynamic> payload) =>
    <String, dynamic>{
      'ok': true,
      'id': payload['id'],
      'storeStatus': 'stored',
      'custodyKind': payload['custodyKind'],
      'custodyContract': payload['custodyContract'],
      'contentHash': payload['contentHash'],
      'size': File(payload['filePath'] as String).lengthSync(),
      'mime': payload['mime'],
      'expiresAtMs': DateTime.utc(2036, 8, 9).millisecondsSinceEpoch,
      'custodyRelayPeerId': 'relay-347',
    };

final class _NoopAckCustodyInboxStore implements AckOrExpiryInboxStore {
  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async => const InboxStoreOutcome(
    status: InboxStoreStatus.stored,
    storeStatus: 'stored',
    custodyContract: ackOrExpiryInboxCustodyContract,
  );
}

final class _StrictGroupBlobRepository extends InMemoryMediaAttachmentRepository
    implements
        GroupMediaBlobCustodyRepository,
        GroupMediaBlobArtifactReferenceInventoryRepository {
  final List<DirectMediaBlobCustodyRow> rows = <DirectMediaBlobCustodyRow>[];
  bool stageCompleted = false;
  int stageCalls = 0;

  @override
  bool get supportsGroupMediaBlobCustody => true;

  @override
  Future<T> runGroupMediaBlobCustodyLifecycle<T>(Future<T> Function() action) =>
      action();

  @override
  Future<GroupMediaBlobCustodyStageOutcome>
  stageFreshOutgoingGroupMediaBlobGeneration({
    required GroupMessage parent,
    required List<MediaAttachment> attachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
    required Map<String, String> custodyBlobIdsByAttachmentId,
  }) async {
    stageCalls++;
    if (rows.isNotEmpty) return GroupMediaBlobCustodyStageOutcome.refused;
    expect(
      custodyBlobIdsByAttachmentId.keys.toSet(),
      attachments.map((attachment) => attachment.id).toSet(),
    );
    for (final attachment in attachments) {
      await saveAttachment(attachment, owner: MediaOwnerLane.group);
    }
    rows.addAll(custodyRows);
    stageCompleted = true;
    return GroupMediaBlobCustodyStageOutcome.applied;
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadGroupMediaBlobCustodyForMessage({
    required String groupId,
    required String messageId,
  }) async => rows
      .where((row) => row.groupId == groupId && row.messageId == messageId)
      .toList(growable: false);

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadGroupMediaBlobCustodyByStates(
    Set<DirectMediaBlobCustodyState> states, {
    int limit = 50,
  }) async => rows
      .where((row) => states.contains(row.state))
      .take(limit)
      .toList(growable: false);

  @override
  Future<DirectMediaBlobCustodyRow?> loadGroupMediaBlobCustodyForTarget({
    required String groupId,
    required String attachmentId,
    required String custodyBlobId,
    required DirectMediaBlobCustodyDirection direction,
    String? recipientPeerId,
  }) async {
    for (final row in rows) {
      if (row.groupId == groupId &&
          row.attachmentId == attachmentId &&
          row.custodyBlobId == custodyBlobId &&
          row.direction == direction &&
          row.recipientPeerId == recipientPeerId) {
        return row;
      }
    }
    return null;
  }

  @override
  Future<bool> transitionGroupMediaBlobCustodyIfExact({
    required DirectMediaBlobCustodyRow expected,
    required DirectMediaBlobCustodyRow next,
  }) async {
    final index = rows.indexWhere(
      (row) => row.exactDatabaseProjectionMatches(expected),
    );
    if (index < 0 || !expected.canTransitionTo(next)) return false;
    rows[index] = next;
    return true;
  }

  @override
  Future<bool> deleteGroupMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async {
    final index = rows.indexWhere(
      (row) => row.exactDatabaseProjectionMatches(expected),
    );
    if (index < 0 ||
        expected.state != DirectMediaBlobCustodyState.outgoingCleanupPending) {
      return false;
    }
    rows.removeAt(index);
    return true;
  }

  @override
  Future<Set<String>> loadGroupMediaBlobArtifactRelativePaths() async =>
      rows.map((row) => row.ciphertextRelativePath).whereType<String>().toSet();

  @override
  Future<bool> commitIncomingGroupMediaBlobLocalPath({
    required MediaAttachment expectedAttachment,
    required DirectMediaBlobCustodyRow expectedCustody,
    required String localPath,
    required String sourceRelayPeerId,
    required String updatedAt,
    required int nowMs,
  }) async => false;

  @override
  Future<bool> terminalizeIncomingGroupMediaBlobForLocalDeletion({
    required MediaAttachment expectedAttachment,
    required DirectMediaBlobCustodyRow expectedCustody,
    required String sourceRelayPeerId,
    required String updatedAt,
  }) async => false;

  @override
  Future<bool> deleteIncomingGroupMediaBlobAckPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async => false;

  @override
  Future<bool> deleteIncomingGroupMediaBlobIfExpired({
    required DirectMediaBlobCustodyRow expected,
    required int nowMs,
  }) async => false;

  @override
  Future<int> countOtherGroupMediaBlobCustodyRowsReferencingArtifact(
    DirectMediaBlobCustodyRow expected,
  ) async => rows
      .where(
        (row) =>
            !row.exactDatabaseProjectionMatches(expected) &&
            row.ciphertextRelativePath == expected.ciphertextRelativePath,
      )
      .length;
}

final class _StrictBlobRepository implements DirectMediaBlobCustodyRepository {
  final Map<String, DirectMediaBlobCustodyRow> rows =
      <String, DirectMediaBlobCustodyRow>{};
  final Map<String, MediaAttachment> attachments = <String, MediaAttachment>{};

  @override
  bool get supportsDirectMediaBlobCustody => true;

  @override
  Future<T> runDirectMediaBlobCustodyLifecycle<T>(
    Future<T> Function() action,
  ) => action();

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectMediaBlobGeneration({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  }) async {
    if (rows.isNotEmpty) {
      return DirectMediaBlobGenerationStageResult(
        outcome: DirectMediaBlobGenerationStageOutcome.idempotent,
        attachments: attachments.values.toList(growable: false),
        custodyRows: rows.values.toList(growable: false),
      );
    }
    for (final attachment in preparedAttachments) {
      attachments[attachment.id] = attachment;
    }
    for (final row in custodyRows) {
      rows[row.attachmentId] = row;
    }
    return DirectMediaBlobGenerationStageResult(
      outcome: DirectMediaBlobGenerationStageOutcome.applied,
      attachments: preparedAttachments,
      custodyRows: custodyRows,
    );
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>>
  loadDirectMediaBlobCustodyRowsForAttachment(String attachmentId) async {
    final row = rows[attachmentId];
    return row == null
        ? const <DirectMediaBlobCustodyRow>[]
        : <DirectMediaBlobCustodyRow>[row];
  }

  @override
  Future<DirectMediaBlobCustodyRow?>
  loadIncomingDirectMediaBlobCustodyForAttachment(String attachmentId) async {
    final row = rows[attachmentId];
    return row != null &&
            row.direction == DirectMediaBlobCustodyDirection.incoming
        ? row
        : null;
  }

  @override
  Future<DirectMediaBlobCustodyRow?>
  loadOutgoingDirectMediaBlobCustodyForTarget({
    required String attachmentId,
    required String recipientPeerId,
  }) async {
    final row = rows[attachmentId];
    return row != null &&
            row.direction == DirectMediaBlobCustodyDirection.outgoing &&
            row.recipientPeerId == recipientPeerId
        ? row
        : null;
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyForMessage(
    String messageId,
  ) async => rows.values
      .where((row) => row.messageId == messageId)
      .toList(growable: false);

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyByStates(
    Set<DirectMediaBlobCustodyState> states, {
    int limit = 50,
  }) async => rows.values
      .where((row) => states.contains(row.state))
      .take(limit)
      .toList(growable: false);

  @override
  Future<bool> transitionDirectMediaBlobCustodyIfExact({
    required DirectMediaBlobCustodyRow expected,
    required DirectMediaBlobCustodyRow next,
  }) async {
    final current = rows[expected.attachmentId];
    if (current == null ||
        !current.exactDatabaseProjectionMatches(expected) ||
        !expected.canTransitionTo(next)) {
      return false;
    }
    rows[expected.attachmentId] = next;
    return true;
  }

  @override
  Future<bool> deleteDirectMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async {
    final current = rows[expected.attachmentId];
    if (current == null ||
        !current.exactDatabaseProjectionMatches(expected) ||
        current.state != DirectMediaBlobCustodyState.outgoingCleanupPending) {
      return false;
    }
    rows.remove(expected.attachmentId);
    return true;
  }
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
