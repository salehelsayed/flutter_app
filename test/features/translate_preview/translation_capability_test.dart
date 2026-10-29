import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/translate_preview/translation_capability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mknoon/gemma_preview');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const iosFloor = 3758096384; // Approved 3.5 GiB, not a measured phone value.
  const androidFloor = 5905580032; // Approved 5.5 GiB, not measured.
  const ampleRam = 8 * 1024 * 1024 * 1024;
  final logs = <String>[];
  final originalDebugPrint = debugPrint;
  final unsupportedLog = matches(
    r'^TRANSLATION_CAPABILITY physicalMemoryBytes=(?:[0-9]+|unknown) '
    r'(?:osVersionMajor|sdkInt|osVersionOrSdk)=(?:[0-9]+|unknown) '
    r'abi=[a-z0-9_]+ supported=false$',
  );

  setUp(() {
    logs.clear();
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugPrint = originalDebugPrint;
  });

  const policyCases =
      <
        ({
          String name,
          TranslationPlatform platform,
          int ram,
          int os,
          bool arm64,
          bool expected,
        })
      >[
        (
          name: 'iOS accepts its RAM and OS boundaries',
          platform: TranslationPlatform.ios,
          ram: iosFloor,
          os: 15,
          arm64: true,
          expected: true,
        ),
        (
          name: 'iOS rejects one byte below its RAM boundary',
          platform: TranslationPlatform.ios,
          ram: iosFloor - 1,
          os: 15,
          arm64: true,
          expected: false,
        ),
        (
          name: 'iOS rejects version 14 despite sufficient RAM',
          platform: TranslationPlatform.ios,
          ram: ampleRam,
          os: 14,
          arm64: true,
          expected: false,
        ),
        (
          name: 'iOS rejects a non-ARM64 running process',
          platform: TranslationPlatform.ios,
          ram: iosFloor,
          os: 15,
          arm64: false,
          expected: false,
        ),
        (
          name: 'Android accepts its RAM and API boundaries',
          platform: TranslationPlatform.android,
          ram: androidFloor,
          os: 30,
          arm64: true,
          expected: true,
        ),
        (
          name: 'Android rejects one byte below its RAM boundary',
          platform: TranslationPlatform.android,
          ram: androidFloor - 1,
          os: 30,
          arm64: true,
          expected: false,
        ),
        (
          name: 'Android rejects API 29 despite sufficient RAM',
          platform: TranslationPlatform.android,
          ram: ampleRam,
          os: 29,
          arm64: true,
          expected: false,
        ),
        (
          name: 'Android rejects x86_64 or 32-bit running processes',
          platform: TranslationPlatform.android,
          ram: androidFloor,
          os: 30,
          arm64: false,
          expected: false,
        ),
        (
          name: 'unknown platforms are unsupported',
          platform: TranslationPlatform.other,
          ram: ampleRam,
          os: 99,
          arm64: true,
          expected: false,
        ),
        (
          name: 'missing RAM decoded as zero is unsupported',
          platform: TranslationPlatform.ios,
          ram: 0,
          os: 15,
          arm64: true,
          expected: false,
        ),
        (
          name: 'negative RAM is unsupported',
          platform: TranslationPlatform.android,
          ram: -1,
          os: 30,
          arm64: true,
          expected: false,
        ),
        (
          name: 'missing OS decoded as zero is unsupported',
          platform: TranslationPlatform.android,
          ram: androidFloor,
          os: 0,
          arm64: true,
          expected: false,
        ),
        (
          name: 'negative OS is unsupported',
          platform: TranslationPlatform.ios,
          ram: iosFloor,
          os: -1,
          arm64: true,
          expected: false,
        ),
        (
          name: 'newer iOS and ample RAM remain supported',
          platform: TranslationPlatform.ios,
          ram: ampleRam,
          os: 26,
          arm64: true,
          expected: true,
        ),
        (
          name: 'newer Android and ample RAM remain supported',
          platform: TranslationPlatform.android,
          ram: ampleRam,
          os: 36,
          arm64: true,
          expected: true,
        ),
      ];

  for (final example in policyCases) {
    test('policy: ${example.name}', () {
      expect(
        supportsOnDeviceTranslation(
          platform: example.platform,
          physicalMemoryBytes: example.ram,
          osMajor: example.os,
          isArm64: example.arm64,
        ),
        example.expected,
      );
    });
  }

  test('reader accepts iOS facts and logs only capability facts', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'physicalMemoryBytes': iosFloor, 'osVersionMajor': 15};
    });

    expect(
      await readTranslationCapability(
        platform: TranslationPlatform.ios,
        processAbi: Abi.iosArm64,
      ),
      isTrue,
    );
    expect(calls, hasLength(1));
    expect(calls.single.method, 'deviceCapabilities');
    expect(calls.single.arguments, isNull);
    expect(logs, [
      'TRANSLATION_CAPABILITY physicalMemoryBytes=$iosFloor '
          'osVersionMajor=15 abi=ios_arm64 supported=true',
    ]);
  });

  test('reader accepts Android facts at the RAM and API floors', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'deviceCapabilities');
      return {'physicalMemoryBytes': androidFloor, 'sdkInt': 30};
    });

    expect(
      await readTranslationCapability(
        platform: TranslationPlatform.android,
        processAbi: Abi.androidArm64,
      ),
      isTrue,
    );
    expect(logs, [
      'TRANSLATION_CAPABILITY physicalMemoryBytes=$androidFloor '
          'sdkInt=30 abi=android_arm64 supported=true',
    ]);
  });

  for (final sdk in [24, 25, 29]) {
    test('reader rejects Android API $sdk despite sufficient RAM', () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        return {'physicalMemoryBytes': ampleRam, 'sdkInt': sdk};
      });

      expect(
        await readTranslationCapability(
          platform: TranslationPlatform.android,
          processAbi: Abi.androidArm64,
        ),
        isFalse,
      );
      expect(logs, [
        'TRANSLATION_CAPABILITY physicalMemoryBytes=$ampleRam '
            'sdkInt=$sdk abi=android_arm64 supported=false',
      ]);
    });
  }

  test('reader rejects iOS 14 with sufficient physical RAM', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      return {'physicalMemoryBytes': ampleRam, 'osVersionMajor': 14};
    });

    expect(
      await readTranslationCapability(
        platform: TranslationPlatform.ios,
        processAbi: Abi.iosArm64,
      ),
      isFalse,
    );
    expect(logs, [unsupportedLog]);
  });

  for (final example in [
    (
      platform: TranslationPlatform.ios,
      abi: Abi.iosArm64,
      facts: {
        'physicalMemoryBytes': iosFloor - 1,
        'availableBytes': ampleRam,
        'osVersionMajor': 15,
      },
    ),
    (
      platform: TranslationPlatform.android,
      abi: Abi.androidArm64,
      facts: {
        'physicalMemoryBytes': androidFloor - 1,
        'availableBytes': ampleRam,
        'sdkInt': 30,
      },
    ),
  ]) {
    test('reader uses physical RAM for ${example.platform.name}', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => example.facts);

      expect(
        await readTranslationCapability(
          platform: example.platform,
          processAbi: example.abi,
        ),
        isFalse,
      );
      expect(logs, [unsupportedLog]);
    });
  }

  const unsupportedProcesses = <({TranslationPlatform platform, Abi abi})>[
    (platform: TranslationPlatform.other, abi: Abi.iosArm64),
    (platform: TranslationPlatform.ios, abi: Abi.iosArm),
    (platform: TranslationPlatform.ios, abi: Abi.iosX64),
    (platform: TranslationPlatform.ios, abi: Abi.androidArm64),
    (platform: TranslationPlatform.android, abi: Abi.androidArm),
    (platform: TranslationPlatform.android, abi: Abi.androidIA32),
    (platform: TranslationPlatform.android, abi: Abi.androidX64),
    (platform: TranslationPlatform.android, abi: Abi.androidRiscv64),
    (platform: TranslationPlatform.android, abi: Abi.iosArm64),
  ];
  for (final example in unsupportedProcesses) {
    test(
      'reader skips channel for ${example.platform.name}/${example.abi}',
      () async {
        var calls = 0;
        messenger.setMockMethodCallHandler(channel, (_) async {
          calls++;
          return {
            'physicalMemoryBytes': ampleRam,
            'osVersionMajor': 15,
            'sdkInt': 30,
          };
        });

        expect(
          await readTranslationCapability(
            platform: example.platform,
            processAbi: example.abi,
          ),
          isFalse,
        );
        expect(calls, 0);
        expect(logs, [unsupportedLog]);
      },
    );
  }

  const malformedIosFacts = <({String name, Object? payload})>[
    (name: 'null reply', payload: null),
    (name: 'empty reply', payload: <String, Object?>{}),
    (name: 'missing RAM', payload: {'osVersionMajor': 15}),
    (name: 'missing OS', payload: {'physicalMemoryBytes': ampleRam}),
    (
      name: 'null RAM',
      payload: {'physicalMemoryBytes': null, 'osVersionMajor': 15},
    ),
    (
      name: 'string RAM',
      payload: {
        'physicalMemoryBytes': 'untrusted-channel-value',
        'osVersionMajor': 15,
      },
    ),
    (
      name: 'double RAM',
      payload: {'physicalMemoryBytes': 8589934592.0, 'osVersionMajor': 15},
    ),
    (
      name: 'boolean RAM',
      payload: {'physicalMemoryBytes': true, 'osVersionMajor': 15},
    ),
    (
      name: 'zero RAM',
      payload: {'physicalMemoryBytes': 0, 'osVersionMajor': 15},
    ),
    (
      name: 'negative RAM',
      payload: {'physicalMemoryBytes': -1, 'osVersionMajor': 15},
    ),
    (
      name: 'null OS',
      payload: {'physicalMemoryBytes': ampleRam, 'osVersionMajor': null},
    ),
    (
      name: 'string OS',
      payload: {
        'physicalMemoryBytes': ampleRam,
        'osVersionMajor': 'untrusted-os-value',
      },
    ),
    (
      name: 'double OS',
      payload: {'physicalMemoryBytes': ampleRam, 'osVersionMajor': 15.0},
    ),
    (
      name: 'boolean OS',
      payload: {'physicalMemoryBytes': ampleRam, 'osVersionMajor': true},
    ),
    (
      name: 'zero OS',
      payload: {'physicalMemoryBytes': ampleRam, 'osVersionMajor': 0},
    ),
    (
      name: 'negative OS',
      payload: {'physicalMemoryBytes': ampleRam, 'osVersionMajor': -1},
    ),
    (
      name: 'wrong OS key',
      payload: {'physicalMemoryBytes': ampleRam, 'sdkInt': 30},
    ),
    (name: 'non-map reply', payload: [ampleRam, 15]),
    (name: 'non-string map key', payload: {1: ampleRam, 'osVersionMajor': 15}),
  ];
  for (final example in malformedIosFacts) {
    test('reader rejects ${example.name}', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => example.payload);

      expect(
        await readTranslationCapability(
          platform: TranslationPlatform.ios,
          processAbi: Abi.iosArm64,
        ),
        isFalse,
      );
      expect(logs, [unsupportedLog]);
    });
  }

  test('reader rejects a double Android SDK value', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      return {'physicalMemoryBytes': ampleRam, 'sdkInt': 30.0};
    });

    expect(
      await readTranslationCapability(
        platform: TranslationPlatform.android,
        processAbi: Abi.androidArm64,
      ),
      isFalse,
    );
    expect(logs, [unsupportedLog]);
  });

  test('reader fails closed on a platform exception', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });

    expect(
      await readTranslationCapability(
        platform: TranslationPlatform.ios,
        processAbi: Abi.iosArm64,
      ),
      isFalse,
    );
    expect(logs, [unsupportedLog]);
  });

  test('reader fails closed when the native method is missing', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw MissingPluginException();
    });

    expect(
      await readTranslationCapability(
        platform: TranslationPlatform.android,
        processAbi: Abi.androidArm64,
      ),
      isFalse,
    );
    expect(logs, [unsupportedLog]);
  });
}
