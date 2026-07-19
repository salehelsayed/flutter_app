import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

/// A fake [UploadMediaFn] for testing.
///
/// Supports a default return value and per-path return values.
class FakeUploadMediaFn {
  MediaAttachment? _defaultResult;
  final Map<String, MediaAttachment?> _resultsByPath = {};
  int _callCount = 0;
  String? _lastLocalPath;
  String? _lastMime;
  int? _lastDurationMs;
  String? _lastBlobId;
  List<String>? _lastAllowedPeers;

  int get callCount => _callCount;
  String? get lastLocalPath => _lastLocalPath;
  String? get lastMime => _lastMime;
  int? get lastDurationMs => _lastDurationMs;
  String? get lastBlobId => _lastBlobId;
  List<String>? get lastAllowedPeers => _lastAllowedPeers;

  /// Set the default return value.
  void willReturn(MediaAttachment? result) {
    _defaultResult = result;
  }

  /// Set a return value for a specific local file path.
  void willReturnForPath(String path, MediaAttachment? result) {
    _resultsByPath[path] = result;
  }

  bool? _lastDeleteSourceWhenDone;
  bool? get lastDeleteSourceWhenDone => _lastDeleteSourceWhenDone;

  EncryptedMediaArtifact? _lastPreparedArtifact;
  EncryptedMediaArtifact? get lastPreparedArtifact => _lastPreparedArtifact;

  /// The callable to pass as `uploadMediaFn`.
  Future<UploadMediaOutcome> call({
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
    _callCount++;
    _lastDeleteSourceWhenDone = deleteSourceWhenDone;
    _lastPreparedArtifact = preparedArtifact;
    _lastLocalPath = localFilePath;
    _lastMime = mime;
    _lastDurationMs = durationMs;
    _lastBlobId = blobId;
    _lastAllowedPeers = allowedPeers == null
        ? null
        : List<String>.from(allowedPeers);

    if (_resultsByPath.containsKey(localFilePath)) {
      return _outcomeFor(_resultsByPath[localFilePath]);
    }
    return _outcomeFor(_defaultResult);
  }

  UploadMediaOutcome _outcomeFor(MediaAttachment? attachment) =>
      attachment == null
      ? const UploadMediaFailed(
          stage: UploadMediaStage.consumerBoundary,
          disposition: UploadMediaDisposition.terminal,
          errorCode: 'FAKE_UPLOAD_FAILED',
        )
      : UploadMediaSucceeded(attachment);
}
