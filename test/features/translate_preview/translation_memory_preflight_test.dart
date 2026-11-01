import 'package:flutter/services.dart';
import 'package:flutter_app/features/translate_preview/translation_capability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mknoon/gemma_preview');
  const floor = 5 * (1 << 29); // Approved provisional 2.5 GiB headroom.
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final platform in [
    TranslationPlatform.android,
    TranslationPlatform.ios,
  ]) {
    for (final bytes in [floor - 1, floor, floor + 1]) {
      test('$platform available-memory boundary $bytes', () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'memory');
          expect(call.arguments, isNull);
          return {'availableBytes': bytes, 'lowMemory': false};
        });
        expect(
          await readTranslationMemoryAvailability(platform: platform),
          bytes >= floor,
        );
      });
    }
  }

  test('Android system lowMemory rejects even ample available RAM', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'availableBytes': 8 * (1 << 30), 'lowMemory': true},
    );
    expect(
      await readTranslationMemoryAvailability(
        platform: TranslationPlatform.android,
      ),
      isFalse,
    );
  });

  test(
    'iOS uses process headroom without an Android lowMemory field',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'availableBytes': floor},
      );
      expect(
        await readTranslationMemoryAvailability(
          platform: TranslationPlatform.ios,
        ),
        isTrue,
      );
    },
  );

  for (final example in <({String name, Object? payload})>[
    (name: 'null', payload: null),
    (name: 'missing available RAM', payload: {'lowMemory': false}),
    (name: 'zero RAM', payload: {'availableBytes': 0, 'lowMemory': false}),
    (name: 'negative RAM', payload: {'availableBytes': -1, 'lowMemory': false}),
    (
      name: 'string RAM',
      payload: {'availableBytes': '$floor', 'lowMemory': false},
    ),
    (
      name: 'double RAM',
      payload: {'availableBytes': floor.toDouble(), 'lowMemory': false},
    ),
    (
      name: 'boolean RAM',
      payload: {'availableBytes': true, 'lowMemory': false},
    ),
    (name: 'missing lowMemory', payload: {'availableBytes': floor}),
    (
      name: 'numeric lowMemory',
      payload: {'availableBytes': floor, 'lowMemory': 0},
    ),
    (
      name: 'string lowMemory',
      payload: {'availableBytes': floor, 'lowMemory': 'false'},
    ),
    (name: 'non-map', payload: 'unavailable'),
  ]) {
    test('Android runtime facts fail closed: ${example.name}', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => example.payload);
      expect(
        await readTranslationMemoryAvailability(
          platform: TranslationPlatform.android,
        ),
        isFalse,
      );
    });
  }

  for (final error in [
    PlatformException(code: 'unavailable'),
    MissingPluginException(),
  ]) {
    test('runtime snapshot fails closed for ${error.runtimeType}', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => throw error);
      expect(
        await readTranslationMemoryAvailability(
          platform: TranslationPlatform.android,
        ),
        isFalse,
      );
    });
  }

  test('each request measures fresh RAM and recovery is not sticky', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'availableBytes': ++calls == 1 ? floor - 1 : floor,
        'lowMemory': false,
      },
    );
    expect(
      await readTranslationMemoryAvailability(
        platform: TranslationPlatform.android,
      ),
      isFalse,
    );
    expect(
      await readTranslationMemoryAvailability(
        platform: TranslationPlatform.android,
      ),
      isTrue,
    );
    expect(calls, 2);
  });

  test('unsupported host platform never asks the native channel', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('unsupported platform must not invoke memory');
    });
    expect(
      await readTranslationMemoryAvailability(
        platform: TranslationPlatform.other,
      ),
      isFalse,
    );
  });
}
