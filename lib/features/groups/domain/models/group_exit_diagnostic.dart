import 'dart:convert';

import 'package:crypto/crypto.dart';

enum GroupExitDiagnosticKind {
  voluntary('voluntary'),
  selfRemovedShell('self_removed_shell'),
  dissolvedShell('dissolved_shell');

  const GroupExitDiagnosticKind(this.databaseValue);

  final String databaseValue;

  static GroupExitDiagnosticKind fromDatabase(String value) =>
      _enumFromDatabase(values, value, 'exit kind');
}

enum GroupExitDiagnosticSeverity {
  failure('failure'),
  warning('warning');

  const GroupExitDiagnosticSeverity(this.databaseValue);

  final String databaseValue;

  static GroupExitDiagnosticSeverity fromDatabase(String value) =>
      _enumFromDatabase(values, value, 'severity');
}

enum GroupExitDiagnosticPhase {
  authority('authority'),
  roleSync('role_sync'),
  notice('notice'),
  native('native'),
  cleanup('cleanup'),
  delivery('delivery'),
  rotation('rotation'),
  localDelete('local_delete');

  const GroupExitDiagnosticPhase(this.databaseValue);

  final String databaseValue;

  static GroupExitDiagnosticPhase fromDatabase(String value) =>
      _enumFromDatabase(values, value, 'phase');
}

enum GroupExitDiagnosticPublicCode {
  ex01('EX01'),
  ex02('EX02'),
  ex03('EX03'),
  ex04('EX04'),
  ex05('EX05'),
  ex06('EX06'),
  ex07('EX07'),
  ex08('EX08'),
  ex09('EX09'),
  ex10('EX10'),
  ex99('EX99');

  const GroupExitDiagnosticPublicCode(this.databaseValue);

  final String databaseValue;

  /// Stable ASCII support code used by presentation. It is not localized.
  String get code => databaseValue;

  /// Compatibility alias for callers that present the stable code directly.
  String get value => databaseValue;

  static GroupExitDiagnosticPublicCode fromDatabase(String value) =>
      _enumFromDatabase(values, value, 'public code');
}

enum GroupExitDiagnosticReason {
  authorityUnavailable('authority_unavailable'),
  roleSyncFailed('role_sync_failed'),
  noticePrepareFailed('notice_prepare_failed'),
  nodeNotInitialized('node_not_initialized'),
  nativeRejected('native_rejected'),
  nativeUncertain('native_uncertain'),
  cleanupIncomplete('cleanup_incomplete'),
  noticeDeliveryDegraded('notice_delivery_degraded'),
  rotationDeferred('rotation_deferred'),
  terminalShellCleanup('terminal_shell_cleanup'),
  unexpected('unexpected');

  const GroupExitDiagnosticReason(this.databaseValue);

  final String databaseValue;

  static GroupExitDiagnosticReason fromDatabase(String value) =>
      _enumFromDatabase(values, value, 'reason');
}

/// A bounded release-safe group-exit fact.
///
/// [groupRef] and [intentRef] are opaque hashes. Raw group and intent ids are
/// accepted only by [GroupExitDiagnostic.create] and are never retained.
class GroupExitDiagnostic {
  GroupExitDiagnostic._({
    required this.id,
    required this.occurredAt,
    required this.groupRef,
    required this.intentRef,
    required this.kind,
    required this.severity,
    required this.phase,
    required this.publicCode,
    required this.reason,
  }) {
    _validate();
  }

  factory GroupExitDiagnostic.create({
    required DateTime occurredAt,
    required String groupId,
    String? intentId,
    required GroupExitDiagnosticKind kind,
    required GroupExitDiagnosticSeverity severity,
    required GroupExitDiagnosticPhase phase,
    required GroupExitDiagnosticPublicCode publicCode,
    required GroupExitDiagnosticReason reason,
  }) {
    return GroupExitDiagnostic._(
      id: null,
      occurredAt: canonicalGroupExitDiagnosticTime(occurredAt),
      groupRef: groupExitGroupRef(groupId),
      intentRef: intentId == null ? null : groupExitIntentRef(intentId),
      kind: kind,
      severity: severity,
      phase: phase,
      publicCode: publicCode,
      reason: reason,
    );
  }

  factory GroupExitDiagnostic.fromMap(Map<String, Object?> map) {
    final occurredAtValue = map['occurred_at'];
    if (occurredAtValue is! String ||
        !_canonicalOccurredAtPattern.hasMatch(occurredAtValue)) {
      throw const FormatException('Invalid group exit diagnostic occurred_at');
    }
    final parsedOccurredAt = DateTime.tryParse(occurredAtValue);
    if (parsedOccurredAt == null ||
        groupExitDiagnosticOccurredAtValue(parsedOccurredAt) !=
            occurredAtValue) {
      throw const FormatException('Invalid group exit diagnostic occurred_at');
    }

    try {
      final rawId = map['id'];
      return GroupExitDiagnostic._(
        id: rawId == null ? null : (rawId as num).toInt(),
        occurredAt: parsedOccurredAt,
        groupRef: map['group_ref'] as String,
        intentRef: map['intent_ref'] as String?,
        kind: GroupExitDiagnosticKind.fromDatabase(map['exit_kind'] as String),
        severity: GroupExitDiagnosticSeverity.fromDatabase(
          map['severity'] as String,
        ),
        phase: GroupExitDiagnosticPhase.fromDatabase(map['phase'] as String),
        publicCode: GroupExitDiagnosticPublicCode.fromDatabase(
          map['public_code'] as String,
        ),
        reason: GroupExitDiagnosticReason.fromDatabase(
          map['reason_code'] as String,
        ),
      );
    } on TypeError {
      throw const FormatException('Invalid group exit diagnostic row');
    } on ArgumentError {
      throw const FormatException('Invalid group exit diagnostic row');
    }
  }

  final int? id;
  final DateTime occurredAt;
  final String groupRef;
  final String? intentRef;
  final GroupExitDiagnosticKind kind;
  final GroupExitDiagnosticSeverity severity;
  final GroupExitDiagnosticPhase phase;
  final GroupExitDiagnosticPublicCode publicCode;
  final GroupExitDiagnosticReason reason;

  Map<String, Object?> toMap({bool includeId = true}) => <String, Object?>{
    if (includeId && id != null) 'id': id,
    'occurred_at': groupExitDiagnosticOccurredAtValue(occurredAt),
    'group_ref': groupRef,
    'intent_ref': intentRef,
    'exit_kind': kind.databaseValue,
    'severity': severity.databaseValue,
    'phase': phase.databaseValue,
    'public_code': publicCode.databaseValue,
    'reason_code': reason.databaseValue,
  };

  void _validate() {
    if (!_lowerHex12.hasMatch(groupRef)) {
      throw ArgumentError.value(groupRef, 'groupRef', 'must be 12 lower hex');
    }
    if (intentRef != null && !_lowerHex24.hasMatch(intentRef!)) {
      throw ArgumentError.value(
        intentRef,
        'intentRef',
        'must be null or 24 lower hex',
      );
    }
    final occurredAtValue = groupExitDiagnosticOccurredAtValue(occurredAt);
    if (!_canonicalOccurredAtPattern.hasMatch(occurredAtValue)) {
      throw ArgumentError.value(
        occurredAt,
        'occurredAt',
        'must have a four-digit UTC year',
      );
    }
    if (!isValidGroupExitDiagnosticTuple(
      kind: kind,
      severity: severity,
      phase: phase,
      publicCode: publicCode,
      reason: reason,
      hasIntentRef: intentRef != null,
    )) {
      throw ArgumentError(
        'Invalid group exit diagnostic code/reason/phase/severity/kind tuple',
      );
    }
  }
}

String groupExitGroupRef(String groupId) => _truncatedSha256(groupId, 12);

String groupExitIntentRef(String intentId) => _truncatedSha256(intentId, 24);

DateTime canonicalGroupExitDiagnosticTime(DateTime value) =>
    DateTime.fromMillisecondsSinceEpoch(
      value.toUtc().millisecondsSinceEpoch,
      isUtc: true,
    );

String groupExitDiagnosticOccurredAtValue(DateTime value) =>
    canonicalGroupExitDiagnosticTime(value).toIso8601String();

bool isValidGroupExitDiagnosticTuple({
  required GroupExitDiagnosticKind kind,
  required GroupExitDiagnosticSeverity severity,
  required GroupExitDiagnosticPhase phase,
  required GroupExitDiagnosticPublicCode publicCode,
  required GroupExitDiagnosticReason reason,
  required bool hasIntentRef,
}) {
  final isVoluntary = kind == GroupExitDiagnosticKind.voluntary;
  final isTerminal =
      kind == GroupExitDiagnosticKind.selfRemovedShell ||
      kind == GroupExitDiagnosticKind.dissolvedShell;

  switch (publicCode) {
    case GroupExitDiagnosticPublicCode.ex01:
      return severity == GroupExitDiagnosticSeverity.failure &&
          phase == GroupExitDiagnosticPhase.authority &&
          reason == GroupExitDiagnosticReason.authorityUnavailable &&
          ((isVoluntary) || (isTerminal && !hasIntentRef));
    case GroupExitDiagnosticPublicCode.ex02:
      return isVoluntary &&
          severity == GroupExitDiagnosticSeverity.failure &&
          phase == GroupExitDiagnosticPhase.roleSync &&
          reason == GroupExitDiagnosticReason.roleSyncFailed;
    case GroupExitDiagnosticPublicCode.ex03:
      return isVoluntary &&
          hasIntentRef &&
          severity == GroupExitDiagnosticSeverity.failure &&
          phase == GroupExitDiagnosticPhase.notice &&
          reason == GroupExitDiagnosticReason.noticePrepareFailed;
    case GroupExitDiagnosticPublicCode.ex04:
      return isVoluntary &&
          hasIntentRef &&
          severity == GroupExitDiagnosticSeverity.failure &&
          phase == GroupExitDiagnosticPhase.native &&
          reason == GroupExitDiagnosticReason.nodeNotInitialized;
    case GroupExitDiagnosticPublicCode.ex05:
      return isVoluntary &&
          hasIntentRef &&
          severity == GroupExitDiagnosticSeverity.failure &&
          phase == GroupExitDiagnosticPhase.native &&
          reason == GroupExitDiagnosticReason.nativeRejected;
    case GroupExitDiagnosticPublicCode.ex06:
      return isVoluntary &&
          hasIntentRef &&
          severity == GroupExitDiagnosticSeverity.failure &&
          phase == GroupExitDiagnosticPhase.native &&
          reason == GroupExitDiagnosticReason.nativeUncertain;
    case GroupExitDiagnosticPublicCode.ex07:
      return isVoluntary &&
          hasIntentRef &&
          severity == GroupExitDiagnosticSeverity.warning &&
          phase == GroupExitDiagnosticPhase.cleanup &&
          reason == GroupExitDiagnosticReason.cleanupIncomplete;
    case GroupExitDiagnosticPublicCode.ex08:
      return isVoluntary &&
          hasIntentRef &&
          severity == GroupExitDiagnosticSeverity.warning &&
          phase == GroupExitDiagnosticPhase.delivery &&
          reason == GroupExitDiagnosticReason.noticeDeliveryDegraded;
    case GroupExitDiagnosticPublicCode.ex09:
      return isVoluntary &&
          hasIntentRef &&
          severity == GroupExitDiagnosticSeverity.warning &&
          phase == GroupExitDiagnosticPhase.rotation &&
          reason == GroupExitDiagnosticReason.rotationDeferred;
    case GroupExitDiagnosticPublicCode.ex10:
      return isTerminal &&
          !hasIntentRef &&
          severity == GroupExitDiagnosticSeverity.failure &&
          phase == GroupExitDiagnosticPhase.localDelete &&
          reason == GroupExitDiagnosticReason.terminalShellCleanup;
    case GroupExitDiagnosticPublicCode.ex99:
      return isVoluntary &&
          hasIntentRef &&
          severity == GroupExitDiagnosticSeverity.failure &&
          phase != GroupExitDiagnosticPhase.localDelete &&
          reason == GroupExitDiagnosticReason.unexpected;
  }
}

String _truncatedSha256(String value, int length) =>
    sha256.convert(utf8.encode(value)).toString().substring(0, length);

T _enumFromDatabase<T>(Iterable<T> values, String value, String label) {
  for (final enumValue in values) {
    final databaseValue = (enumValue as dynamic).databaseValue as String;
    if (databaseValue == value) return enumValue;
  }
  throw FormatException('Unsupported group exit diagnostic $label: $value');
}

final RegExp _lowerHex12 = RegExp(r'^[0-9a-f]{12}$');
final RegExp _lowerHex24 = RegExp(r'^[0-9a-f]{24}$');
final RegExp _canonicalOccurredAtPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
