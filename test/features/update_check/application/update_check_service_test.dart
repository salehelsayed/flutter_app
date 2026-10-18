import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/features/update_check/application/update_check_service.dart';
import 'package:flutter_app/features/update_check/application/update_check_switch.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/update_check_state.dart';
import 'package:flutter_app/features/update_check/domain/version_file_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/update_check_test_keys.dart';

const _on = UpdateCheckSwitch(
  mode: 'on',
  isDebugBuild: false,
  e2eTestMode: false,
  simsBuildProfileId: '',
);

void main() {
  late TempStateStore temp;
  late FakeVersionFileFetcher fetcher;
  var now = DateTime.utc(2026, 10, 10, 12);

  setUp(() async {
    temp = await TempStateStore.create();
    fetcher = FakeVersionFileFetcher();
    now = DateTime.utc(2026, 10, 10, 12);
  });

  tearDown(() => temp.dispose());

  UpdateCheckService service({
    String installed = '110',
    UpdateCheckSwitch updateSwitch = _on,
    VersionFileVerifier? verifier,
    UpdatePlatform platform = UpdatePlatform.ios,
  }) => UpdateCheckService(
    updateSwitch: updateSwitch,
    verifier: verifier ?? testVerifier(),
    fetcher: fetcher,
    store: temp.store,
    installedBuildNumber: () async => installed,
    platform: platform,
    clock: () => now,
  );

  // latestBuild defaults to max(120, min) so every file is valid.
  Uint8List k1(int sequence, {int? latest, int min = 100}) => signedEnvelope(
    payloadBytes(
      sequence: sequence,
      ios: section(latest ?? (min > 120 ? min : 120), min),
    ),
  );

  Uint8List k2(int sequence, {int? latest, int min = 100}) => signedEnvelope(
    payloadBytes(
      sequence: sequence,
      ios: section(latest ?? (min > 120 ? min : 120), min),
    ),
    keyId: 'k2',
  );

  group('decision through the service (AC1)', () {
    test('none, soft and hard', () async {
      fetcher.responses.addAll([k1(1), k1(1), k1(1)]);
      expect(
        await service(installed: '120').check(),
        const UpdateDecisionNone(),
      );
      expect(
        await service(installed: '110').check(),
        isA<UpdateDecisionSoft>(),
      );
      expect(await service(installed: '99').check(), isA<UpdateDecisionHard>());
    });

    test('a file with minBuild > latestBuild is ignored', () async {
      fetcher.responses.add(k1(1, latest: 100, min: 200));
      expect(await service(installed: '1').check(), const UpdateDecisionNone());
      expect((await temp.load()).lastEnvelope, isNull);
    });

    test('an unparsable installed build -> none', () async {
      fetcher.responses.add(k1(1));
      expect(await service(installed: 'x').check(), const UpdateDecisionNone());
    });

    test('a failed check without a stored envelope -> none', () async {
      fetcher.responses.add(null);
      expect(await service(installed: '1').check(), const UpdateDecisionNone());
      expect((await temp.load()).lastCheckAt, now);
    });

    test('a failed check falls back to the stored envelope', () async {
      fetcher.responses.addAll([k1(1), null]);
      expect(await service(installed: '99').check(), isA<UpdateDecisionHard>());
      expect(await service(installed: '99').check(), isA<UpdateDecisionHard>());
      expect(fetcher.calls, 2);
    });

    test(
      'dismissal holds for the same latestBuild; a higher one returns',
      () async {
        final svc = service(installed: '110');
        fetcher.responses.add(k1(1, latest: 120));
        final first = await svc.check() as UpdateDecisionSoft;
        await svc.dismissSoft(first.latestBuild);
        fetcher.responses.add(k1(1, latest: 120));
        expect(await svc.check(), const UpdateDecisionNone());
        fetcher.responses.add(k1(2, latest: 121));
        expect(
          await svc.check(),
          const UpdateDecisionSoft(
            latestBuild: 121,
            reasonCode: UpdateReasonCode.general,
          ),
        );
      },
    );
  });

  test('a dismissal during a running check is not overwritten', () async {
    final svc = service(installed: '110');
    fetcher.responses.add(k1(1, latest: 120));
    await svc.check();
    fetcher.responses.add(k1(1, latest: 120));
    final running = svc.check();
    await svc.dismissSoft(120);
    await running;
    expect((await temp.load()).dismissedLatestBuild, 120);
    fetcher.responses.add(k1(1, latest: 120));
    expect(await svc.check(), const UpdateDecisionNone());
  });

  group('replay within a rank (AC3)', () {
    test('a lower sequence is ignored', () async {
      fetcher.responses.addAll([k1(5, min: 100), k1(4, min: 200)]);
      expect(await service().check(), isA<UpdateDecisionSoft>());
      expect(await service().check(), isA<UpdateDecisionSoft>());
      expect((await temp.load()).sequence, 5);
    });

    test('equal sequence + identical payload is a refresh', () async {
      fetcher.responses.add(k1(5));
      await service().check();
      final before = await temp.load();
      now = now.add(const Duration(hours: 7));
      fetcher.responses.add(k1(5));
      await service().check();
      final after = await temp.load();
      expect(after.lastEnvelope, before.lastEnvelope);
      expect(after.sequence, 5);
      expect(after.lastCheckAt, now);
    });

    test('equal sequence + different payload is ignored', () async {
      fetcher.responses.addAll([k1(5, min: 100), k1(5, min: 200)]);
      expect(await service().check(), isA<UpdateDecisionSoft>());
      expect(await service().check(), isA<UpdateDecisionSoft>());
      expect((await temp.load()).sequence, 5);
    });
  });

  group('ranked keys (AC4)', () {
    test('(a) after k2 is accepted, any k1 file is ignored', () async {
      fetcher.responses.addAll([k2(1), k1(999999, min: 999999)]);
      await service().check();
      expect(await service().check(), isA<UpdateDecisionSoft>());
      final state = await temp.load();
      expect(state.highestAcceptedRank, 2);
      expect(state.sequence, 1);
    });

    test('(b) stored k1 state is discarded once k2 is accepted', () async {
      fetcher.responses.addAll([k1(50), k2(1)]);
      await service().check();
      expect((await temp.load()).sequence, 50);
      await service().check();
      final state = await temp.load();
      expect(state.highestAcceptedRank, 2);
      expect(state.sequence, 1);
      expect(jsonDecode(utf8.decode(state.lastEnvelope!))['keyId'], 'k2');
    });

    test(
      '(c) a k2 file overrides a hostile k1 file (minBuild=999999)',
      () async {
        fetcher.responses.addAll([
          k1(1 << 40, latest: 999999, min: 999999),
          k2(1, latest: 120, min: 100),
        ]);
        expect(await service().check(), isA<UpdateDecisionHard>());
        expect(await service().check(), isA<UpdateDecisionSoft>());
      },
    );

    test(
      '(d) a stored envelope whose key is no longer built in is discarded',
      () async {
        fetcher.responses.add(k1(1, min: 200));
        expect(await service().check(), isA<UpdateDecisionHard>());
        // A later build drops k1. The download fails, so only the stored
        // envelope could block, and it must not.
        fetcher.responses.add(null);
        final withoutK1 = service(verifier: testVerifier(withK1: false));
        expect(await withoutK1.check(), const UpdateDecisionNone());
        final state = await temp.load();
        expect(state.lastEnvelope, isNull);
        // T4a: only the envelope goes. The rank and sequence never go down.
        expect(state.highestAcceptedRank, 1);
        expect(state.sequence, 1);
      },
    );

    test(
      'F2: after the envelope is dropped, the same file restores the hard gate',
      () async {
        fetcher.responses.add(k1(3, min: 200));
        expect(await service().check(), isA<UpdateDecisionHard>());
        // Corrupt the stored envelope bytes: the next load drops it but keeps
        // rank 1 and sequence 3.
        final json =
            jsonDecode(await temp.file.readAsString()) as Map<String, Object?>;
        json['lastEnvelope'] = base64.encode(utf8.encode('{"v":1}'));
        await temp.file.writeAsString(jsonEncode(json));
        // The publisher has not bumped the sequence: the same file comes back.
        fetcher.responses.add(k1(3, min: 200));
        expect(await service().check(), isA<UpdateDecisionHard>());
        final state = await temp.load();
        expect((state.highestAcceptedRank, state.sequence), (1, 3));
        expect(state.lastEnvelope, isNotNull);
      },
    );

    test('(e) the k2 sequence starts fresh when the rank rises', () async {
      fetcher.responses.addAll([k1(1000), k2(1), k2(2)]);
      await service().check();
      await service().check();
      expect((await temp.load()).sequence, 1);
      await service().check();
      expect((await temp.load()).sequence, 2);
    });

    test('(f) a raised stored rank drops the envelope -> none', () async {
      fetcher.responses.add(k1(1, min: 200));
      await service().check();

      // Tamper: raise the stored rank so it no longer matches the key.
      final json =
          jsonDecode(await temp.file.readAsString()) as Map<String, Object?>;
      json['highestAcceptedRank'] = 2;
      await temp.file.writeAsString(jsonEncode(json));
      fetcher.responses.add(null);
      expect(await service().check(), const UpdateDecisionNone());
      final state = await temp.load();
      expect(state.lastEnvelope, isNull);
      // T4a never lowers a rank, so the raised rank stays. Writing the app's
      // private files is outside the threat model.
      expect(state.highestAcceptedRank, 2);
    });

    test('(f2) corrupt or tampered stored state is discarded -> none', () async {
      // Corrupt: not JSON at all.
      await temp.file.writeAsString('{{{ not json');
      fetcher.responses.add(null);
      expect(await service().check(), const UpdateDecisionNone());

      // Tamper: flip a byte in the stored envelope.
      fetcher.responses.add(k1(2, min: 200));
      await service().check();
      final stored =
          jsonDecode(await temp.file.readAsString()) as Map<String, Object?>;
      final envelope = base64.decode(stored['lastEnvelope']! as String);
      final payload = jsonDecode(utf8.decode(envelope)) as Map<String, Object?>;
      final payloadBytes = base64.decode(payload['payload']! as String)
        ..[5] ^= 1;
      payload['payload'] = base64.encode(payloadBytes);
      stored['lastEnvelope'] = base64.encode(utf8.encode(jsonEncode(payload)));
      await temp.file.writeAsString(jsonEncode(stored));
      fetcher.responses.add(null);
      expect(await service().check(), const UpdateDecisionNone());
    });
  });

  group('kill switch (AC6)', () {
    UpdateCheckSwitch sw({
      String mode = '',
      bool debug = false,
      bool e2e = false,
      String sims = '',
      bool testProfile = false,
    }) => UpdateCheckSwitch(
      mode: mode,
      isDebugBuild: debug,
      e2eTestMode: e2e,
      simsBuildProfileId: sims,
      testProfileOptIn: testProfile,
    );

    test('defaults: on in release/profile, off in debug', () {
      expect(sw().enabled, isTrue);
      expect(sw(debug: true).enabled, isFalse);
      expect(sw(debug: true, mode: 'on').enabled, isTrue);
      expect(sw(mode: 'off').enabled, isFalse);
    });

    test('fixture opt-in is debug E2E and exact-profile only', () {
      for (final profile in [
        'android.e2e.production_call_local',
        'ios.simulator.app',
      ]) {
        expect(
          sw(
            mode: 'on',
            debug: true,
            e2e: true,
            sims: profile,
            testProfile: true,
          ).enabled,
          isTrue,
        );
        expect(
          sw(
            mode: 'off',
            debug: true,
            e2e: true,
            sims: profile,
            testProfile: true,
          ).enabled,
          isFalse,
        );
        expect(
          sw(mode: 'on', debug: true, e2e: true, sims: profile).enabled,
          isFalse,
        );
      }
      for (final configuration in [
        sw(
          mode: 'on',
          e2e: true,
          sims: 'android.e2e.production_call_local',
          testProfile: true,
        ),
        sw(
          mode: 'off',
          e2e: true,
          sims: 'android.e2e.production_call_local',
          testProfile: true,
        ),
        sw(
          mode: 'on',
          debug: true,
          sims: 'android.e2e.production_call_local',
          testProfile: true,
        ),
        sw(
          mode: 'on',
          debug: true,
          e2e: true,
          sims: 'android.e2e.production',
          testProfile: true,
        ),
        sw(mode: 'on', debug: true, e2e: true, sims: '', testProfile: true),
      ]) {
        expect(() => configuration.enabled, throwsStateError);
      }
    });

    test('E2E and SIMS stay off without an approved fixture opt-in', () {
      expect(sw(mode: 'on', e2e: true).enabled, isFalse);
      expect(sw(mode: 'on', sims: 'ios.device.production').enabled, isFalse);
    });

    for (final (name, off) in [
      ('E2E_TEST_MODE=true', sw(mode: 'on', e2e: true)),
      ('SIMS_BUILD_PROFILE_ID set', sw(mode: 'on', sims: 'android.e2e')),
      ('MKNOON_UPDATE_CHECK=off', sw(mode: 'off')),
      ('debug default', sw(debug: true)),
    ]) {
      test(
        '$name: no request and decision none, even with a stored hard file',
        () async {
          fetcher.responses.add(k1(1, min: 200));
          expect(await service().check(), isA<UpdateDecisionHard>());
          expect(fetcher.calls, 1);

          fetcher.responses.add(k1(2, min: 200));
          final disabled = service(updateSwitch: off);
          expect(await disabled.check(), const UpdateDecisionNone());
          expect(await disabled.isCheckDue(now), isFalse);
          expect(fetcher.calls, 1);
        },
      );
    }
  });

  group('schedule through the service (AC8)', () {
    test('due at launch, not due right after, due after 6 h', () async {
      final svc = service();
      expect(await svc.isCheckDue(now), isTrue);
      fetcher.responses.add(k1(1));
      await svc.check();
      expect(await svc.isCheckDue(now.add(const Duration(hours: 1))), isFalse);
      expect(
        await svc.isCheckDue(now.add(const Duration(hours: 6, minutes: 1))),
        isTrue,
      );
      expect(
        await svc.isCheckDue(now.subtract(const Duration(minutes: 1))),
        isTrue,
      );
      // A new launch (new service) is due even right after a check.
      expect(await service().isCheckDue(now), isTrue);
    });
  });

  group('startup is not delayed (AC5)', () {
    test(
      'check() returns a pending future and does no synchronous work',
      () async {
        final svc = service();
        fetcher.responses.add(k1(1));
        final future = svc.check();
        expect(future, isA<Future<UpdateDecision>>());
        expect(fetcher.calls, 0, reason: 'nothing ran before the event loop');
        await future;
        expect(fetcher.calls, 1);
      },
    );

    test('concurrent calls share one run', () async {
      final svc = service();
      fetcher.responses.add(k1(1));
      final results = await Future.wait([svc.check(), svc.check()]);
      expect(fetcher.calls, 1);
      expect(results[0], results[1]);
    });
  });

  group('storage (AC9)', () {
    test(
      'a plain JSON file in the given app directory, written atomically',
      () async {
        fetcher.responses.add(k1(1));
        await service().check();
        final names = temp.directory
            .listSync()
            .map((e) => e.uri.pathSegments.last)
            .toList();
        expect(names, ['se41_update_check_state.json']);
        final json = jsonDecode(await temp.file.readAsString()) as Map;
        expect(json['highestAcceptedRank'], 1);
        expect(json['sequence'], 1);
      },
    );

    test('a leftover temp file from a crash does not break loading', () async {
      fetcher.responses.add(k1(1));
      await service().check();
      await File('${temp.file.path}.tmp').writeAsString('half writ');
      expect((await temp.load()).sequence, 1);
      await temp.store.save(const UpdateCheckState(dismissedLatestBuild: 3));
      expect(File('${temp.file.path}.tmp').existsSync(), isFalse);
      expect((await temp.load()).dismissedLatestBuild, 3);
    });

    test('state code uses neither Keychain nor flutter_secure_storage', () {
      for (final entity in Directory(
        'lib/features/update_check',
      ).listSync(recursive: true).whereType<File>()) {
        final source = entity.readAsStringSync();
        expect(
          source,
          isNot(contains('package:flutter_secure_storage')),
          reason: entity.path,
        );
        expect(source, isNot(contains('FlutterSecureStorage(')));
        // T4a: only background/ talks to native code (scheduling and
        // notifications); the state code itself never does.
        if (entity.path.contains('/background/')) continue;
        expect(source, isNot(contains('MethodChannel')), reason: entity.path);
      }
    });
  });
}
