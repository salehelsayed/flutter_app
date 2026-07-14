import 'package:image/image.dart' as image;

class AndroidPictureInPictureBounds {
  const AndroidPictureInPictureBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get centerX => (left + right) ~/ 2;
  int get centerY => (top + bottom) ~/ 2;
  bool get isHittable => right > left && bottom > top;

  bool containsCenterOf(AndroidPictureInPictureBounds candidate) {
    return candidate.centerX >= left &&
        candidate.centerX <= right &&
        candidate.centerY >= top &&
        candidate.centerY <= bottom;
  }

  @override
  String toString() => '$left $top $right $bottom';
}

enum AndroidPictureInPictureSystemUiAction { expand, close }

class AndroidPictureInPictureSystemUiControl {
  const AndroidPictureInPictureSystemUiControl({
    required this.action,
    required this.selectorSource,
    required this.resourceId,
    required this.contentDescription,
    required this.bounds,
  });

  final AndroidPictureInPictureSystemUiAction action;
  final String selectorSource;
  final String resourceId;
  final String contentDescription;
  final AndroidPictureInPictureBounds bounds;
}

class AndroidPictureInPictureSystemUiSelectionException implements Exception {
  const AndroidPictureInPictureSystemUiSelectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AndroidPictureInPictureGeometryEnvironment {
  const AndroidPictureInPictureGeometryEnvironment({
    required this.deviceCodename,
    required this.deviceModel,
    required this.sdk,
    required this.displayWidth,
    required this.displayHeight,
    required this.displayDensity,
    required this.rotation,
  });

  final String deviceCodename;
  final String deviceModel;
  final int sdk;
  final int displayWidth;
  final int displayHeight;
  final int displayDensity;
  final int rotation;
}

class AndroidPictureInPictureGeometrySelection {
  const AndroidPictureInPictureGeometrySelection({
    required this.action,
    required this.centerX,
    required this.centerY,
    required this.evidence,
  });

  final AndroidPictureInPictureSystemUiAction action;
  final int centerX;
  final int centerY;
  final String evidence;
}

/// Selects one API-36 WMShell control only for the reviewed Pixel 6 geometry.
///
/// Pixel API 36 renders the PiP menu in a Surface-hosted WMShell layer which
/// is visible in screencaps but absent from UIAutomator. This fallback binds
/// the device, display, rotation, live PiP dimensions, and the four-corner
/// AOSP `expand_button` glyph over the reviewed SMPTE fixture before deriving
/// one control center from the live bounds.
AndroidPictureInPictureGeometrySelection
selectPixel6Api36PictureInPictureSystemUiGeometry({
  required image.Image screenshot,
  required AndroidPictureInPictureSystemUiAction action,
  required AndroidPictureInPictureBounds pictureInPictureBounds,
  required AndroidPictureInPictureGeometryEnvironment environment,
}) {
  if (environment.deviceCodename != 'oriole' ||
      environment.deviceModel != 'Pixel 6' ||
      environment.sdk != 36 ||
      environment.displayWidth != 1080 ||
      environment.displayHeight != 2400 ||
      environment.displayDensity != 420 ||
      environment.rotation != 0) {
    throw const AndroidPictureInPictureSystemUiSelectionException(
      'Pixel 6 API 36 WMShell geometry environment did not match.',
    );
  }
  if (screenshot.width != environment.displayWidth ||
      screenshot.height != environment.displayHeight) {
    throw const AndroidPictureInPictureSystemUiSelectionException(
      'Post-reveal screenshot dimensions did not match the live display.',
    );
  }
  if (pictureInPictureBounds.right - pictureInPictureBounds.left != 521 ||
      pictureInPictureBounds.bottom - pictureInPictureBounds.top != 293 ||
      pictureInPictureBounds.left < 0 ||
      pictureInPictureBounds.top < 0 ||
      pictureInPictureBounds.right > screenshot.width ||
      pictureInPictureBounds.bottom > screenshot.height) {
    throw const AndroidPictureInPictureSystemUiSelectionException(
      'Live PiP bounds did not match the reviewed 521x293 Pixel geometry.',
    );
  }

  final centerX = pictureInPictureBounds.centerX;
  final centerY = pictureInPictureBounds.centerY;
  _requireBrightPixelCount(
    screenshot,
    left: centerX - 32,
    top: centerY - 32,
    right: centerX - 6,
    bottom: centerY - 6,
    minimum: 100,
    maximum: 160,
    label: 'expand top-left corner',
  );
  _requireBrightPixelCount(
    screenshot,
    left: centerX - 32,
    top: centerY + 6,
    right: centerX - 6,
    bottom: centerY + 32,
    minimum: 100,
    maximum: 160,
    label: 'expand bottom-left corner',
  );
  _requireBrightPixelCount(
    screenshot,
    left: centerX + 6,
    top: centerY - 32,
    right: centerX + 32,
    bottom: centerY - 6,
    minimum: 100,
    maximum: 160,
    label: 'expand top-right corner',
  );
  _requireBrightPixelCount(
    screenshot,
    left: centerX + 6,
    top: centerY + 6,
    right: centerX + 32,
    bottom: centerY + 32,
    minimum: 100,
    maximum: 160,
    label: 'expand bottom-right corner',
  );
  _requireBrightPixelCount(
    screenshot,
    left: centerX - 6,
    top: centerY - 6,
    right: centerX + 6,
    bottom: centerY + 6,
    minimum: 0,
    maximum: 5,
    label: 'expand center gap',
  );

  return AndroidPictureInPictureGeometrySelection(
    action: action,
    centerX: action == AndroidPictureInPictureSystemUiAction.expand
        ? centerX
        : pictureInPictureBounds.right - 64,
    centerY: action == AndroidPictureInPictureSystemUiAction.expand
        ? centerY
        : pictureInPictureBounds.top + 64,
    evidence:
        'pixel6-api36-1080x2400-420dpi-rotation0-pip521x293-expand-glyph-v1',
  );
}

void _requireBrightPixelCount(
  image.Image screenshot, {
  required int left,
  required int top,
  required int right,
  required int bottom,
  required int minimum,
  required int maximum,
  required String label,
}) {
  var brightPixels = 0;
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      final pixel = screenshot.getPixel(x, y);
      if (pixel.r >= 240 && pixel.g >= 240 && pixel.b >= 240) {
        brightPixels++;
      }
    }
  }
  if (brightPixels < minimum || brightPixels > maximum) {
    throw AndroidPictureInPictureSystemUiSelectionException(
      '$label did not match the accepted probe: $brightPixels bright pixels.',
    );
  }
}

const _resourceIdsByAction =
    <AndroidPictureInPictureSystemUiAction, Set<String>>{
      AndroidPictureInPictureSystemUiAction.expand: {
        'com.android.systemui:id/expand_button',
        'com.android.systemui:id/fullscreen_button',
        'com.android.wm.shell:id/expand_button',
        'com.android.wm.shell:id/fullscreen_button',
      },
      AndroidPictureInPictureSystemUiAction.close: {
        'com.android.systemui:id/dismiss',
        'com.android.systemui:id/close_button',
        'com.android.systemui:id/dismiss_button',
        'com.android.wm.shell:id/dismiss',
        'com.android.wm.shell:id/close_button',
        'com.android.wm.shell:id/dismiss_button',
      },
    };

const _contentDescriptionsByAction =
    <AndroidPictureInPictureSystemUiAction, Set<String>>{
      AndroidPictureInPictureSystemUiAction.expand: {
        'expand',
        'expand picture in picture',
        'expand to full screen',
        'enter full screen',
        'enter fullscreen',
        'full screen',
        'fullscreen',
      },
      AndroidPictureInPictureSystemUiAction.close: {
        'close',
        'close picture in picture',
        'dismiss',
        'dismiss picture in picture',
      },
    };

AndroidPictureInPictureSystemUiControl
selectAndroidPictureInPictureSystemUiControl(
  String xml, {
  required AndroidPictureInPictureSystemUiAction action,
  required AndroidPictureInPictureBounds pictureInPictureBounds,
}) {
  if (!pictureInPictureBounds.isHittable) {
    throw const AndroidPictureInPictureSystemUiSelectionException(
      'Live picture-in-picture bounds are not hittable.',
    );
  }

  final eligible = <_SystemUiNode>[];
  for (final match in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final raw = match.group(0)!;
    if (_attribute(raw, 'enabled') != 'true' ||
        _attribute(raw, 'clickable') != 'true' ||
        _attribute(raw, 'visible-to-user') != 'true') {
      continue;
    }
    final bounds = _bounds(raw);
    if (bounds == null ||
        !bounds.isHittable ||
        !pictureInPictureBounds.containsCenterOf(bounds)) {
      continue;
    }
    eligible.add(
      _SystemUiNode(
        resourceId: _attribute(raw, 'resource-id'),
        contentDescription: _xmlDecode(_attribute(raw, 'content-desc')),
        bounds: bounds,
      ),
    );
  }

  final resourceIds = _resourceIdsByAction[action]!;
  final resourceMatches = eligible
      .where((node) => resourceIds.contains(node.resourceId))
      .toList(growable: false);
  if (resourceMatches.isNotEmpty) {
    return _requireExactlyOne(
      action: action,
      selectorSource: 'resource-id',
      matches: resourceMatches,
    );
  }

  final allowedDescriptions = _contentDescriptionsByAction[action]!;
  final descriptionMatches = eligible
      .where(
        (node) => allowedDescriptions.contains(
          _normalizeDescription(node.contentDescription),
        ),
      )
      .toList(growable: false);
  return _requireExactlyOne(
    action: action,
    selectorSource: 'content-desc',
    matches: descriptionMatches,
  );
}

AndroidPictureInPictureSystemUiControl _requireExactlyOne({
  required AndroidPictureInPictureSystemUiAction action,
  required String selectorSource,
  required List<_SystemUiNode> matches,
}) {
  if (matches.length != 1) {
    throw AndroidPictureInPictureSystemUiSelectionException(
      'Expected exactly one visible, enabled, clickable SystemUI '
      '${action.name} control selected by $selectorSource; found '
      '${matches.length}.',
    );
  }
  final match = matches.single;
  return AndroidPictureInPictureSystemUiControl(
    action: action,
    selectorSource: selectorSource,
    resourceId: match.resourceId,
    contentDescription: match.contentDescription,
    bounds: match.bounds,
  );
}

String _attribute(String node, String name) {
  return RegExp('$name="([^"]*)"').firstMatch(node)?.group(1) ?? '';
}

AndroidPictureInPictureBounds? _bounds(String node) {
  final match = RegExp(
    r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
  ).firstMatch(node);
  if (match == null) return null;
  return AndroidPictureInPictureBounds(
    left: int.parse(match.group(1)!),
    top: int.parse(match.group(2)!),
    right: int.parse(match.group(3)!),
    bottom: int.parse(match.group(4)!),
  );
}

String _normalizeDescription(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

String _xmlDecode(String value) {
  return value
      .replaceAll('&#10;', '\n')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

class _SystemUiNode {
  const _SystemUiNode({
    required this.resourceId,
    required this.contentDescription,
    required this.bounds,
  });

  final String resourceId;
  final String contentDescription;
  final AndroidPictureInPictureBounds bounds;
}
