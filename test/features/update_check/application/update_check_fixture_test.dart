import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/update_check/application/update_check_fixture.dart';
import 'package:flutter_app/features/update_check/application/update_check_service.dart';
import 'package:flutter_app/features/update_check/application/update_check_switch.dart';
import 'package:flutter_app/features/update_check/domain/update_check_keys.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/version_file_verifier.dart';
import 'package:flutter_app/features/update_check/infrastructure/update_check_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/update_check_test_keys.dart';

const fixtureSwitch = UpdateCheckSwitch(
  mode: 'on',
  isDebugBuild: true,
  e2eTestMode: true,
  simsBuildProfileId: 'android.e2e.production_call_local',
  testProfileOptIn: true,
);

void main() {
  late Directory directory;
  late File envelope;
  final publicKey = base64Encode(testOnlyK1.verifyKey);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('se41-fixture-');
    envelope = File(
      '${directory.path}/$updateCheckFixtureDirectory/$updateCheckFixtureEnvelope',
    );
    await envelope.parent.create();
  });

  tearDown(() => directory.delete(recursive: true));

  test('ordinary E2E/SIMS builds do not acquire the fixture source or key', () {
    const ordinary = UpdateCheckSwitch(
      mode: 'on',
      isDebugBuild: true,
      e2eTestMode: true,
      simsBuildProfileId: 'android.e2e.production_call_local',
    );
    expect(updateCheckFixtureFetcher(updateSwitch: ordinary), isNull);
    expect(
      updateCheckFixtureVerifier(updateSwitch: ordinary, publicKeyBase64: ''),
      isNull,
    );
    expect(
      () => updateCheckFixtureVerifier(
        updateSwitch: ordinary,
        publicKeyBase64: publicKey,
      ),
      throwsStateError,
    );
  });

  test('a release/profile build refuses the fixture even with mode off', () {
    const release = UpdateCheckSwitch(
      mode: 'off',
      isDebugBuild: false,
      e2eTestMode: true,
      simsBuildProfileId: 'android.e2e.production_call_local',
      testProfileOptIn: true,
    );
    expect(
      () => updateCheckFixtureFetcher(updateSwitch: release),
      throwsStateError,
    );
    expect(
      () => updateCheckFixtureVerifier(
        updateSwitch: release,
        publicKeyBase64: publicKey,
      ),
      throwsStateError,
    );
  });

  test(
    'fixture reads are bounded and missing files never use the network',
    () async {
      final fetcher = updateCheckFixtureFetcher(
        updateSwitch: fixtureSwitch,
        directoryProvider: () async => directory,
      )!;
      final url = Uri.parse('https://fixture.invalid/version.json');
      expect(await fetcher.fetch(url), isNull);
      await envelope.writeAsBytes(List.filled(maxVersionFileBytes + 1, 1));
      expect(await fetcher.fetch(url), isNull);
      await envelope.writeAsString('fixture');
      expect(await fetcher.fetch(Uri.parse('http://fixture.invalid')), isNull);
      expect(utf8.decode((await fetcher.fetch(url))!), 'fixture');
      await envelope.writeAsString('next');
      expect(utf8.decode((await fetcher.fetch(url))!), 'next');
    },
  );

  test(
    'the TEST key cannot authenticate an envelope in the production verifier',
    () {
      final bytes = signedEnvelope(
        payloadBytes(),
        keyId: updateCheckFixtureKeyId,
      );
      final fixture = updateCheckFixtureVerifier(
        updateSwitch: fixtureSwitch,
        publicKeyBase64: publicKey,
      )!;
      expect(
        fixture
            .verify(
              bytes,
              highestAcceptedRank: 0,
              requiredPlatforms: {UpdatePlatform.android},
            )
            .isAccepted,
        isTrue,
      );
      expect(
        VersionFileVerifier(builtInVersionKeys())
            .verify(
              bytes,
              highestAcceptedRank: 0,
              requiredPlatforms: {UpdatePlatform.android},
            )
            .isAccepted,
        isFalse,
      );
      expect(
        fixture
            .verify(
              signedEnvelope(payloadBytes()),
              highestAcceptedRank: 0,
              requiredPlatforms: {UpdatePlatform.android},
            )
            .isAccepted,
        isFalse,
      );
    },
  );

  test(
    'one TEST configuration varies signed runtime manifests through the real service',
    () async {
      final service = UpdateCheckService(
        updateSwitch: fixtureSwitch,
        verifier: updateCheckFixtureVerifier(
          updateSwitch: fixtureSwitch,
          publicKeyBase64: publicKey,
        ),
        fetcher: updateCheckFixtureFetcher(
          updateSwitch: fixtureSwitch,
          directoryProvider: () async => directory,
        ),
        store: UpdateCheckStateStore(directoryProvider: () async => directory),
        installedBuildNumber: () async => '110',
        platform: UpdatePlatform.android,
      );
      Future<void> serve(List<int> bytes) async {
        final temp = File('${envelope.path}.tmp');
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(envelope.path);
      }

      // issuedAt is informational. A genuinely old signed payload is accepted.
      await serve(
        signedEnvelope(
          payloadBytes(issuedAt: 1),
          keyId: updateCheckFixtureKeyId,
        ),
      );
      expect(await service.check(), isA<UpdateDecisionSoft>());
      await serve(
        signedEnvelope(
          payloadBytes(sequence: 2, android: section(130, 115)),
          keyId: updateCheckFixtureKeyId,
        ),
      );
      expect(
        await service.check(),
        const UpdateDecisionHard(
          minBuild: 115,
          reasonCode: UpdateReasonCode.general,
        ),
      );
      // A correctly signed lower sequence cannot replace the newer hard decision.
      await serve(
        signedEnvelope(
          payloadBytes(sequence: 1, android: section(140, 100)),
          keyId: updateCheckFixtureKeyId,
        ),
      );
      expect(await service.check(), isA<UpdateDecisionHard>());
      // A higher sequence from another key cannot replace it either.
      await serve(
        signedEnvelope(
          payloadBytes(sequence: 3, android: section(140, 100)),
          keyId: updateCheckFixtureKeyId,
          signer: testOnlyRogue,
        ),
      );
      expect(await service.check(), isA<UpdateDecisionHard>());
      await envelope.delete();
      expect(await service.check(), isA<UpdateDecisionHard>());
    },
  );
}
