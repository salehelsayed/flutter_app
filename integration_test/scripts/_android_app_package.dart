import 'dart:io';

const _defaultAndroidAppPackage = 'com.mknoon.app';

String resolveAndroidAppPackage() {
  final envValue = Platform.environment['ANDROID_APP_PACKAGE']?.trim();
  if (envValue != null && envValue.isNotEmpty) {
    return envValue;
  }

  final localProperties = File('android/local.properties');
  if (!localProperties.existsSync()) {
    return _defaultAndroidAppPackage;
  }

  for (final rawLine in localProperties.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.startsWith('android.applicationId=')) {
      final value = line.substring('android.applicationId='.length).trim();
      if (value.isNotEmpty) return value;
    }
  }

  return _defaultAndroidAppPackage;
}
