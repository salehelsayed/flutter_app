import 'dart:convert';
import 'dart:io';

import 'verdict.dart';

enum SimsFailureClass { product, test, harness, environment, flake }

final class CheckpointValidation {
  const CheckpointValidation({required this.isValid, required this.reasons});

  final bool isValid;
  final List<String> reasons;
}

final class SimsRetryResumePlan {
  const SimsRetryResumePlan({
    required this.retryIds,
    required this.resumeIds,
    required this.finalCleanRunRequired,
  });

  final List<String> retryIds;
  final List<String> resumeIds;
  final bool finalCleanRunRequired;
}

final class SimsCheckpoint {
  const SimsCheckpoint({
    required this.failedId,
    required this.manifestDigest,
    required this.sourceDigest,
    required this.deviceDigest,
    required this.buildArtifactDigests,
    required this.redactedCommand,
    required this.targetAssignments,
    required this.targetStateDigests,
    required this.logPaths,
    required this.failureClass,
    required this.passedIds,
    required this.passedVerdicts,
    required this.nextId,
    required this.createdAt,
    required this.finalCleanRunRequired,
  });

  factory SimsCheckpoint.fromJson(Map<String, Object?> json) => SimsCheckpoint(
    failedId: _requiredString(json, 'failedId'),
    manifestDigest: _requiredString(json, 'manifestDigest'),
    sourceDigest: _requiredString(json, 'sourceDigest'),
    deviceDigest: _requiredString(json, 'deviceDigest'),
    buildArtifactDigests: _stringMap(json, 'buildArtifactDigests'),
    redactedCommand: _stringList(json, 'redactedCommand'),
    targetAssignments: _stringMap(json, 'targetAssignments'),
    targetStateDigests: _stringMap(json, 'targetStateDigests'),
    logPaths: _stringList(json, 'logPaths'),
    failureClass: SimsFailureClass.values.byName(
      _requiredString(json, 'failureClass'),
    ),
    passedIds: _stringList(json, 'passedIds'),
    passedVerdicts: _verdictList(json, 'passedVerdicts'),
    nextId: json['nextId'] as String?,
    createdAt: DateTime.parse(_requiredString(json, 'createdAt')).toUtc(),
    finalCleanRunRequired: _requiredBool(json, 'finalCleanRunRequired'),
  );

  static SimsCheckpoint loadSync(File file) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      throw const FormatException('checkpoint root must be an object');
    }
    return SimsCheckpoint.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  final String failedId;
  final String manifestDigest;
  final String sourceDigest;
  final String deviceDigest;
  final Map<String, String> buildArtifactDigests;
  final List<String> redactedCommand;
  final Map<String, String> targetAssignments;
  final Map<String, String> targetStateDigests;
  final List<String> logPaths;
  final SimsFailureClass failureClass;
  final List<String> passedIds;
  final List<SimsVerdict> passedVerdicts;
  final String? nextId;
  final DateTime createdAt;
  final bool finalCleanRunRequired;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'failedId': failedId,
    'manifestDigest': manifestDigest,
    'sourceDigest': sourceDigest,
    'deviceDigest': deviceDigest,
    'buildArtifactDigests': buildArtifactDigests,
    'redactedCommand': redactedCommand,
    'targetAssignments': targetAssignments,
    'targetStateDigests': targetStateDigests,
    'logPaths': logPaths,
    'failureClass': failureClass.name,
    'passedIds': passedIds,
    'passedVerdicts': passedVerdicts
        .map((verdict) => verdict.toJson())
        .toList(growable: false),
    if (nextId != null) 'nextId': nextId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'finalCleanRunRequired': finalCleanRunRequired,
  };

  void saveSync(File file) {
    file.parent.createSync(recursive: true);
    final temporary = File('${file.path}.tmp');
    temporary.writeAsStringSync('${jsonEncode(toJson())}\n', flush: true);
    temporary.renameSync(file.path);
  }

  SimsRetryResumePlan retryResumePlan(List<String> orderedPlanIds) {
    final failedIndex = orderedPlanIds.indexOf(failedId);
    if (failedIndex < 0) {
      throw StateError(
        'Checkpoint capability is absent from the current plan: $failedId',
      );
    }
    final passed = passedIds.toSet();
    final resume = orderedPlanIds
        .skip(failedIndex + 1)
        .where((id) => !passed.contains(id))
        .toList(growable: false);
    return SimsRetryResumePlan(
      retryIds: <String>[failedId],
      resumeIds: resume,
      finalCleanRunRequired: true,
    );
  }

  CheckpointValidation validateResume({
    required String manifestDigest,
    required String sourceDigest,
    required String deviceDigest,
    required Map<String, String> buildArtifactDigests,
    Set<String>? relevantBuildProfileIds,
    bool allowRepairInputChanges = false,
    Map<String, String>? currentTargetAssignments,
    Map<String, String>? currentTargetStateDigests,
  }) {
    final reasons = <String>[];
    if (this.manifestDigest != manifestDigest) {
      reasons.add('manifest digest changed');
    }
    if (!allowRepairInputChanges && this.sourceDigest != sourceDigest) {
      reasons.add('source digest changed');
    }
    final selectedTargetContinuityMatches =
        allowRepairInputChanges &&
        _completeTargetContinuityMatches(
          targetAssignments,
          targetStateDigests,
          currentTargetAssignments,
          currentTargetStateDigests,
        );
    if (this.deviceDigest != deviceDigest && !selectedTargetContinuityMatches) {
      reasons.add('device matrix changed');
    }
    final artifactDigestsMatch = relevantBuildProfileIds == null
        ? _sameMapEntries(
            this.buildArtifactDigests,
            buildArtifactDigests,
            this.buildArtifactDigests.keys.toSet(),
          )
        : _sameMapEntries(
            this.buildArtifactDigests,
            buildArtifactDigests,
            relevantBuildProfileIds,
          );
    if (!allowRepairInputChanges && !artifactDigestsMatch) {
      reasons.add('build artifact digests changed');
    }
    return CheckpointValidation(
      isValid: reasons.isEmpty,
      reasons: List<String>.unmodifiable(reasons),
    );
  }
}

bool _completeTargetContinuityMatches(
  Map<String, String> checkpointAssignments,
  Map<String, String> checkpointStateDigests,
  Map<String, String>? currentAssignments,
  Map<String, String>? currentStateDigests,
) {
  if (checkpointAssignments.isEmpty ||
      currentAssignments == null ||
      currentStateDigests == null) {
    return false;
  }
  final assignedTargetIds = checkpointAssignments.values.toSet();
  if (assignedTargetIds.isEmpty ||
      checkpointStateDigests.keys
          .toSet()
          .difference(assignedTargetIds)
          .isNotEmpty ||
      assignedTargetIds
          .difference(checkpointStateDigests.keys.toSet())
          .isNotEmpty) {
    return false;
  }
  return _sameMap(checkpointAssignments, currentAssignments) &&
      _sameMap(checkpointStateDigests, currentStateDigests);
}

bool _sameMap(Map<String, String> left, Map<String, String> right) =>
    left.length == right.length &&
    left.entries.every((entry) => right[entry.key] == entry.value);

bool _sameMapEntries(
  Map<String, String> left,
  Map<String, String> right,
  Set<String> keys,
) => keys.every(
  (key) =>
      left.containsKey(key) &&
      right.containsKey(key) &&
      left[key] == right[key],
);

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a nonempty string');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a boolean');
  return value;
}

List<String> _stringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$key must be a string array');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

Map<String, String> _stringMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map ||
      value.entries.any(
        (entry) => entry.key is! String || entry.value is! String,
      )) {
    throw FormatException('$key must be a string map');
  }
  return Map<String, String>.unmodifiable(value.cast<String, String>());
}

List<SimsVerdict> _verdictList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const <SimsVerdict>[];
  if (value is! List || value.any((item) => item is! Map)) {
    throw FormatException('$key must be an object array');
  }
  return List<SimsVerdict>.unmodifiable(
    value.map(
      (item) => SimsVerdict.fromJson(
        (item as Map).map<String, Object?>(
          (entryKey, entryValue) => MapEntry('$entryKey', entryValue),
        ),
      ),
    ),
  );
}
