import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/src/receive_sharing_intent_mobile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const messages = MethodChannel('receive_sharing_intent/messages');
  const events = MethodChannel('receive_sharing_intent/events-media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late ReceiveSharingIntentMobile plugin;
  Object? initialResponse;
  var resets = 0;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('initial-share-boundary-');
    plugin = ReceiveSharingIntentMobile();
    initialResponse = null;
    resets = 0;
    messenger.setMockMethodCallHandler(messages, (call) async {
      expect(call.method, 'getInitialMedia');
      return initialResponse;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(messages, null);
    messenger.setMockMethodCallHandler(events, null);
    directory.deleteSync(recursive: true);
  });

  ShareIntentService service({Future<Directory> Function()? cacheDirectory}) =>
      ShareIntentService(
        getInitialMedia: plugin.getInitialMedia,
        getMediaStream: plugin.getMediaStream,
        getCacheDirectory: cacheDirectory ?? () async => directory,
        resetShareIntent: () => resets++,
      );

  for (final fixture in [
    (
      name: 'missing path',
      payload: '[{"type":"file"}]',
      failure: isA<TypeError>(),
    ),
    (
      name: 'null path',
      payload: '[{"path":null,"type":"image"}]',
      failure: isA<TypeError>(),
    ),
    (
      name: 'invalid JSON',
      payload: 'not JSON',
      failure: isA<FormatException>(),
    ),
  ]) {
    test('${fixture.name} cannot abort the optional startup probe', () async {
      initialResponse = fixture.payload;
      final shares = service();
      // Execute the real pinned plugin decoder, including the Pixel failure's
      // null-to-String boundary, rather than injecting a hand-made TypeError.
      await expectLater(shares.getInitialIntent(), throwsA(fixture.failure));

      final startup = await Future.wait<Object?>([
        shares.captureInitialIntent(),
        Future<String>.value('documents-ready'),
      ]);

      expect(startup, [null, 'documents-ready']);
      expect(shares.hasPendingIntent, isFalse);
      expect(resets, 0);
    });
  }

  test('ordinary null native result remains an empty initial probe', () async {
    final shares = service();
    expect(await shares.captureInitialIntent(), isNull);
    expect(shares.hasPendingIntent, isFalse);
    expect(resets, 0);
  });

  test('native probe errors do not prevent startup', () async {
    messenger.setMockMethodCallHandler(messages, (_) async {
      throw PlatformException(code: 'probe-unavailable');
    });
    final shares = service();
    await expectLater(
      shares.getInitialIntent(),
      throwsA(isA<PlatformException>()),
    );
    expect(await shares.captureInitialIntent(), isNull);
    expect(shares.hasPendingIntent, isFalse);
    expect(resets, 0);
  });

  test('valid cold mixed share still copies and buffers files once', () async {
    final source = File('${directory.path}/original/photo.jpg');
    source.parent.createSync();
    source.writeAsStringSync('synthetic image fixture');
    initialResponse = jsonEncode([
      {'path': 'shared caption', 'type': 'text'},
      {'path': source.path, 'type': 'image'},
    ]);
    final shares = service();

    final initial = await shares.captureInitialIntent();
    expect(initial?.type, ShareIntentType.mixed);
    expect(initial?.text, 'shared caption');
    expect(initial?.filePaths, [source.path]);
    final pending = shares.consumePendingIntent();
    expect(pending?.type, ShareIntentType.mixed);
    expect(pending?.text, 'shared caption');
    final cached = '${directory.path}/share_cache/photo.jpg';
    expect(pending?.filePaths, [cached]);
    expect(File(cached).readAsStringSync(), 'synthetic image fixture');
    expect(shares.consumePendingIntent(), isNull);
    expect(source.readAsStringSync(), 'synthetic image fixture');
    expect(resets, 0);
  });

  test(
    'failed probe preserves pending share and later warm delivery',
    () async {
      initialResponse = '[{"type":"file"}]';
      final shares = service();
      const pending = ShareIntent(type: ShareIntentType.text, text: 'buffered');
      await shares.bufferIntent(pending);
      expect(await shares.captureInitialIntent(), isNull);
      expect(shares.consumePendingIntent(), same(pending));

      final listening = Completer<void>();
      messenger.setMockMethodCallHandler(events, (call) async {
        if (call.method == 'listen') listening.complete();
        return null;
      });
      final next = shares.intentStream.first;
      await listening.future;
      await messenger.handlePlatformMessage(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope(
          jsonEncode([
            {'path': 'valid warm share', 'type': 'text'},
          ]),
        ),
        (_) {},
      );
      final warm = await next;
      expect(warm.type, ShareIntentType.text);
      expect(warm.text, 'valid warm share');
      expect(warm.filePaths, isEmpty);
      expect(resets, 0);
    },
  );

  test(
    'valid-share buffering errors still propagate outside probe guard',
    () async {
      initialResponse = '[{"path":"/fixture/photo.jpg","type":"image"}]';
      final failure = StateError('cache unavailable');
      final shares = service(cacheDirectory: () async => throw failure);
      await expectLater(shares.captureInitialIntent(), throwsA(same(failure)));
      expect(shares.hasPendingIntent, isFalse);
    },
  );
}
