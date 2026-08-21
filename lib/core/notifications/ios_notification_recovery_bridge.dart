import 'dart:convert';

import 'package:flutter/services.dart';

import '../database/helpers/canonical_notification_badge_state_db_helpers.dart';

const iosNotificationRecoveryChannelName = 'mknoon/ios_notification_recovery';

const int _maxSignedInt64 = 9223372036854775807;
const Set<String> _mailboxAlertLeasePhases = <String>{
  'PREPARED',
  'PUBLISHING',
  'AUDIBLE_AMBIGUOUS',
};

/// Optional native ambiguity lease for one collapsed fixed mailbox wake.
final class IosMailboxAlertLease {
  const IosMailboxAlertLease({
    required this.token,
    required this.accountHash,
    required this.bindingHash,
    required this.requestIdentifier,
    required this.generation,
    required this.sequence,
    required this.phase,
  });

  final String token;
  final String accountHash;
  final String bindingHash;
  final String requestIdentifier;
  final int generation;
  final int sequence;
  final String phase;
}

/// Native token captured before Dart reads canonical SQLite state.
final class IosNotificationReconciliationToken {
  const IosNotificationReconciliationToken({
    required this.token,
    required this.watermark,
    this.mailboxAlertLease,
  });

  final String token;
  final int watermark;
  final IosMailboxAlertLease? mailboxAlertLease;
}

/// Narrow owner boundary for exact iOS remote-notification recovery.
///
/// Dart supplies raw canonical identities. It never reads or writes the native
/// ledger and never hashes identifiers independently.
abstract interface class IosNotificationRecoveryBridge {
  Future<IosNotificationReconciliationToken> beginReconciliation(
    String accountPeerId,
  );

  Future<void> commitReconciliation({
    required IosNotificationReconciliationToken begin,
    required String accountPeerId,
    required CanonicalNotificationBadgeState canonicalState,
    required bool canonicalStateComplete,
  });

  /// Consumes the exact lease captured by [beginReconciliation] only after the
  /// corresponding paged inbox generation reaches `hasMore == false`.
  Future<void> consumeMailboxAlertLease({
    required IosNotificationReconciliationToken begin,
    required IosMailboxAlertLease lease,
  });

  Future<void> retireConversation({
    required String accountPeerId,
    required CanonicalNotificationLane lane,
    required String conversationId,
  });

  /// Retires delivered cards for one exact group-invite identity only.
  Future<void> retireGroupInvite({
    required String groupId,
    required String inviteId,
  });

  /// Clears the native account owner through exact state-owned retirement.
  /// This is deliberately not a remove-all-notifications operation.
  Future<void> clearAccount();
}

/// Production MethodChannel adapter for [IosNotificationRecoveryBridge].
final class MethodChannelIosNotificationRecoveryBridge
    implements IosNotificationRecoveryBridge {
  MethodChannelIosNotificationRecoveryBridge({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel(iosNotificationRecoveryChannelName);

  final MethodChannel _channel;

  @override
  Future<IosNotificationReconciliationToken> beginReconciliation(
    String accountPeerId,
  ) async {
    final response = await _channel.invokeMethod<Object?>(
      'beginReconciliation',
      <String, Object?>{'accountPeerId': _requiredId(accountPeerId)},
    );
    final map = _exactMap(
      response,
      method: 'beginReconciliation',
      keys: const {'token', 'watermark', 'mailboxAlertLease'},
    );
    final token = map['token'];
    final watermark = map['watermark'];
    if (!_isBoundedPrintableString(token, maxUtf8Bytes: 128)) {
      throw const FormatException(
        'beginReconciliation token must be a non-empty string',
      );
    }
    if (watermark is! int || watermark < 0 || watermark > _maxSignedInt64) {
      throw const FormatException(
        'beginReconciliation watermark must be a non-negative integer',
      );
    }
    final lease = _decodeMailboxAlertLease(map['mailboxAlertLease']);
    return IosNotificationReconciliationToken(
      token: token as String,
      watermark: watermark,
      mailboxAlertLease: lease,
    );
  }

  @override
  Future<void> consumeMailboxAlertLease({
    required IosNotificationReconciliationToken begin,
    required IosMailboxAlertLease lease,
  }) async {
    final response = await _channel
        .invokeMethod<Object?>('consumeMailboxAlertLease', <String, Object?>{
          'token': _requiredOpaqueToken(begin.token),
          'watermark': begin.watermark,
          'generation': lease.generation,
          'sequence': lease.sequence,
        });
    _requireAcknowledgement(response, method: 'consumeMailboxAlertLease');
  }

  @override
  Future<void> commitReconciliation({
    required IosNotificationReconciliationToken begin,
    required String accountPeerId,
    required CanonicalNotificationBadgeState canonicalState,
    required bool canonicalStateComplete,
  }) async {
    final response = await _channel.invokeMethod<Object?>(
      'commitReconciliation',
      <String, Object?>{
        'token': _requiredOpaqueToken(begin.token),
        'watermark': begin.watermark,
        'accountPeerId': _requiredId(accountPeerId),
        'canonicalStateComplete': canonicalStateComplete,
        'canonicalBadgeCount': canonicalState.unreadCount,
        'identities': canonicalState.identities
            .map(
              (identity) => <String, Object?>{
                'lane': identity.lane.name,
                'conversationId': identity.conversationId,
                'eventId': identity.eventId,
              },
            )
            .toList(growable: false),
      },
    );
    _requireAcknowledgement(response, method: 'commitReconciliation');
  }

  @override
  Future<void> retireConversation({
    required String accountPeerId,
    required CanonicalNotificationLane lane,
    required String conversationId,
  }) async {
    final response = await _channel
        .invokeMethod<Object?>('retireConversation', <String, Object?>{
          'accountPeerId': _requiredId(accountPeerId),
          'lane': lane.name,
          'conversationId': _requiredId(conversationId),
        });
    _requireAcknowledgement(response, method: 'retireConversation');
  }

  @override
  Future<void> retireGroupInvite({
    required String groupId,
    required String inviteId,
  }) async {
    final response = await _channel
        .invokeMethod<Object?>('retireGroupInvite', <String, Object?>{
          'groupId': _requiredRetirementId(groupId, argumentName: 'groupId'),
          'inviteId': _requiredRetirementId(inviteId, argumentName: 'inviteId'),
        });
    _requireAcknowledgement(response, method: 'retireGroupInvite');
  }

  @override
  Future<void> clearAccount() async {
    final response = await _channel.invokeMethod<Object?>(
      'clearAccount',
      const <String, Object?>{},
    );
    _requireAcknowledgement(response, method: 'clearAccount');
  }
}

IosMailboxAlertLease? _decodeMailboxAlertLease(Object? value) {
  if (value == null) return null;
  final map = _exactMap(
    value,
    method: 'beginReconciliation.mailboxAlertLease',
    keys: const {
      'token',
      'accountHash',
      'bindingHash',
      'requestIdentifier',
      'generation',
      'sequence',
      'phase',
    },
  );
  final token = map['token'];
  final accountHash = map['accountHash'];
  final bindingHash = map['bindingHash'];
  final requestIdentifier = map['requestIdentifier'];
  final generation = map['generation'];
  final sequence = map['sequence'];
  final phase = map['phase'];
  if (!_isBoundedPrintableString(token, maxUtf8Bytes: 128) ||
      accountHash is! String ||
      !_lowercaseSha256.hasMatch(accountHash) ||
      bindingHash is! String ||
      !_lowercaseSha256.hasMatch(bindingHash) ||
      !_isBoundedPrintableString(requestIdentifier, maxUtf8Bytes: 512) ||
      generation is! int ||
      generation <= 0 ||
      generation > _maxSignedInt64 ||
      sequence is! int ||
      sequence <= 0 ||
      sequence > _maxSignedInt64 ||
      phase is! String ||
      !_mailboxAlertLeasePhases.contains(phase)) {
    throw const FormatException('invalid mailbox alert lease');
  }
  return IosMailboxAlertLease(
    token: token as String,
    accountHash: accountHash,
    bindingHash: bindingHash,
    requestIdentifier: requestIdentifier as String,
    generation: generation,
    sequence: sequence,
    phase: phase,
  );
}

final RegExp _lowercaseSha256 = RegExp(r'^[0-9a-f]{64}$');

bool _isBoundedPrintableString(Object? value, {required int maxUtf8Bytes}) {
  if (value is! String ||
      value.isEmpty ||
      value != value.trim() ||
      utf8.encode(value).length > maxUtf8Bytes) {
    return false;
  }
  return !value.runes.any(
    (rune) => rune < 0x20 || (rune >= 0x7f && rune <= 0x9f),
  );
}

String _requiredOpaqueToken(String value) {
  if (!_isBoundedPrintableString(value, maxUtf8Bytes: 128)) {
    throw ArgumentError.value(value, 'token', 'invalid opaque token');
  }
  return value;
}

String _requiredId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, 'value', 'must not be empty');
  }
  return normalized;
}

String _requiredRetirementId(String value, {required String argumentName}) {
  final normalized = value.trim();
  if (!_isBoundedPrintableString(normalized, maxUtf8Bytes: 512)) {
    throw ArgumentError.value(value, argumentName, 'invalid identifier');
  }
  return normalized;
}

Map<String, Object?> _exactMap(
  Object? value, {
  required String method,
  required Set<String> keys,
}) {
  if (value is! Map) {
    throw FormatException('$method returned a non-map response');
  }
  final normalized = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String || normalized.containsKey(key)) {
      throw FormatException('$method returned invalid map keys');
    }
    normalized[key] = entry.value;
  }
  if (normalized.keys.toSet().length != keys.length ||
      !normalized.keys.toSet().containsAll(keys)) {
    throw FormatException('$method returned an unexpected response shape');
  }
  return normalized;
}

void _requireAcknowledgement(Object? value, {required String method}) {
  final map = _exactMap(value, method: method, keys: const {'ok'});
  if (map['ok'] != true) {
    throw FormatException('$method did not acknowledge the operation');
  }
}
