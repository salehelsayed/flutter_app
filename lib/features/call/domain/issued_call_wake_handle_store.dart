import 'dart:collection';

import 'call_wake_handle_grant.dart';

/// Durable issuer-side state for one contact account.
///
/// A revoke-pending record is retained as a tombstone until the relay confirms
/// that the recorded grant generation can no longer wake this account.
final class CallIssuedWakeHandleRecord {
  factory CallIssuedWakeHandleRecord({
    required String contactAccountPeerId,
    required CallWakeHandleGrant grant,
    required Iterable<String> authorizedSenderDevicePeerIds,
    bool revokePending = false,
    bool distributionPending = true,
    int? distributionReceiptVersion,
  }) {
    if (!CallWakeHandleGrant.hasValidPeerIdGrammar(contactAccountPeerId)) {
      throw ArgumentError('invalid contact account peer id');
    }
    final devices = SplayTreeSet<String>.from(authorizedSenderDevicePeerIds);
    if (devices.any(
      (value) => !CallWakeHandleGrant.hasValidPeerIdGrammar(value),
    )) {
      throw ArgumentError('invalid authorized sender device peer id');
    }
    if (distributionReceiptVersion != null &&
        (distributionReceiptVersion <= 0 ||
            distributionReceiptVersion > CallWakeHandleGrant.maxSafeInteger ||
            revokePending ||
            distributionPending)) {
      throw ArgumentError('invalid distribution receipt proof');
    }
    return CallIssuedWakeHandleRecord._(
      contactAccountPeerId: contactAccountPeerId,
      grant: grant,
      authorizedSenderDevicePeerIds: Set<String>.unmodifiable(devices),
      revokePending: revokePending,
      distributionPending: distributionPending,
      distributionReceiptVersion: distributionReceiptVersion,
    );
  }

  const CallIssuedWakeHandleRecord._({
    required this.contactAccountPeerId,
    required this.grant,
    required this.authorizedSenderDevicePeerIds,
    required this.revokePending,
    required this.distributionPending,
    required this.distributionReceiptVersion,
  });

  factory CallIssuedWakeHandleRecord.fromCanonicalMap(Object? value) {
    try {
      if (value is! Map) throw const FormatException();
      final map = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String || map.containsKey(entry.key)) {
          throw const FormatException();
        }
        map[entry.key! as String] = entry.value;
      }
      final keys = map.keys.toSet();
      if (keys.difference(_canonicalKeys).isNotEmpty ||
          _requiredCanonicalKeys.difference(keys).isNotEmpty ||
          map['contactAccountPeerId'] is! String ||
          map['authorizedSenderDevicePeerIds'] is! List ||
          map['revokePending'] is! bool ||
          map['distributionPending'] is! bool ||
          (map.containsKey('distributionReceiptVersion') &&
              map['distributionReceiptVersion'] is! int)) {
        throw const FormatException();
      }
      final rawDevices = map['authorizedSenderDevicePeerIds']! as List;
      if (rawDevices.any((value) => value is! String) ||
          rawDevices.toSet().length != rawDevices.length) {
        throw const FormatException();
      }
      return CallIssuedWakeHandleRecord(
        contactAccountPeerId: map['contactAccountPeerId']! as String,
        grant: CallWakeHandleGrant.fromCanonicalMap(map['grant']),
        authorizedSenderDevicePeerIds: rawDevices.cast<String>(),
        revokePending: map['revokePending']! as bool,
        distributionPending: map['distributionPending']! as bool,
        distributionReceiptVersion: map['distributionReceiptVersion'] as int?,
      );
    } on FormatException {
      throw const FormatException('invalid issued call wake handle record');
    } on ArgumentError {
      throw const FormatException('invalid issued call wake handle record');
    }
  }

  final String contactAccountPeerId;
  final CallWakeHandleGrant grant;
  final Set<String> authorizedSenderDevicePeerIds;
  final bool revokePending;
  final bool distributionPending;
  final int? distributionReceiptVersion;

  static const int currentDistributionReceiptVersion = 1;

  /// True only when this exact grant generation received the currently
  /// understood receiver-commit proof. Legacy records intentionally return
  /// false so process-start repair can redistribute them once.
  bool get hasCurrentDistributionReceipt =>
      distributionReceiptVersion == currentDistributionReceiptVersion;

  Map<String, Object> toCanonicalMap() => Map<String, Object>.unmodifiable(
    SplayTreeMap<String, Object>.from(<String, Object>{
      'contactAccountPeerId': contactAccountPeerId,
      'grant': grant.toCanonicalMap(),
      'authorizedSenderDevicePeerIds': authorizedSenderDevicePeerIds.toList(
        growable: false,
      ),
      'revokePending': revokePending,
      'distributionPending': distributionPending,
      'distributionReceiptVersion': ?distributionReceiptVersion,
    }),
  );

  CallIssuedWakeHandleRecord copyWith({
    String? contactAccountPeerId,
    CallWakeHandleGrant? grant,
    Iterable<String>? authorizedSenderDevicePeerIds,
    bool? revokePending,
    bool? distributionPending,
    int? distributionReceiptVersion,
  }) {
    final nextRevokePending = revokePending ?? this.revokePending;
    final nextDistributionPending =
        distributionPending ?? this.distributionPending;
    final nextContactAccountPeerId =
        contactAccountPeerId ?? this.contactAccountPeerId;
    final nextGrant = grant ?? this.grant;
    final proofBindingChanged =
        nextContactAccountPeerId != this.contactAccountPeerId ||
        nextGrant != this.grant;
    return CallIssuedWakeHandleRecord(
      contactAccountPeerId: nextContactAccountPeerId,
      grant: nextGrant,
      authorizedSenderDevicePeerIds:
          authorizedSenderDevicePeerIds ?? this.authorizedSenderDevicePeerIds,
      revokePending: nextRevokePending,
      distributionPending: nextDistributionPending,
      distributionReceiptVersion:
          nextRevokePending || nextDistributionPending || proofBindingChanged
          ? null
          : distributionReceiptVersion ?? this.distributionReceiptVersion,
    );
  }

  static const Set<String> _canonicalKeys = <String>{
    'contactAccountPeerId',
    'grant',
    'authorizedSenderDevicePeerIds',
    'revokePending',
    'distributionPending',
    'distributionReceiptVersion',
  };

  static const Set<String> _requiredCanonicalKeys = <String>{
    'contactAccountPeerId',
    'grant',
    'authorizedSenderDevicePeerIds',
    'revokePending',
    'distributionPending',
  };
}

abstract interface class IssuedCallWakeHandleStore {
  Future<List<CallIssuedWakeHandleRecord>> readAll();

  Future<CallIssuedWakeHandleRecord?> readForContact(
    String contactAccountPeerId,
  );

  Future<void> write(CallIssuedWakeHandleRecord record);

  Future<void> removeForContact(String contactAccountPeerId);

  Future<void> clear();
}
