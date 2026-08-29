import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../../integration_test/support/android_picture_in_picture_system_ui_control.dart';

void main() {
  const liveBounds = AndroidPictureInPictureBounds(
    left: 389,
    top: 1570,
    right: 910,
    bottom: 1863,
  );

  test('selects the one hittable SystemUI expand resource inside live PiP', () {
    final xml = File(
      'test/fixtures/android_picture_in_picture_system_ui_menu.xml',
    ).readAsStringSync();

    final control = selectAndroidPictureInPictureSystemUiControl(
      xml,
      action: AndroidPictureInPictureSystemUiAction.expand,
      pictureInPictureBounds: liveBounds,
    );

    expect(control.selectorSource, 'resource-id');
    expect(control.resourceId, 'com.android.systemui:id/expand_button');
    expect(control.contentDescription, 'Full screen');
    expect(control.bounds.toString(), '405 1586 517 1698');
    expect((control.bounds.centerX, control.bounds.centerY), (461, 1642));
  });

  test('selects the distinct close resource from the same menu', () {
    final xml = File(
      'test/fixtures/android_picture_in_picture_system_ui_menu.xml',
    ).readAsStringSync();

    final control = selectAndroidPictureInPictureSystemUiControl(
      xml,
      action: AndroidPictureInPictureSystemUiAction.close,
      pictureInPictureBounds: liveBounds,
    );

    expect(control.selectorSource, 'resource-id');
    expect(control.resourceId, 'com.android.systemui:id/dismiss');
    expect((control.bounds.centerX, control.bounds.centerY), (838, 1642));
  });

  test('falls back to one exact accessibility label', () {
    const xml = '''
<hierarchy>
  <node resource-id="" content-desc="Enter fullscreen" clickable="true"
      enabled="true" visible-to-user="true" bounds="[500,1600][620,1720]" />
</hierarchy>
''';

    final control = selectAndroidPictureInPictureSystemUiControl(
      xml,
      action: AndroidPictureInPictureSystemUiAction.expand,
      pictureInPictureBounds: liveBounds,
    );

    expect(control.selectorSource, 'content-desc');
    expect(control.contentDescription, 'Enter fullscreen');
  });

  test('fails closed when matching resource IDs are ambiguous', () {
    const xml = '''
<hierarchy>
  <node resource-id="com.android.systemui:id/expand_button"
      content-desc="Full screen" clickable="true" enabled="true"
      visible-to-user="true" bounds="[400,1600][500,1700]" />
  <node resource-id="com.android.wm.shell:id/expand_button"
      content-desc="Full screen" clickable="true" enabled="true"
      visible-to-user="true" bounds="[520,1600][620,1700]" />
</hierarchy>
''';

    expect(
      () => selectAndroidPictureInPictureSystemUiControl(
        xml,
        action: AndroidPictureInPictureSystemUiAction.expand,
        pictureInPictureBounds: liveBounds,
      ),
      throwsA(
        isA<AndroidPictureInPictureSystemUiSelectionException>().having(
          (error) => error.message,
          'message',
          contains('found 2'),
        ),
      ),
    );
  });

  test('rejects hidden, disabled, non-clickable, and out-of-bounds nodes', () {
    const xml = '''
<hierarchy>
  <node resource-id="com.android.systemui:id/expand_button"
      content-desc="Full screen" clickable="true" enabled="true"
      visible-to-user="false" bounds="[400,1600][500,1700]" />
  <node resource-id="com.android.systemui:id/expand_button"
      content-desc="Full screen" clickable="true" enabled="false"
      visible-to-user="true" bounds="[520,1600][620,1700]" />
  <node resource-id="com.android.systemui:id/expand_button"
      content-desc="Full screen" clickable="false" enabled="true"
      visible-to-user="true" bounds="[640,1600][740,1700]" />
  <node resource-id="com.android.systemui:id/expand_button"
      content-desc="Full screen" clickable="true" enabled="true"
      visible-to-user="true" bounds="[950,100][1050,200]" />
</hierarchy>
''';

    expect(
      () => selectAndroidPictureInPictureSystemUiControl(
        xml,
        action: AndroidPictureInPictureSystemUiAction.expand,
        pictureInPictureBounds: liveBounds,
      ),
      throwsA(
        isA<AndroidPictureInPictureSystemUiSelectionException>().having(
          (error) => error.message,
          'message',
          contains('found 0'),
        ),
      ),
    );
  });

  test('accepted Pixel 6 API 36 probe selects the expand glyph center', () {
    final probe = _loadPixel6Probe();

    final selection = selectPixel6Api36PictureInPictureSystemUiGeometry(
      screenshot: probe.screenshot,
      action: AndroidPictureInPictureSystemUiAction.expand,
      pictureInPictureBounds: probe.bounds,
      environment: probe.environment,
    );

    expect((selection.centerX, selection.centerY), (649, 2148));
    expect(selection.evidence, contains('420dpi'));
  });

  test('accepted geometry derives the distinct close control center', () {
    final probe = _loadPixel6Probe();

    final selection = selectPixel6Api36PictureInPictureSystemUiGeometry(
      screenshot: probe.screenshot,
      action: AndroidPictureInPictureSystemUiAction.close,
      pictureInPictureBounds: probe.bounds,
      environment: probe.environment,
    );

    expect((selection.centerX, selection.centerY), (846, 2066));
  });

  test('accepts the reviewed larger API 36 WMShell PiP geometry', () {
    final probe = _loadPixel6Probe();
    const largerBounds = AndroidPictureInPictureBounds(
      left: 350,
      top: 1980,
      right: 948,
      bottom: 2316,
    );

    final selection = selectPixel6Api36PictureInPictureSystemUiGeometry(
      screenshot: probe.screenshot,
      action: AndroidPictureInPictureSystemUiAction.expand,
      pictureInPictureBounds: largerBounds,
      environment: probe.environment,
    );

    expect((selection.centerX, selection.centerY), (649, 2148));
    expect(selection.evidence, contains('pip598x336'));
  });

  test('geometry fallback fails closed when the expand glyph is absent', () {
    final probe = _loadPixel6Probe();
    _fillRegion(
      probe.screenshot,
      left: probe.bounds.centerX - 32,
      top: probe.bounds.centerY - 32,
      right: probe.bounds.centerX - 6,
      bottom: probe.bounds.centerY - 6,
      red: 0,
      green: 0,
      blue: 0,
    );

    expect(
      () => selectPixel6Api36PictureInPictureSystemUiGeometry(
        screenshot: probe.screenshot,
        action: AndroidPictureInPictureSystemUiAction.expand,
        pictureInPictureBounds: probe.bounds,
        environment: probe.environment,
      ),
      throwsA(
        isA<AndroidPictureInPictureSystemUiSelectionException>().having(
          (error) => error.message,
          'message',
          contains('expand top-left corner'),
        ),
      ),
    );
  });

  test('geometry fallback rejects any environment drift', () {
    final probe = _loadPixel6Probe();

    expect(
      () => selectPixel6Api36PictureInPictureSystemUiGeometry(
        screenshot: probe.screenshot,
        action: AndroidPictureInPictureSystemUiAction.expand,
        pictureInPictureBounds: probe.bounds,
        environment: AndroidPictureInPictureGeometryEnvironment(
          deviceCodename: probe.environment.deviceCodename,
          deviceModel: probe.environment.deviceModel,
          sdk: probe.environment.sdk,
          displayWidth: probe.environment.displayWidth,
          displayHeight: probe.environment.displayHeight,
          displayDensity: 440,
          rotation: probe.environment.rotation,
        ),
      ),
      throwsA(
        isA<AndroidPictureInPictureSystemUiSelectionException>().having(
          (error) => error.message,
          'message',
          contains('environment did not match'),
        ),
      ),
    );
  });

  test('captured stale bounds cannot stand in for immediate live bounds', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/android_picture_in_picture_pixel6_stale_bounds_probe.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final stale = _boundsFromJson(fixture['staleCaptureBounds']);
    final live = _boundsFromJson(fixture['liveScreenshotBounds']);

    expect((stale.centerX, stale.centerY), (649, 1716));
    expect((live.centerX, live.centerY), (649, 2148));
    expect(live.containsCenterOf(stale), isFalse);
    expect(live.containsCenterOf(live), isTrue);
  });
}

AndroidPictureInPictureBounds _boundsFromJson(Object? value) {
  final coordinates = (value! as List<dynamic>).cast<int>();
  return AndroidPictureInPictureBounds(
    left: coordinates[0],
    top: coordinates[1],
    right: coordinates[2],
    bottom: coordinates[3],
  );
}

({
  image.Image screenshot,
  AndroidPictureInPictureBounds bounds,
  AndroidPictureInPictureGeometryEnvironment environment,
})
_loadPixel6Probe() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/android_picture_in_picture_pixel6_api36_expand_probe.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final display = (fixture['display'] as List<dynamic>).cast<int>();
  final boundsValues = (fixture['pipBounds'] as List<dynamic>).cast<int>();
  final bounds = AndroidPictureInPictureBounds(
    left: boundsValues[0],
    top: boundsValues[1],
    right: boundsValues[2],
    bottom: boundsValues[3],
  );
  final screenshot = image.Image(
    width: display[0],
    height: display[1],
    numChannels: 4,
  );
  final counts = fixture['brightPixelCounts'] as Map<String, dynamic>;
  _paintBrightPixels(
    screenshot,
    left: bounds.centerX - 32,
    top: bounds.centerY - 32,
    right: bounds.centerX - 6,
    bottom: bounds.centerY - 6,
    count: counts['topLeft']! as int,
  );
  _paintBrightPixels(
    screenshot,
    left: bounds.centerX - 32,
    top: bounds.centerY + 6,
    right: bounds.centerX - 6,
    bottom: bounds.centerY + 32,
    count: counts['bottomLeft']! as int,
  );
  _paintBrightPixels(
    screenshot,
    left: bounds.centerX + 6,
    top: bounds.centerY - 32,
    right: bounds.centerX + 32,
    bottom: bounds.centerY - 6,
    count: counts['topRight']! as int,
  );
  _paintBrightPixels(
    screenshot,
    left: bounds.centerX + 6,
    top: bounds.centerY + 6,
    right: bounds.centerX + 32,
    bottom: bounds.centerY + 32,
    count: counts['bottomRight']! as int,
  );
  return (
    screenshot: screenshot,
    bounds: bounds,
    environment: AndroidPictureInPictureGeometryEnvironment(
      deviceCodename: fixture['deviceCodename']! as String,
      deviceModel: fixture['deviceModel']! as String,
      sdk: fixture['sdk']! as int,
      displayWidth: display[0],
      displayHeight: display[1],
      displayDensity: fixture['density']! as int,
      rotation: fixture['rotation']! as int,
    ),
  );
}

void _paintBrightPixels(
  image.Image screenshot, {
  required int left,
  required int top,
  required int right,
  required int bottom,
  required int count,
}) {
  var remaining = count;
  for (var y = top; y <= bottom && remaining > 0; y++) {
    for (var x = left; x <= right && remaining > 0; x++) {
      screenshot.setPixelRgb(x, y, 255, 255, 255);
      remaining--;
    }
  }
  if (remaining != 0) {
    throw StateError('Probe count exceeded its target region.');
  }
}

void _fillRegion(
  image.Image screenshot, {
  required int left,
  required int top,
  required int right,
  required int bottom,
  required int red,
  required int green,
  required int blue,
}) {
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      screenshot.setPixelRgb(x, y, red, green, blue);
    }
  }
}
