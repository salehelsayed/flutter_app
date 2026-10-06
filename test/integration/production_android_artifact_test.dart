import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/production_android_artifact.dart';

void main() {
  late Directory cache;
  const profile = 'android.production_fcm.journey';
  final input = sha256.convert(utf8.encode('provider input')).toString();
  final bytes = utf8.encode('provider APK fixture');
  final digest = sha256.convert(bytes).toString();

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('production-artifact-');
  });
  tearDown(() async => cache.delete(recursive: true));

  Map<String, String> environment(File artifact) => {
    'SIMS_CACHE_DIR': cache.path,
    'SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM_JOURNEY': artifact.path,
    'SIMS_ARTIFACT_INPUT_DIGEST_ANDROID_PRODUCTION_FCM_JOURNEY': input,
    'SIMS_ARTIFACT_SHA256_ANDROID_PRODUCTION_FCM_JOURNEY': digest,
  };

  File prepare({String? profileId, String? inputDigest}) {
    final artifact = File(
      '${cache.path}/${profileId ?? profile}/${inputDigest ?? input}/artifact.apk',
    );
    artifact.parent.createSync(recursive: true);
    artifact.writeAsBytesSync(bytes);
    File('${artifact.parent.path}/attestation.json').writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'profileId': profileId ?? profile,
        'inputDigest': inputDigest ?? input,
        'artifactDigest': digest,
        'artifactPath': artifact.path,
        'redactedCommand': <String>[],
        'createdAt': DateTime.utc(2026).toIso8601String(),
      }),
    );
    return artifact;
  }

  test('companion binds its own profile, input, bytes and cache path', () {
    final artifact = prepare();
    final bound = ProductionAndroidArtifact.fromEnvironment(
      profile,
      environment(artifact),
      primary: false,
    );
    expect(bound.file.path, artifact.absolute.path);
    expect(bound.inputDigest, input);
    expect(bound.artifactDigest, digest);
  });

  test('missing companion digest cannot borrow primary digest', () {
    final artifact = prepare();
    final values = environment(artifact)
      ..remove('SIMS_ARTIFACT_SHA256_ANDROID_PRODUCTION_FCM_JOURNEY')
      ..['SIMS_ARTIFACT_SHA256'] = digest;
    expect(
      () => ProductionAndroidArtifact.fromEnvironment(
        profile,
        values,
        primary: false,
      ),
      throwsStateError,
    );
  });

  test('stale input and swapped profile attestations are rejected', () {
    final artifact = prepare(profileId: 'android.e2e.production');
    final values = environment(artifact);
    expect(
      () => ProductionAndroidArtifact.fromEnvironment(
        profile,
        values,
        primary: false,
      ),
      throwsStateError,
    );
    final correct = prepare();
    values['SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM_JOURNEY'] = correct.path;
    values['SIMS_ARTIFACT_INPUT_DIGEST_ANDROID_PRODUCTION_FCM_JOURNEY'] = sha256
        .convert(utf8.encode('stale'))
        .toString();
    expect(
      () => ProductionAndroidArtifact.fromEnvironment(
        profile,
        values,
        primary: false,
      ),
      throwsStateError,
    );
  });

  test('tampered bytes and foreign ambient artifact are rejected', () {
    final artifact = prepare();
    artifact.writeAsBytesSync(utf8.encode('tampered'));
    expect(
      () => ProductionAndroidArtifact.fromEnvironment(
        profile,
        environment(artifact),
        primary: false,
      ),
      throwsStateError,
    );
    artifact.writeAsBytesSync(bytes);
    final foreign = File('${cache.path}/ambient.apk')..writeAsBytesSync(bytes);
    File('${foreign.parent.path}/attestation.json').writeAsStringSync(
      File('${artifact.parent.path}/attestation.json').readAsStringSync(),
    );
    expect(
      () => ProductionAndroidArtifact.fromEnvironment(
        profile,
        environment(foreign),
        primary: false,
      ),
      throwsStateError,
    );
  });
}
