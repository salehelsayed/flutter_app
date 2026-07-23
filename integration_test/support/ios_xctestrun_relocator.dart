import 'dart:io';

final class IosXctestrunRelocation {
  const IosXctestrunRelocation({
    required this.plist,
    required this.uiTargetsPatched,
    required this.productPathsPatched,
  });

  final Map<String, Object?> plist;
  final int uiTargetsPatched;
  final int productPathsPatched;
}

/// Relocates a build-for-testing plist after its Products directory has moved
/// into the content-addressed Sims cache.
///
/// Both Xcode's `__TESTROOT__` macro form and absolute DerivedData
/// `/Build/Products/` paths are handled. The exact cached app is pinned as the
/// UI target, and only the RunnerUITests target receives fixture variables.
IosXctestrunRelocation relocateIosXctestrun({
  required Map<String, Object?> plist,
  required Directory cachedProducts,
  required Directory cachedApplication,
  required Map<String, String> uiEnvironment,
  String uiTargetBundleIdentifier = 'com.mknoon.app',
}) {
  if (!RegExp(
    r'^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$',
  ).hasMatch(uiTargetBundleIdentifier)) {
    throw FormatException(
      'Unsafe UI target bundle identifier: $uiTargetBundleIdentifier',
    );
  }
  final patcher = _Relocator(
    products: cachedProducts,
    application: cachedApplication,
    environment: uiEnvironment,
    targetBundleIdentifier: uiTargetBundleIdentifier,
  );
  final relocated = patcher.patch(plist);
  return IosXctestrunRelocation(
    plist: relocated,
    uiTargetsPatched: patcher.uiTargetsPatched,
    productPathsPatched: patcher.productPathsPatched,
  );
}

List<String> iosTestWithoutBuildingArguments({
  required File xctestrun,
  required String receiverDeviceId,
  required String selector,
  required Directory resultBundle,
}) {
  final validatedSelector = validatedIosUiTestSelector(selector);
  return <String>[
    'test-without-building',
    '-xctestrun',
    xctestrun.path,
    '-destination',
    'platform=iOS,id=$receiverDeviceId',
    '-parallel-testing-enabled',
    'NO',
    '-only-testing:$validatedSelector',
    '-resultBundlePath',
    resultBundle.path,
  ];
}

/// Returns one safe Xcode UI-test selector.
///
/// Existing notification callers may continue to pass a bare method name; it
/// is resolved against NotificationTapUITests. New callers use the explicit
/// `RunnerUITests/Class/method` form so the shared prebuilt bundle can run a
/// focused controller without rebuilding or widening the selected test suite.
String validatedIosUiTestSelector(String selector) {
  final value = selector.trim();
  final fullSelector = value.contains('/')
      ? value
      : 'RunnerUITests/NotificationTapUITests/$value';
  if (!RegExp(
    r'^RunnerUITests/[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*$',
  ).hasMatch(fullSelector)) {
    throw FormatException('Unsafe RunnerUITests selector: $selector');
  }
  return fullSelector;
}

final class _Relocator {
  _Relocator({
    required this.products,
    required this.application,
    required this.environment,
    required this.targetBundleIdentifier,
  });

  final Directory products;
  final Directory application;
  final Map<String, String> environment;
  final String targetBundleIdentifier;
  int uiTargetsPatched = 0;
  int productPathsPatched = 0;

  Map<String, Object?> patch(Map<String, Object?> input) =>
      _patchValue(input) as Map<String, Object?>;

  Object? _patchValue(Object? value) {
    if (value is List) {
      return value.map<Object?>(_patchValue).toList(growable: false);
    }
    if (value is! Map) {
      return value is String ? _patchString(value) : value;
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      result['${entry.key}'] = _patchValue(entry.value);
    }
    final testBundle = result['TestBundlePath'];
    if (testBundle is String && testBundle.contains('RunnerUITests')) {
      uiTargetsPatched += 1;
      result['UITargetAppPath'] = application.path;
      result['UITargetAppBundleIdentifier'] = targetBundleIdentifier;
      result['EnvironmentVariables'] = <String, Object?>{
        if (result['EnvironmentVariables'] is Map)
          for (final entry in (result['EnvironmentVariables']! as Map).entries)
            '${entry.key}': entry.value,
        ...environment,
      };
    }
    return result;
  }

  String _patchString(String value) {
    const marker = '/Build/Products/';
    final markerIndex = value.indexOf(marker);
    if (markerIndex >= 0) {
      productPathsPatched += 1;
      final suffix = value.substring(markerIndex + marker.length);
      return '${products.path}${Platform.pathSeparator}$suffix';
    }
    if (value == '__TESTROOT__') {
      productPathsPatched += 1;
      return products.path;
    }
    if (value.startsWith('__TESTROOT__/')) {
      productPathsPatched += 1;
      return '${products.path}${Platform.pathSeparator}'
          '${value.substring('__TESTROOT__/'.length)}';
    }
    return value;
  }
}
