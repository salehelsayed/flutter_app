import 'dart:io';

const _defaultAndroidAppPackage = 'com.mknoon.app';
final RegExp _androidAppPackagePattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
);

bool isValidAndroidAppPackage(String value) {
  final match = _androidAppPackagePattern.firstMatch(value);
  return match != null && match.start == 0 && match.end == value.length;
}

String validateAndroidAppPackage(String value, {required String source}) {
  if (!isValidAndroidAppPackage(value)) {
    throw FormatException('invalid Android application ID from $source');
  }
  return value;
}

String resolveAndroidAppPackage() {
  final localProperties = File('android/local.properties');
  return resolveAndroidAppPackageFromSources(
    environmentValue: Platform.environment['ANDROID_APP_PACKAGE'],
    localPropertyLines: localProperties.existsSync()
        ? localProperties.readAsLinesSync()
        : null,
  );
}

String resolveAndroidAppPackageFromSources({
  required String? environmentValue,
  required Iterable<String>? localPropertyLines,
}) {
  final envValue = environmentValue;
  if (envValue != null && envValue.isNotEmpty) {
    return validateAndroidAppPackage(envValue, source: 'ANDROID_APP_PACKAGE');
  }

  if (localPropertyLines != null) {
    for (final rawLine in localPropertyLines) {
      final line = rawLine.trim();
      if (line.startsWith('android.applicationId=')) {
        final value = line.substring('android.applicationId='.length).trim();
        return validateAndroidAppPackage(
          value,
          source: 'android.applicationId',
        );
      }
    }
  }

  return validateAndroidAppPackage(
    _defaultAndroidAppPackage,
    source: 'default',
  );
}
