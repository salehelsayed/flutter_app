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
  });

  /// Infers the logical media type from a MIME string.
  static String mediaTypeFromMime(String mime) {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'audio';
    return 'file';
  }

  /// Creates a MediaAttachment from a database row map (snake_case keys).
  factory MediaAttachment.fromMap(Map<String, dynamic> map) {
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
    };
  }

  /// Creates a MediaAttachment from a wire-format JSON map (camelCase keys).
  factory MediaAttachment.fromJson(Map<String, dynamic> json) {
    final mime = json['mime'] as String? ?? 'application/octet-stream';
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
      createdAt: json['createdAt'] as String? ??
          DateTime.now().toUtc().toIso8601String(),
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
    };
  }

  /// Creates a copy with updated fields.
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
    String? downloadStatus,
    String? createdAt,
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
      localPath: localPath ?? this.localPath,
      downloadStatus: downloadStatus ?? this.downloadStatus,
      createdAt: createdAt ?? this.createdAt,
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
