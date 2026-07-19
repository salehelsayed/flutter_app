import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const targetUnavailableNaReason = 'target_unavailable_by_project_policy';

const requiredCriticalCorePaths = <String>{
  'lib/core/bridge',
  'lib/core/database',
  'lib/core/inbox',
  'lib/core/lifecycle',
  'lib/core/local_discovery',
  'lib/core/media',
  'lib/core/notifications',
  'lib/core/permissions',
  'lib/core/secure_storage',
  'lib/core/services',
};

enum SimsMode { smoke, full, major }

extension SimsModeName on SimsMode {
  String get wireName => name;

  static SimsMode parse(String value) => switch (value) {
    'smoke' => SimsMode.smoke,
    'full' => SimsMode.full,
    'major' => SimsMode.major,
    _ => throw FormatException('Unknown sims mode: $value'),
  };
}

enum ResourceAccess { read, write, exclusive }

const Set<String> _simsExactResourceNames = <String>{
  'host.cpu',
  'performance.global',
  'unknown',
};

const List<String> _simsResourcePrefixes = <String>[
  'artifact:',
  'build:',
  'device:',
  'device-control:',
  'relay-mutation:',
];

bool isKnownSimsResourceName(String name) {
  if (_simsExactResourceNames.contains(name)) return true;
  for (final prefix in _simsResourcePrefixes) {
    if (name.startsWith(prefix) && name.length > prefix.length) return true;
  }
  return false;
}

class ResourceLock {
  const ResourceLock({required this.name, required this.access});

  factory ResourceLock.fromJson(Map<String, Object?> json) => ResourceLock(
    name: _requiredString(json, 'name'),
    access: ResourceAccess.values.byName(_requiredString(json, 'access')),
  );

  final String name;
  final ResourceAccess access;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'access': access.name,
  };

  @override
  String toString() => '${access.name}:$name';
}

class BuildProfileSpec {
  const BuildProfileSpec({
    required this.id,
    required this.platform,
    required this.artifactKind,
    required this.buildRequired,
    required this.compileDefines,
    required this.declaredException,
  });

  factory BuildProfileSpec.fromJson(Map<String, Object?> json) =>
      BuildProfileSpec(
        id: _requiredString(json, 'id'),
        platform: _requiredString(json, 'platform'),
        artifactKind: _requiredString(json, 'artifactKind'),
        buildRequired: _requiredBool(json, 'buildRequired'),
        compileDefines: _stringMap(json['compileDefines']),
        declaredException: _optionalBool(json, 'declaredException') ?? false,
      );

  final String id;
  final String platform;
  final String artifactKind;
  final bool buildRequired;
  final Map<String, String> compileDefines;
  final bool declaredException;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'platform': platform,
    'artifactKind': artifactKind,
    'buildRequired': buildRequired,
    'compileDefines': compileDefines,
    'declaredException': declaredException,
  };
}

class CapabilitySpec {
  const CapabilitySpec({
    required this.id,
    required this.owner,
    required this.proofBoundaryId,
    required this.assertionIds,
    required this.lane,
    required this.modes,
    required this.families,
    required this.required,
    required this.command,
    required this.buildProfileId,
    required this.dependencies,
    required this.resources,
    required this.targetCapabilities,
    required this.allowedNaReason,
    required this.artifactRequired,
    required this.artifactValidator,
    this.explicitArtifactValidators = const <String>[],
    required this.active,
    required this.declaredBuildException,
    this.automationReady = true,
  });

  factory CapabilitySpec.fromJson(Map<String, Object?> json) => CapabilitySpec(
    id: _requiredString(json, 'id'),
    owner: _requiredString(json, 'owner'),
    proofBoundaryId: _requiredString(json, 'proofBoundary'),
    assertionIds: _stringList(json['assertions']),
    lane: _requiredString(json, 'lane'),
    modes: _stringList(json['modes']).map(SimsModeName.parse).toSet(),
    families: _stringList(json['families']).toSet(),
    required: _requiredBool(json, 'required'),
    command: _stringList(json['command']),
    buildProfileId: _requiredString(json, 'buildProfile'),
    dependencies: _stringList(json['dependencies']),
    resources: _objectList(
      json['resources'],
    ).map(ResourceLock.fromJson).toList(growable: false),
    targetCapabilities: _stringList(json['targetCapabilities']),
    allowedNaReason: _optionalString(json, 'allowedNaReason'),
    artifactRequired: _optionalBool(json, 'artifactRequired') ?? false,
    artifactValidator: _optionalString(json, 'artifactValidator'),
    explicitArtifactValidators: json['artifactValidators'] == null
        ? const <String>[]
        : _stringList(json['artifactValidators']),
    active: _optionalBool(json, 'active') ?? true,
    declaredBuildException:
        _optionalBool(json, 'declaredBuildException') ?? false,
    automationReady: _optionalBool(json, 'automationReady') ?? true,
  );

  final String id;
  final String owner;
  final String proofBoundaryId;
  final List<String> assertionIds;
  final String lane;
  final Set<SimsMode> modes;
  final Set<String> families;
  final bool required;
  final List<String> command;
  final String buildProfileId;
  final List<String> dependencies;
  final List<ResourceLock> resources;
  final List<String> targetCapabilities;
  final String? allowedNaReason;
  final bool artifactRequired;
  final String? artifactValidator;
  final List<String> explicitArtifactValidators;
  List<String> get artifactValidators => explicitArtifactValidators.isNotEmpty
      ? explicitArtifactValidators
      : artifactValidator == null
      ? const <String>[]
      : <String>[artifactValidator!];
  final bool active;
  final bool declaredBuildException;
  final bool automationReady;

  String get commandKey => jsonEncode(command);

  bool participatesIn(SimsMode mode) => active && modes.contains(mode);

  CapabilitySpec copyWith({
    String? id,
    String? proofBoundaryId,
    List<String>? command,
    List<String>? dependencies,
    List<ResourceLock>? resources,
    List<String>? targetCapabilities,
    Set<SimsMode>? modes,
    bool? required,
    bool? active,
  }) => CapabilitySpec(
    id: id ?? this.id,
    owner: owner,
    proofBoundaryId: proofBoundaryId ?? this.proofBoundaryId,
    assertionIds: assertionIds,
    lane: lane,
    modes: modes ?? this.modes,
    families: families,
    required: required ?? this.required,
    command: command ?? this.command,
    buildProfileId: buildProfileId,
    dependencies: dependencies ?? this.dependencies,
    resources: resources ?? this.resources,
    targetCapabilities: targetCapabilities ?? this.targetCapabilities,
    allowedNaReason: allowedNaReason,
    artifactRequired: artifactRequired,
    artifactValidator: artifactValidator,
    explicitArtifactValidators: explicitArtifactValidators,
    active: active ?? this.active,
    declaredBuildException: declaredBuildException,
    automationReady: automationReady,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'owner': owner,
    'proofBoundary': proofBoundaryId,
    'assertions': assertionIds,
    'lane': lane,
    'modes': modes.map((mode) => mode.wireName).toList()..sort(),
    'families': families.toList()..sort(),
    'required': required,
    'command': command,
    'buildProfile': buildProfileId,
    'dependencies': dependencies,
    'resources': resources.map((resource) => resource.toJson()).toList(),
    'targetCapabilities': targetCapabilities,
    if (allowedNaReason != null) 'allowedNaReason': allowedNaReason,
    'artifactRequired': artifactRequired,
    if (artifactValidator != null) 'artifactValidator': artifactValidator,
    if (artifactValidators.length > 1 ||
        (artifactValidators.length == 1 && artifactValidator == null))
      'artifactValidators': artifactValidators,
    'active': active,
    'declaredBuildException': declaredBuildException,
    'automationReady': automationReady,
  };
}

class FeatureOwnership {
  const FeatureOwnership({
    required this.path,
    required this.capabilityId,
    required this.critical,
    required this.rationale,
  });

  factory FeatureOwnership.fromJson(Map<String, Object?> json) =>
      FeatureOwnership(
        path: _requiredString(json, 'path').replaceAll('\\', '/'),
        capabilityId: _requiredString(json, 'capability'),
        critical: _requiredBool(json, 'critical'),
        rationale: _optionalString(json, 'rationale') ?? '',
      );

  final String path;
  final String capabilityId;
  final bool critical;
  final String rationale;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'capability': capabilityId,
    'critical': critical,
    if (rationale.isNotEmpty) 'rationale': rationale,
  };
}

class SimsManifest {
  const SimsManifest({
    required this.schemaVersion,
    required this.buildProfiles,
    required this.capabilities,
    required this.ownership,
  });

  factory SimsManifest.fromJson(Map<String, Object?> json) => SimsManifest(
    schemaVersion: _requiredInt(json, 'schemaVersion'),
    buildProfiles: _objectList(
      json['buildProfiles'],
    ).map(BuildProfileSpec.fromJson).toList(growable: false),
    capabilities: _objectList(
      json['capabilities'],
    ).map(CapabilitySpec.fromJson).toList(growable: false),
    ownership: _objectList(
      json['ownership'],
    ).map(FeatureOwnership.fromJson).toList(growable: false),
  );

  factory SimsManifest.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Sims manifest root must be a JSON object.');
    }
    return SimsManifest.fromJson(decoded);
  }

  static SimsManifest loadSync(File file) =>
      SimsManifest.fromJsonString(file.readAsStringSync());

  final int schemaVersion;
  final List<BuildProfileSpec> buildProfiles;
  final List<CapabilitySpec> capabilities;
  final List<FeatureOwnership> ownership;

  String get digest =>
      sha256.convert(utf8.encode(canonicalJson(toJson()))).toString();

  CapabilitySpec? capabilityById(String id) {
    for (final capability in capabilities) {
      if (capability.id == id) return capability;
    }
    return null;
  }

  BuildProfileSpec? buildProfileById(String id) {
    for (final profile in buildProfiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  SimsManifest copyWith({List<CapabilitySpec>? capabilities}) => SimsManifest(
    schemaVersion: schemaVersion,
    buildProfiles: buildProfiles,
    capabilities: capabilities ?? this.capabilities,
    ownership: ownership,
  );

  List<String> validate({
    Set<String>? requiredFeaturePaths,
    Set<String>? requiredCorePaths,
  }) {
    final errors = <String>[];
    if (schemaVersion != 1) {
      errors.add('Unsupported manifest schemaVersion: $schemaVersion');
    }

    final profileIds = <String>{};
    for (final profile in buildProfiles) {
      if (!profileIds.add(profile.id)) {
        errors.add('Duplicate build profile ID: ${profile.id}');
      }
      if (profile.id.isEmpty ||
          profile.platform.isEmpty ||
          profile.artifactKind.isEmpty) {
        errors.add('Incomplete build profile: ${profile.id}');
      }
    }

    final ids = <String>{};
    final boundaries = <String>{};
    final commands = <String>{};
    for (final capability in capabilities) {
      if (!ids.add(capability.id)) {
        errors.add('Duplicate capability ID: ${capability.id}');
      }
      if (!boundaries.add(capability.proofBoundaryId)) {
        errors.add('Duplicate proof boundary: ${capability.proofBoundaryId}');
      }
      if (!commands.add(capability.commandKey)) {
        errors.add(
          'Duplicate executable command: ${capability.command.join(' ')}',
        );
      }
      if (capability.id.isEmpty ||
          capability.owner.isEmpty ||
          capability.proofBoundaryId.isEmpty ||
          capability.assertionIds.isEmpty ||
          capability.lane.isEmpty ||
          capability.modes.isEmpty ||
          capability.families.isEmpty ||
          capability.command.isEmpty ||
          capability.buildProfileId.isEmpty ||
          capability.resources.isEmpty) {
        errors.add('Incomplete capability row: ${capability.id}');
      }
      if (!profileIds.contains(capability.buildProfileId)) {
        errors.add(
          'Unknown build profile ${capability.buildProfileId} for ${capability.id}',
        );
      }
      if (capability.allowedNaReason != null &&
          capability.allowedNaReason != targetUnavailableNaReason) {
        errors.add('Invalid N/A reason for ${capability.id}');
      }
      if (capability.artifactRequired &&
          capability.artifactValidators.isEmpty) {
        errors.add('Missing artifact validator for ${capability.id}');
      }
      if (capability.artifactValidators.toSet().length !=
          capability.artifactValidators.length) {
        errors.add('Duplicate artifact validator for ${capability.id}');
      }
      for (final resource in capability.resources) {
        if (resource.name.trim().isEmpty) {
          errors.add('Empty resource name for ${capability.id}');
        } else if (!isKnownSimsResourceName(resource.name)) {
          errors.add(
            'Unknown resource class ${resource.name} for ${capability.id}',
          );
        }
      }
      errors.addAll(_targetResourceErrors(capability));
    }

    for (final capability in capabilities) {
      for (final dependency in capability.dependencies) {
        if (!ids.contains(dependency)) {
          errors.add('Unknown dependency $dependency for ${capability.id}');
        }
        if (dependency == capability.id) {
          errors.add('Self dependency for ${capability.id}');
        }
      }
    }

    final ownershipPaths = <String>{};
    for (final owner in ownership) {
      if (!ownershipPaths.add(owner.path)) {
        errors.add('Duplicate ownership path: ${owner.path}');
      }
      final capability = capabilityById(owner.capabilityId);
      if (capability == null) {
        errors.add('Unknown ownership capability ${owner.capabilityId}');
      } else if (owner.critical &&
          (!capability.active ||
              !capability.required ||
              !capability.modes.contains(SimsMode.major))) {
        errors.add(
          'Critical ownership ${owner.path} must use an active, required, '
          'major capability: ${owner.capabilityId}',
        );
      }
      if (!owner.critical && owner.rationale.trim().isEmpty) {
        errors.add('Noncritical ownership requires rationale: ${owner.path}');
      }
    }

    for (final path in <String>{
      ...?requiredFeaturePaths,
      ...?requiredCorePaths,
    }) {
      if (!ownershipPaths.contains(path.replaceAll('\\', '/'))) {
        errors.add('Missing critical ownership: $path');
      }
    }
    return errors;
  }

  void validateOrThrow({
    Set<String>? requiredFeaturePaths,
    Set<String>? requiredCorePaths,
  }) {
    final errors = validate(
      requiredFeaturePaths: requiredFeaturePaths,
      requiredCorePaths: requiredCorePaths,
    );
    if (errors.isNotEmpty) {
      throw FormatException(errors.join('\n'));
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'buildProfiles': buildProfiles.map((profile) => profile.toJson()).toList(),
    'capabilities': capabilities
        .map((capability) => capability.toJson())
        .toList(),
    'ownership': ownership.map((owner) => owner.toJson()).toList(),
  };
}

List<String> _targetResourceErrors(CapabilitySpec capability) {
  final resources = capability.resources
      .map((resource) => resource.name)
      .toSet();
  final errors = <String>[];

  void requireTargetLock(String capabilityName, Set<String> acceptableLocks) {
    if (!capability.targetCapabilities.contains(capabilityName)) return;
    if (!resources.any(acceptableLocks.contains)) {
      errors.add(
        '${capability.id} declares target $capabilityName without a matching '
        'device resource lock',
      );
    }
  }

  requireTargetLock('android.physical', const <String>{
    'device:android-physical',
    'device-control:android-physical',
  });
  requireTargetLock('android.emulator', const <String>{
    'device:android-emulator',
    'device-control:android-emulator',
  });
  if (capability.targetCapabilities.contains('android.emulator.count2')) {
    for (final lock in const <String>{
      'device:android-emulator',
      'device:android-emulator-second',
    }) {
      if (!resources.contains(lock)) {
        errors.add(
          '${capability.id} declares target android.emulator.count2 without '
          '$lock',
        );
      }
    }
  }
  requireTargetLock('ios.physical', const <String>{'device:ios-physical'});
  if (capability.targetCapabilities.contains('ios.simulator')) {
    requireTargetLock('ios.simulator', const <String>{
      'device:ios-simulator-a',
    });
  }
  if (capability.targetCapabilities.contains('ios.simulator.count4')) {
    for (final suffix in const <String>['a', 'b', 'c', 'd']) {
      final lock = 'device:ios-simulator-$suffix';
      if (!resources.contains(lock)) {
        errors.add(
          '${capability.id} declares target ios.simulator.count4 without $lock',
        );
      }
    }
  }
  return errors;
}

String canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value.trim();
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string when present.');
  }
  return value.trim();
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a bool.');
  return value;
}

bool? _optionalBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) throw FormatException('$key must be a bool.');
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an int.');
  return value;
}

List<String> _stringList(Object? value) {
  if (value is! List) throw const FormatException('Expected a string list.');
  return value
      .map((item) {
        if (item is! String || item.trim().isEmpty) {
          throw const FormatException('Expected a non-empty string list item.');
        }
        return item.trim();
      })
      .toList(growable: false);
}

List<Map<String, Object?>> _objectList(Object? value) {
  if (value is! List) throw const FormatException('Expected an object list.');
  return value
      .map((item) {
        if (item is! Map) {
          throw const FormatException('Expected an object list item.');
        }
        return item.map<String, Object?>(
          (key, value) => MapEntry('$key', value),
        );
      })
      .toList(growable: false);
}

Map<String, String> _stringMap(Object? value) {
  if (value == null) return const <String, String>{};
  if (value is! Map) throw const FormatException('Expected a string map.');
  return value.map<String, String>((key, item) {
    if (item is! String) {
      throw const FormatException('Expected string map values.');
    }
    return MapEntry('$key', item);
  });
}
