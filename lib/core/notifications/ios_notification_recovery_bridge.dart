import 'package:flutter/services.dart';

import '../database/helpers/canonical_notification_badge_state_db_helpers.dart';

const iosNotificationRecoveryChannelName = 'mknoon/ios_notification_recovery';

/// Native token captured before Dart reads canonical SQLite state.
final class IosNotificationReconciliationToken {
  const IosNotificationReconciliationToken({
    required this.token,
    required this.watermark,
  });

  final String token;
  final int watermark;
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

  Future<void> retireConversation({
    required String accountPeerId,
    required CanonicalNotificationLane lane,
    required String conversationId,
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
      keys: const {'token', 'watermark'},
    );
    final token = map['token'];
    final watermark = map['watermark'];
    if (token is! String || token.trim().isEmpty) {
      throw const FormatException(
        'beginReconciliation token must be a non-empty string',
      );
    }
    if (watermark is! int || watermark < 0) {
      throw const FormatException(
        'beginReconciliation watermark must be a non-negative integer',
      );
    }
    return IosNotificationReconciliationToken(
      token: token,
      watermark: watermark,
    );
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
        'token': _requiredId(begin.token),
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
  Future<void> clearAccount() async {
    final response = await _channel.invokeMethod<Object?>(
      'clearAccount',
      const <String, Object?>{},
    );
    _requireAcknowledgement(response, method: 'clearAccount');
  }
}

String _requiredId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, 'value', 'must not be empty');
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
