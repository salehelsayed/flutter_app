import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
import 'package:flutter_app/features/call/diagnostics/routine_authority_publication.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_test/flutter_test.dart';

final class _PublicationBridge implements Bridge {
  final requests = <Map<String, dynamic>>[];
  Completer<String>? pending;
  bool reject = false;

  @override
  bool get isInitialized => true;

  @override
  Future<String> send(String message) async {
    requests.add(jsonDecode(message) as Map<String, dynamic>);
    final current = pending;
    if (current != null) return current.future;
    return jsonEncode(
      reject
          ? {'ok': false, 'errorCode': 'CALL_BACKEND_UNAVAILABLE'}
          : {'ok': true},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SignedCallEndpointRecord endpoint(int epoch) {
  final record = CallEndpointRecord(
    accountPeerId: 'PRIVATE_ACCOUNT',
    devicePeerId: 'PRIVATE_DEVICE',
    capabilities: const {'voice_call_v1'},
    platform: CallEndpointPlatform.ios,
    expiresAtMs: 100000 + epoch,
    preferenceEpoch: epoch,
    deviceKeyEpoch: 9,
    routingHandle: '0123456789abcdef0123456789abcdef',
  );
  return SignedCallEndpointRecord(
    record: record,
    signature: 'PRIVATE_SIGNATURE_$epoch',
    canonicalRecordBase64: base64Encode(
      utf8.encode(record.canonicalRecordJson),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late CallDiagnostics diagnostics;
  late _PublicationBridge bridge;
  late BridgeCallAuthorityClient client;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('routine-authority-');
    diagnostics = await CallDiagnostics.installForTesting(directory: directory);
    bridge = _PublicationBridge();
    client = BridgeCallAuthorityClient(bridge: bridge);
  });

  tearDown(() async {
    await diagnostics.dispose();
    await directory.delete(recursive: true);
  });

  Future<List<Map<String, Object?>>> publications() async =>
      (await diagnostics.eventsForTesting())
          .where((e) => e['stage'] == 'authority' && e['action'] == 'publish')
          .toList();

  Future<T> routine<T>(
    Future<T> Function() action, {
    bool Function()? eligible,
  }) => diagnostics.runWithOperation(
    diagnostics.beginOperation(reason: 'resume_refresh'),
    () => runWithRoutineAuthorityDiagnostics(
      eligible: eligible ?? () => true,
      action: action,
    ),
  );

  test(
    'real publications complete immediately while success records coalesce',
    () async {
      await routine(() async {
        for (var epoch = 1; epoch <= 3; epoch++) {
          expect(await client.setEndpoint(endpoint(epoch)), isTrue);
        }
      });
      expect(bridge.requests, hasLength(3));
      expect(
        bridge.requests.map((r) => (r['payload'] as Map)['preferenceEpoch']),
        [1, 2, 3],
      );
      expect((await publications()).map((e) => e['outcome']), ['started']);
      final preview = await diagnostics.exportPreview();
      final records = await publications();
      expect(records.map((e) => e['outcome']), ['started', 'ok']);
      expect(records.last['values'], {'count': 3});
      expect(preview, isNot(contains('PRIVATE_')));
      expect(
        records.every((e) => CallDiagnostics.validateEvent(e) != null),
        isTrue,
      );
    },
  );

  test('unknown producer origin retains every start and outcome', () async {
    final operation = diagnostics.beginOperation(reason: 'resume_refresh');
    await diagnostics.runWithOperation(operation, () async {
      await client.setEndpoint(endpoint(1));
      await client.setEndpoint(endpoint(2));
    });
    expect(bridge.requests, hasLength(2));
    expect((await publications()).map((e) => e['outcome']), [
      'started',
      'ok',
      'started',
      'ok',
    ]);
  });

  test(
    'pause persists the final success and count before a cold reload',
    () async {
      await routine(() async {
        await client.setEndpoint(endpoint(1));
        await client.setEndpoint(endpoint(2));
      });
      expect(bridge.requests, hasLength(2));
      diagnostics.didChangeAppLifecycleState(AppLifecycleState.paused);
      await diagnostics.eventsForTesting(); // Join the durable write barrier.
      final coldImage = await Directory(
        '${directory.path}/cold-image',
      ).create();
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File) {
          await entry.copy('${coldImage.path}/${entry.uri.pathSegments.last}');
        }
      }
      // Freeze disk before the testing helper's graceful dispose could rescue a
      // RAM-only success. Reopen only this image, as after process termination.
      diagnostics = await CallDiagnostics.installForTesting(
        directory: coldImage,
        enabled: null,
      );
      final records = await publications();
      expect(records.map((e) => e['outcome']), ['started', 'ok']);
      expect(records.last['values'], {'count': 2});
    },
  );

  test(
    'a call becoming active during await preserves the pending request',
    () async {
      var active = false;
      await routine(() async {
        await client.setEndpoint(endpoint(1));
        bridge.pending = Completer<String>();
        final second = client.setEndpoint(endpoint(2));
        active = true;
        bridge.pending!.complete(jsonEncode({'ok': true}));
        expect(await second, isTrue);
      }, eligible: () => !active);
      expect(bridge.requests, hasLength(2));
      final records = await publications();
      expect(records.map((e) => e['outcome']), [
        'started',
        'ok',
        'started',
        'ok',
      ]);
      expect(records.last['values'], isEmpty);
      expect(records[2]['requestId'], records.last['requestId']);
    },
  );

  test(
    'native rejection is observed in full and still rejects publication',
    () async {
      await routine(() async {
        await client.setEndpoint(endpoint(1));
        bridge.reject = true;
        await expectLater(
          client.setEndpoint(endpoint(2)),
          throwsA(isA<CallAuthorityException>()),
        );
      });
      final records = await publications();
      expect(bridge.requests, hasLength(2));
      expect(records.map((e) => e['outcome']), [
        'started',
        'ok',
        'started',
        'rejected',
      ]);
      expect(records.last['reason'], 'backend_unavailable');
      expect(records[2]['requestId'], records.last['requestId']);
    },
  );

  test(
    'clear cannot resurrect the buffered final success in a new consent epoch',
    () async {
      await routine(() => client.setEndpoint(endpoint(1)));
      await diagnostics.clear();
      await diagnostics.exportPreview();
      expect(await publications(), isEmpty);
      await routine(() async {
        bridge.reject = true;
        await expectLater(
          client.setEndpoint(endpoint(2)),
          throwsA(isA<CallAuthorityException>()),
        );
      });
      expect((await publications()).map((e) => e['outcome']), [
        'started',
        'rejected',
      ]);
    },
  );
}
