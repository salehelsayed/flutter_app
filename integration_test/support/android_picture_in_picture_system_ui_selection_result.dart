import 'dart:convert';
import 'dart:io';

const androidPictureInPictureSystemUiSelectionSchema =
    'mknoon.android-pip-system-ui-control.v1';

const _selectionKeys = <String>{
  'schema',
  'selectorSource',
  'resourceId',
  'contentDescription',
  'bounds',
  'center',
  'geometryEvidence',
};

class AndroidPictureInPictureSystemUiSelectionResult {
  const AndroidPictureInPictureSystemUiSelectionResult({
    required this.selectorSource,
    required this.resourceId,
    required this.contentDescription,
    required this.bounds,
    required this.center,
    required this.geometryEvidence,
  });

  final String selectorSource;
  final String resourceId;
  final String contentDescription;
  final List<int> bounds;
  final List<int> center;
  final String geometryEvidence;

  Map<String, Object> toJson() => <String, Object>{
    'schema': androidPictureInPictureSystemUiSelectionSchema,
    'selectorSource': selectorSource,
    'resourceId': resourceId,
    'contentDescription': contentDescription,
    'bounds': bounds,
    'center': center,
    'geometryEvidence': geometryEvidence,
  };

  static AndroidPictureInPictureSystemUiSelectionResult parseExact(
    String source,
  ) {
    for (final key in _selectionKeys) {
      if (RegExp('"${RegExp.escape(key)}"\\s*:').allMatches(source).length !=
          1) {
        throw FormatException('Selection key must occur exactly once: $key');
      }
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded.keys.toSet().difference(_selectionKeys).isNotEmpty ||
        _selectionKeys.difference(decoded.keys.toSet()).isNotEmpty) {
      throw const FormatException('Selection keys did not match exact schema.');
    }
    if (decoded['schema'] != androidPictureInPictureSystemUiSelectionSchema ||
        decoded['selectorSource'] is! String ||
        (decoded['selectorSource'] as String).isEmpty ||
        decoded['resourceId'] is! String ||
        decoded['contentDescription'] is! String ||
        decoded['geometryEvidence'] is! String) {
      throw const FormatException('Selection scalar fields were invalid.');
    }
    final bounds = _exactIntList(decoded['bounds'], 4, 'bounds');
    final center = _exactIntList(decoded['center'], 2, 'center');
    if (bounds[2] <= bounds[0] ||
        bounds[3] <= bounds[1] ||
        center[0] < bounds[0] ||
        center[0] > bounds[2] ||
        center[1] < bounds[1] ||
        center[1] > bounds[3]) {
      throw const FormatException('Selection bounds or center were invalid.');
    }
    return AndroidPictureInPictureSystemUiSelectionResult(
      selectorSource: decoded['selectorSource'] as String,
      resourceId: decoded['resourceId'] as String,
      contentDescription: decoded['contentDescription'] as String,
      bounds: bounds,
      center: center,
      geometryEvidence: decoded['geometryEvidence'] as String,
    );
  }

  void writeAtomic(File output) {
    if (output.existsSync() || Link(output.path).existsSync()) {
      throw FileSystemException(
        'Selection output already exists.',
        output.path,
      );
    }
    final temporary = File('${output.path}.tmp.$pid');
    try {
      temporary.writeAsStringSync('${jsonEncode(toJson())}\n', flush: true);
      temporary.renameSync(output.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }
}

List<int> _exactIntList(Object? value, int length, String label) {
  if (value is! List<dynamic> ||
      value.length != length ||
      value.any((entry) => entry is! int)) {
    throw FormatException('Selection $label was invalid.');
  }
  return value.cast<int>();
}
