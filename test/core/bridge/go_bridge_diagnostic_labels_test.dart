import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.mknoon/go_bridge');
const _privateMarker = 'PRIVATE_BRIDGE_FIXTURE_CONTENT';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDiagnostics diagnostics;
  late GoBridgeClient client;
  final uploads = <Map<String, Object?>>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bridge-labels-');
    diagnostics = await AppDiagnostics.installForTesting(
      directory: directory,
      upload: (batch) async {
        uploads.addAll(batch);
        return batch.map((event) => event['eventId']! as String).toSet();
      },
    );
    uploads.clear();
    client = GoBridgeClient();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    client.dispose();
    await diagnostics.dispose();
    await directory.delete(recursive: true);
  });

  Future<String> send(String command, String? native) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => native);
    return client.send(
      jsonEncode({
        'cmd': command,
        'payload': {
          'peerId': _privateMarker,
          'text': _privateMarker,
          'nested': {'token': _privateMarker},
        },
      }),
    );
  }

  Future<Map<String, Object?>> failure() async =>
      (await diagnostics.eventsForTesting())
          .where(
            (event) =>
                event['outcome'] == 'failed' &&
                ((event['feature'] == 'runtime' &&
                        event['stage'] == 'bridge') ||
                    (event['feature'] == 'network' &&
                        event['stage'] == 'finish')),
          )
          .single;

  Future<void> expectLabels(String command, String family, String kind) async {
    final event = await failure();
    expect(event['values'], containsPair('bridgeCommandFamily', family));
    expect(event['values'], containsPair('bridgeRejectionKind', kind));
    expect(AppDiagnostics.validateEvent(event), isNotNull);
    final exported = await diagnostics.exportPreview();
    expect(exported, isNot(contains(_privateMarker)));
    expect(exported, isNot(contains(command)));
    await diagnostics.flush();
    final uploaded = uploads.singleWhere(
      (row) => row['eventId'] == event['eventId'],
    );
    expect(uploaded['values'], containsPair('bridgeCommandFamily', family));
    expect(uploaded['values'], containsPair('bridgeRejectionKind', kind));
    expect(jsonEncode(uploaded), isNot(contains(_privateMarker)));
    expect(jsonEncode(uploaded), isNot(contains(command)));
    expect(uploaded['eventId'], event['eventId']);
  }

  // Representative real commands exercise every reporting family through the
  // existing native boundary. Diagnostic transport commands are tested below.
  for (final sample in const [
    (command: 'identity.generate', family: 'identity'),
    (command: 'message.encrypt', family: 'crypto'),
    (command: 'migration.session.encap', family: 'migration'),
    (command: 'peer:dial', family: 'network'),
    (command: 'call_endpoint_get_v1', family: 'call_control'),
    (command: 'message:send', family: 'messaging'),
    (command: 'inbox:store', family: 'inbox'),
    (command: 'media:download', family: 'media'),
    (command: 'profile:download', family: 'profile'),
    (command: 'group:join', family: 'group'),
    (command: 'bg:end', family: 'background'),
  ]) {
    test(
      '${sample.family} accepted response preserves bridge result',
      () async {
        final native = jsonEncode({'ok': true, 'data': _privateMarker});
        expect(await send(sample.command, native), native);
        expect(
          (await diagnostics.eventsForTesting()).where(
            (event) => event['outcome'] == 'failed',
          ),
          isEmpty,
        );
        expect(
          await diagnostics.exportPreview(),
          isNot(contains(_privateMarker)),
        );
      },
    );

    test(
      '${sample.family} rejection labels export and upload privately',
      () async {
        final native = jsonEncode({
          'ok': false,
          'errorCode': 'INTERNAL_ERROR',
          'errorMessage': _privateMarker,
        });
        final returned = jsonDecode(await send(sample.command, native)) as Map;
        expect(returned['ok'], false);
        expect(returned['errorCode'], 'INTERNAL_ERROR');
        expect(returned['errorMessage'], _privateMarker);
        await expectLabels(sample.command, sample.family, 'internal');
      },
    );

    test(
      '${sample.family} null response keeps result and labels malformed',
      () async {
        final returned = jsonDecode(await send(sample.command, null)) as Map;
        expect(returned['ok'], false);
        expect(returned['errorCode'], 'NULL_RESPONSE');
        await expectLabels(sample.command, sample.family, 'malformed_response');
      },
    );
  }

  for (final sample in const [
    (code: 'BRIDGE_TIMEOUT', kind: 'timeout'),
    (code: 'NOT_INITIALIZED', kind: 'not_ready'),
    (code: 'INVALID_INPUT', kind: 'invalid_argument'),
    (code: 'GROUP_KEY_NOT_FOUND', kind: 'not_found'),
    (code: 'CALL_UNAUTHORIZED', kind: 'permission'),
    (code: 'INTERNAL_ERROR', kind: 'internal'),
    (code: 'MALFORMED_RESPONSE', kind: 'malformed_response'),
    (code: 'CALL_CONTROL_UNSUPPORTED', kind: 'unsupported'),
    (code: 'INBOX_FULL', kind: 'capacity'),
    (code: 'DIAL_ERROR', kind: 'unknown'),
    (code: 'INBOX_ERROR', kind: 'unknown'),
    (code: 'MEDIA_ERROR', kind: 'unknown'),
    (code: 'DECRYPT_AUTH_ERROR', kind: 'unknown'),
    (code: 'PRIVATE_BRIDGE_FIXTURE_CONTENT', kind: 'unknown'),
  ]) {
    test(
      'native ${sample.code} maps only its bounded rejection kind',
      () async {
        await send(
          'media:download',
          jsonEncode({
            'ok': false,
            'errorCode': sample.code,
            // These words must never override the code-derived classification.
            'errorMessage': 'timeout permission not found $_privateMarker',
          }),
        );
        await expectLabels('media:download', 'media', sample.kind);
      },
    );
  }

  for (final malformed in ['not JSON $_privateMarker', '[]', 'true', '7']) {
    test('malformed native response $malformed stays sanitized', () async {
      final returned = jsonDecode(await send('message:send', malformed)) as Map;
      expect(returned['ok'], false);
      expect(returned['errorCode'], 'MALFORMED_RESPONSE');
      await expectLabels('message:send', 'messaging', 'malformed_response');
    });
  }

  test('unknown command is bounded and never invokes native code', () async {
    var invoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async {
          invoked = true;
          return jsonEncode({'ok': true});
        });
    const command = 'private.command.$_privateMarker';
    final returned =
        jsonDecode(
              await client.send(
                jsonEncode({
                  'cmd': command,
                  'payload': {'peerId': _privateMarker},
                }),
              ),
            )
            as Map;
    expect(returned['errorCode'], 'UNKNOWN_COMMAND');
    expect(returned['errorMessage'], 'Unknown command: $command');
    expect(invoked, false);
    await expectLabels(command, 'unknown', 'unknown');
  });

  for (final command in ['app_diagnostics_v1', 'call_diagnostics_v1']) {
    for (final native in [
      jsonEncode({'ok': false, 'errorCode': 'INTERNAL_ERROR'}),
      null,
    ]) {
      test(
        '$command failure does not recursively diagnose itself ($native)',
        () async {
          await send(command, native);
          expect(
            (await diagnostics.eventsForTesting()).where(
              (event) => event['outcome'] == 'failed',
            ),
            isEmpty,
          );
        },
      );
    }
  }

  for (final command in ['bg:begin', 'bg:grantProbe', 'bg:timeRemaining']) {
    test('$command keeps its existing raw-string response contract', () async {
      const native = 'raw native value $_privateMarker';
      expect(await send(command, native), native);
      expect(
        (await diagnostics.eventsForTesting()).where(
          (event) => event['outcome'] == 'failed',
        ),
        isEmpty,
      );
    });
  }

  test('new label values remain closed at diagnostic admission', () async {
    expect(
      diagnostics.record(
        feature: 'runtime',
        stage: 'bridge',
        outcome: 'failed',
        reason: 'bridge_rejected',
        values: {
          'bridgeCommandFamily': 'messaging',
          'bridgeRejectionKind': 'unknown',
        },
      ),
      true,
    );
    final valid = await failure();
    for (final key in ['bridgeCommandFamily', 'bridgeRejectionKind']) {
      final invalid = <String, Object?>{
        ...valid,
        'values': {...(valid['values'] as Map), key: _privateMarker},
      };
      expect(AppDiagnostics.validateEvent(invalid), isNull);
    }
  });
}
