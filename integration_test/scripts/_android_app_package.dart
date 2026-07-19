import 'dart:io';

import '../../tool/sims/android_app_package.dart';

export '../../tool/sims/android_app_package.dart'
    show
        isValidAndroidAppPackage,
        resolveAndroidAppPackageFromSources,
        validateAndroidAppPackage;

String resolveAndroidAppPackage() {
  final localProperties = File('android/local.properties');
  return resolveAndroidAppPackageFromSources(
    environmentValue: Platform.environment['ANDROID_APP_PACKAGE'],
    simsApplicationId: Platform.environment['SIMS_APP_ID'],
    gradleApplicationId:
        Platform.environment['ORG_GRADLE_PROJECT_androidApplicationId'],
    localPropertyLines: localProperties.existsSync()
        ? localProperties.readAsLinesSync()
        : null,
  );
}
