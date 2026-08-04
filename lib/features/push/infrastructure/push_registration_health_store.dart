import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/push/domain/push_registration_health.dart';

const pushRegistrationHealthSecureStorageKey = 'push_registration_health_v1';
const pushRegistrationHealthSchemaVersion = 1;

abstract interface class PushRegistrationHealthStorage {
  Future<PushRegistrationHealthRecord?> read();
  Future<void> write(PushRegistrationHealthRecord record);
  Future<void> clear();
}

typedef PushRegistrationHealthBinding = ({
  String accountPeerId,
  String installationId,
});

typedef PushRegistrationHealthBindingResolver =
    Future<PushRegistrationHealthBinding> Function();

/// A health store whose operations can be pinned to one immutable account and
/// installation authority.
///
/// Registration attempts may outlive an in-process account cutover. Calling
/// the unscoped [write] at completion time would resolve the *new* account and
/// could persist the old attempt's outcome under that account. Coordinators use
/// these bound operations so the authority captured at attempt start remains
/// the authority for every read, write, and clear in that attempt.
abstract interface class BindingScopedPushRegistrationHealthStorage
    implements PushRegistrationHealthStorage {
  Future<PushRegistrationHealthBinding> resolveBinding();

  Future<PushRegistrationHealthRecord?> readForBinding(
    PushRegistrationHealthBinding binding,
  );

  Future<void> writeForBinding(
    PushRegistrationHealthBinding binding,
    PushRegistrationHealthRecord record,
  );

  Future<void> clearForBinding(PushRegistrationHealthBinding binding);
}

/// Resolves the active account and installation at operation time.
///
/// Production creates the coordinator before a first-run identity exists, while
/// registration itself starts only after the transport node is live. Resolving
/// lazily preserves that startup order and also makes account cutover fail
/// closed through the concrete store's binding mismatch handling.
final class ResolvingPushRegistrationHealthStore
    implements BindingScopedPushRegistrationHealthStorage {
  const ResolvingPushRegistrationHealthStore({
    required SecureKeyStore secureKeyStore,
    required PushRegistrationHealthBindingResolver resolveBinding,
  }) : _secureKeyStore = secureKeyStore,
       _resolveBinding = resolveBinding;

  final SecureKeyStore _secureKeyStore;
  final PushRegistrationHealthBindingResolver _resolveBinding;

  PushRegistrationHealthStore _storeForBinding(
    PushRegistrationHealthBinding binding,
  ) {
    return PushRegistrationHealthStore(
      secureKeyStore: _secureKeyStore,
      accountPeerId: binding.accountPeerId,
      installationId: binding.installationId,
    );
  }

  @override
  Future<PushRegistrationHealthBinding> resolveBinding() async {
    final binding = await _resolveBinding();
    final accountPeerId = binding.accountPeerId.trim();
    final installationId = binding.installationId.trim();
    if (accountPeerId.isEmpty || installationId.isEmpty) {
      throw StateError('Push registration health binding is unavailable.');
    }
    return (accountPeerId: accountPeerId, installationId: installationId);
  }

  @override
  Future<PushRegistrationHealthRecord?> read() async {
    return readForBinding(await resolveBinding());
  }

  @override
  Future<void> write(PushRegistrationHealthRecord record) async {
    await writeForBinding(await resolveBinding(), record);
  }

  @override
  Future<void> clear() async {
    await clearForBinding(await resolveBinding());
  }

  @override
  Future<PushRegistrationHealthRecord?> readForBinding(
    PushRegistrationHealthBinding binding,
  ) {
    return _storeForBinding(binding).read();
  }

  @override
  Future<void> writeForBinding(
    PushRegistrationHealthBinding binding,
    PushRegistrationHealthRecord record,
  ) {
    return _storeForBinding(binding).write(record);
  }

  @override
  Future<void> clearForBinding(PushRegistrationHealthBinding binding) {
    return _storeForBinding(binding).clear();
  }
}

final class PushRegistrationHealthStore
    implements PushRegistrationHealthStorage {
  PushRegistrationHealthStore({
    required SecureKeyStore secureKeyStore,
    required String accountPeerId,
    required String installationId,
  }) : _secureKeyStore = secureKeyStore,
       _accountBindingSha256 = _bindingDigest(
         accountPeerId,
         fieldName: 'accountPeerId',
       ),
       _installationBindingSha256 = _bindingDigest(
         installationId,
         fieldName: 'installationId',
       );

  static const _exactKeys = <String>{
    'schemaVersion',
    'accountBindingSha256',
    'installationBindingSha256',
    'phase',
    'reason',
    'consecutiveFailures',
    'firstFailureAtMs',
    'lastAttemptAtMs',
    'lastSuccessAtMs',
  };

  final SecureKeyStore _secureKeyStore;
  final String _accountBindingSha256;
  final String _installationBindingSha256;

  @override
  Future<PushRegistrationHealthRecord?> read() async {
    String? raw;
    try {
      raw = await _secureKeyStore.read(pushRegistrationHealthSecureStorageKey);
    } catch (_) {
      return null;
    }
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('not an object');
      final json = decoded.cast<String, Object?>();
      if (json.keys.toSet().length != _exactKeys.length ||
          !json.keys.toSet().containsAll(_exactKeys)) {
        throw const FormatException('unexpected health record keys');
      }
      if (json['schemaVersion'] != pushRegistrationHealthSchemaVersion ||
          json['accountBindingSha256'] != _accountBindingSha256 ||
          json['installationBindingSha256'] != _installationBindingSha256) {
        throw const FormatException('health record binding mismatch');
      }

      final phase = _enumByName(
        PushRegistrationHealthPhase.values,
        json['phase'],
      );
      final reason = _enumByName(
        PushRegistrationHealthReason.values,
        json['reason'],
      );
      final failures = _strictNonNegativeInt(json['consecutiveFailures']);
      final firstFailureAt = _optionalUtcDate(json['firstFailureAtMs']);
      final lastAttemptAt = _requiredUtcDate(json['lastAttemptAtMs']);
      final lastSuccessAt = _optionalUtcDate(json['lastSuccessAtMs']);
      _validateState(
        phase: phase,
        reason: reason,
        failures: failures,
        firstFailureAt: firstFailureAt,
        lastAttemptAt: lastAttemptAt,
        lastSuccessAt: lastSuccessAt,
      );
      return PushRegistrationHealthRecord(
        phase: phase,
        reason: reason,
        consecutiveFailures: failures,
        firstFailureAt: firstFailureAt,
        lastAttemptAt: lastAttemptAt,
        lastSuccessAt: lastSuccessAt,
      );
    } catch (_) {
      await _clearBestEffort();
      return null;
    }
  }

  @override
  Future<void> write(PushRegistrationHealthRecord record) {
    final json = <String, Object?>{
      'schemaVersion': pushRegistrationHealthSchemaVersion,
      'accountBindingSha256': _accountBindingSha256,
      'installationBindingSha256': _installationBindingSha256,
      'phase': record.phase.name,
      'reason': record.reason.name,
      'consecutiveFailures': record.consecutiveFailures,
      'firstFailureAtMs': record.firstFailureAt?.millisecondsSinceEpoch,
      'lastAttemptAtMs': record.lastAttemptAt.millisecondsSinceEpoch,
      'lastSuccessAtMs': record.lastSuccessAt?.millisecondsSinceEpoch,
    };
    return _secureKeyStore.write(
      pushRegistrationHealthSecureStorageKey,
      jsonEncode(json),
    );
  }

  @override
  Future<void> clear() =>
      _secureKeyStore.delete(pushRegistrationHealthSecureStorageKey);

  Future<void> _clearBestEffort() async {
    try {
      await clear();
    } catch (_) {}
  }
}

String _bindingDigest(String raw, {required String fieldName}) {
  final normalized = raw.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(raw, fieldName, 'must not be empty');
  }
  return sha256.convert(utf8.encode(normalized)).toString();
}

T _enumByName<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) throw const FormatException('invalid enum');
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw const FormatException('unknown enum');
}

int _strictNonNegativeInt(Object? raw) {
  if (raw is! int || raw < 0 || raw > 1000000) {
    throw const FormatException('invalid counter');
  }
  return raw;
}

DateTime _requiredUtcDate(Object? raw) {
  final value = _optionalUtcDate(raw);
  if (value == null) throw const FormatException('missing timestamp');
  return value;
}

DateTime? _optionalUtcDate(Object? raw) {
  if (raw == null) return null;
  if (raw is! int || raw < 0) {
    throw const FormatException('invalid timestamp');
  }
  return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
}

void _validateState({
  required PushRegistrationHealthPhase phase,
  required PushRegistrationHealthReason reason,
  required int failures,
  required DateTime? firstFailureAt,
  required DateTime lastAttemptAt,
  required DateTime? lastSuccessAt,
}) {
  if (firstFailureAt != null && firstFailureAt.isAfter(lastAttemptAt)) {
    throw const FormatException('failure starts after attempt');
  }
  if (lastSuccessAt != null && lastSuccessAt.isAfter(lastAttemptAt)) {
    throw const FormatException('success follows attempt');
  }
  switch (phase) {
    case PushRegistrationHealthPhase.healthy:
      if (reason != PushRegistrationHealthReason.none ||
          failures != 0 ||
          firstFailureAt != null ||
          lastSuccessAt == null) {
        throw const FormatException('invalid healthy state');
      }
    case PushRegistrationHealthPhase.permissionDenied:
      if (reason != PushRegistrationHealthReason.permissionDenied ||
          failures != 0 ||
          firstFailureAt == null) {
        throw const FormatException('invalid permission state');
      }
    case PushRegistrationHealthPhase.retrying:
      if (!reason.isTransient || failures <= 0 || firstFailureAt == null) {
        throw const FormatException('invalid retry state');
      }
    case PushRegistrationHealthPhase.checking:
      final validPrior = switch (reason) {
        PushRegistrationHealthReason.none =>
          failures == 0 && firstFailureAt == null,
        PushRegistrationHealthReason.permissionDenied =>
          failures == 0 && firstFailureAt != null,
        _ => reason.isTransient && failures > 0 && firstFailureAt != null,
      };
      if (!validPrior) {
        throw const FormatException('invalid checking state');
      }
  }
}
