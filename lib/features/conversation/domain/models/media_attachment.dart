import 'dart:convert';

const kMediaAttachmentEncryptionSchemeBlobAesGcmV1 = 'blob_aes_256_gcm_v1';

/// Model representing a media attachment on a conversation message.
///
/// Maps to the `media_attachments` database table. Each attachment belongs
/// to a message identified by `messageId`.
class MediaAttachment {
  /// Unique attachment ID (UUID = relay blob ID).
  final String id;

  /// FK to messages.id.
  final String messageId;

  /// MIME type, e.g. 'image/jpeg'.
  final String mime;

  /// File size in bytes.
  final int size;

  /// Logical media type: 'image', 'video', 'audio', 'file'.
  final String mediaType;

  /// Width in pixels (image/video only).
  final int? width;

  /// Height in pixels (image/video only).
  final int? height;

  /// Duration in milliseconds (video/audio only).
  final int? durationMs;

  /// Local file path. NULL until downloaded.
  final String? localPath;

  /// Download status: 'pending', 'downloading', 'done', 'failed'.
  final String downloadStatus;

  /// ISO-8601 timestamp when the attachment was created.
  final String createdAt;

  /// Normalized waveform samples [0.0, 1.0] for audio visualization.
  final List<double>? waveform;

  /// Number of upload retry attempts for outgoing attachments.
  /// Incremented on each transient failure. Terminal after kMaxUploadRetries.
  final int? uploadRetryCount;

  /// Canonical lowercase SHA-256 digest for group media relay blob bytes.
  final String? contentHash;

  /// Canonical lowercase SHA-256 digest for a remote thumbnail blob, if any.
  final String? thumbnailHash;

  /// Base64-encoded per-object media encryption key.
  final String? encryptionKeyBase64;

  /// Base64-encoded per-object media encryption nonce.
  final String? encryptionNonce;

  /// Versioned encryption scheme for encrypted media blobs.
  final String? encryptionScheme;

  const MediaAttachment({
    required this.id,
    required this.messageId,
    required this.mime,
    required this.size,
    required this.mediaType,
    this.width,
    this.height,
    this.durationMs,
    this.localPath,
    required this.downloadStatus,
    required this.createdAt,
    this.waveform,
    this.uploadRetryCount,
    this.contentHash,
    this.thumbnailHash,
    this.encryptionKeyBase64,
    this.encryptionNonce,
    this.encryptionScheme,
  });

  bool get isAnimated => mime == 'image/gif';

  bool get hasEncryptionMetadata =>
      encryptionKeyBase64 != null &&
      encryptionKeyBase64!.isNotEmpty &&
      encryptionNonce != null &&
      encryptionNonce!.isNotEmpty &&
      (encryptionScheme == null ||
          encryptionScheme == kMediaAttachmentEncryptionSchemeBlobAesGcmV1);

  bool get isEncrypted => hasEncryptionMetadata;

  /// Infers the logical media type from a MIME string.
  static String mediaTypeFromMime(String mime) {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'audio';
    return 'file';
  }

  /// Creates a MediaAttachment from a database row map (snake_case keys).
  factory MediaAttachment.fromMap(Map<String, dynamic> map) {
    List<double>? waveform;
    final waveformStr = map['waveform'] as String?;
    if (waveformStr != null) {
      final decoded = jsonDecode(waveformStr) as List<dynamic>;
      waveform = decoded.map((e) => (e as num).toDouble()).toList();
    }

    return MediaAttachment(
      id: map['id'] as String,
      messageId: map['message_id'] as String,
      mime: map['mime'] as String,
      size: map['size'] as int? ?? 0,
      mediaType: map['media_type'] as String,
      width: map['width'] as int?,
      height: map['height'] as int?,
      durationMs: map['duration_ms'] as int?,
      localPath: map['local_path'] as String?,
      downloadStatus: map['download_status'] as String? ?? 'pending',
      createdAt: map['created_at'] as String,
      waveform: waveform,
      uploadRetryCount: map['upload_retry_count'] as int?,
      contentHash: map['content_hash'] as String?,
      thumbnailHash: map['thumbnail_hash'] as String?,
      encryptionKeyBase64: map['encryption_key_base64'] as String?,
      encryptionNonce: map['encryption_nonce'] as String?,
      encryptionScheme: map['encryption_scheme'] as String?,
    );
  }

  /// Converts the model to a database row map (snake_case keys).
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'message_id': messageId,
      'mime': mime,
      'size': size,
      'media_type': mediaType,
      'width': width,
      'height': height,
      'duration_ms': durationMs,
      'local_path': localPath,
      'download_status': downloadStatus,
      'created_at': createdAt,
      'waveform': waveform != null ? jsonEncode(waveform) : null,
      if (uploadRetryCount != null) 'upload_retry_count': uploadRetryCount,
      'content_hash': contentHash,
      'thumbnail_hash': thumbnailHash,
      'encryption_key_base64': encryptionKeyBase64,
      'encryption_nonce': encryptionNonce,
      'encryption_scheme': encryptionScheme,
    };
  }

  /// Creates a MediaAttachment from a wire-format JSON map (camelCase keys).
  factory MediaAttachment.fromJson(Map<String, dynamic> json) {
    final mime = json['mime'] as String? ?? 'application/octet-stream';

    List<double>? waveform;
    final wfRaw = json['waveform'];
    if (wfRaw is List) {
      waveform = wfRaw.map((e) => (e as num).toDouble()).toList();
    }

    return MediaAttachment(
      id: json['id'] as String,
      messageId: json['messageId'] as String? ?? '',
      mime: mime,
      size: json['size'] as int? ?? 0,
      mediaType: json['mediaType'] as String? ?? mediaTypeFromMime(mime),
      width: json['width'] as int?,
      height: json['height'] as int?,
      durationMs: json['durationMs'] as int?,
      localPath: null,
      downloadStatus: 'pending',
      createdAt:
          json['createdAt'] as String? ??
          DateTime.now().toUtc().toIso8601String(),
      waveform: waveform,
      contentHash: json['contentHash'] as String?,
      thumbnailHash: json['thumbnailHash'] as String?,
      encryptionKeyBase64: json['encryptionKeyBase64'] as String?,
      encryptionNonce: json['encryptionNonce'] as String?,
      encryptionScheme: json['encryptionScheme'] as String?,
    );
  }

  /// Converts to wire-format JSON map (camelCase keys).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mime': mime,
      'size': size,
      'mediaType': mediaType,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'durationMs': durationMs,
      if (waveform != null) 'waveform': waveform,
      if (contentHash != null) 'contentHash': contentHash,
      if (thumbnailHash != null) 'thumbnailHash': thumbnailHash,
      if (encryptionKeyBase64 != null)
        'encryptionKeyBase64': encryptionKeyBase64,
      if (encryptionNonce != null) 'encryptionNonce': encryptionNonce,
      if (encryptionScheme != null) 'encryptionScheme': encryptionScheme,
    };
  }

  /// Creates a copy with updated fields.
  ///
  /// Use [clearWaveform] = true to explicitly set waveform to null.
  MediaAttachment copyWith({
    String? id,
    String? messageId,
    String? mime,
    int? size,
    String? mediaType,
    int? width,
    int? height,
    int? durationMs,
    String? localPath,
    bool clearLocalPath = false,
    String? downloadStatus,
    String? createdAt,
    List<double>? waveform,
    bool clearWaveform = false,
    int? uploadRetryCount,
    String? contentHash,
    bool clearContentHash = false,
    String? thumbnailHash,
    bool clearThumbnailHash = false,
    String? encryptionKeyBase64,
    bool clearEncryptionKeyBase64 = false,
    String? encryptionNonce,
    bool clearEncryptionNonce = false,
    String? encryptionScheme,
    bool clearEncryptionScheme = false,
  }) {
    return MediaAttachment(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      mime: mime ?? this.mime,
      size: size ?? this.size,
      mediaType: mediaType ?? this.mediaType,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      downloadStatus: downloadStatus ?? this.downloadStatus,
      createdAt: createdAt ?? this.createdAt,
      waveform: clearWaveform ? null : (waveform ?? this.waveform),
      uploadRetryCount: uploadRetryCount ?? this.uploadRetryCount,
      contentHash: clearContentHash ? null : (contentHash ?? this.contentHash),
      thumbnailHash: clearThumbnailHash
          ? null
          : (thumbnailHash ?? this.thumbnailHash),
      encryptionKeyBase64: clearEncryptionKeyBase64
          ? null
          : (encryptionKeyBase64 ?? this.encryptionKeyBase64),
      encryptionNonce: clearEncryptionNonce
          ? null
          : (encryptionNonce ?? this.encryptionNonce),
      encryptionScheme: clearEncryptionScheme
          ? null
          : (encryptionScheme ?? this.encryptionScheme),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MediaAttachment && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'MediaAttachment(id: ${id.length > 8 ? id.substring(0, 8) : id}..., messageId: ${messageId.length > 8 ? messageId.substring(0, 8) : messageId}..., mime: $mime, size: $size)';
  }
}
