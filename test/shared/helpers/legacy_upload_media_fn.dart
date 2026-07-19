import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

/// Transitional adapter for older widget-test seams that model upload failure
/// as null. Production code and focused upload contract tests use
/// [UploadMediaOutcome] directly.
typedef LegacyTestUploadMediaFn =
    Future<MediaAttachment?> Function({
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
      bool deleteSourceWhenDone,
      EncryptedMediaArtifact? preparedArtifact,
    });

UploadMediaFn adaptLegacyTestUploadMediaFn(LegacyTestUploadMediaFn legacy) =>
    ({
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
    }) async {
      final attachment = await legacy(
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
      );
      return attachment == null
          ? const UploadMediaFailed(
              stage: UploadMediaStage.consumerBoundary,
              disposition: UploadMediaDisposition.terminal,
              errorCode: 'LEGACY_TEST_UPLOAD_NULL',
            )
          : UploadMediaSucceeded(attachment);
    };
