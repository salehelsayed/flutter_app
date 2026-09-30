import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../tool/sims/build_cache.dart';

/// Each consumed profile is bound to the executor's independently prepared
/// digests. A companion may never borrow the primary artifact's attestation.
final class ProductionAndroidArtifact {
  ProductionAndroidArtifact.fromEnvironment(
    this.profileId,
    Map<String, String> environment, {
    required bool primary,
  }) {
    String required(String name) {
      final value = environment[name];
      if (value == null || value.isEmpty) throw StateError('missing $name');
      return value;
    }

    final suffix = profileId.toUpperCase().replaceAll('.', '_');
    file = File(required('SIMS_ARTIFACT_$suffix')).absolute;
    inputDigest = required(
      primary
          ? 'SIMS_ARTIFACT_INPUT_DIGEST'
          : 'SIMS_ARTIFACT_INPUT_DIGEST_$suffix',
    );
    artifactDigest = required(
      primary ? 'SIMS_ARTIFACT_SHA256' : 'SIMS_ARTIFACT_SHA256_$suffix',
    );
    final cacheRoot = environment['SIMS_CACHE_DIR']?.trim();
    final expected = File(
      '${cacheRoot == null || cacheRoot.isEmpty ? 'build/sims/cache' : cacheRoot}'
      '/$profileId/$inputDigest/artifact.apk',
    ).absolute;
    final attestation = BuildAttestation.fromJson(
      Map<String, Object?>.from(
        jsonDecode(
              File('${file.parent.path}/attestation.json').readAsStringSync(),
            )
            as Map,
      ),
    );
    if (file.path != expected.path ||
        File(attestation.artifactPath).absolute.path != file.path ||
        attestation.schemaVersion != 1 ||
        attestation.profileId != profileId ||
        attestation.inputDigest != inputDigest ||
        attestation.artifactDigest != artifactDigest ||
        sha256.convert(file.readAsBytesSync()).toString() != artifactDigest) {
      throw StateError(
        'prepared artifact identity rejected; no fallback build',
      );
    }
  }

  final String profileId;
  late final File file;
  late final String inputDigest, artifactDigest;

  Map<String, Object?> toJson() => {
    'profileId': profileId,
    'inputDigest': inputDigest,
    'artifactDigest': artifactDigest,
  };
}
