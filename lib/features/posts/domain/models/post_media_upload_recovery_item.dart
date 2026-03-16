import 'dart:convert';

class PostMediaUploadRecoveryItem {
  final String postId;
  final int position;
  final String localFilePath;
  final String mime;
  final String kind;
  final int? width;
  final int? height;
  final int? durationMs;
  final List<double>? waveform;
  final String createdAt;

  const PostMediaUploadRecoveryItem({
    required this.postId,
    required this.position,
    required this.localFilePath,
    required this.mime,
    required this.kind,
    this.width,
    this.height,
    this.durationMs,
    this.waveform,
    required this.createdAt,
  });

  factory PostMediaUploadRecoveryItem.fromMap(Map<String, Object?> map) {
    return PostMediaUploadRecoveryItem(
      postId: map['post_id'] as String,
      position: (map['position'] as num).toInt(),
      localFilePath: map['local_file_path'] as String,
      mime: map['mime'] as String,
      kind: map['kind'] as String,
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      durationMs: (map['duration_ms'] as num?)?.toInt(),
      waveform: _decodeWaveform(map['waveform']),
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'post_id': postId,
      'position': position,
      'local_file_path': localFilePath,
      'mime': mime,
      'kind': kind,
      'width': width,
      'height': height,
      'duration_ms': durationMs,
      'waveform': waveform == null ? null : jsonEncode(waveform),
      'created_at': createdAt,
    };
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
