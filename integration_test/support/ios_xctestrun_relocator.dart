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
}) {
  final patcher = _Relocator(
    products: cachedProducts,
    application: cachedApplication,
    environment: uiEnvironment,
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
}) => <String>[
  'test-without-building',
  '-xctestrun',
  xctestrun.path,
  '-destination',
  'platform=iOS,id=$receiverDeviceId',
  '-parallel-testing-enabled',
  'NO',
  '-only-testing:RunnerUITests/NotificationTapUITests/$selector',
  '-resultBundlePath',
  resultBundle.path,
];

final class _Relocator {
  _Relocator({
    required this.products,
    required this.application,
    required this.environment,
  });

  final Directory products;
  final Directory application;
  final Map<String, String> environment;
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
      result['UITargetAppBundleIdentifier'] = 'com.mknoon.app';
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
