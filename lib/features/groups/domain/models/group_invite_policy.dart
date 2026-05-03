enum GroupInviteReusePolicy {
  singleUse('singleUse'),
  multiUse('multiUse');

  const GroupInviteReusePolicy(this.wireValue);

  final String wireValue;

  Map<String, dynamic> toJson() => {'mode': wireValue};

  static GroupInviteReusePolicy? fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.length != 1 ||
        !value.containsKey('mode')) {
      return null;
    }

    final mode = value['mode'];
    if (mode is! String || mode.trim() != mode || mode.isEmpty) {
      return null;
    }

    for (final policy in GroupInviteReusePolicy.values) {
      if (policy.wireValue == mode) {
        return policy;
      }
    }
    return null;
  }
}

class GroupInvitePolicy {
  static const inlineGroupKeyKind = 'inlineGroupKey';

  final DateTime expiresAt;
  final List<String> allowedDevices;
  final String assignedRole;
  final bool? canInviteOthers;
  final String joinMaterialKind;
  final int keyEpoch;
  final GroupInviteReusePolicy reusePolicy;
  final String? welcomeKeyPackageId;
  final String? welcomeKeyPackagePublicMaterialHash;
  final DateTime? welcomeKeyPackageExpiresAt;

  const GroupInvitePolicy({
    required this.expiresAt,
    required this.allowedDevices,
    required this.assignedRole,
    this.canInviteOthers,
    required this.joinMaterialKind,
    required this.keyEpoch,
    this.reusePolicy = GroupInviteReusePolicy.singleUse,
    this.welcomeKeyPackageId,
    this.welcomeKeyPackagePublicMaterialHash,
    this.welcomeKeyPackageExpiresAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'allowedDevices': allowedDevices,
      'invitePermissions': {
        'assignedRole': assignedRole,
        if (canInviteOthers != null) 'canInviteOthers': canInviteOthers,
      },
      'joinMaterialRef': {
        'kind': joinMaterialKind,
        'keyEpoch': keyEpoch,
        if (welcomeKeyPackageId != null &&
            welcomeKeyPackageId!.trim().isNotEmpty)
          'welcomeKeyPackageId': welcomeKeyPackageId,
        if (welcomeKeyPackagePublicMaterialHash != null &&
            welcomeKeyPackagePublicMaterialHash!.trim().isNotEmpty)
          'welcomeKeyPackagePublicMaterialHash':
              welcomeKeyPackagePublicMaterialHash,
        if (welcomeKeyPackageExpiresAt != null)
          'welcomeKeyPackageExpiresAt': welcomeKeyPackageExpiresAt!
              .toUtc()
              .toIso8601String(),
      },
      'reusePolicy': reusePolicy.toJson(),
    };
  }

  static GroupInvitePolicy? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }

    final expiresAtRaw = value['expiresAt'];
    final expiresAt = expiresAtRaw is String
        ? DateTime.tryParse(expiresAtRaw)?.toUtc()
        : null;
    final allowedDevicesRaw = value['allowedDevices'];
    final invitePermissions = value['invitePermissions'];
    final joinMaterialRef = value['joinMaterialRef'];
    final reusePolicy = GroupInviteReusePolicy.fromJson(value['reusePolicy']);

    if (expiresAt == null ||
        allowedDevicesRaw is! List ||
        invitePermissions is! Map<String, dynamic> ||
        joinMaterialRef is! Map<String, dynamic> ||
        reusePolicy == null) {
      return null;
    }

    final allowedDevices = <String>[];
    for (final rawDevice in allowedDevicesRaw) {
      if (rawDevice is! String || rawDevice.trim().isEmpty) {
        return null;
      }
      allowedDevices.add(rawDevice);
    }

    final assignedRole = invitePermissions['assignedRole'];
    final canInviteOthers = invitePermissions['canInviteOthers'];
    final joinMaterialKind = joinMaterialRef['kind'];
    final keyEpoch = joinMaterialRef['keyEpoch'];
    final welcomeKeyPackageId = _readOptionalString(
      joinMaterialRef,
      'welcomeKeyPackageId',
    );
    final welcomeKeyPackagePublicMaterialHash = _readOptionalString(
      joinMaterialRef,
      'welcomeKeyPackagePublicMaterialHash',
    );
    final welcomeKeyPackageExpiresAtRaw =
        joinMaterialRef['welcomeKeyPackageExpiresAt'];
    final welcomeKeyPackageExpiresAt = welcomeKeyPackageExpiresAtRaw is String
        ? DateTime.tryParse(welcomeKeyPackageExpiresAtRaw)?.toUtc()
        : null;

    if (assignedRole is! String ||
        assignedRole.trim().isEmpty ||
        (canInviteOthers != null && canInviteOthers is! bool) ||
        joinMaterialKind is! String ||
        keyEpoch is! int) {
      return null;
    }
    if (joinMaterialRef.containsKey('welcomeKeyPackageId') &&
        welcomeKeyPackageId == null) {
      return null;
    }
    if (joinMaterialRef.containsKey('welcomeKeyPackagePublicMaterialHash') &&
        welcomeKeyPackagePublicMaterialHash == null) {
      return null;
    }
    if (joinMaterialRef.containsKey('welcomeKeyPackageExpiresAt') &&
        welcomeKeyPackageExpiresAt == null) {
      return null;
    }

    return GroupInvitePolicy(
      expiresAt: expiresAt,
      allowedDevices: allowedDevices,
      assignedRole: assignedRole,
      canInviteOthers: canInviteOthers as bool?,
      joinMaterialKind: joinMaterialKind,
      keyEpoch: keyEpoch,
      reusePolicy: reusePolicy,
      welcomeKeyPackageId: welcomeKeyPackageId,
      welcomeKeyPackagePublicMaterialHash: welcomeKeyPackagePublicMaterialHash,
      welcomeKeyPackageExpiresAt: welcomeKeyPackageExpiresAt,
    );
  }

  static String? _readOptionalString(Map<String, dynamic> value, String key) {
    final raw = value[key];
    if (raw == null) {
      return null;
    }
    if (raw is! String) {
      return null;
    }
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
