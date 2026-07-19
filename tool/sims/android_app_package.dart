const defaultAndroidAppPackage = 'com.mknoon.app';

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

/// Resolves the application ID shared by the central Android build and its
/// host-side device runner.
///
/// An explicitly supplied but invalid value fails closed instead of silently
/// selecting a lower-precedence package and driving the wrong installed app.
String resolveAndroidAppPackageFromSources({
  required String? environmentValue,
  String? simsApplicationId,
  String? gradleApplicationId,
  required Iterable<String>? localPropertyLines,
}) {
  final envValue = environmentValue;
  if (envValue != null && envValue.isNotEmpty) {
    return validateAndroidAppPackage(envValue, source: 'ANDROID_APP_PACKAGE');
  }

  final simsValue = simsApplicationId?.trim();
  if (simsValue != null && simsValue.isNotEmpty) {
    return validateAndroidAppPackage(simsValue, source: 'SIMS_APP_ID');
  }

  final gradleValue = gradleApplicationId?.trim();
  if (gradleValue != null && gradleValue.isNotEmpty) {
    return validateAndroidAppPackage(
      gradleValue,
      source: 'ORG_GRADLE_PROJECT_androidApplicationId',
    );
  }

  final localValue = javaPropertyValue(
    localPropertyLines,
    'android.applicationId',
  );
  if (localValue != null) {
    return validateAndroidAppPackage(
      localValue,
      source: 'android.applicationId',
    );
  }

  return validateAndroidAppPackage(defaultAndroidAppPackage, source: 'default');
}

/// Reads a Java property using its whitespace, `:`, or `=` separator forms.
///
/// Leading whitespace and comment lines follow the forms used by Java
/// property files. Escaped keys and continuation lines are intentionally not
/// accepted for this security-sensitive application-ID setting.
String? javaPropertyValue(Iterable<String>? lines, String key) {
  if (lines == null) return null;
  final keyPattern = RegExp.escape(key);
  final propertyPattern = RegExp('^$keyPattern(?:\\s*[:=]\\s*|\\s+)(.*)\$');
  for (final rawLine in lines) {
    final line = rawLine.trimLeft();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) {
      continue;
    }
    final match = propertyPattern.firstMatch(line);
    if (match != null) return match.group(1)!.trim();
    if (line == key) return '';
  }
  return null;
}
