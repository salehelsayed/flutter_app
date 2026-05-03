import 'dart:convert';

import 'package:crypto/crypto.dart';

const groupWelcomeKeyPackageSchemaVersion = 1;
const groupWelcomeKeyPackageMinPublicMaterialLength = 8;
const groupWelcomeKeyPackageIdPrefix = 'key-package-';

String? defaultGroupWelcomeKeyPackageIdForDevice(String? deviceId) {
  final normalizedDeviceId = deviceId?.trim();
  if (normalizedDeviceId == null || normalizedDeviceId.isEmpty) {
    return null;
  }
  return '$groupWelcomeKeyPackageIdPrefix$normalizedDeviceId';
}

class GroupWelcomeKeyPackage {
  final int schemaVersion;
  final String packageId;
  final String publicMaterial;
  final String publicMaterialHash;
  final String recipientPeerId;
  final String recipientDeviceId;
  final String recipientTransportPeerId;
  final String recipientMlKemPublicKey;
  final String inviteId;
  final String groupId;
  final int keyEpoch;
  final DateTime issuedAt;
  final DateTime expiresAt;

  const GroupWelcomeKeyPackage({
    this.schemaVersion = groupWelcomeKeyPackageSchemaVersion,
    required this.packageId,
    required this.publicMaterial,
    required this.publicMaterialHash,
    required this.recipientPeerId,
    required this.recipientDeviceId,
    required this.recipientTransportPeerId,
    required this.recipientMlKemPublicKey,
    required this.inviteId,
    required this.groupId,
    required this.keyEpoch,
    required this.issuedAt,
    required this.expiresAt,
  });

  factory GroupWelcomeKeyPackage.create({
    required String packageId,
    required String publicMaterial,
    required String recipientPeerId,
    required String recipientDeviceId,
    required String recipientTransportPeerId,
    required String recipientMlKemPublicKey,
    required String inviteId,
    required String groupId,
    required int keyEpoch,
    required DateTime issuedAt,
    required DateTime expiresAt,
  }) {
    final normalizedPublicMaterial = publicMaterial.trim();
    return GroupWelcomeKeyPackage(
      packageId: packageId.trim(),
      publicMaterial: normalizedPublicMaterial,
      publicMaterialHash: hashPublicMaterial(normalizedPublicMaterial),
      recipientPeerId: recipientPeerId.trim(),
      recipientDeviceId: recipientDeviceId.trim(),
      recipientTransportPeerId: recipientTransportPeerId.trim(),
      recipientMlKemPublicKey: recipientMlKemPublicKey.trim(),
      inviteId: inviteId.trim(),
      groupId: groupId.trim(),
      keyEpoch: keyEpoch,
      issuedAt: issuedAt.toUtc(),
      expiresAt: expiresAt.toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'packageId': packageId,
      'publicMaterial': publicMaterial,
      'publicMaterialHash': publicMaterialHash,
      'recipientPeerId': recipientPeerId,
      'recipientDeviceId': recipientDeviceId,
      'recipientTransportPeerId': recipientTransportPeerId,
      'recipientMlKemPublicKey': recipientMlKemPublicKey,
      'inviteId': inviteId,
      'groupId': groupId,
      'keyEpoch': keyEpoch,
      'issuedAt': issuedAt.toUtc().toIso8601String(),
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    };
  }

  static GroupWelcomeKeyPackage? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final schemaVersion = value['schemaVersion'];
    final packageId = _readString(value, 'packageId');
    final publicMaterial = _readString(value, 'publicMaterial');
    final publicMaterialHash = _readString(value, 'publicMaterialHash');
    final recipientPeerId = _readString(value, 'recipientPeerId');
    final recipientDeviceId = _readString(value, 'recipientDeviceId');
    final recipientTransportPeerId = _readString(
      value,
      'recipientTransportPeerId',
    );
    final recipientMlKemPublicKey = _readString(
      value,
      'recipientMlKemPublicKey',
    );
    final inviteId = _readString(value, 'inviteId');
    final groupId = _readString(value, 'groupId');
    final keyEpoch = value['keyEpoch'];
    final issuedAt = _parseDateTime(_readString(value, 'issuedAt'));
    final expiresAt = _parseDateTime(_readString(value, 'expiresAt'));

    if (schemaVersion != groupWelcomeKeyPackageSchemaVersion ||
        packageId == null ||
        publicMaterial == null ||
        publicMaterialHash == null ||
        recipientPeerId == null ||
        recipientDeviceId == null ||
        recipientTransportPeerId == null ||
        recipientMlKemPublicKey == null ||
        inviteId == null ||
        groupId == null ||
        keyEpoch is! int ||
        issuedAt == null ||
        expiresAt == null) {
      return null;
    }

    final package = GroupWelcomeKeyPackage(
      schemaVersion: schemaVersion as int,
      packageId: packageId,
      publicMaterial: publicMaterial,
      publicMaterialHash: publicMaterialHash,
      recipientPeerId: recipientPeerId,
      recipientDeviceId: recipientDeviceId,
      recipientTransportPeerId: recipientTransportPeerId,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      inviteId: inviteId,
      groupId: groupId,
      keyEpoch: keyEpoch,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
    return package.isStructurallyValid() ? package : null;
  }

  bool isStructurallyValid({DateTime? at}) {
    if (schemaVersion != groupWelcomeKeyPackageSchemaVersion ||
        !_isNonEmpty(packageId) ||
        !_isNonEmpty(publicMaterial) ||
        publicMaterial.length < groupWelcomeKeyPackageMinPublicMaterialLength ||
        !_isNonEmpty(publicMaterialHash) ||
        !_isNonEmpty(recipientPeerId) ||
        !_isNonEmpty(recipientDeviceId) ||
        !_isNonEmpty(recipientTransportPeerId) ||
        !_isNonEmpty(recipientMlKemPublicKey) ||
        !_isNonEmpty(inviteId) ||
        !_isNonEmpty(groupId) ||
        keyEpoch <= 0) {
      return false;
    }
    if (hashPublicMaterial(publicMaterial) != publicMaterialHash) {
      return false;
    }
    if (!expiresAt.isAfter(issuedAt)) {
      return false;
    }
    final validationTime = at?.toUtc();
    if (validationTime != null && !expiresAt.isAfter(validationTime)) {
      return false;
    }
    return true;
  }

  bool matchesInviteAndRecipient({
    required String inviteId,
    required String groupId,
    required int keyEpoch,
    required String? recipientPeerId,
    required String? recipientDeviceId,
    required String? recipientTransportPeerId,
    required String? recipientMlKemPublicKey,
    required String? recipientKeyPackageId,
    required String? recipientKeyPackagePublicMaterial,
    DateTime? at,
  }) {
    if (!isStructurallyValid(at: at)) {
      return false;
    }
    return this.inviteId == inviteId.trim() &&
        this.groupId == groupId.trim() &&
        this.keyEpoch == keyEpoch &&
        _matches(this.recipientPeerId, recipientPeerId) &&
        _matches(this.recipientDeviceId, recipientDeviceId) &&
        _matches(this.recipientTransportPeerId, recipientTransportPeerId) &&
        _matches(this.recipientMlKemPublicKey, recipientMlKemPublicKey) &&
        _matches(packageId, recipientKeyPackageId) &&
        recipientKeyPackagePublicMaterial != null &&
        hashPublicMaterial(recipientKeyPackagePublicMaterial.trim()) ==
            publicMaterialHash;
  }

  static String hashPublicMaterial(String publicMaterial) {
    return sha256.convert(utf8.encode(publicMaterial.trim())).toString();
  }

  static String? _readString(Map<dynamic, dynamic> value, String key) {
    final raw = value[key];
    if (raw is! String) {
      return null;
    }
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _parseDateTime(String? value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  static bool _isNonEmpty(String value) => value.trim().isNotEmpty;

  static bool _matches(String expected, String? actual) {
    final actualTrimmed = actual?.trim();
    return actualTrimmed != null &&
        actualTrimmed.isNotEmpty &&
        actualTrimmed == expected;
  }
}
