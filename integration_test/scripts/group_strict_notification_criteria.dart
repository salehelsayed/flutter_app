import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const String groupStrictNotificationCapabilityId =
    'groups.strict_notification_closure';
const String groupStrictNotificationScenarioId =
    'android_strict_group_notification_closure';
const String groupStrictNotificationArtifactSchema =
    'mknoon.plan393.group-strict-notification-proof.v1';
const int groupStrictNotificationArtifactVersion = 1;

const List<String> groupStrictNotificationCriteria = <String>[
  'groups.strict_exact_chat_suppressed',
  'groups.strict_message_killed_card',
  'groups.strict_reaction_author_card',
  'groups.strict_relay_provenance',
  'groups.strict_state_restored',
];

final class GroupStrictNotificationValidation {
  GroupStrictNotificationValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  bool get ok => failures.isEmpty;
  String get detail => ok ? 'accepted' : failures.join('; ');
}

Future<GroupStrictNotificationValidation>
validateGroupStrictNotificationArtifact({
  required File artifactFile,
  String? expectedPhysicalDeviceId,
  String? expectedEmulatorDeviceId,
  String? expectedApkSha256,
  String? expectedPackageName,
}) async {
  final failures = <String>[];
  if (!await artifactFile.exists()) {
    return GroupStrictNotificationValidation(<String>[
      'missing artifact ${artifactFile.path}',
    ]);
  }
  late final String raw;
  try {
    raw = await artifactFile.readAsString();
  } on Object {
    return GroupStrictNotificationValidation(<String>['artifact unreadable']);
  }
  if (raw.contains('BEGIN PRIVATE KEY')) {
    failures.add('artifact contains private key material');
  }
  for (final forbiddenKey in const <String>[
    'pushToken',
    'fcmToken',
    'authorityTransfer',
    'privateKey',
  ]) {
    if (RegExp('"$forbiddenKey"\\s*:').hasMatch(raw)) {
      failures.add('artifact contains $forbiddenKey');
    }
  }
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on Object {
    failures.add('artifact is not JSON');
    return GroupStrictNotificationValidation(failures);
  }
  final root = _map(decoded, r'$', failures);
  if (root == null) return GroupStrictNotificationValidation(failures);
  _keys(
    root,
    const <String>{
      'schema',
      'version',
      'scenario',
      'status',
      'appPackage',
      'preparedArtifactSha256',
      'topology',
      'authority',
      'exactChat',
      'killedMessage',
      'reaction',
      'relay',
      'automation',
      'redaction',
    },
    r'$',
    failures,
  );
  _value(root, 'schema', groupStrictNotificationArtifactSchema, r'$', failures);
  _value(
    root,
    'version',
    groupStrictNotificationArtifactVersion,
    r'$',
    failures,
  );
  _value(root, 'scenario', groupStrictNotificationScenarioId, r'$', failures);
  _value(root, 'status', 'passed', r'$', failures);
  if (expectedPackageName != null) {
    _value(root, 'appPackage', expectedPackageName, r'$', failures);
  } else if (root['appPackage'] is! String ||
      '${root['appPackage']}'.trim().isEmpty) {
    failures.add(r'$.appPackage missing');
  }
  if (expectedApkSha256 != null) {
    _value(root, 'preparedArtifactSha256', expectedApkSha256, r'$', failures);
  }
  if (!_digest(root['preparedArtifactSha256'])) {
    failures.add(r'$.preparedArtifactSha256 is not SHA-256');
  }

  final topology = _map(root['topology'], r'$.topology', failures);
  if (topology != null) {
    _keys(
      topology,
      const <String>{'physical', 'emulator'},
      r'$.topology',
      failures,
    );
    _device(
      topology['physical'],
      r'$.topology.physical',
      expectedPhysicalDeviceId,
      'physical',
      failures,
    );
    _device(
      topology['emulator'],
      r'$.topology.emulator',
      expectedEmulatorDeviceId,
      'emulator',
      failures,
    );
  }

  final authority = _map(root['authority'], r'$.authority', failures);
  if (authority != null) {
    _keys(
      authority,
      const <String>{
        'groupName',
        'steps',
        'firstAuthorityDigest',
        'finalAuthorityDigest',
        'bothDevicesInstalledFinalAuthority',
        'revokedHistoricalDevices',
      },
      r'$.authority',
      failures,
    );
    final name = authority['groupName'];
    if (name is! String ||
        !RegExp(r'^Plan393S-[A-Za-z0-9]{6,32}$').hasMatch(name)) {
      failures.add(r'$.authority.groupName is not the fresh strict fixture');
    }
    for (final key in const <String>[
      'firstAuthorityDigest',
      'finalAuthorityDigest',
    ]) {
      if (!_digest(authority[key])) {
        failures.add(
          r'$.authority.'
          '$key invalid',
        );
      }
    }
    if (authority['firstAuthorityDigest'] ==
        authority['finalAuthorityDigest']) {
      failures.add(r'$.authority final snapshot did not advance');
    }
    _value(
      authority,
      'bothDevicesInstalledFinalAuthority',
      true,
      r'$.authority',
      failures,
    );
    _value(authority, 'revokedHistoricalDevices', 2, r'$.authority', failures);
    final steps = authority['steps'];
    const expected = <(String, String)>[
      ('physical', 'author_authority'),
      ('emulator', 'install_authority'),
      ('emulator', 'author_authority'),
      ('physical', 'install_authority'),
    ];
    if (steps is! List || steps.length != expected.length) {
      failures.add(r'$.authority.steps must contain the four ordered steps');
    } else {
      for (var index = 0; index < expected.length; index += 1) {
        final step = _map(steps[index], r'$.authority.steps[$index]', failures);
        if (step == null) continue;
        _keys(
          step,
          const <String>{
            'role',
            'phase',
            'authorityDigest',
            'authorityEventAt',
            'authorityEventIdSha256',
            'keyEpoch',
          },
          r'$.authority.steps[$index]',
          failures,
        );
        _value(
          step,
          'role',
          expected[index].$1,
          r'$.authority.steps[$index]',
          failures,
        );
        _value(
          step,
          'phase',
          expected[index].$2,
          r'$.authority.steps[$index]',
          failures,
        );
        if (!_digest(step['authorityDigest']) ||
            !_digest(step['authorityEventIdSha256'])) {
          failures.add(r'$.authority.steps digest invalid');
        }
        if (DateTime.tryParse('${step['authorityEventAt']}')?.isUtc != true ||
            step['keyEpoch'] is! int ||
            (step['keyEpoch'] as int) <= 0) {
          failures.add(r'$.authority.steps timestamp/key epoch invalid');
        }
      }
    }
  }

  _transition(
    root['exactChat'],
    r'$.exactChat',
    expectedDelta: 1,
    expectedProcessAbsent: false,
    expectedCardCount: 0,
    expectedFlow: 'suppressed',
    failures: failures,
  );
  _transition(
    root['killedMessage'],
    r'$.killedMessage',
    expectedDelta: 1,
    expectedProcessAbsent: true,
    expectedCardCount: 1,
    expectedFlow: 'received_decrypt_shown',
    failures: failures,
  );
  _transition(
    root['reaction'],
    r'$.reaction',
    expectedDelta: 1,
    expectedProcessAbsent: true,
    expectedCardCount: 1,
    expectedFlow: 'received_decrypt_shown',
    failures: failures,
  );
  final killed = root['killedMessage'];
  final reaction = root['reaction'];
  if (killed is Map &&
      reaction is Map &&
      killed['notificationId'] != reaction['notificationId']) {
    failures.add(r'$.reaction did not replace the stable group card');
  }
  if (reaction is Map && reaction['typedReactionCopy'] != true) {
    failures.add(r'$.reaction.typedReactionCopy must be true');
  }

  final relay = _map(root['relay'], r'$.relay', failures);
  if (relay != null) {
    _keys(
      relay,
      const <String>{
        'revision',
        'sha256',
        'journal',
        'metricsBaseline',
        'metricsBeforeKilled',
        'metricsBeforeReaction',
        'metricsFinal',
      },
      r'$.relay',
      failures,
    );
    if (relay['revision'] is! String || '${relay['revision']}'.trim().isEmpty) {
      failures.add(r'$.relay.revision missing');
    }
    if (!_digest(relay['sha256'])) failures.add(r'$.relay.sha256 invalid');
    for (final key in const <String>[
      'journal',
      'metricsBaseline',
      'metricsBeforeKilled',
      'metricsBeforeReaction',
      'metricsFinal',
    ]) {
      await _evidenceReference(
        relay[key],
        artifactFile.parent,
        r'$.relay.'
        '$key',
        failures,
      );
    }
  }

  final automation = _map(root['automation'], r'$.automation', failures);
  if (automation != null) {
    _keys(
      automation,
      const <String>{
        'manualTaps',
        'notificationCardTaps',
        'childBuildCount',
        'statePreparedByParent',
        'commandJournal',
      },
      r'$.automation',
      failures,
    );
    _value(automation, 'manualTaps', 0, r'$.automation', failures);
    _value(automation, 'notificationCardTaps', 0, r'$.automation', failures);
    _value(automation, 'childBuildCount', 0, r'$.automation', failures);
    _value(
      automation,
      'statePreparedByParent',
      true,
      r'$.automation',
      failures,
    );
    await _evidenceReference(
      automation['commandJournal'],
      artifactFile.parent,
      r'$.automation.commandJournal',
      failures,
    );
  }
  final redaction = _map(root['redaction'], r'$.redaction', failures);
  if (redaction != null) {
    _keys(
      redaction,
      const <String>{
        'tokensPersisted',
        'privateKeysPersisted',
        'authorityTransferPersisted',
        'rawPeerIdsPersisted',
      },
      r'$.redaction',
      failures,
    );
    for (final key in redaction.keys) {
      _value(redaction, key, false, r'$.redaction', failures);
    }
  }
  return GroupStrictNotificationValidation(failures);
}

void _transition(
  Object? raw,
  String path, {
  required int expectedDelta,
  required bool expectedProcessAbsent,
  required int expectedCardCount,
  required String expectedFlow,
  required List<String> failures,
}) {
  final value = _map(raw, path, failures);
  if (value == null) return;
  final expectedKeys = <String>{
    'markerSha256',
    'processAbsentBeforeSend',
    'attemptedDelta',
    'cardCount',
    'notificationId',
    'flow',
    'flowEvidence',
    'notificationEvidence',
    if (path == r'$.reaction') 'typedReactionCopy',
  };
  _keys(value, expectedKeys, path, failures);
  if (!_digest(value['markerSha256'])) {
    failures.add('$path.markerSha256 invalid');
  }
  _value(
    value,
    'processAbsentBeforeSend',
    expectedProcessAbsent,
    path,
    failures,
  );
  _value(value, 'attemptedDelta', expectedDelta, path, failures);
  _value(value, 'cardCount', expectedCardCount, path, failures);
  _value(value, 'flow', expectedFlow, path, failures);
  final id = value['notificationId'];
  if (expectedCardCount == 0 && id != null) {
    failures.add('$path.notificationId must be null');
  }
  if (expectedCardCount == 1 && id is! int) {
    failures.add('$path.notificationId must be an integer');
  }
}

void _device(
  Object? raw,
  String path,
  String? expectedId,
  String expectedKind,
  List<String> failures,
) {
  final value = _map(raw, path, failures);
  if (value == null) return;
  _keys(value, const <String>{'deviceId', 'kind', 'platform'}, path, failures);
  if (expectedId != null) {
    _value(value, 'deviceId', expectedId, path, failures);
  } else if (value['deviceId'] is! String ||
      '${value['deviceId']}'.trim().isEmpty) {
    failures.add('$path.deviceId missing');
  }
  _value(value, 'kind', expectedKind, path, failures);
  _value(value, 'platform', 'android', path, failures);
}

Future<void> _evidenceReference(
  Object? raw,
  Directory root,
  String path,
  List<String> failures,
) async {
  final value = _map(raw, path, failures);
  if (value == null) return;
  _keys(value, const <String>{'path', 'sha256', 'bytes'}, path, failures);
  final name = value['path'];
  if (name is! String ||
      name.isEmpty ||
      name != File(name).uri.pathSegments.last) {
    failures.add('$path.path must be a basename');
    return;
  }
  final file = File('${root.path}${Platform.pathSeparator}$name');
  if (!await file.exists()) {
    failures.add('$path file is missing');
    return;
  }
  final bytes = await file.readAsBytes();
  if (value['bytes'] != bytes.length ||
      value['sha256'] != sha256.convert(bytes).toString()) {
    failures.add('$path content binding mismatch');
  }
}

Map<String, Object?>? _map(Object? raw, String path, List<String> failures) {
  if (raw is! Map) {
    failures.add('$path must be an object');
    return null;
  }
  try {
    return Map<String, Object?>.from(raw);
  } on Object {
    failures.add('$path keys must be strings');
    return null;
  }
}

void _keys(
  Map<String, Object?> value,
  Set<String> expected,
  String path,
  List<String> failures,
) {
  if (value.keys.toSet().length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    failures.add('$path keys mismatch');
  }
}

void _value(
  Map<String, Object?> value,
  String key,
  Object? expected,
  String path,
  List<String> failures,
) {
  if (value[key] != expected) failures.add('$path.$key mismatch');
}

bool _digest(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
