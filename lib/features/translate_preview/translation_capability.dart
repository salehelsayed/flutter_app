import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum TranslationPlatform { ios, android, other }

// Approved conservative policy inferences for nominal 4/6 GB phones, pending
// calibration against OS-reported RAM. These are not plugin requirements.
const _iosMinimumPhysicalMemoryBytes = 7 * (1 << 29); // 3.5 GiB.
const _androidMinimumPhysicalMemoryBytes = 11 * (1 << 29); // 5.5 GiB.

const _capabilityChannel = MethodChannel('mknoon/gemma_preview');

/// Whether the supplied device facts meet the translation policy.
/// [osMajor] is the iOS major version or Android SDK/API level.
/// [isArm64] describes the running process, not the device's supported ABIs.
bool supportsOnDeviceTranslation({
  required TranslationPlatform platform,
  required int physicalMemoryBytes,
  required int osMajor,
  required bool isArm64,
}) {
  if (!isArm64) return false;

  return switch (platform) {
    TranslationPlatform.ios =>
      osMajor >= 15 && physicalMemoryBytes >= _iosMinimumPhysicalMemoryBytes,
    TranslationPlatform.android =>
      osMajor >= 30 &&
          physicalMemoryBytes >= _androidMinimumPhysicalMemoryBytes,
    TranslationPlatform.other => false,
  };
}

/// Reads capability without loading the model. Unavailable facts fail closed.
/// Optional [platform] and [processAbi] facts are for host tests; production
/// callers use the runtime defaults.
Future<bool> readTranslationCapability({
  TranslationPlatform? platform,
  Abi? processAbi,
}) async {
  int? observedMemoryBytes;
  int? observedOsMajor;
  Abi? observedAbi;
  var osKey = 'osVersionOrSdk';
  var supported = false;
  try {
    final actualPlatform =
        platform ??
        (Platform.isIOS
            ? TranslationPlatform.ios
            : Platform.isAndroid
            ? TranslationPlatform.android
            : TranslationPlatform.other);
    if (actualPlatform == TranslationPlatform.other) return false;

    final actualAbi = processAbi ?? Abi.current();
    observedAbi = actualAbi;
    final requiredAbi = actualPlatform == TranslationPlatform.ios
        ? Abi.iosArm64
        : Abi.androidArm64;
    if (actualAbi != requiredAbi) return false;

    final facts = await _capabilityChannel.invokeMapMethod<String, Object?>(
      'deviceCapabilities',
    );
    final physicalMemoryBytes = facts?['physicalMemoryBytes'];
    osKey = actualPlatform == TranslationPlatform.ios
        ? 'osVersionMajor'
        : 'sdkInt';
    final osMajor = facts?[osKey];
    if (physicalMemoryBytes is int && physicalMemoryBytes > 0) {
      observedMemoryBytes = physicalMemoryBytes;
    }
    if (osMajor is int && osMajor > 0) observedOsMajor = osMajor;
    if (observedMemoryBytes == null || observedOsMajor == null) {
      return false;
    }

    supported = supportsOnDeviceTranslation(
      platform: actualPlatform,
      physicalMemoryBytes: observedMemoryBytes,
      osMajor: observedOsMajor,
      isArm64: true,
    );
    return supported;
  } on Object {
    return false;
  } finally {
    debugPrint(
      'TRANSLATION_CAPABILITY '
      'physicalMemoryBytes=${observedMemoryBytes ?? 'unknown'} '
      '$osKey=${observedOsMajor ?? 'unknown'} '
      'abi=${observedAbi ?? 'unknown'} supported=$supported',
    );
  }
}
