import 'manifest.dart';

class SimsPlan {
  const SimsPlan({
    required this.mode,
    required this.simultaneous,
    required this.releaseEligibleCandidate,
    required this.manifestDigest,
    required this.family,
    required this.onlyId,
    required this.rows,
    this.lane,
  });

  factory SimsPlan.fromJson(Map<String, Object?> json) => SimsPlan(
    mode: SimsModeName.parse(json['mode']! as String),
    simultaneous: json['simultaneous']! as bool,
    releaseEligibleCandidate: json['releaseEligibleCandidate']! as bool,
    manifestDigest: json['manifestDigest']! as String,
    family: json['family'] as String?,
    onlyId: json['onlyId'] as String?,
    lane: json['lane'] as String?,
    rows: (json['rows']! as List<dynamic>)
        .map(
          (row) => CapabilitySpec.fromJson(
            (row as Map).map<String, Object?>(
              (key, value) => MapEntry('$key', value),
            ),
          ),
        )
        .toList(growable: false),
  );

  final SimsMode mode;
  final bool simultaneous;
  final bool releaseEligibleCandidate;
  final String manifestDigest;
  final String? family;
  final String? onlyId;
  final String? lane;
  final List<CapabilitySpec> rows;

  Set<String> get selectedIds => rows.map((row) => row.id).toSet();

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'mode': mode.wireName,
    'simultaneous': simultaneous,
    'releaseEligibleCandidate': releaseEligibleCandidate,
    'manifestDigest': manifestDigest,
    if (family != null) 'family': family,
    if (onlyId != null) 'onlyId': onlyId,
    if (lane != null) 'lane': lane,
    'selectedIds': rows.map((row) => row.id).toList(),
    'rows': rows.map((row) => row.toJson()).toList(),
  };
}

class SimsPlanner {
  const SimsPlanner(this.manifest);

  final SimsManifest manifest;

  SimsPlan compile({
    SimsMode mode = SimsMode.major,
    String? family,
    String? lane,
    String? onlyId,
    bool simultaneous = false,
  }) {
    manifest.validateOrThrow();
    final activeForMode = manifest.capabilities
        .where((capability) => capability.participatesIn(mode))
        .toList(growable: false);
    final byId = <String, CapabilitySpec>{
      for (final capability in activeForMode) capability.id: capability,
    };

    Iterable<CapabilitySpec> initial = activeForMode;
    if (family != null) {
      initial = initial.where(
        (capability) => capability.families.contains(family),
      );
    }
    if (lane != null) {
      initial = initial.where((capability) => capability.lane == lane);
    }
    if (onlyId != null) {
      final selected = byId[onlyId];
      if (selected == null) {
        throw StateError('Unknown or inactive capability for $mode: $onlyId');
      }
      initial = <CapabilitySpec>[selected];
    }

    final selectedIds = initial.map((capability) => capability.id).toSet();
    void includeDependencies(String id) {
      final capability = byId[id];
      if (capability == null) {
        throw StateError('Selected capability depends on inactive row: $id');
      }
      for (final dependency in capability.dependencies) {
        if (selectedIds.add(dependency)) includeDependencies(dependency);
      }
    }

    for (final id in selectedIds.toList(growable: false)) {
      includeDependencies(id);
    }
    if (selectedIds.isEmpty) {
      throw StateError('No sims capabilities matched the requested selection.');
    }

    final selected = activeForMode
        .where((capability) => selectedIds.contains(capability.id))
        .toList(growable: false);
    final ordered = _topologicalOrder(selected);
    return SimsPlan(
      mode: mode,
      simultaneous: simultaneous,
      releaseEligibleCandidate:
          mode == SimsMode.major &&
          family == null &&
          lane == null &&
          onlyId == null,
      manifestDigest: manifest.digest,
      family: family,
      onlyId: onlyId,
      rows: ordered,
      lane: lane,
    );
  }
}

List<CapabilitySpec> _topologicalOrder(List<CapabilitySpec> rows) {
  final byId = <String, CapabilitySpec>{for (final row in rows) row.id: row};
  final originalOrder = <String, int>{
    for (var index = 0; index < rows.length; index++) rows[index].id: index,
  };
  final remainingDependencies = <String, Set<String>>{
    for (final row in rows)
      row.id: row.dependencies.where(byId.containsKey).toSet(),
  };
  final ordered = <CapabilitySpec>[];

  while (remainingDependencies.isNotEmpty) {
    final ready =
        remainingDependencies.entries
            .where((entry) => entry.value.isEmpty)
            .map((entry) => entry.key)
            .toList()
          ..sort(
            (left, right) =>
                originalOrder[left]!.compareTo(originalOrder[right]!),
          );
    if (ready.isEmpty) {
      throw StateError(
        'Sims capability dependency cycle: '
        '${remainingDependencies.keys.toList()..sort()}',
      );
    }
    for (final id in ready) {
      ordered.add(byId[id]!);
      remainingDependencies.remove(id);
      for (final dependencies in remainingDependencies.values) {
        dependencies.remove(id);
      }
    }
  }
  return List<CapabilitySpec>.unmodifiable(ordered);
}
