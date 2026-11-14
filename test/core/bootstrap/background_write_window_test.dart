import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/app/bootstrap/background_write_window.dart';
import 'package:flutter_test/flutter_test.dart';

/// BL-30: build 131 was killed with 0xdead10cc about 2.5 s after a background
/// launch while the bootstrap committed to identity.db. On iOS the
/// every-launch open plus its post-open writes must run inside one
/// background assertion.
const _channel = MethodChannel('com.mknoon/go_bridge');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> order;

  void mockChannel(Object? Function(MethodCall call) answer) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          order.add(
            call.method == 'bgEnd'
                ? 'bgEnd:${(jsonDecode(call.arguments as String) as Map)['taskId']}'
                : call.method,
          );
          return answer(call);
        });
  }

  Future<String> openAndWrite(
    BackgroundWriteWindow window, {
    Object? writeError,
  }) => openIdentityDatabaseWithPostOpenWrites<String>(
    window: window,
    open: () async {
      order.add('open');
      return 'db';
    },
    postOpenWrites: (db) async {
      expect(db, 'db');
      order.add('writes');
      if (writeError != null) throw writeError;
    },
  );

  setUp(() => order = <String>[]);
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  test('a: iOS open and post-open writes sit inside one assertion', () async {
    mockChannel((call) => call.method == 'bgBegin' ? '77' : null);

    final db = await openAndWrite(const IosBackgroundWriteWindow());

    expect(db, 'db');
    expect(order, <String>['bgBegin', 'open', 'writes', 'bgEnd:77']);
  });

  test('b: a failing write still ends the assertion and rethrows', () async {
    mockChannel((call) => call.method == 'bgBegin' ? '78' : null);
    final failure = StateError('repair failed');

    Object? error;
    try {
      await openAndWrite(const IosBackgroundWriteWindow(), writeError: failure);
    } catch (caught) {
      error = caught;
    }

    expect(error, same(failure));
    expect(order, <String>['bgBegin', 'open', 'writes', 'bgEnd:78']);
  });

  test('c: a refused assertion still runs the writes', () async {
    mockChannel((call) => call.method == 'bgBegin' ? '' : null);

    final db = await openAndWrite(const IosBackgroundWriteWindow());

    expect(db, 'db');
    expect(order, <String>['bgBegin', 'open', 'writes']);
  });

  test('d: a missing plugin still runs the writes', () async {
    mockChannel((call) => throw MissingPluginException(call.method));

    final db = await openAndWrite(const IosBackgroundWriteWindow());

    expect(db, 'db');
    expect(order, <String>['bgBegin', 'open', 'writes']);
  });

  test('e: off iOS the writes make no channel call', () async {
    mockChannel((call) => '79');

    await openAndWrite(defaultBackgroundWriteWindow(isIOS: false));
    await openAndWrite(const PassthroughBackgroundWriteWindow());

    expect(order, <String>['open', 'writes', 'open', 'writes']);
  });

  test('f: the iOS default and the bootstrap wiring use the window', () {
    expect(
      defaultBackgroundWriteWindow(isIOS: true),
      isA<IosBackgroundWriteWindow>(),
    );

    final source = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    final call = source.indexOf(
      'await openIdentityDatabaseWithPostOpenWrites<Database>(',
    );
    expect(call, greaterThanOrEqualTo(0));
    expect(
      source.indexOf(
        'window: backgroundWriteWindow ?? defaultBackgroundWriteWindow()',
        call,
      ),
      greaterThan(call),
    );
    final writes = [
      'await repairDirectNotificationDurabilityDeleteTriggers(db);',
      'await repairLegacyPushMessageTransports(db);',
      'await migrateSecretsToSecureStorage(',
      'await runSecretNullChecksMigration(db);',
      'await scrubLegacyGroupSecretsToSecureStorage(',
    ].map((line) => source.indexOf(line, call)).toList();
    expect(writes, everyElement(greaterThan(call)));
    expect(writes, orderedEquals([...writes]..sort()));
  });
}
