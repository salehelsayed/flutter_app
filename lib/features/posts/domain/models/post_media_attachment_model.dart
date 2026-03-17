import 'dart:convert';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

class PostMediaAttachmentModel {
  final String mediaId;
  final String postId;
  final String blobId;
  final String kind;
  final String mime;
  final int sizeBytes;
  final int position;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? localPath;
  final String downloadStatus;
  final String createdAt;
  final List<double>? waveform;
  final String? thumbnailBlobId;
  final String? encryptionKeyBase64;
  final String? encryptionNonce;
  final bool isEncrypted;

  const PostMediaAttachmentModel({
    required this.mediaId,
    required this.postId,
    required this.blobId,
    required this.kind,
    required this.mime,
    required this.sizeBytes,
    this.position = 0,
    this.width,
    this.height,
    this.durationMs,
    this.localPath,
    this.downloadStatus = 'pending',
    required this.createdAt,
    this.waveform,
    this.thumbnailBlobId,
    this.encryptionKeyBase64,
    this.encryptionNonce,
    this.isEncrypted = false,
  });

  factory PostMediaAttachmentModel.fromMap(Map<String, Object?> map) {
    return PostMediaAttachmentModel(
      mediaId: map['media_id'] as String,
      postId: map['post_id'] as String,
      blobId: map['blob_id'] as String,
      kind: map['kind'] as String,
      mime: map['mime'] as String,
      sizeBytes: (map['size_bytes'] as int?) ?? 0,
      position: (map['position'] as int?) ?? 0,
      width: map['width'] as int?,
      height: map['height'] as int?,
      durationMs: map['duration_ms'] as int?,
      localPath: map['local_path'] as String?,
      downloadStatus: map['download_status'] as String? ?? 'pending',
      createdAt: map['created_at'] as String,
      waveform: _decodeWaveform(map['waveform']),
      thumbnailBlobId: map['thumbnail_blob_id'] as String?,
      encryptionKeyBase64: map['encryption_key_base64'] as String?,
      encryptionNonce: map['encryption_nonce'] as String?,
      isEncrypted: (map['is_encrypted'] as int?) == 1,
    );
  }

  factory PostMediaAttachmentModel.fromRenderableJson(
    Map<String, dynamic> json, {
    required String postId,
    required int position,
    String downloadStatus = 'pending',
    String? localPath,
    String? createdAt,
    String? encryptionKeyBase64,
    String? encryptionNonce,
    bool isEncrypted = false,
  }) {
    return PostMediaAttachmentModel(
      mediaId: json['media_id'] as String,
      postId: postId,
      blobId: json['blob_id'] as String,
      kind: json['kind'] as String,
      mime: json['mime'] as String,
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      position: position,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: createdAt ?? DateTime.now().toUtc().toIso8601String(),
      waveform: _decodeWaveform(json['waveform']),
      thumbnailBlobId: json['thumbnail_blob_id'] as String?,
      encryptionKeyBase64: encryptionKeyBase64,
      encryptionNonce: encryptionNonce,
      isEncrypted: isEncrypted,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'media_id': mediaId,
      'post_id': postId,
      'blob_id': blobId,
      'kind': kind,
      'mime': mime,
      'size_bytes': sizeBytes,
      'position': position,
      'width': width,
      'height': height,
      'duration_ms': durationMs,
      'local_path': localPath,
      'download_status': downloadStatus,
      'created_at': createdAt,
      'waveform': waveform == null ? null : jsonEncode(waveform),
      'thumbnail_blob_id': thumbnailBlobId,
      'encryption_key_base64': encryptionKeyBase64,
      'encryption_nonce': encryptionNonce,
      'is_encrypted': isEncrypted ? 1 : 0,
    };
  }

  Map<String, Object?> toRenderableJson() {
    return <String, Object?>{
      'media_id': mediaId,
      'blob_id': blobId,
      'kind': kind,
      'mime': mime,
      'size_bytes': sizeBytes,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'duration_ms': durationMs,
      if (waveform != null) 'waveform': waveform,
      if (thumbnailBlobId != null) 'thumbnail_blob_id': thumbnailBlobId,
    };
  }

  MediaAttachment toSharedMediaAttachment() {
    return MediaAttachment(
      id: blobId,
      messageId: postId,
      mime: mime,
      size: sizeBytes,
      mediaType: kind == 'voice' ? 'audio' : kind,
      width: width,
      height: height,
      durationMs: durationMs,
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: createdAt,
      waveform: waveform,
    );
  }

  PostMediaAttachmentModel copyWith({
    String? mediaId,
    String? postId,
    String? blobId,
    String? kind,
    String? mime,
    int? sizeBytes,
    int? position,
    int? width,
    int? height,
    int? durationMs,
    String? localPath,
    String? downloadStatus,
    String? createdAt,
    List<double>? waveform,
    bool clearWaveform = false,
    String? thumbnailBlobId,
    String? encryptionKeyBase64,
    String? encryptionNonce,
    bool? isEncrypted,
  }) {
    return PostMediaAttachmentModel(
      mediaId: mediaId ?? this.mediaId,
      postId: postId ?? this.postId,
      blobId: blobId ?? this.blobId,
      kind: kind ?? this.kind,
      mime: mime ?? this.mime,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      position: position ?? this.position,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      localPath: localPath ?? this.localPath,
      downloadStatus: downloadStatus ?? this.downloadStatus,
      createdAt: createdAt ?? this.createdAt,
      waveform: clearWaveform ? null : (waveform ?? this.waveform),
      thumbnailBlobId: thumbnailBlobId ?? this.thumbnailBlobId,
      encryptionKeyBase64: encryptionKeyBase64 ?? this.encryptionKeyBase64,
      encryptionNonce: encryptionNonce ?? this.encryptionNonce,
      isEncrypted: isEncrypted ?? this.isEncrypted,
    );
  }

  static String deriveMediaKind(List<PostMediaAttachmentModel> attachments) {
    if (attachments.isEmpty) {
      return 'none';
    }
    final firstKind = attachments.first.kind;
    if (firstKind == 'image' && attachments.length > 1) {
      return 'image_carousel';
    }
    return firstKind;
  }

  static bool isValidSnapshotMedia({
    required String mediaKind,
    required List<PostMediaAttachmentModel> media,
  }) {
    switch (mediaKind) {
      case 'none':
        return media.isEmpty;
      case 'image':
        return media.length == 1 &&
            media.every((attachment) => attachment.kind == 'image');
      case 'image_carousel':
        return media.length > 1 &&
            media.every((attachment) => attachment.kind == 'image');
      case 'video':
        return media.length == 1 && media.single.kind == 'video';
      case 'voice':
        return media.length == 1 && media.single.kind == 'voice';
      default:
        return false;
    }
  }

  static List<double>? _decodeWaveform(Object? raw) {
    if (raw is String) {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((value) => (value as num).toDouble()).toList();
    }
    if (raw is List) {
      return raw.map((value) => (value as num).toDouble()).toList();
    }
    return null;
  }
}
