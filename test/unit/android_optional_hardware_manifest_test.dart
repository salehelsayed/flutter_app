import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _androidNamespace = 'http://schemas.android.com/apk/res/android';
const _manifestPath = String.fromEnvironment(
  'MKNOON_ANDROID_MANIFEST_UNDER_TEST',
  defaultValue: 'android/app/src/main/AndroidManifest.xml',
);

void main() {
  late XmlElement manifest;
  setUpAll(() {
    manifest = XmlDocument.parse(File(_manifestPath).readAsStringSync())
        .rootElement;
  });

  for (final name in const [
    'android.hardware.wifi',
    'android.hardware.bluetooth',
    'android.hardware.location',
    'android.hardware.microphone',
  ]) {
    test('$name is explicitly optional', () {
      final declarations = manifest
          .findElements('uses-feature')
          .where(
            (feature) =>
                feature.getAttribute('name', namespace: _androidNamespace) ==
                name,
          );
      expect(
        declarations.map(
          (feature) =>
              feature.getAttribute('required', namespace: _androidNamespace),
        ),
        <String?>['false'],
      );
    });
  }
}
