import 'dart:convert';

import 'package:flutter_app/core/notifications/ios_nse_inbox_projection.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

/// Recipient-owned group context consumed by the iOS notification extension.
const String sharedGroupReactionContextsKey = 'group_reaction_contexts_v1';

/// Bounded locally-authored group targets consumed by the iOS extension.
const String sharedGroupReactionAuthoredTargetsKey =
    'group_reaction_authored_targets_v1';

/// Latest active/tombstoned recipient-owned reaction comparands consumed by
/// the iOS extension before it claims a delayed ADD notification.
const String sharedGroupReactionLatestStatesKey =
    'group_reaction_latest_states_v1';

typedef GroupReactionNotificationContextSnapshot = ({
  List<GroupModel> groups,
  Map<String, List<GroupMember>> membersByGroup,
  Map<String, GroupKeyInfo?> latestKeysByGroup,
  Set<String> terminalGroupIds,
});

typedef LoadGroupReactionNotificationContextSnapshot =
    Future<GroupReactionNotificationContextSnapshot> Function();

typedef LoadGroupReactionNotificationAuthoredTargets =
    Future<List<GroupMessage>> Function(
      String accountPeerId, {
      required int limit,
    });

/// One current, verified physical sender binding for protected group content.
final class GroupNotificationSenderAuthorityTuple {
  const GroupNotificationSenderAuthorityTuple({
    required this.logicalSender,
    required this.deviceId,
    required this.transportPeerId,
    required this.signingPublicKey,
  });

  final String logicalSender;
  final String deviceId;
  final String transportPeerId;
  final String signingPublicKey;

  Map<String, Object?> toJson() => <String, Object?>{
    'logicalSender': logicalSender,
    'deviceId': deviceId,
    'transportPeerId': transportPeerId,
    'signingPublicKey': signingPublicKey,
  };
}

/// The only group sender generation the NSE may use for enrichment.
final class GroupNotificationSenderAuthority {
  const GroupNotificationSenderAuthority({
    required this.authorityEventAt,
    required this.authorityEventId,
    required this.keyEpoch,
    required this.tuples,
  });

  final String authorityEventAt;
  final String authorityEventId;
  final int keyEpoch;
  final List<GroupNotificationSenderAuthorityTuple> tuples;

  Map<String, Object?> toJson() => <String, Object?>{
    'authorityEventAt': authorityEventAt,
    'authorityEventId': authorityEventId,
    'keyEpoch': keyEpoch,
    'tuples': tuples.map((tuple) => tuple.toJson()).toList(growable: false),
  };
}

typedef LoadGroupNotificationSenderAuthority =
    Future<GroupNotificationSenderAuthority?> Function(String groupId);

/// Mirrors only recipient-owned group-reaction display and eligibility state.
///
/// Reaction emoji remains inside the encrypted payload. Message text, group
/// keys, public keys, signatures, and sender-supplied display fields are never
/// written here. All writes are serialized because group, roster, key, and
/// message repositories can commit concurrently.
class GroupReactionNotificationProjection {
  final SecureKeyStore _store;
  final int maxAuthoredTargets;
  final int maxReactionComparands;
  final int maxSenderAuthorityTuples;
  Future<void> _tail = Future<void>.value();
  String? _expectedAccountPeerId;
  final Set<String> _terminalGroupIds = <String>{};

  GroupReactionNotificationProjection({
    required SecureKeyStore store,
    this.maxAuthoredTargets = 256,
    this.maxReactionComparands = 1024,
    this.maxSenderAuthorityTuples = 256,
  }) : assert(maxAuthoredTargets > 0),
       assert(maxReactionComparands > 0),
       assert(maxSenderAuthorityTuples > 0),
       _store = store;

  /// Establishes the active account and this exact installation before any
  /// group projection is restored. The installation identifiers are never
  /// derived from group rosters: a sibling that remains active must not make a
  /// revoked local installation notification-eligible.
  ///
  /// A different account atomically replaces both logical documents with empty
  /// account-owned state, so old group or target rows cannot cross identities.
  Future<void> replaceLocalIdentity({
    required String? accountPeerId,
    required String? deviceId,
    required String? transportPeerId,
  }) {
    final normalizedAccount = _nonEmpty(accountPeerId);
    final normalizedDevice = _nonEmpty(deviceId);
    final normalizedTransport = _nonEmpty(transportPeerId);
    if (_expectedAccountPeerId != normalizedAccount) {
      _terminalGroupIds.clear();
    }
    _expectedAccountPeerId = normalizedAccount;
    return _enqueue(() async {
      if (normalizedAccount == null ||
          normalizedDevice == null ||
          normalizedTransport == null) {
        await _deleteAllDocuments();
        return;
      }

      final current = await _readContexts();
      if (current.accountPeerId == normalizedAccount) {
        await _writeContexts(
          _ProjectionContexts(
            accountPeerId: normalizedAccount,
            deviceId: normalizedDevice,
            transportPeerId: normalizedTransport,
            groups: current.groups,
          ),
        );
        final targets = await _readTargets(
          expectedAccountPeerId: normalizedAccount,
        );
        await _writeTargets(normalizedAccount, targets);
        final states = await _readReactionComparands(
          expectedAccountPeerId: normalizedAccount,
        );
        await _writeReactionComparands(normalizedAccount, states);
        return;
      }

      // Invalidate the old recipient generation before any new-owner write.
      // If a following write fails, the NSE sees no group context and cannot
      // keep authorizing old group or announcement routes.
      await _deleteAllDocuments();
      await _writeContexts(
        _ProjectionContexts(
          accountPeerId: normalizedAccount,
          deviceId: normalizedDevice,
          transportPeerId: normalizedTransport,
          groups: <String, Map<String, Object?>>{},
        ),
      );
      await _writeTargets(normalizedAccount, const <_ProjectedGroupTarget>[]);
      await _writeReactionComparands(
        normalizedAccount,
        const <_ProjectedGroupReactionComparand>[],
      );
    }, propagateError: true);
  }

  Future<void> clearForLogout() {
    _expectedAccountPeerId = null;
    _terminalGroupIds.clear();
    return _enqueue(_deleteAllDocuments, propagateError: true);
  }

  /// Plan 321: the single public authority on which group types carry a
  /// notification context. The fresh-join atomic publish MUST consult this
  /// (never a hand-rolled type check — a chat-only filter would permanently
  /// blank announcement joiners).
  bool supportsGroupType(GroupType type) => _supportedGroupType(type);

  Future<void> upsertGroup(GroupModel group) {
    final groupId = group.id.trim();
    if (group.selfRemovedAt != null && groupId.isNotEmpty) {
      _terminalGroupIds.add(groupId);
    }
    return _enqueue(() async {
      final contexts = await _readContexts();
      if (!_ownsContexts(contexts)) return;
      if (group.selfRemovedAt != null) {
        contexts.groups.remove(groupId);
        await _writeContexts(contexts);
        final targets = await _readTargets(
          expectedAccountPeerId: contexts.accountPeerId,
        );
        targets.removeWhere((target) => target.groupId == groupId);
        await _writeTargetsAndPruneComparands(contexts.accountPeerId, targets);
        return;
      }
      if (!_supportedGroupType(group.type)) {
        contexts.groups.remove(group.id);
        await _writeContexts(contexts);
        return;
      }

      final name = group.name.trim();
      if (groupId.isEmpty || name.isEmpty) {
        contexts.groups.remove(groupId);
        await _writeContexts(contexts);
        return;
      }
      final previous = contexts.groups[groupId];
      _terminalGroupIds.remove(groupId);
      contexts.groups[groupId] = <String, Object?>{
        'name': name,
        'type': group.type.toValue(),
        'muted': group.isMuted,
        'archived': group.isArchived,
        'dissolved': group.isDissolved || group.dissolvedAt != null,
        if (previous?['keyEpoch'] is int)
          'keyEpoch': previous!['keyEpoch'] as int,
        'members': _copyMembers(previous?['members']),
        if (previous?['senderAuthority'] is Map)
          'senderAuthority': Map<String, Object?>.from(
            previous!['senderAuthority']! as Map,
          ),
      };
      await _writeContexts(contexts);
    });
  }

  Future<void> removeGroup(String groupId) => _enqueue(() async {
    final contexts = await _readContexts();
    if (!_ownsContexts(contexts)) {
      throw StateError('group notification projection owner is unavailable');
    }
    contexts.groups.remove(groupId);
    await _writeContexts(contexts);
    final targets = await _readTargets(
      expectedAccountPeerId: contexts.accountPeerId,
    );
    targets.removeWhere((target) => target.groupId == groupId);
    await _writeTargetsAndPruneComparands(contexts.accountPeerId, targets);
  });

  /// Fail-closed variant used when group authority is being destroyed.
  ///
  /// Ordinary projection maintenance remains best effort, but a removed shell
  /// cannot discard its retry addresses until notification authorization has
  /// definitely been removed from the shared store.
  Future<void> removeGroupStrict(String groupId) {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isNotEmpty) {
      // Register the terminal generation before queueing storage work. A
      // backfill that already captured SQL rows can therefore never republish
      // this context or any authored target after strict removal returns.
      _terminalGroupIds.add(normalizedGroupId);
    }
    return _enqueue(() async {
      final contexts = await _readContexts();
      if (!_ownsContexts(contexts)) return;
      contexts.groups.remove(normalizedGroupId);
      await _writeContexts(contexts);
      final targets = await _readTargets(
        expectedAccountPeerId: contexts.accountPeerId,
      );
      targets.removeWhere((target) => target.groupId == normalizedGroupId);
      await _writeTargetsAndPruneComparands(contexts.accountPeerId, targets);
    }, propagateError: true);
  }

  Future<void> upsertMember(GroupMember member) => _enqueue(() async {
    final contexts = await _readContexts();
    final group = contexts.groups[member.groupId];
    if (!_ownsContexts(contexts) || group == null) return;
    final peerId = member.peerId.trim();
    final username = member.username?.trim() ?? '';
    if (peerId.isEmpty || username.isEmpty) {
      final members = _copyMembers(group['members']);
      members.remove(peerId);
      group['members'] = members;
      await _writeContexts(contexts);
      return;
    }

    final devices = member.activeDevicesWithLegacyFallback();
    final deviceIds = _sortedUnique(devices.map((device) => device.deviceId));
    final transportPeerIds = _sortedUnique(
      devices.map((device) => device.transportPeerId),
    );
    final members = _copyMembers(group['members']);
    members[peerId] = <String, Object?>{
      'username': username,
      'role': member.role.toValue(),
      'deviceIds': deviceIds,
      'transportPeerIds': transportPeerIds,
    };
    group['members'] = members;
    await _writeContexts(contexts);
  });

  Future<void> removeMember({
    required String groupId,
    required String peerId,
  }) => _enqueue(() async {
    final contexts = await _readContexts();
    if (!_ownsContexts(contexts)) return;
    final group = contexts.groups[groupId];
    if (group == null) return;
    final members = _copyMembers(group['members']);
    members.remove(peerId);
    group['members'] = members;
    await _writeContexts(contexts);
  });

  Future<void> removeAllMembers(String groupId) => _enqueue(() async {
    final contexts = await _readContexts();
    if (!_ownsContexts(contexts)) return;
    final group = contexts.groups[groupId];
    if (group == null) return;
    group['members'] = <String, Map<String, Object?>>{};
    await _writeContexts(contexts);
  });

  Future<void> upsertKeyEpoch(GroupKeyInfo key) => _enqueue(() async {
    final contexts = await _readContexts();
    if (!_ownsContexts(contexts)) return;
    final group = contexts.groups[key.groupId];
    if (group == null || key.keyGeneration < 0) return;
    final currentEpoch = group['keyEpoch'];
    if (currentEpoch is int && currentEpoch > key.keyGeneration) return;
    group['keyEpoch'] = key.keyGeneration;
    await _writeContexts(contexts);
  });

  Future<void> clearKeyEpoch(String groupId) => _enqueue(() async {
    final contexts = await _readContexts();
    if (!_ownsContexts(contexts)) return;
    final group = contexts.groups[groupId];
    if (group == null) return;
    group.remove('keyEpoch');
    await _writeContexts(contexts);
  });

  /// Removes one group's physical sender authorization and verifies absence
  /// before its authoritative database generation is allowed to mutate.
  Future<void> retireGroupSenderAuthority(String groupId) => _enqueue(() async {
    final normalized = _nonEmpty(groupId);
    if (normalized == null) {
      throw ArgumentError.value(groupId, 'groupId');
    }
    final contexts = await _readContexts();
    if (!_ownsContexts(contexts)) {
      throw StateError('group notification projection owner is unavailable');
    }
    contexts.groups[normalized]?.remove('senderAuthority');
    await _writeContexts(contexts);
    final readBack = await _readContexts();
    if (!_ownsContexts(readBack) ||
        readBack.groups[normalized]?['senderAuthority'] != null) {
      throw StateError('group sender authority retirement failed');
    }
  }, propagateError: true);

  /// Publishes one complete, currently verified sender generation. Failure
  /// invalidates the shared documents so a previous generation cannot remain.
  Future<void> replaceGroupSenderAuthority(
    String groupId,
    GroupNotificationSenderAuthority? authority,
  ) => _enqueue(() async {
    final normalized = _nonEmpty(groupId);
    if (normalized == null) {
      throw ArgumentError.value(groupId, 'groupId');
    }
    final contexts = await _readContexts();
    if (!_ownsContexts(contexts)) {
      throw StateError('group notification projection owner is unavailable');
    }
    final group = contexts.groups[normalized];
    if (group == null) {
      if (authority == null) return;
      throw StateError('group notification context is unavailable');
    }
    if (authority == null) {
      group.remove('senderAuthority');
    } else {
      group['senderAuthority'] = _canonicalSenderAuthority(authority);
    }
    await _writeContexts(contexts);
    final expected = group['senderAuthority'];
    final readBack = await _readContexts();
    final actual = readBack.groups[normalized]?['senderAuthority'];
    if (!_ownsContexts(readBack) ||
        jsonEncode(expected) != jsonEncode(actual)) {
      throw StateError('group sender authority read-back failed');
    }
  }, propagateError: true);

  /// Startup replacement for all committed, verified group generations.
  Future<void> replaceAllGroupSenderAuthorities(
    Map<String, GroupNotificationSenderAuthority?> authorities,
  ) => _enqueue(() async {
    final contexts = await _readContexts();
    if (!_ownsContexts(contexts)) {
      throw StateError('group notification projection owner is unavailable');
    }
    for (final entry in contexts.groups.entries) {
      final authority = authorities[entry.key];
      if (authority == null) {
        entry.value.remove('senderAuthority');
      } else {
        entry.value['senderAuthority'] = _canonicalSenderAuthority(authority);
      }
    }
    await _writeContexts(contexts);
    final readBack = await _readContexts();
    if (!_ownsContexts(readBack) ||
        jsonEncode(contexts.groups) != jsonEncode(readBack.groups)) {
      throw StateError('group sender authority backfill read-back failed');
    }
  }, propagateError: true);

  Map<String, Object?> _canonicalSenderAuthority(
    GroupNotificationSenderAuthority authority,
  ) {
    final eventAt = _nonEmpty(authority.authorityEventAt);
    final eventId = _strictAuthorityString(authority.authorityEventId);
    final parsedAt = eventAt == null ? null : DateTime.tryParse(eventAt);
    if (eventAt == null ||
        parsedAt == null ||
        !parsedAt.isUtc ||
        _fixedUtc(parsedAt) != eventAt ||
        eventId == null ||
        authority.keyEpoch < 0 ||
        authority.tuples.isEmpty ||
        authority.tuples.length > maxSenderAuthorityTuples) {
      throw const FormatException('invalid group sender authority generation');
    }
    final tuples =
        authority.tuples
            .map((tuple) {
              final logical = _strictAuthorityString(
                tuple.logicalSender,
                maxUtf8Bytes: 1024,
              );
              final device = _strictAuthorityString(
                tuple.deviceId,
                maxUtf8Bytes: 1024,
              );
              final transport =
                  isNativeCompatibleIosNsePeerId(tuple.transportPeerId)
                  ? tuple.transportPeerId
                  : null;
              final signingKey = _strictAuthorityString(
                tuple.signingPublicKey,
                maxUtf8Bytes: 512,
              );
              if (logical == null ||
                  device == null ||
                  transport == null ||
                  signingKey == null ||
                  !_isCanonicalEd25519PublicKey(signingKey)) {
                throw const FormatException(
                  'invalid group sender authority tuple',
                );
              }
              return <String, Object?>{
                'logicalSender': logical,
                'deviceId': device,
                'transportPeerId': transport,
                'signingPublicKey': signingKey,
              };
            })
            .toList(growable: false)
          ..sort((left, right) {
            for (final key in const <String>[
              'logicalSender',
              'deviceId',
              'transportPeerId',
              'signingPublicKey',
            ]) {
              final order = (left[key]! as String).compareTo(
                right[key]! as String,
              );
              if (order != 0) return order;
            }
            return 0;
          });
    final seenTuples = <String>{};
    final seenTransports = <String>{};
    final tupleByLogicalDevice = <String, String>{};
    for (final tuple in tuples) {
      final encoded = jsonEncode(tuple);
      if (!seenTuples.add(encoded)) {
        throw const FormatException('duplicate group sender authority tuple');
      }
      final transport = tuple['transportPeerId']! as String;
      if (!seenTransports.add(transport)) {
        throw const FormatException('ambiguous group sender transport');
      }
      final logicalDevice =
          '${tuple['logicalSender']}\u0000${tuple['deviceId']}';
      final transportAndKey = '$transport\u0000${tuple['signingPublicKey']}';
      if (tupleByLogicalDevice.putIfAbsent(
            logicalDevice,
            () => transportAndKey,
          ) !=
          transportAndKey) {
        throw const FormatException('ambiguous group sender device');
      }
    }
    return <String, Object?>{
      'authorityEventAt': eventAt,
      'authorityEventId': eventId,
      'keyEpoch': authority.keyEpoch,
      'tuples': tuples,
    };
  }

  /// Strictly replaces one accepted group's complete notification context.
  ///
  /// Accepted post-removal re-entry must not publish group, roster, and key
  /// authority through separate best-effort writes: a later write could fail
  /// after an earlier one exposed a partial context. This method constructs
  /// the complete replacement in memory, commits it with one queued document
  /// write, and propagates storage failures to the authority owner so it can
  /// perform its exact rollback. The terminal-generation guard is cleared only
  /// after that write succeeds.
  Future<void> replaceAcceptedGroupContextStrict({
    required GroupModel group,
    required Iterable<GroupMember> members,
    required GroupKeyInfo key,
  }) {
    final groupId = group.id.trim();
    final name = group.name.trim();
    if (groupId.isEmpty ||
        name.isEmpty ||
        group.selfRemovedAt != null ||
        !_supportedGroupType(group.type) ||
        key.groupId != groupId ||
        key.keyGeneration < 0) {
      throw ArgumentError('Invalid accepted group projection material.');
    }

    final projectedMembers = <String, Map<String, Object?>>{};
    for (final member in members) {
      if (member.groupId != groupId) {
        throw ArgumentError('Accepted roster contains another group.');
      }
      final peerId = member.peerId.trim();
      final username = member.username?.trim() ?? '';
      if (peerId.isEmpty || username.isEmpty) continue;
      final devices = member.activeDevicesWithLegacyFallback();
      projectedMembers[peerId] = <String, Object?>{
        'username': username,
        'role': member.role.toValue(),
        'deviceIds': _sortedUnique(devices.map((device) => device.deviceId)),
        'transportPeerIds': _sortedUnique(
          devices.map((device) => device.transportPeerId),
        ),
      };
    }

    final replacement = <String, Object?>{
      'name': name,
      'type': group.type.toValue(),
      'muted': group.isMuted,
      'archived': group.isArchived,
      'dissolved': group.isDissolved || group.dissolvedAt != null,
      'keyEpoch': key.keyGeneration,
      'members': projectedMembers,
    };
    return _enqueue(() async {
      final contexts = await _readContexts();
      if (!_ownsContexts(contexts)) return;
      final previousAuthority = contexts.groups[groupId]?['senderAuthority'];
      if (previousAuthority is Map) {
        replacement['senderAuthority'] = Map<String, Object?>.from(
          previousAuthority,
        );
      }
      contexts.groups[groupId] = replacement;
      await _writeContexts(contexts);
      _terminalGroupIds.remove(groupId);
    }, propagateError: true);
  }

  /// Launch-time authoritative replacement from committed SQLCipher rows.
  Future<void> replaceContexts({
    required Iterable<GroupModel> groups,
    required Map<String, List<GroupMember>> membersByGroup,
    required Map<String, GroupKeyInfo?> latestKeysByGroup,
  }) => _enqueue(
    () => _replaceContextsAssumingQueued(
      groups: groups,
      membersByGroup: membersByGroup,
      latestKeysByGroup: latestKeysByGroup,
    ),
  );

  /// Loads and replaces the launch snapshot as one projection-queue unit.
  ///
  /// Keeping the authoritative SQL read inside the queue prevents a snapshot
  /// captured before terminal removal from being published after a later
  /// accepted membership has replaced that terminal generation.
  Future<void> replaceContextsFromAuthoritativeLoader(
    LoadGroupReactionNotificationContextSnapshot load,
  ) => _enqueue(() async {
    final initial = await _readContexts();
    final accountPeerId = _ownedAccountPeerId(initial);
    if (accountPeerId == null) return;
    final snapshot = await load();
    if (_expectedAccountPeerId != accountPeerId) return;
    final current = await _readContexts();
    if (_ownedAccountPeerId(current) != accountPeerId) return;
    final terminalGroupIds = snapshot.terminalGroupIds
        .map((groupId) => groupId.trim())
        .where((groupId) => groupId.isNotEmpty)
        .toSet();
    _terminalGroupIds.addAll(terminalGroupIds);
    await _replaceContextsAssumingQueued(
      groups: snapshot.groups,
      membersByGroup: snapshot.membersByGroup,
      latestKeysByGroup: snapshot.latestKeysByGroup,
    );
    if (terminalGroupIds.isNotEmpty) {
      final contexts = await _readContexts();
      if (!_ownsContexts(contexts)) return;
      final targets = await _readTargets(
        expectedAccountPeerId: contexts.accountPeerId,
      );
      targets.removeWhere(
        (target) => terminalGroupIds.contains(target.groupId),
      );
      await _writeTargetsAndPruneComparands(contexts.accountPeerId, targets);
    }
  }, propagateError: true);

  Future<void> _replaceContextsAssumingQueued({
    required Iterable<GroupModel> groups,
    required Map<String, List<GroupMember>> membersByGroup,
    required Map<String, GroupKeyInfo?> latestKeysByGroup,
  }) async {
    final current = await _readContexts();
    if (!_ownsContexts(current)) return;
    final accountPeerId = current.accountPeerId;
    if (accountPeerId == null) return;
    final replacement = <String, Map<String, Object?>>{};
    final sortedGroups =
        groups
            .where(
              (group) =>
                  group.selfRemovedAt == null &&
                  !_terminalGroupIds.contains(group.id.trim()) &&
                  _supportedGroupType(group.type),
            )
            .toList(growable: false)
          ..sort((left, right) => left.id.compareTo(right.id));
    for (final group in sortedGroups) {
      final groupId = group.id.trim();
      final name = group.name.trim();
      if (groupId.isEmpty || name.isEmpty) continue;
      final members = <String, Map<String, Object?>>{};
      for (final member in membersByGroup[groupId] ?? const <GroupMember>[]) {
        final peerId = member.peerId.trim();
        final username = member.username?.trim() ?? '';
        if (peerId.isEmpty || username.isEmpty) continue;
        final devices = member.activeDevicesWithLegacyFallback();
        members[peerId] = <String, Object?>{
          'username': username,
          'role': member.role.toValue(),
          'deviceIds': _sortedUnique(devices.map((device) => device.deviceId)),
          'transportPeerIds': _sortedUnique(
            devices.map((device) => device.transportPeerId),
          ),
        };
      }
      final keyEpoch = latestKeysByGroup[groupId]?.keyGeneration;
      replacement[groupId] = <String, Object?>{
        'name': name,
        'type': group.type.toValue(),
        'muted': group.isMuted,
        'archived': group.isArchived,
        'dissolved': group.isDissolved || group.dissolvedAt != null,
        if (keyEpoch != null && keyEpoch >= 0) 'keyEpoch': keyEpoch,
        'members': members,
        if (current.groups[groupId]?['senderAuthority'] is Map)
          'senderAuthority': Map<String, Object?>.from(
            current.groups[groupId]!['senderAuthority']! as Map,
          ),
      };
    }
    await _writeContexts(
      _ProjectionContexts(
        accountPeerId: accountPeerId,
        deviceId: current.deviceId,
        transportPeerId: current.transportPeerId,
        groups: replacement,
      ),
    );
  }

  Future<void> upsertAuthoredTarget(GroupMessage message) => _enqueue(() async {
    final contexts = await _readContexts();
    if (!_ownsContexts(contexts)) return;
    final accountPeerId = contexts.accountPeerId;
    if (accountPeerId == null) return;
    final targets = await _readTargets(expectedAccountPeerId: accountPeerId);
    targets.removeWhere((target) => target.id == message.id);
    final groupId = message.groupId.trim();
    if (_isAuthoredBy(message, accountPeerId) &&
        groupId.isNotEmpty &&
        !_terminalGroupIds.contains(groupId) &&
        contexts.groups.containsKey(groupId)) {
      targets.add(_ProjectedGroupTarget.fromMessage(message));
    }
    await _writeTargetsAndPruneComparands(
      accountPeerId,
      _boundedTargets(targets),
    );
  });

  Future<void> removeAuthoredTarget(String messageId) => _enqueue(() async {
    final contexts = await _readContexts();
    if (!_ownsContexts(contexts)) return;
    final accountPeerId = contexts.accountPeerId;
    if (accountPeerId == null) return;
    final targets = await _readTargets(expectedAccountPeerId: accountPeerId);
    targets.removeWhere((target) => target.id == messageId);
    await _writeTargetsAndPruneComparands(accountPeerId, targets);
  });

  Future<void> removeAuthoredTargetsForGroup(String groupId) => _enqueue(
    () async {
      final contexts = await _readContexts();
      if (!_ownsContexts(contexts)) return;
      final accountPeerId = contexts.accountPeerId;
      if (accountPeerId == null) return;
      final targets = await _readTargets(expectedAccountPeerId: accountPeerId);
      targets.removeWhere((target) => target.groupId == groupId);
      await _writeTargetsAndPruneComparands(accountPeerId, targets);
    },
  );

  /// Launch/retention self-heal from an authoritative committed-row query.
  Future<void> replaceAuthoredTargets(Iterable<GroupMessage> messages) =>
      _enqueue(() => _replaceAuthoredTargetsAssumingQueued(messages));

  /// Loads and replaces authored targets as one projection-queue unit.
  ///
  /// This gives the target backfill the same terminal-generation ordering as
  /// the group-context backfill, so accepted re-entry cannot make an old
  /// pre-removal target snapshot eligible again.
  Future<void> replaceAuthoredTargetsFromAuthoritativeLoader(
    LoadGroupReactionNotificationAuthoredTargets load,
  ) => _enqueue(() async {
    final initial = await _readContexts();
    final accountPeerId = _ownedAccountPeerId(initial);
    if (accountPeerId == null) return;
    final messages = await load(accountPeerId, limit: maxAuthoredTargets);
    await _replaceAuthoredTargetsAssumingQueued(messages);
  }, propagateError: true);

  Future<void> _replaceAuthoredTargetsAssumingQueued(
    Iterable<GroupMessage> messages,
  ) async {
    final contexts = await _readContexts();
    if (!_ownsContexts(contexts)) return;
    final accountPeerId = contexts.accountPeerId;
    if (accountPeerId == null) return;
    final targets = messages
        .where((message) {
          final groupId = message.groupId.trim();
          return _isAuthoredBy(message, accountPeerId) &&
              groupId.isNotEmpty &&
              !_terminalGroupIds.contains(groupId) &&
              contexts.groups.containsKey(groupId);
        })
        .map(_ProjectedGroupTarget.fromMessage)
        .toList(growable: true);
    await _writeTargetsAndPruneComparands(
      accountPeerId,
      _boundedTargets(targets),
    );
  }

  /// Projects the committed last-writer-wins state for a reaction on a
  /// locally-authored group target. Non-group/direct targets are ignored.
  Future<void> upsertReactionComparand(MessageReaction reaction) => _enqueue(
    () async {
      final contexts = await _readContexts();
      if (!_ownsContexts(contexts)) return;
      final accountPeerId = contexts.accountPeerId;
      if (accountPeerId == null) return;
      final targets = await _readTargets(expectedAccountPeerId: accountPeerId);
      _ProjectedGroupTarget? target;
      for (final candidate in targets) {
        if (candidate.id == reaction.messageId) {
          target = candidate;
          break;
        }
      }
      if (target == null) return;
      final projected = _ProjectedGroupReactionComparand.fromReaction(
        groupId: target.groupId,
        reaction: reaction,
      );
      if (projected == null) return;
      final states = await _readReactionComparands(
        expectedAccountPeerId: accountPeerId,
      );
      states.removeWhere((state) => state.hasSameKey(projected));
      states.add(projected);
      await _writeReactionComparands(
        accountPeerId,
        _boundedReactionComparands(states),
      );
    },
  );

  /// Launch-time authoritative replacement from committed SQLCipher rows.
  Future<void> replaceReactionComparands(Iterable<MessageReaction> reactions) =>
      _enqueue(() async {
        final contexts = await _readContexts();
        if (!_ownsContexts(contexts)) return;
        final accountPeerId = contexts.accountPeerId;
        if (accountPeerId == null) return;
        final targets = await _readTargets(
          expectedAccountPeerId: accountPeerId,
        );
        final targetsById = <String, _ProjectedGroupTarget>{
          for (final target in targets) target.id: target,
        };
        final states = <_ProjectedGroupReactionComparand>[];
        for (final reaction in reactions) {
          final target = targetsById[reaction.messageId];
          if (target == null) continue;
          final projected = _ProjectedGroupReactionComparand.fromReaction(
            groupId: target.groupId,
            reaction: reaction,
          );
          if (projected != null) states.add(projected);
        }
        await _writeReactionComparands(
          accountPeerId,
          _boundedReactionComparands(states),
        );
      });

  Future<void> removeReactionComparandsForMessage(String messageId) =>
      _enqueue(() async {
        final contexts = await _readContexts();
        if (!_ownsContexts(contexts)) return;
        final accountPeerId = contexts.accountPeerId;
        if (accountPeerId == null) return;
        final states = await _readReactionComparands(
          expectedAccountPeerId: accountPeerId,
        );
        states.removeWhere((state) => state.targetMessageId == messageId);
        await _writeReactionComparands(accountPeerId, states);
      });

  Future<String?> readLocalAccountPeerId() async =>
      _ownedAccountPeerId(await _readContexts());

  /// Test/diagnostic read. Production eligibility is consumed by the NSE.
  Future<Map<String, Object?>> readContexts() async {
    final contexts = await _readContexts();
    return _contextsJson(contexts);
  }

  /// Test/diagnostic read. Production eligibility is consumed by the NSE.
  Future<List<Map<String, Object?>>> readAuthoredTargets() async {
    final contexts = await _readContexts();
    return (await _readTargets(
      expectedAccountPeerId: contexts.accountPeerId,
    )).map((target) => target.toJson()).toList(growable: false);
  }

  /// Test/diagnostic read. Production eligibility is consumed by the NSE.
  Future<List<Map<String, Object?>>> readReactionComparands() async {
    final contexts = await _readContexts();
    return (await _readReactionComparands(
      expectedAccountPeerId: contexts.accountPeerId,
    )).map((state) => state.toJson()).toList(growable: false);
  }

  Future<void> _enqueue(
    Future<void> Function() action, {
    bool propagateError = false,
  }) {
    final next = _tail.then((_) async {
      try {
        await action();
      } catch (error) {
        Object? invalidationError;
        try {
          await _deleteAllDocuments();
        } catch (failure) {
          invalidationError = failure;
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REACTION_PUSH_PROJECTION_ERROR',
          details: {
            'error': error.toString(),
            if (invalidationError != null)
              'invalidationError': invalidationError.toString(),
          },
        );
        if (propagateError) rethrow;
      }
    });
    _tail = next.catchError((Object _) {});
    return next;
  }

  bool _ownsContexts(_ProjectionContexts contexts) =>
      _ownedAccountPeerId(contexts) != null;

  String? _ownedAccountPeerId(_ProjectionContexts contexts) {
    final expected = _expectedAccountPeerId;
    return expected != null && contexts.accountPeerId == expected
        ? expected
        : null;
  }

  Future<_ProjectionContexts> _readContexts() async {
    final raw = await _store.read(sharedGroupReactionContextsKey);
    if (raw == null || raw.isEmpty) return const _ProjectionContexts.empty();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        return const _ProjectionContexts.empty();
      }
      final accountPeerId = _nonEmpty(decoded['localAccountPeerId']);
      if (accountPeerId == null) return const _ProjectionContexts.empty();
      final deviceId = _nonEmpty(decoded['localDeviceId']);
      final transportPeerId = _nonEmpty(decoded['localTransportPeerId']);
      final groups = <String, Map<String, Object?>>{};
      final rawGroups = decoded['groups'];
      if (rawGroups is Map) {
        for (final entry in rawGroups.entries) {
          final groupId = _nonEmpty(entry.key);
          final group = _sanitizeGroup(
            entry.value,
            sanitizeAuthority: _sanitizeStoredSenderAuthority,
          );
          if (groupId != null && group != null) groups[groupId] = group;
        }
      }
      return _ProjectionContexts(
        accountPeerId: accountPeerId,
        deviceId: deviceId,
        transportPeerId: transportPeerId,
        groups: groups,
      );
    } catch (_) {
      return const _ProjectionContexts.empty();
    }
  }

  Future<void> _writeContexts(_ProjectionContexts contexts) => _store.write(
    sharedGroupReactionContextsKey,
    jsonEncode(_contextsJson(contexts)),
  );

  Map<String, Object?>? _sanitizeStoredSenderAuthority(Object? value) {
    if (value is! Map ||
        value.length != 4 ||
        !value.keys.toSet().containsAll(const <String>{
          'authorityEventAt',
          'authorityEventId',
          'keyEpoch',
          'tuples',
        })) {
      return null;
    }
    final tuplesRaw = value['tuples'];
    if (tuplesRaw is! List ||
        tuplesRaw.isEmpty ||
        tuplesRaw.length > maxSenderAuthorityTuples) {
      return null;
    }
    final tuples = <GroupNotificationSenderAuthorityTuple>[];
    for (final raw in tuplesRaw) {
      if (raw is! Map ||
          raw.length != 4 ||
          !raw.keys.toSet().containsAll(const <String>{
            'logicalSender',
            'deviceId',
            'transportPeerId',
            'signingPublicKey',
          })) {
        return null;
      }
      final logical = _strictAuthorityString(
        raw['logicalSender'],
        maxUtf8Bytes: 1024,
      );
      final device = _strictAuthorityString(
        raw['deviceId'],
        maxUtf8Bytes: 1024,
      );
      final transport = isNativeCompatibleIosNsePeerId(raw['transportPeerId'])
          ? raw['transportPeerId']! as String
          : null;
      final signingKey = _strictAuthorityString(
        raw['signingPublicKey'],
        maxUtf8Bytes: 512,
      );
      if (logical == null ||
          device == null ||
          transport == null ||
          signingKey == null ||
          !_isCanonicalEd25519PublicKey(signingKey)) {
        return null;
      }
      tuples.add(
        GroupNotificationSenderAuthorityTuple(
          logicalSender: logical,
          deviceId: device,
          transportPeerId: transport,
          signingPublicKey: signingKey,
        ),
      );
    }
    try {
      final canonical = _canonicalSenderAuthority(
        GroupNotificationSenderAuthority(
          authorityEventAt: _nonEmpty(value['authorityEventAt']) ?? '',
          authorityEventId:
              _strictAuthorityString(value['authorityEventId']) ?? '',
          keyEpoch: value['keyEpoch'] is int ? value['keyEpoch']! as int : -1,
          tuples: tuples,
        ),
      );
      return jsonEncode(value) == jsonEncode(canonical) ? canonical : null;
    } on Object {
      return null;
    }
  }

  Map<String, Object?> _contextsJson(_ProjectionContexts contexts) {
    return <String, Object?>{
      'version': 1,
      'localAccountPeerId': ?contexts.accountPeerId,
      'localDeviceId': ?contexts.deviceId,
      'localTransportPeerId': ?contexts.transportPeerId,
      'groups': contexts.groups,
    };
  }

  Future<List<_ProjectedGroupTarget>> _readTargets({
    required String? expectedAccountPeerId,
  }) async {
    if (expectedAccountPeerId == null) return <_ProjectedGroupTarget>[];
    final raw = await _store.read(sharedGroupReactionAuthoredTargetsKey);
    if (raw == null || raw.isEmpty) return <_ProjectedGroupTarget>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        return <_ProjectedGroupTarget>[];
      }
      if (_nonEmpty(decoded['localAccountPeerId']) != expectedAccountPeerId) {
        return <_ProjectedGroupTarget>[];
      }
      final values = decoded['targets'];
      if (values is! List) return <_ProjectedGroupTarget>[];
      return values
          .whereType<Map>()
          .map(_ProjectedGroupTarget.fromJson)
          .whereType<_ProjectedGroupTarget>()
          .toList(growable: true);
    } catch (_) {
      return <_ProjectedGroupTarget>[];
    }
  }

  Future<void> _writeTargets(
    String accountPeerId,
    List<_ProjectedGroupTarget> targets,
  ) => _store.write(
    sharedGroupReactionAuthoredTargetsKey,
    jsonEncode(<String, Object?>{
      'version': 1,
      'localAccountPeerId': accountPeerId,
      'targets': targets.map((target) => target.toJson()).toList(),
    }),
  );

  Future<void> _writeTargetsAndPruneComparands(
    String? accountPeerId,
    List<_ProjectedGroupTarget> targets,
  ) async {
    if (accountPeerId == null) return;
    await _writeTargets(accountPeerId, targets);
    final targetIds = targets.map((target) => target.id).toSet();
    final states = await _readReactionComparands(
      expectedAccountPeerId: accountPeerId,
    );
    states.removeWhere((state) => !targetIds.contains(state.targetMessageId));
    await _writeReactionComparands(accountPeerId, states);
  }

  Future<List<_ProjectedGroupReactionComparand>> _readReactionComparands({
    required String? expectedAccountPeerId,
  }) async {
    if (expectedAccountPeerId == null) {
      return <_ProjectedGroupReactionComparand>[];
    }
    final raw = await _store.read(sharedGroupReactionLatestStatesKey);
    if (raw == null || raw.isEmpty) {
      return <_ProjectedGroupReactionComparand>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        return <_ProjectedGroupReactionComparand>[];
      }
      if (_nonEmpty(decoded['localAccountPeerId']) != expectedAccountPeerId) {
        return <_ProjectedGroupReactionComparand>[];
      }
      final values = decoded['states'];
      if (values is! List) return <_ProjectedGroupReactionComparand>[];
      return values
          .whereType<Map>()
          .map(_ProjectedGroupReactionComparand.fromJson)
          .whereType<_ProjectedGroupReactionComparand>()
          .toList(growable: true);
    } catch (_) {
      return <_ProjectedGroupReactionComparand>[];
    }
  }

  Future<void> _writeReactionComparands(
    String accountPeerId,
    List<_ProjectedGroupReactionComparand> states,
  ) => _store.write(
    sharedGroupReactionLatestStatesKey,
    jsonEncode(<String, Object?>{
      'version': 1,
      'localAccountPeerId': accountPeerId,
      'states': states.map((state) => state.toJson()).toList(),
    }),
  );

  List<_ProjectedGroupReactionComparand> _boundedReactionComparands(
    List<_ProjectedGroupReactionComparand> states,
  ) {
    final byKey = <String, _ProjectedGroupReactionComparand>{
      for (final state in states) state.storageKey: state,
    };
    final sorted = byKey.values.toList(growable: false)
      ..sort((left, right) {
        final timestampOrder = right.authoritativeTimestamp.compareTo(
          left.authoritativeTimestamp,
        );
        if (timestampOrder != 0) return timestampOrder;
        return left.storageKey.compareTo(right.storageKey);
      });
    return sorted.take(maxReactionComparands).toList(growable: false);
  }

  Future<void> _deleteAllDocuments() async {
    Object? firstError;
    try {
      await _store.delete(sharedGroupReactionContextsKey);
    } catch (error) {
      firstError = error;
    }
    try {
      await _store.delete(sharedGroupReactionAuthoredTargetsKey);
    } catch (error) {
      firstError ??= error;
    }
    try {
      await _store.delete(sharedGroupReactionLatestStatesKey);
    } catch (error) {
      firstError ??= error;
    }
    if (firstError != null) throw firstError;
  }

  List<_ProjectedGroupTarget> _boundedTargets(
    List<_ProjectedGroupTarget> targets,
  ) {
    final byId = <String, _ProjectedGroupTarget>{
      for (final target in targets) target.id: target,
    };
    final sorted = byId.values.toList(growable: false)
      ..sort((left, right) {
        final timestampOrder = right.timestamp.compareTo(left.timestamp);
        if (timestampOrder != 0) return timestampOrder;
        return left.id.compareTo(right.id);
      });
    return sorted.take(maxAuthoredTargets).toList(growable: false);
  }
}

String _fixedUtc(DateTime value) {
  final utc = value.toUtc();
  String two(int part) => part.toString().padLeft(2, '0');
  final micros =
      utc.millisecond * Duration.microsecondsPerMillisecond + utc.microsecond;
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:'
      '${two(utc.minute)}:${two(utc.second)}.'
      '${micros.toString().padLeft(6, '0')}Z';
}

class _ProjectionContexts {
  final String? accountPeerId;
  final String? deviceId;
  final String? transportPeerId;
  final Map<String, Map<String, Object?>> groups;

  const _ProjectionContexts({
    required this.accountPeerId,
    required this.deviceId,
    required this.transportPeerId,
    required this.groups,
  });

  const _ProjectionContexts.empty()
    : accountPeerId = null,
      deviceId = null,
      transportPeerId = null,
      groups = const <String, Map<String, Object?>>{};
}

class _ProjectedGroupTarget {
  final String id;
  final String groupId;
  final int keyEpoch;
  final String timestamp;

  const _ProjectedGroupTarget({
    required this.id,
    required this.groupId,
    required this.keyEpoch,
    required this.timestamp,
  });

  factory _ProjectedGroupTarget.fromMessage(GroupMessage message) =>
      _ProjectedGroupTarget(
        id: message.id,
        groupId: message.groupId,
        keyEpoch: message.keyGeneration,
        timestamp: message.timestamp.toUtc().toIso8601String(),
      );

  static _ProjectedGroupTarget? fromJson(Map<Object?, Object?> value) {
    final id = _nonEmpty(value['id']);
    final groupId = _nonEmpty(value['groupId']);
    final keyEpoch = value['keyEpoch'];
    final timestamp = _nonEmpty(value['timestamp']);
    if (id == null ||
        groupId == null ||
        keyEpoch is! int ||
        keyEpoch < 0 ||
        timestamp == null ||
        DateTime.tryParse(timestamp) == null) {
      return null;
    }
    return _ProjectedGroupTarget(
      id: id,
      groupId: groupId,
      keyEpoch: keyEpoch,
      timestamp: timestamp,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'groupId': groupId,
    'keyEpoch': keyEpoch,
    'timestamp': timestamp,
  };
}

class _ProjectedGroupReactionComparand {
  final String groupId;
  final String targetMessageId;
  final String reactorPeerId;
  final String timestamp;
  final String? removedAt;

  const _ProjectedGroupReactionComparand({
    required this.groupId,
    required this.targetMessageId,
    required this.reactorPeerId,
    required this.timestamp,
    required this.removedAt,
  });

  static _ProjectedGroupReactionComparand? fromReaction({
    required String groupId,
    required MessageReaction reaction,
  }) {
    final normalizedGroupId = _nonEmpty(groupId);
    final targetMessageId = _nonEmpty(reaction.messageId);
    final reactorPeerId = _nonEmpty(reaction.senderPeerId);
    final timestamp = _normalizedTimestamp(reaction.timestamp);
    final removedAt = reaction.removedAt == null
        ? null
        : _normalizedTimestamp(reaction.removedAt!);
    if (normalizedGroupId == null ||
        targetMessageId == null ||
        reactorPeerId == null ||
        timestamp == null ||
        (reaction.removedAt != null && removedAt == null)) {
      return null;
    }
    return _ProjectedGroupReactionComparand(
      groupId: normalizedGroupId,
      targetMessageId: targetMessageId,
      reactorPeerId: reactorPeerId,
      timestamp: timestamp,
      removedAt: removedAt,
    );
  }

  static _ProjectedGroupReactionComparand? fromJson(
    Map<Object?, Object?> value,
  ) {
    final groupId = _nonEmpty(value['groupId']);
    final targetMessageId = _nonEmpty(value['targetMessageId']);
    final reactorPeerId = _nonEmpty(value['reactorPeerId']);
    final timestampValue = _nonEmpty(value['timestamp']);
    final timestamp = timestampValue == null
        ? null
        : _normalizedTimestamp(timestampValue);
    final removedAtValue = value['removedAt'];
    final removedAt = removedAtValue == null
        ? null
        : removedAtValue is String
        ? _normalizedTimestamp(removedAtValue)
        : null;
    if (groupId == null ||
        targetMessageId == null ||
        reactorPeerId == null ||
        timestamp == null ||
        (removedAtValue != null && removedAt == null)) {
      return null;
    }
    return _ProjectedGroupReactionComparand(
      groupId: groupId,
      targetMessageId: targetMessageId,
      reactorPeerId: reactorPeerId,
      timestamp: timestamp,
      removedAt: removedAt,
    );
  }

  String get storageKey => '$targetMessageId\u0000$reactorPeerId';

  String get authoritativeTimestamp => removedAt ?? timestamp;

  bool hasSameKey(_ProjectedGroupReactionComparand other) =>
      targetMessageId == other.targetMessageId &&
      reactorPeerId == other.reactorPeerId;

  Map<String, Object?> toJson() => <String, Object?>{
    'groupId': groupId,
    'targetMessageId': targetMessageId,
    'reactorPeerId': reactorPeerId,
    'timestamp': timestamp,
    'removedAt': ?removedAt,
  };
}

bool _supportedGroupType(GroupType type) =>
    type == GroupType.chat || type == GroupType.announcement;

bool _isAuthoredBy(GroupMessage message, String accountPeerId) =>
    message.id.trim().isNotEmpty &&
    message.groupId.trim().isNotEmpty &&
    message.keyGeneration >= 0 &&
    message.senderPeerId.trim() == accountPeerId;

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _strictAuthorityString(Object? value, {int maxUtf8Bytes = 512}) {
  if (value is! String ||
      value.isEmpty ||
      value != value.trim() ||
      utf8.encode(value).length > maxUtf8Bytes ||
      value.runes.any(
        (rune) => rune < 0x20 || (rune >= 0x7f && rune <= 0x9f),
      )) {
    return null;
  }
  return value;
}

bool _isCanonicalEd25519PublicKey(String value) {
  try {
    final bytes = base64Decode(value);
    return bytes.length == 32 && base64Encode(bytes) == value;
  } on Object {
    return false;
  }
}

String? _normalizedTimestamp(String value) {
  final parsed = DateTime.tryParse(value.trim());
  return parsed?.toUtc().toIso8601String();
}

List<String> _sortedUnique(Iterable<String> values) {
  final result =
      values
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
  return result;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return _sortedUnique(value.whereType<String>());
}

Map<String, Map<String, Object?>> _copyMembers(Object? value) {
  final result = <String, Map<String, Object?>>{};
  if (value is! Map) return result;
  for (final entry in value.entries) {
    final peerId = _nonEmpty(entry.key);
    final member = entry.value;
    if (peerId == null || member is! Map) continue;
    final username = _nonEmpty(member['username']);
    final role = _nonEmpty(member['role']);
    if (username == null ||
        (role != 'admin' && role != 'writer' && role != 'reader')) {
      continue;
    }
    result[peerId] = <String, Object?>{
      'username': username,
      'role': role,
      'deviceIds': _stringList(member['deviceIds']),
      'transportPeerIds': _stringList(member['transportPeerIds']),
    };
  }
  return result;
}

Map<String, Object?>? _sanitizeGroup(
  Object? value, {
  required Map<String, Object?>? Function(Object?) sanitizeAuthority,
}) {
  if (value is! Map) return null;
  final name = _nonEmpty(value['name']);
  final type = _nonEmpty(value['type']);
  if (name == null || (type != 'chat' && type != 'announcement')) return null;
  final keyEpoch = value['keyEpoch'];
  final authorityRaw = value['senderAuthority'];
  final authority = authorityRaw == null
      ? null
      : sanitizeAuthority(authorityRaw);
  return <String, Object?>{
    'name': name,
    'type': type,
    'muted': value['muted'] == true,
    'archived': value['archived'] == true,
    'dissolved': value['dissolved'] == true,
    if (keyEpoch is int && keyEpoch >= 0) 'keyEpoch': keyEpoch,
    'members': _copyMembers(value['members']),
    'senderAuthority': ?authority,
  };
}
