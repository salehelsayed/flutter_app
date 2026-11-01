import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum TranslationPlatform { ios, android, other }

// Approved conservative policy inferences for nominal 4/6 GB phones, pending
// calibration against OS-reported RAM. These are not plugin requirements.
const _iosMinimumPhysicalMemoryBytes = 7 * (1 << 29); // 3.5 GiB.
// Nominal 6 GB Android phones can report less than 5.5 GiB to the kernel.
const _androidMinimumPhysicalMemoryBytes = 9 * (1 << 29); // 4.5 GiB.
const _androidMinimumAvailableMemoryBytes =
    7 * (1 << 28); // 1.75 GiB cold load.
const _iosMinimumAvailableMemoryBytes = 5 * (1 << 29); // 2.5 GiB cold load.

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
}) async => (await readTranslationCapabilityFacts(
  platform: platform,
  processAbi: processAbi,
)).supported;

/// Keeps a measured RAM rejection distinct from API/ABI or unavailable facts.
Future<({bool supported, bool insufficientMemory})>
readTranslationCapabilityFacts({
  TranslationPlatform? platform,
  Abi? processAbi,
}) async {
  const unknown = (supported: false, insufficientMemory: false);
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
    if (actualPlatform == TranslationPlatform.other) return unknown;

    final actualAbi = processAbi ?? Abi.current();
    observedAbi = actualAbi;
    final requiredAbi = actualPlatform == TranslationPlatform.ios
        ? Abi.iosArm64
        : Abi.androidArm64;
    if (actualAbi != requiredAbi) return unknown;

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
      return unknown;
    }

    supported = supportsOnDeviceTranslation(
      platform: actualPlatform,
      physicalMemoryBytes: observedMemoryBytes,
      osMajor: observedOsMajor,
      isArm64: true,
    );
    final minimumRam = actualPlatform == TranslationPlatform.ios
        ? _iosMinimumPhysicalMemoryBytes
        : _androidMinimumPhysicalMemoryBytes;
    final minimumOs = actualPlatform == TranslationPlatform.ios ? 15 : 30;
    return (
      supported: supported,
      insufficientMemory:
          observedOsMajor >= minimumOs && observedMemoryBytes < minimumRam,
    );
  } on Object {
    return unknown;
  } finally {
    debugPrint(
      'TRANSLATION_CAPABILITY '
      'physicalMemoryBytes=${observedMemoryBytes ?? 'unknown'} '
      '$osKey=${observedOsMajor ?? 'unknown'} '
      'abi=${observedAbi ?? 'unknown'} supported=$supported',
    );
  }
}

/// A fresh snapshot before a cold load; temporary failures never alter
/// static eligibility. iOS reports process headroom, Android system RAM.
Future<bool> readTranslationMemoryAvailability({
  TranslationPlatform? platform,
}) async {
  final actualPlatform =
      platform ??
      (Platform.isIOS
          ? TranslationPlatform.ios
          : Platform.isAndroid
          ? TranslationPlatform.android
          : TranslationPlatform.other);
  if (actualPlatform == TranslationPlatform.other) return false;
  try {
    final facts = await _capabilityChannel.invokeMapMethod<String, Object?>(
      'memory',
    );
    final available = facts?['availableBytes'];
    final minimum = actualPlatform == TranslationPlatform.android
        ? _androidMinimumAvailableMemoryBytes
        : _iosMinimumAvailableMemoryBytes;
    if (available is! int || available < minimum) {
      return false;
    }
    return actualPlatform != TranslationPlatform.android ||
        facts?['lowMemory'] == false;
  } on Object {
    return false;
  }
}
