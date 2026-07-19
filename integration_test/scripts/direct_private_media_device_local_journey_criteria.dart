const String directPrivateMediaDeviceLocalJourneySchema =
    'plan234.direct-private-media-device-local-journey';
const int directPrivateMediaDeviceLocalJourneyVersion = 2;

class DirectPrivateMediaDeviceLocalJourneyValidation {
  DirectPrivateMediaDeviceLocalJourneyValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  bool get ok => failures.isEmpty;

  String get detail => ok ? 'accepted' : failures.join('; ');
}

/// Validates the bounded, device-local Plan 234 Session 06 proof artifact.
///
/// The validator intentionally accepts only observations emitted by the
/// instrumented app harness. It does not accept screenshots, prose verdicts,
/// operator assertions, or relay/account-wide claims as substitutes.
DirectPrivateMediaDeviceLocalJourneyValidation
validateDirectPrivateMediaDeviceLocalJourneyArtifact(Object? artifact) {
  final failures = <String>[];
  _scanForSensitiveFields(artifact, r'$', failures);

  final root = _asStringMap(artifact, r'$', failures);
  if (root == null) {
    return DirectPrivateMediaDeviceLocalJourneyValidation(failures);
  }

  _expectExactKeys(root, _rootKeys, r'$', failures);
  _expectString(
    root,
    'schema',
    directPrivateMediaDeviceLocalJourneySchema,
    r'$',
    failures,
  );
  _expectInt(
    root,
    'version',
    directPrivateMediaDeviceLocalJourneyVersion,
    r'$',
    failures,
  );
  _expectString(
    root,
    'generatedBy',
    'automated_instrumented_harness',
    r'$',
    failures,
  );

  final topology = _mapField(root, 'topology', r'$', failures);
  final claims = _mapField(root, 'claims', r'$', failures);
  final sender = _mapField(root, 'sender', r'$', failures);
  final recipient = _mapField(root, 'recipient', r'$', failures);

  String? senderDeviceId;
  String? recipientDeviceId;
  String? senderDeviceKind;
  String? recipientDeviceKind;
  String? senderFixtureDigest;
  String? recipientFixtureDigest;

  if (topology != null) {
    _expectExactKeys(topology, _topologyKeys, r'$.topology', failures);
    _expectString(topology, 'platform', 'android', r'$.topology', failures);
    _expectString(
      topology,
      'automation',
      'fully_automated',
      r'$.topology',
      failures,
    );
    _expectString(
      topology,
      'transportScope',
      'device_local_app_layer',
      r'$.topology',
      failures,
    );

    senderDeviceId = _requiredString(
      topology,
      'senderDeviceId',
      r'$.topology',
      failures,
    );
    recipientDeviceId = _requiredString(
      topology,
      'recipientDeviceId',
      r'$.topology',
      failures,
    );
    senderDeviceKind = _requiredString(
      topology,
      'senderDeviceKind',
      r'$.topology',
      failures,
    );
    recipientDeviceKind = _requiredString(
      topology,
      'recipientDeviceKind',
      r'$.topology',
      failures,
    );

    _validateDeviceKind(
      senderDeviceKind,
      r'$.topology.senderDeviceKind',
      failures,
    );
    _validateDeviceKind(
      recipientDeviceKind,
      r'$.topology.recipientDeviceKind',
      failures,
    );

    if (senderDeviceKind != null &&
        recipientDeviceKind != null &&
        (senderDeviceKind != 'physical' || recipientDeviceKind != 'emulator')) {
      failures.add(
        r'$.topology sender must be physical and recipient must be emulator',
      );
    }

    if (senderDeviceId != null && recipientDeviceId != null) {
      if (senderDeviceId == recipientDeviceId) {
        failures.add(r'$.topology sender and recipient device IDs must differ');
      }
      _validateDeviceId(
        senderDeviceId,
        senderDeviceKind,
        r'$.topology.senderDeviceId',
        failures,
      );
      _validateDeviceId(
        recipientDeviceId,
        recipientDeviceKind,
        r'$.topology.recipientDeviceId',
        failures,
      );
    }
  }

  if (claims != null) {
    _expectExactKeys(claims, _claimKeys, r'$.claims', failures);
    _expectBool(claims, 'consumeReceipt', false, r'$.claims', failures);
    _expectBool(claims, 'accountWideConsumption', false, r'$.claims', failures);
    _expectBool(
      claims,
      'relayAuthoritativeRevocation',
      false,
      r'$.claims',
      failures,
    );
  }

  if (sender != null) {
    _expectExactKeys(sender, _roleKeys, r'$.sender', failures);
    _expectString(sender, 'role', 'sender', r'$.sender', failures);
    _expectString(
      sender,
      'observationSource',
      'instrumented_app',
      r'$.sender',
      failures,
    );
    final roleDeviceId = _requiredString(
      sender,
      'deviceId',
      r'$.sender',
      failures,
    );
    if (roleDeviceId != null &&
        senderDeviceId != null &&
        roleDeviceId != senderDeviceId) {
      failures.add(r'$.sender.deviceId must match $.topology.senderDeviceId');
    }

    final observations = _mapField(
      sender,
      'observations',
      r'$.sender',
      failures,
    );
    if (observations != null) {
      _expectExactKeys(
        observations,
        _senderObservationKeys,
        r'$.sender.observations',
        failures,
      );
      senderFixtureDigest = _fixtureDigest(
        observations,
        r'$.sender.observations',
        failures,
      );
      _expectString(
        observations,
        'encryptedEnvelopeCodec',
        'encrypted-v2',
        r'$.sender.observations',
        failures,
      );
      _expectBool(
        observations,
        'outerPrivateMediaPresent',
        false,
        r'$.sender.observations',
        failures,
      );
      _expectBool(
        observations,
        'innerPrivateMediaPresent',
        true,
        r'$.sender.observations',
        failures,
      );
      _expectBool(
        observations,
        'ordinarySendPreserved',
        true,
        r'$.sender.observations',
        failures,
      );
      _validateProductionConversationObservations(
        observations,
        r'$.sender.observations',
        failures,
      );
    }
  }

  if (recipient != null) {
    _expectExactKeys(recipient, _roleKeys, r'$.recipient', failures);
    _expectString(recipient, 'role', 'recipient', r'$.recipient', failures);
    _expectString(
      recipient,
      'observationSource',
      'instrumented_app',
      r'$.recipient',
      failures,
    );
    final roleDeviceId = _requiredString(
      recipient,
      'deviceId',
      r'$.recipient',
      failures,
    );
    if (roleDeviceId != null &&
        recipientDeviceId != null &&
        roleDeviceId != recipientDeviceId) {
      failures.add(
        r'$.recipient.deviceId must match $.topology.recipientDeviceId',
      );
    }

    final observations = _mapField(
      recipient,
      'observations',
      r'$.recipient',
      failures,
    );
    if (observations != null) {
      recipientFixtureDigest = _fixtureDigest(
        observations,
        r'$.recipient.observations',
        failures,
      );
      _validateRecipientObservations(observations, failures);
    }
  }

  if (senderFixtureDigest != null &&
      recipientFixtureDigest != null &&
      senderFixtureDigest != recipientFixtureDigest) {
    failures.add(
      r'$.recipient.observations.fixtureDigest must match '
      r'$.sender.observations.fixtureDigest',
    );
  }

  return DirectPrivateMediaDeviceLocalJourneyValidation(failures);
}

void _validateRecipientObservations(
  Map<String, Object?> observations,
  List<String> failures,
) {
  const path = r'$.recipient.observations';
  _expectExactKeys(observations, _recipientObservationKeys, path, failures);

  _expectBool(observations, 'privatePayloadPersisted', true, path, failures);
  _expectBool(observations, 'privatePolicyApplied', true, path, failures);
  _expectBool(observations, 'privateEgressDenied', true, path, failures);
  _expectBool(
    observations,
    'legacyOrdinaryViewerEntryDenied',
    true,
    path,
    failures,
  );
  _expectBool(
    observations,
    'typedPictureInPictureDenied',
    true,
    path,
    failures,
  );

  final persistedSequence = _positiveInt(
    observations,
    'persistedSequence',
    path,
    failures,
  );
  final policySequence = _positiveInt(
    observations,
    'policySequence',
    path,
    failures,
  );
  final previewSequence = _positiveInt(
    observations,
    'previewSequence',
    path,
    failures,
  );
  final downloadSequence = _positiveInt(
    observations,
    'downloadSequence',
    path,
    failures,
  );

  if (persistedSequence != null &&
      policySequence != null &&
      persistedSequence >= policySequence) {
    failures.add('$path persistence must precede private policy evaluation');
  }
  if (policySequence != null &&
      previewSequence != null &&
      policySequence >= previewSequence) {
    failures.add('$path private policy evaluation must precede preview');
  }
  if (policySequence != null &&
      downloadSequence != null &&
      policySequence >= downloadSequence) {
    failures.add('$path private policy evaluation must precede download');
  }

  _expectString(
    observations,
    'notificationCopy',
    'Private media',
    path,
    failures,
  );
  _expectString(observations, 'quoteCopy', 'Private media', path, failures);
  _expectInt(observations, 'autoDownloadCount', 0, path, failures);
  _expectInt(observations, 'manualDownloadCount', 1, path, failures);
  _expectString(
    observations,
    'manualDownloadResult',
    'canonical_durable_storage',
    path,
    failures,
  );
  _expectInt(observations, 'viewOnceRevealCount', 1, path, failures);
  _expectBool(observations, 'viewOnceCleanupCompleted', true, path, failures);
  _expectBool(
    observations,
    'viewOnceAttachmentPresentAfterCleanup',
    false,
    path,
    failures,
  );
  _expectBool(
    observations,
    'viewOnceAvailableAfterReopen',
    false,
    path,
    failures,
  );
  _expectBool(
    observations,
    'disappearingExpiryCompleted',
    true,
    path,
    failures,
  );
  _expectBool(
    observations,
    'disappearingAvailableAfterExpiry',
    false,
    path,
    failures,
  );
  _expectBool(
    observations,
    'protectedFirstOpenDecisionAllowed',
    true,
    path,
    failures,
  );
  _expectBool(
    observations,
    'protectedRepeatOpenDecisionAllowed',
    true,
    path,
    failures,
  );
  _expectBool(
    observations,
    'protectedAvailableAfterRepeat',
    true,
    path,
    failures,
  );
  _expectBool(observations, 'ordinaryPreviewSucceeded', true, path, failures);
  _expectBool(
    observations,
    'ordinaryManualDownloadSucceeded',
    true,
    path,
    failures,
  );
  _expectInt(observations, 'consumeReceiptCount', 0, path, failures);
  _validateProductionConversationObservations(observations, path, failures);
}

void _validateProductionConversationObservations(
  Map<String, Object?> observations,
  String path,
  List<String> failures,
) {
  _expectBool(
    observations,
    'productionConversationMounted',
    true,
    path,
    failures,
  );
  _expectInt(observations, 'productionLetterCardCount', 3, path, failures);
  _expectInt(observations, 'privateSlotCount', 3, path, failures);
  _expectInt(observations, 'slotsInsideDecoratedBodies', 3, path, failures);
  _expectInt(observations, 'nonZeroPrivateSlotCount', 3, path, failures);
  _expectInt(observations, 'slotImageWidgetCount', 0, path, failures);
  _expectInt(observations, 'slotDecorationImageCount', 0, path, failures);
  _expectBool(observations, 'outgoingActionVisible', true, path, failures);
  _expectBool(observations, 'incomingActionVisible', true, path, failures);
  _expectBool(
    observations,
    'terminalActionVisibleAfterRepump',
    true,
    path,
    failures,
  );
}

Map<String, Object?>? _asStringMap(
  Object? value,
  String path,
  List<String> failures,
) {
  if (value is! Map) {
    failures.add('$path must be a JSON object');
    return null;
  }

  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      failures.add('$path contains a non-string key');
      continue;
    }
    result[key] = entry.value;
  }
  return result;
}

Map<String, Object?>? _mapField(
  Map<String, Object?> owner,
  String key,
  String path,
  List<String> failures,
) {
  if (!owner.containsKey(key)) return null;
  return _asStringMap(owner[key], '$path.$key', failures);
}

void _expectExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String path,
  List<String> failures,
) {
  final missing = expected.difference(value.keys.toSet()).toList()..sort();
  final unexpectedIndexes = <int>[];
  var fieldIndex = 0;
  for (final key in value.keys) {
    if (!expected.contains(key)) unexpectedIndexes.add(fieldIndex);
    fieldIndex += 1;
  }
  if (missing.isNotEmpty) {
    failures.add('$path missing fields: ${missing.join(', ')}');
  }
  if (unexpectedIndexes.isNotEmpty) {
    failures.add(
      '$path contains unexpected fields at indexes: '
      '${unexpectedIndexes.join(', ')}',
    );
  }
}

String? _requiredString(
  Map<String, Object?> owner,
  String key,
  String path,
  List<String> failures,
) {
  if (!owner.containsKey(key)) return null;
  final value = owner[key];
  if (value is! String || value.isEmpty) {
    failures.add('$path.$key must be a non-empty string');
    return null;
  }
  return value;
}

void _expectString(
  Map<String, Object?> owner,
  String key,
  String expected,
  String path,
  List<String> failures,
) {
  if (!owner.containsKey(key)) return;
  final value = owner[key];
  if (value is! String || value != expected) {
    failures.add('$path.$key must equal "$expected"');
  }
}

void _expectBool(
  Map<String, Object?> owner,
  String key,
  bool expected,
  String path,
  List<String> failures,
) {
  if (!owner.containsKey(key)) return;
  final value = owner[key];
  if (value is! bool || value != expected) {
    failures.add('$path.$key must equal $expected');
  }
}

void _expectInt(
  Map<String, Object?> owner,
  String key,
  int expected,
  String path,
  List<String> failures,
) {
  if (!owner.containsKey(key)) return;
  final value = owner[key];
  if (value is! int || value != expected) {
    failures.add('$path.$key must equal integer $expected');
  }
}

int? _positiveInt(
  Map<String, Object?> owner,
  String key,
  String path,
  List<String> failures,
) {
  if (!owner.containsKey(key)) return null;
  final value = owner[key];
  if (value is! int || value <= 0) {
    failures.add('$path.$key must be a positive integer');
    return null;
  }
  return value;
}

String? _fixtureDigest(
  Map<String, Object?> owner,
  String path,
  List<String> failures,
) {
  if (!owner.containsKey('fixtureDigest')) return null;
  final value = owner['fixtureDigest'];
  if (value is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
    failures.add('$path.fixtureDigest must be exactly 64 hexadecimal digits');
    return null;
  }
  return value;
}

void _validateDeviceKind(String? kind, String path, List<String> failures) {
  if (kind != null && kind != 'physical' && kind != 'emulator') {
    failures.add('$path must equal "physical" or "emulator"');
  }
}

void _validateDeviceId(
  String id,
  String? kind,
  String path,
  List<String> failures,
) {
  final safeSerial = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');
  final reserved = <String>{'all', 'any', 'auto', 'default', 'unknown'};
  if (!safeSerial.hasMatch(id) || reserved.contains(id.toLowerCase())) {
    failures.add('$path must be an explicit safe Android device ID');
    return;
  }
  if (kind == 'emulator' && !RegExp(r'^emulator-[0-9]+$').hasMatch(id)) {
    failures.add('$path must be an explicit Android emulator ID');
  }
  if (kind == 'physical' && id.startsWith('emulator-')) {
    failures.add('$path cannot name an emulator when kind is physical');
  }
}

void _scanForSensitiveFields(
  Object? value,
  String path,
  List<String> failures,
) {
  if (value is Map) {
    var fieldIndex = 0;
    for (final entry in value.entries) {
      final key = entry.key;
      final fieldPath = key is String && _isKnownArtifactFieldName(key)
          ? '$path.$key'
          : '$path.<field[$fieldIndex]>';
      if (key is String && _isSensitiveFieldName(key)) {
        failures.add('$fieldPath contains a forbidden sensitive field');
      }
      _scanForSensitiveFields(entry.value, fieldPath, failures);
      fieldIndex += 1;
    }
  } else if (value is Iterable) {
    var index = 0;
    for (final entry in value) {
      _scanForSensitiveFields(entry, '$path[$index]', failures);
      index += 1;
    }
  } else if (value is String && _containsSensitiveValueToken(value)) {
    failures.add('$path contains forbidden sensitive string value');
  }
}

bool _isSensitiveFieldName(String field) {
  return _containsTokenFrom(field, _sensitiveFieldTokens);
}

bool _containsSensitiveValueToken(String value) {
  return _containsTokenFrom(value, _sensitiveValueTokens);
}

bool _containsTokenFrom(String value, Set<String> forbiddenTokens) {
  final separated = value.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (match) => '${match.group(1)}_${match.group(2)}',
  );
  final tokens = separated
      .toLowerCase()
      .split(RegExp('[^a-z0-9]+'))
      .where((token) => token.isNotEmpty);
  return tokens.any(forbiddenTokens.contains);
}

bool _isKnownArtifactFieldName(String field) {
  return _rootKeys.contains(field) ||
      _topologyKeys.contains(field) ||
      _claimKeys.contains(field) ||
      _roleKeys.contains(field) ||
      _senderObservationKeys.contains(field) ||
      _recipientObservationKeys.contains(field);
}

const Set<String> _sensitiveFieldTokens = <String>{
  'secret',
  'plaintext',
  'caption',
  'path',
  'filepath',
  'key',
  'nonce',
};

const Set<String> _sensitiveValueTokens = <String>{
  ..._sensitiveFieldTokens,
  'blob',
  'bytes',
  'ciphertext',
  'dimension',
  'dimensions',
  'duration',
  'kem',
  'kind',
  'lifecycle',
  'mime',
  'policy',
  'size',
};

const Set<String> _rootKeys = <String>{
  'schema',
  'version',
  'generatedBy',
  'topology',
  'claims',
  'sender',
  'recipient',
};

const Set<String> _topologyKeys = <String>{
  'platform',
  'automation',
  'transportScope',
  'senderDeviceId',
  'senderDeviceKind',
  'recipientDeviceId',
  'recipientDeviceKind',
};

const Set<String> _claimKeys = <String>{
  'consumeReceipt',
  'accountWideConsumption',
  'relayAuthoritativeRevocation',
};

const Set<String> _roleKeys = <String>{
  'role',
  'deviceId',
  'observationSource',
  'observations',
};

const Set<String> _senderObservationKeys = <String>{
  'fixtureDigest',
  'encryptedEnvelopeCodec',
  'outerPrivateMediaPresent',
  'innerPrivateMediaPresent',
  'ordinarySendPreserved',
  ..._productionConversationObservationKeys,
};

const Set<String> _recipientObservationKeys = <String>{
  'fixtureDigest',
  'privatePayloadPersisted',
  'privatePolicyApplied',
  'privateEgressDenied',
  'legacyOrdinaryViewerEntryDenied',
  'typedPictureInPictureDenied',
  'persistedSequence',
  'policySequence',
  'previewSequence',
  'downloadSequence',
  'notificationCopy',
  'quoteCopy',
  'autoDownloadCount',
  'manualDownloadCount',
  'manualDownloadResult',
  'viewOnceRevealCount',
  'viewOnceCleanupCompleted',
  'viewOnceAttachmentPresentAfterCleanup',
  'viewOnceAvailableAfterReopen',
  'disappearingExpiryCompleted',
  'disappearingAvailableAfterExpiry',
  'protectedFirstOpenDecisionAllowed',
  'protectedRepeatOpenDecisionAllowed',
  'protectedAvailableAfterRepeat',
  'ordinaryPreviewSucceeded',
  'ordinaryManualDownloadSucceeded',
  'consumeReceiptCount',
  ..._productionConversationObservationKeys,
};

const Set<String> _productionConversationObservationKeys = <String>{
  'productionConversationMounted',
  'productionLetterCardCount',
  'privateSlotCount',
  'slotsInsideDecoratedBodies',
  'nonZeroPrivateSlotCount',
  'slotImageWidgetCount',
  'slotDecorationImageCount',
  'outgoingActionVisible',
  'incomingActionVisible',
  'terminalActionVisibleAfterRepump',
};
