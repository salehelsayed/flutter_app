import 'dart:io';

import 'package:flutter_app/features/call/infrastructure/headless_call_admission_entrypoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nonce = '11111111-1111-4111-8111-111111111111';
  const callId = '22222222-2222-4222-8222-222222222222';
  const wakeHandle = '33333333333343338333333333333333';
  const expiresAtMs = 1_800_000_045_000;

  test('invocation parser accepts only the exact opaque four-field shape', () {
    final invocation = HeadlessCallAdmissionInvocation.parse(const <String>[
      nonce,
      callId,
      wakeHandle,
      '$expiresAtMs',
    ]);

    expect(invocation.nonce, nonce);
    expect(invocation.callId, callId);
    expect(invocation.wakeHandle, wakeHandle);
    expect(invocation.expiresAtMs, expiresAtMs);
    expect(invocation.identityPayload(), const <String, Object?>{
      'nonce': nonce,
      'callId': callId,
      'wakeHandle': wakeHandle,
      'expiresAtMs': expiresAtMs,
    });

    for (final invalid in <List<String>>[
      const <String>[nonce, callId, wakeHandle],
      const <String>['', callId, wakeHandle, '$expiresAtMs'],
      <String>[
        nonce,
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'.toUpperCase(),
        wakeHandle,
        '$expiresAtMs',
      ],
      const <String>[nonce, callId, 'readable-handle', '$expiresAtMs'],
      const <String>[nonce, callId, wakeHandle, '0'],
      const <String>[nonce, callId, wakeHandle, '1.5'],
    ]) {
      expect(
        () => HeadlessCallAdmissionInvocation.parse(invalid),
        throwsFormatException,
      );
    }
  });

  // Device 2026-09-05 17:44Z: a call presented headlessly (app killed) and
  // declined on the Pixel never told the caller; the iPhone rang back until
  // its own cancel. The native decline now schedules a second headless run in
  // decline-reply mode, carried as one extra fixed argument.
  test('invocation parser accepts the decline reply mode as a fifth field', () {
    final admission = HeadlessCallAdmissionInvocation.parse(const <String>[
      nonce,
      callId,
      wakeHandle,
      '$expiresAtMs',
    ]);
    expect(admission.mode, HeadlessCallAdmissionMode.admission);

    final decline = HeadlessCallAdmissionInvocation.parse(const <String>[
      nonce,
      callId,
      wakeHandle,
      '$expiresAtMs',
      'decline_reply',
    ]);
    expect(decline.mode, HeadlessCallAdmissionMode.declineReply);
    expect(decline.callId, callId);
    expect(decline.expiresAtMs, expiresAtMs);
    expect(decline.identityPayload(), admission.identityPayload());

    for (final invalid in <List<String>>[
      const <String>[nonce, callId, wakeHandle, '$expiresAtMs', 'admission'],
      const <String>[nonce, callId, wakeHandle, '$expiresAtMs', ''],
      const <String>[
        nonce,
        callId,
        wakeHandle,
        '$expiresAtMs',
        'DECLINE_REPLY',
      ],
      const <String>[
        nonce,
        callId,
        wakeHandle,
        '$expiresAtMs',
        'decline-reply',
      ],
      const <String>[
        nonce,
        callId,
        wakeHandle,
        '$expiresAtMs',
        'decline_reply',
        'decline_reply',
      ],
    ]) {
      expect(
        () => HeadlessCallAdmissionInvocation.parse(invalid),
        throwsFormatException,
      );
    }
  });

  test('admitted completion echoes only the fixed safe result shape', () async {
    final channel = _FakeChannel();
    await runAndroidHeadlessCallAdmission(
      const <String>[nonce, callId, wakeHandle, '$expiresAtMs'],
      resultChannel: channel,
      emergencyShutdown: () async => throw StateError('must not run'),
      runAdmission: ({required invocation, required isStopRequested}) async {
        channel.cancel();
        expect(isStopRequested(), isTrue);
        return const HeadlessCallAdmissionRunReport(
          disposition: HeadlessCallAdmissionDisposition.admitted,
          requiredPersistenceComplete: true,
          databaseClosed: true,
          leaseReleased: true,
        );
      },
    );

    expect(channel.methods, const <String>['complete']);
    expect(channel.payloads.single, const <String, Object?>{
      'nonce': nonce,
      'callId': callId,
      'wakeHandle': wakeHandle,
      'expiresAtMs': expiresAtMs,
      'disposition': 'admitted',
      'requiredPersistenceComplete': true,
      'databaseClosed': true,
      'leaseReleased': true,
    });
    expect(channel.disposed, isTrue);
  });

  test(
    'runner failure reports deferred with fail-closed cleanup facts',
    () async {
      final channel = _FakeChannel();
      var cleanupCalls = 0;
      await runAndroidHeadlessCallAdmission(
        const <String>[nonce, callId, wakeHandle, '$expiresAtMs'],
        resultChannel: channel,
        runAdmission: ({required invocation, required isStopRequested}) async {
          throw StateError('redacted failure');
        },
        emergencyShutdown: () async {
          cleanupCalls++;
          return const HeadlessCallAdmissionCleanup(
            databaseClosed: false,
            leaseReleased: false,
          );
        },
      );

      expect(cleanupCalls, 1);
      expect(channel.methods, const <String>['complete']);
      expect(channel.payloads.single, containsPair('disposition', 'deferred'));
      expect(
        channel.payloads.single,
        containsPair('requiredPersistenceComplete', false),
      );
      expect(channel.payloads.single, containsPair('databaseClosed', false));
      expect(channel.payloads.single, containsPair('leaseReleased', false));
      expect(channel.disposed, isTrue);
    },
  );

  test('production main exposes the dedicated AOT admission entrypoint', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(
      source,
      contains(
        "@pragma('vm:entry-point')\n"
        'Future<void> androidHeadlessCallAdmissionMain',
      ),
    );
    expect(
      source,
      contains('runProductionAndroidHeadlessCallAdmission(arguments)'),
    );
    expect(source, isNot(contains("package:flutter_app/features/call/")));
    final production = File(
      'lib/app/bootstrap/production_headless_call_admission.dart',
    ).readAsStringSync();
    expect(production, contains('runAndroidHeadlessCallAdmission('));
    expect(
      production,
      contains('runAdmission: runProductionHeadlessCallAdmission'),
    );
    expect(
      production,
      contains('emergencyShutdown: cleanupProductionHeadlessCallAdmission'),
    );
  });
}

final class _FakeChannel implements HeadlessCallAdmissionResultChannel {
  void Function()? _cancel;
  final List<String> methods = <String>[];
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
  bool disposed = false;

  void cancel() => _cancel?.call();

  @override
  void registerCancelHandler(void Function() onCancel) => _cancel = onCancel;

  @override
  Future<void> send({
    required String method,
    required Map<String, Object?> payload,
  }) async {
    methods.add(method);
    payloads.add(payload);
  }

  @override
  void dispose() {
    disposed = true;
    _cancel = null;
  }
}
