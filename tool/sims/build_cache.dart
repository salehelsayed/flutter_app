import 'dart:convert';

import 'package:crypto/crypto.dart';

/// All inputs that can affect a reusable build artifact.
///
/// [runtimeConfig] is intentionally excluded from [inputDigest]. Runtime
/// scenario, role, nonce, and run-specific state are staged after the shared
/// artifact is installed.
final class BuildProfileInput {
  BuildProfileInput({
    required this.profileId,
    required this.platform,
    required this.architecture,
    required this.entrypoint,
    required this.mode,
    required this.flavor,
    required this.compileDefines,
    required this.appId,
    required this.providerConfigDigests,
    required this.signingDigests,
    required this.inputFiles,
    required this.toolchain,
    required this.buildOptions,
    required this.runtimeConfig,
  });

  final String profileId;
  final String platform;
  final String architecture;
  final String entrypoint;
  final String mode;
  final String flavor;
  final Map<String, String> compileDefines;
  final String appId;
  final Map<String, String> providerConfigDigests;
  final Map<String, String> signingDigests;
  final Map<String, List<int>> inputFiles;
  final Map<String, String> toolchain;
  final List<String> buildOptions;
  final Map<String, Object?> runtimeConfig;

  String get inputDigest =>
      sha256.convert(utf8.encode(_canonicalJson(fingerprintJson))).toString();

  Map<String, Object?> get fingerprintJson => <String, Object?>{
    'profileId': profileId,
    'platform': platform,
    'architecture': architecture,
    'entrypoint': entrypoint,
    'mode': mode,
    'flavor': flavor,
    'compileDefines': compileDefines,
    'appId': appId,
    'providerConfigDigests': providerConfigDigests,
    'signingDigests': signingDigests,
    'inputFiles': <String, String>{
      for (final entry in inputFiles.entries)
        entry.key: sha256.convert(entry.value).toString(),
    },
    'toolchain': toolchain,
    'buildOptions': buildOptions,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    ...fingerprintJson,
    'inputDigest': inputDigest,
    'runtimeConfig': runtimeConfig,
  };
}

final class BuildRequestSet {
  const BuildRequestSet._(this.profileIds);

  factory BuildRequestSet.fromProfileIds(Iterable<String> profileIds) {
    final unique = <String>{};
    for (final profileId in profileIds) {
      if (profileId.trim().isEmpty) {
        throw ArgumentError.value(profileId, 'profileIds', 'must be nonempty');
      }
      unique.add(profileId);
    }
    return BuildRequestSet._(List<String>.unmodifiable(unique));
  }

  final List<String> profileIds;
}

final class BuildAttestation {
  const BuildAttestation({
    required this.schemaVersion,
    required this.profileId,
    required this.inputDigest,
    required this.artifactDigest,
    required this.artifactPath,
    required this.redactedCommand,
    required this.createdAt,
  });

  factory BuildAttestation.create({
    required BuildProfileInput input,
    required List<int> artifactBytes,
    required String artifactPath,
    required List<String> redactedCommand,
    required DateTime createdAt,
  }) => BuildAttestation(
    schemaVersion: 1,
    profileId: input.profileId,
    inputDigest: input.inputDigest,
    artifactDigest: sha256.convert(artifactBytes).toString(),
    artifactPath: artifactPath,
    redactedCommand: List<String>.unmodifiable(redactedCommand),
    createdAt: createdAt.toUtc(),
  );

  factory BuildAttestation.fromJson(Map<String, Object?> json) {
    final command = json['redactedCommand'];
    if (command is! List || command.any((value) => value is! String)) {
      throw const FormatException('redactedCommand must be a string array');
    }
    return BuildAttestation(
      schemaVersion: _requiredInt(json, 'schemaVersion'),
      profileId: _requiredString(json, 'profileId'),
      inputDigest: _requiredDigest(json, 'inputDigest'),
      artifactDigest: _requiredDigest(json, 'artifactDigest'),
      artifactPath: _requiredString(json, 'artifactPath'),
      redactedCommand: command.cast<String>(),
      createdAt: DateTime.parse(_requiredString(json, 'createdAt')).toUtc(),
    );
  }

  final int schemaVersion;
  final String profileId;
  final String inputDigest;
  final String artifactDigest;
  final String artifactPath;
  final List<String> redactedCommand;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'profileId': profileId,
    'inputDigest': inputDigest,
    'artifactDigest': artifactDigest,
    'artifactPath': artifactPath,
    'redactedCommand': redactedCommand,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

enum BuildCacheMissReason {
  none,
  unattested,
  unsupportedAttestation,
  wrongProfile,
  wrongInput,
  wrongArtifact,
}

final class BuildCacheVerification {
  const BuildCacheVerification({required this.isHit, required this.reason});

  final bool isHit;
  final BuildCacheMissReason reason;
}

abstract final class BuildCacheVerifier {
  static BuildCacheVerification verify(
    BuildProfileInput input,
    BuildAttestation? attestation,
    List<int> artifactBytes,
  ) {
    if (attestation == null) {
      return const BuildCacheVerification(
        isHit: false,
        reason: BuildCacheMissReason.unattested,
      );
    }
    if (attestation.schemaVersion != 1) {
      return const BuildCacheVerification(
        isHit: false,
        reason: BuildCacheMissReason.unsupportedAttestation,
      );
    }
    if (attestation.profileId != input.profileId) {
      return const BuildCacheVerification(
        isHit: false,
        reason: BuildCacheMissReason.wrongProfile,
      );
    }
    if (attestation.inputDigest != input.inputDigest) {
      return const BuildCacheVerification(
        isHit: false,
        reason: BuildCacheMissReason.wrongInput,
      );
    }
    if (attestation.artifactDigest !=
        sha256.convert(artifactBytes).toString()) {
      return const BuildCacheVerification(
        isHit: false,
        reason: BuildCacheMissReason.wrongArtifact,
      );
    }
    return const BuildCacheVerification(
      isHit: true,
      reason: BuildCacheMissReason.none,
    );
  }
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is Iterable) return value.map(_canonicalize).toList();
  return value;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a nonempty string');
  }
  return value;
}

String _requiredDigest(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('$key must be a lowercase SHA-256 digest');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer');
  return value;
}
