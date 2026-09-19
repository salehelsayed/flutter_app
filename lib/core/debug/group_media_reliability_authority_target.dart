import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The creator observation that receiver readiness must actually reach.
/// This plain-Dart value is shared by the host runner and debug endpoint.
final class GroupMediaReliabilityAuthorityTarget {
  const GroupMediaReliabilityAuthorityTarget._({
    required this.groupIdSha256,
    required this.keyEpoch,
    required this.authoritySha256,
    required this.authorityEventAt,
    required this.memberRolesSha256,
  });

  static const _keys = {
    'groupIdSha256',
    'keyEpoch',
    'authoritySha256',
    'authorityEventAt',
    'memberRolesSha256',
  };

  factory GroupMediaReliabilityAuthorityTarget.fromJson(Object? value) {
    final hex = RegExp(r'^[a-f0-9]{64}$');
    if (value is! Map ||
        value.length != _keys.length ||
        !value.keys.toSet().containsAll(_keys) ||
        value['keyEpoch'] is! int ||
        (value['keyEpoch'] as int) <= 0 ||
        const ['groupIdSha256', 'authoritySha256', 'memberRolesSha256'].any(
          (key) => value[key] is! String || !hex.hasMatch(value[key] as String),
        ) ||
        value['authorityEventAt'] is! String ||
        (value['authorityEventAt'] as String).length > 40 ||
        !(value['authorityEventAt'] as String).endsWith('Z') ||
        DateTime.tryParse(value['authorityEventAt'] as String) == null) {
      throw const FormatException('group-media authority target rejected');
    }
    return GroupMediaReliabilityAuthorityTarget._(
      groupIdSha256: value['groupIdSha256'] as String,
      keyEpoch: value['keyEpoch'] as int,
      authoritySha256: value['authoritySha256'] as String,
      authorityEventAt: value['authorityEventAt'] as String,
      memberRolesSha256: value['memberRolesSha256'] as String,
    );
  }

  factory GroupMediaReliabilityAuthorityTarget.fromObservation(
    Map<String, Object?> observation,
  ) {
    if (observation['schema'] != 'mknoon.group-media-authority.v1' ||
        observation['admission'] != 'strict') {
      throw const FormatException('group-media authority target is not strict');
    }
    return GroupMediaReliabilityAuthorityTarget.fromJson({
      for (final key in _keys) key: observation[key],
    });
  }

  final String groupIdSha256;
  final int keyEpoch;
  final String authoritySha256;
  final String authorityEventAt;
  final String memberRolesSha256;

  Map<String, Object?> toJson() => {
    'groupIdSha256': groupIdSha256,
    'keyEpoch': keyEpoch,
    'authoritySha256': authoritySha256,
    'authorityEventAt': authorityEventAt,
    'memberRolesSha256': memberRolesSha256,
  };

  bool isForGroup(String groupId) =>
      sha256.convert(utf8.encode(groupId)).toString() == groupIdSha256;

  bool matchesObservation(Map<String, Object?> observation) =>
      observation['schema'] == 'mknoon.group-media-authority.v1' &&
      observation['admission'] == 'strict' &&
      observation['groupIdSha256'] == groupIdSha256 &&
      observation['keyEpoch'] == keyEpoch &&
      observation['authoritySha256'] == authoritySha256 &&
      observation['authorityEventAt'] == authorityEventAt &&
      observation['memberRolesSha256'] == memberRolesSha256;
}
