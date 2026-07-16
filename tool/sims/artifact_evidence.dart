import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Durable, content-addressed proof emitted by a runtime sims adapter.
///
/// The adapter supplies this claim, but the sims executor and report verifier
/// both re-read [path], recompute [sha256Digest], and bind [validatorIds] to the
/// exact validator list declared by the selected manifest row.
final class SimsArtifactEvidence {
  const SimsArtifactEvidence({
    required this.path,
    required this.sha256Digest,
    required this.validatorIds,
  });

  factory SimsArtifactEvidence.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('artifactEvidence must be an object');
    }
    final json = value.map<String, Object?>(
      (key, item) => MapEntry('$key', item),
    );
    final path = json['path'];
    final digest = json['sha256'];
    final validators = json['validatorIds'];
    if (path is! String || path.trim().isEmpty) {
      throw const FormatException(
        'artifactEvidence.path must be a nonempty string',
      );
    }
    if (digest is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException(
        'artifactEvidence.sha256 must be a lowercase SHA-256 digest',
      );
    }
    if (validators is! List ||
        validators.isEmpty ||
        validators.any((validator) => validator is! String)) {
      throw const FormatException(
        'artifactEvidence.validatorIds must be a nonempty string array',
      );
    }
    final validatorIds = validators.cast<String>();
    if (validatorIds.any((validator) => validator.trim().isEmpty) ||
        validatorIds.toSet().length != validatorIds.length) {
      throw const FormatException(
        'artifactEvidence.validatorIds must be nonempty and unique',
      );
    }
    return SimsArtifactEvidence(
      path: path,
      sha256Digest: digest,
      validatorIds: List<String>.unmodifiable(validatorIds),
    );
  }

  final String path;
  final String sha256Digest;
  final List<String> validatorIds;

  SimsArtifactEvidence copyWith({String? path}) => SimsArtifactEvidence(
    path: path ?? this.path,
    sha256Digest: sha256Digest,
    validatorIds: validatorIds,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'sha256': sha256Digest,
    'validatorIds': validatorIds,
  };
}

/// Writes a durable proof artifact atomically and returns the content-addressed
/// evidence envelope that an adapter places in its result sentinel.
SimsArtifactEvidence writeSimsArtifactEvidenceSync({
  required Directory directory,
  required String capabilityId,
  required List<String> validatorIds,
  required Map<String, Object?> payload,
}) {
  if (capabilityId.trim().isEmpty || validatorIds.isEmpty) {
    throw const FormatException(
      'proof artifacts require a capability ID and validator IDs',
    );
  }
  directory.createSync(recursive: true);
  final safeCapability = capabilityId.replaceAll(
    RegExp(r'[^A-Za-z0-9_.-]'),
    '_',
  );
  final token = '${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';
  final file = File('${directory.path}/$safeCapability-$token.json');
  final temporary = File('${file.path}.tmp');
  if (temporary.existsSync()) temporary.deleteSync();
  final encoded = jsonEncode(<String, Object?>{
    ...payload,
    'schema': 'mknoon.sims.proof.v1',
    'capabilityId': capabilityId,
    'validatorIds': validatorIds,
  });
  temporary.writeAsStringSync('$encoded\n', flush: true);
  if (file.existsSync()) file.deleteSync();
  temporary.renameSync(file.path);
  final canonicalPath = file.resolveSymbolicLinksSync();
  final digest = sha256
      .convert(File(canonicalPath).readAsBytesSync())
      .toString();
  return SimsArtifactEvidence(
    path: canonicalPath,
    sha256Digest: digest,
    validatorIds: List<String>.unmodifiable(validatorIds),
  );
}

final class SimsArtifactEvidenceAudit {
  const SimsArtifactEvidenceAudit._({
    required this.isValid,
    required this.detail,
    this.canonicalPath,
  });

  const SimsArtifactEvidenceAudit.valid(String canonicalPath)
    : this._(
        isValid: true,
        detail: 'artifact evidence is valid',
        canonicalPath: canonicalPath,
      );

  const SimsArtifactEvidenceAudit.invalid(String detail)
    : this._(isValid: false, detail: detail);

  final bool isValid;
  final String detail;
  final String? canonicalPath;
}

/// Audits evidence without trusting the producer's existence, digest, or
/// validator-binding claims.
SimsArtifactEvidenceAudit auditSimsArtifactEvidence({
  required SimsArtifactEvidence evidence,
  required List<String> expectedValidatorIds,
}) {
  if (!_sameOrderedStrings(evidence.validatorIds, expectedValidatorIds)) {
    return SimsArtifactEvidenceAudit.invalid(
      'artifact validator IDs do not exactly match the manifest: expected '
      '${expectedValidatorIds.join(', ')}, received '
      '${evidence.validatorIds.join(', ')}',
    );
  }

  final absolutePath = File(evidence.path).absolute.path;
  if (FileSystemEntity.typeSync(absolutePath, followLinks: false) !=
      FileSystemEntityType.file) {
    return SimsArtifactEvidenceAudit.invalid(
      'artifact evidence path is not a regular file: $absolutePath',
    );
  }

  late final String canonicalPath;
  try {
    canonicalPath = File(absolutePath).resolveSymbolicLinksSync();
  } on FileSystemException catch (error) {
    return SimsArtifactEvidenceAudit.invalid(
      'artifact evidence path cannot be resolved: ${error.message}',
    );
  }

  late final String actualDigest;
  try {
    actualDigest = sha256
        .convert(File(canonicalPath).readAsBytesSync())
        .toString();
  } on FileSystemException catch (error) {
    return SimsArtifactEvidenceAudit.invalid(
      'artifact evidence cannot be read: ${error.message}',
    );
  }
  if (actualDigest != evidence.sha256Digest) {
    return SimsArtifactEvidenceAudit.invalid(
      'artifact evidence SHA-256 mismatch: expected '
      '${evidence.sha256Digest}, computed $actualDigest',
    );
  }
  return SimsArtifactEvidenceAudit.valid(canonicalPath);
}

bool _sameOrderedStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
