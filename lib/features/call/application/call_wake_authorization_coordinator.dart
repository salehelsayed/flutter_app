import 'dart:async';
import 'dart:collection';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../domain/call_signal.dart';
import '../domain/call_wake_handle_grant.dart';
import '../domain/issued_call_wake_handle_store.dart';
import '../infrastructure/call_authority_client.dart';
import '../infrastructure/secure_call_envelope_codec.dart';

typedef SetCallWakeHandle = Future<bool> Function(CallWakeHandleRecord record);
typedef RevokeCallWakeHandle =
    Future<bool> Function({required String authorizedSenderPeerId});
typedef PublishNativeCallWakeContact =
    Future<void> Function({
      required String wakeHandle,
      required String displayName,
    });
typedef RevokeNativeCallWakeContact = Future<void> Function(String wakeHandle);
typedef GenerateCallWakeHandle = String Function();

/// The complete current call-wake authority for one accepted, unblocked
/// contact. Archived contacts remain eligible and should still be supplied.
final class CallWakeEligibleContact {
  factory CallWakeEligibleContact({
    required String contactAccountPeerId,
    required String displayName,
    required Iterable<String> authorizedSenderDevicePeerIds,
  }) {
    if (!CallWakeHandleGrant.hasValidPeerIdGrammar(contactAccountPeerId) ||
        !_validDisplayName(displayName)) {
      throw ArgumentError('invalid call wake eligible contact');
    }
    final devices = SplayTreeSet<String>.from(authorizedSenderDevicePeerIds);
    if (devices.any(
      (device) => !CallWakeHandleGrant.hasValidPeerIdGrammar(device),
    )) {
      throw ArgumentError('invalid call wake sender device');
    }
    return CallWakeEligibleContact._(
      contactAccountPeerId: contactAccountPeerId,
      displayName: displayName,
      authorizedSenderDevicePeerIds: Set<String>.unmodifiable(devices),
    );
  }

  const CallWakeEligibleContact._({
    required this.contactAccountPeerId,
    required this.displayName,
    required this.authorizedSenderDevicePeerIds,
  });

  final String contactAccountPeerId;
  final String displayName;
  final Set<String> authorizedSenderDevicePeerIds;

  static bool _validDisplayName(String value) =>
      value.isNotEmpty &&
      value.trim() == value &&
      value.length <= 80 &&
      !value.runes.any(
        (scalar) => scalar <= 0x1f || (scalar >= 0x7f && scalar <= 0x9f),
      );

  @override
  String toString() =>
      'CallWakeEligibleContact(devices: '
      '${authorizedSenderDevicePeerIds.length})';
}

/// Serializes durable call-only wake grants and their native/relay authority.
///
/// A successful [reconcile] proves this order for every active contact:
/// durable grant -> native opaque-contact mapping -> relay sender grants.
/// Shutdown only drains the lane; valid durable grants are not revoked merely
/// because this process exits.
final class CallWakeAuthorizationCoordinator {
  CallWakeAuthorizationCoordinator({
    required IssuedCallWakeHandleStore store,
    required SetCallWakeHandle setWakeHandle,
    required RevokeCallWakeHandle revokeWakeHandle,
    required PublishNativeCallWakeContact publishNativeContact,
    required RevokeNativeCallWakeContact revokeNativeContact,
    required GenerateCallWakeHandle generateHandle,
    required int Function() nowMs,
    this.grantLifetime = const Duration(days: 1),
  }) : _store = store,
       _setWakeHandle = setWakeHandle,
       _revokeWakeHandle = revokeWakeHandle,
       _publishNativeContact = publishNativeContact,
       _revokeNativeContact = revokeNativeContact,
       _generateHandle = generateHandle,
       _nowMs = nowMs {
    if (grantLifetime < minimumRemainingGrantLifetime ||
        grantLifetime.inMilliseconds > CallWakeHandleGrant.maxSafeInteger) {
      throw ArgumentError('invalid call wake grant lifetime');
    }
  }

  static const int maxEligibleContacts = 512;
  static const int maxHandleGenerationAttempts = 8;

  /// A grant admitted for a new call must remain valid across the complete
  /// invite/answer window and the longest postconnect control envelope.
  static final Duration minimumRemainingGrantLifetime = Duration(
    milliseconds:
        CallSignal.maximumPreconnectLifetimeMs +
        SecureCallEnvelopeCodec.maximumPostconnectLifetime.inMilliseconds,
  );

  final IssuedCallWakeHandleStore _store;
  final SetCallWakeHandle _setWakeHandle;
  final RevokeCallWakeHandle _revokeWakeHandle;
  final PublishNativeCallWakeContact _publishNativeContact;
  final RevokeNativeCallWakeContact _revokeNativeContact;
  final GenerateCallWakeHandle _generateHandle;
  final int Function() _nowMs;
  final Duration grantLifetime;

  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _closed = false;

  Future<bool> reconcile({
    required Iterable<CallWakeEligibleContact> eligibleContacts,
    required String localRecipientDevicePeerId,
    required int localDeviceKeyEpoch,
  }) => _schedule<bool>(
    () => _reconcile(
      eligibleContacts: eligibleContacts,
      localRecipientDevicePeerId: localRecipientDevicePeerId,
      localDeviceKeyEpoch: localDeviceKeyEpoch,
    ),
    closedValue: false,
  );

  /// Returns an already-current grant or durably issues one for encrypted
  /// contact-request delivery. A stale binding is first tombstoned and returns
  /// null; [reconcile] must revoke/rotate it before a later retry can resolve.
  Future<CallWakeHandleGrant?> resolveOrIssueGrantForContact({
    required CallWakeEligibleContact contact,
    required String localRecipientDevicePeerId,
    required int localDeviceKeyEpoch,
  }) => _schedule<CallWakeHandleGrant?>(
    () => _resolveOrIssueGrantForContact(
      contact: contact,
      localRecipientDevicePeerId: localRecipientDevicePeerId,
      localDeviceKeyEpoch: localDeviceKeyEpoch,
    ),
    closedValue: null,
  );

  /// Clears distribution-pending and persists the current exact-receipt proof
  /// only when [grant] is still the exact current generation. Late callbacks
  /// from a revoked or rotated grant are ignored.
  Future<bool> markDistributed({
    required String contactAccountPeerId,
    required CallWakeHandleGrant grant,
  }) => _schedule<bool>(() async {
    if (!CallWakeHandleGrant.hasValidPeerIdGrammar(contactAccountPeerId)) {
      return false;
    }
    final current = await _store.readForContact(contactAccountPeerId);
    if (current == null || current.revokePending || current.grant != grant) {
      return false;
    }
    if (!current.distributionPending && current.hasCurrentDistributionReceipt) {
      return true;
    }
    await _store.write(
      current.copyWith(
        distributionPending: false,
        distributionReceiptVersion:
            CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
      ),
    );
    return true;
  }, closedValue: false);

  /// Re-arms each still-current grant once per owning process so an encrypted
  /// key-exchange retry can heal a peer that missed the prior delivery.
  /// Already-pending, receipt-proven, revoked, and expired records remain
  /// untouched. A legacy `distributionPending=false` record has no versioned
  /// proof, so it is re-armed once and becomes pending for subsequent calls.
  Future<bool> rearmCurrentGrantDistribution() => _schedule<bool>(() async {
    final nowMs = _nowMs();
    for (final record in await _store.readAll()) {
      if (record.revokePending ||
          record.distributionPending ||
          record.hasCurrentDistributionReceipt ||
          !record.grant.isValidAt(nowMs)) {
        continue;
      }
      await _store.write(record.copyWith(distributionPending: true));
    }
    return true;
  }, closedValue: false);

  Future<bool> _reconcile({
    required Iterable<CallWakeEligibleContact> eligibleContacts,
    required String localRecipientDevicePeerId,
    required int localDeviceKeyEpoch,
  }) async {
    final context = _validatedContext(
      localRecipientDevicePeerId,
      localDeviceKeyEpoch,
    );
    if (context == null) {
      _emitReconcileFailure('invalid_context');
      return false;
    }

    final contacts = eligibleContacts.toList(growable: false);
    if (contacts.length > maxEligibleContacts) {
      _emitReconcileFailure('contact_cap');
      return false;
    }
    final desiredByAccount = SplayTreeMap<String, CallWakeEligibleContact>();
    for (final contact in contacts) {
      if (desiredByAccount.containsKey(contact.contactAccountPeerId)) {
        _emitReconcileFailure('duplicate_contact');
        return false;
      }
      desiredByAccount[contact.contactAccountPeerId] = contact;
    }

    final loaded = await _store.readAll();
    final recordsByAccount = SplayTreeMap<String, CallIssuedWakeHandleRecord>();
    for (final record in loaded) {
      if (recordsByAccount.containsKey(record.contactAccountPeerId)) {
        _emitReconcileFailure('duplicate_record');
        return false;
      }
      recordsByAccount[record.contactAccountPeerId] = record;
    }
    final reservedHandles = loaded.map((record) => record.grant.handle).toSet();
    var allSucceeded = true;

    // A removed contact, stale local binding, grant without enough remaining
    // call lifetime, or an existing tombstone is revoked from durable state
    // before any replacement is made.
    for (final accountPeerId in recordsByAccount.keys.toList(growable: false)) {
      var record = recordsByAccount[accountPeerId]!;
      final desired = desiredByAccount[accountPeerId];
      final needsRotation =
          desired != null &&
          (record.grant.recipientDevicePeerId !=
                  context.localRecipientDevicePeerId ||
              record.grant.deviceKeyEpoch != context.localDeviceKeyEpoch ||
              !_hasMinimumRemainingLifetime(record.grant, context.nowMs));
      if (!record.revokePending && desired != null && !needsRotation) {
        continue;
      }

      if (!record.revokePending) {
        record = record.copyWith(revokePending: true);
        await _store.write(record);
        recordsByAccount[accountPeerId] = record;
      }
      final revocation = await _revokeRecord(record);
      record = revocation.record;
      recordsByAccount[accountPeerId] = record;
      if (!revocation.succeeded) {
        _emitReconcileFailure('record_revoke');
        allSucceeded = false;
        continue;
      }

      if (desired == null) {
        await _store.removeForContact(accountPeerId);
        recordsByAccount.remove(accountPeerId);
        continue;
      }

      final nextGeneration = _nextGeneration(prior: record.grant);
      if (nextGeneration == null) {
        _emitReconcileFailure('generation');
        allSucceeded = false;
        continue;
      }
      final replacement = _newRecord(
        contact: desired,
        localRecipientDevicePeerId: context.localRecipientDevicePeerId,
        localDeviceKeyEpoch: context.localDeviceKeyEpoch,
        generation: nextGeneration,
        nowMs: context.nowMs,
        reservedHandles: reservedHandles,
      );
      if (replacement == null) {
        _emitReconcileFailure('replacement_issue');
        allSucceeded = false;
        continue;
      }
      await _store.write(replacement);
      recordsByAccount[accountPeerId] = replacement;
      reservedHandles.add(replacement.grant.handle);
    }

    // Persist every missing grant before exposing it to either native code or
    // the relay. This also makes a crash between effects safely retryable.
    for (final entry in desiredByAccount.entries) {
      if (recordsByAccount.containsKey(entry.key)) continue;
      final issued = _newRecord(
        contact: entry.value,
        localRecipientDevicePeerId: context.localRecipientDevicePeerId,
        localDeviceKeyEpoch: context.localDeviceKeyEpoch,
        generation: _freshGeneration(context.nowMs),
        nowMs: context.nowMs,
        reservedHandles: reservedHandles,
      );
      if (issued == null) {
        _emitReconcileFailure('initial_issue');
        allSucceeded = false;
        continue;
      }
      await _store.write(issued);
      recordsByAccount[entry.key] = issued;
      reservedHandles.add(issued.grant.handle);
    }

    for (final entry in desiredByAccount.entries) {
      final desired = entry.value;
      final loadedRecord = recordsByAccount[entry.key];
      if (loadedRecord == null || loadedRecord.revokePending) {
        _emitReconcileFailure('missing_active_record');
        allSucceeded = false;
        continue;
      }
      var record = loadedRecord;

      final removedDevices =
          record.authorizedSenderDevicePeerIds
              .difference(desired.authorizedSenderDevicePeerIds)
              .toList(growable: false)
            ..sort();
      var removedAll = true;
      for (final devicePeerId in removedDevices) {
        var revoked = false;
        try {
          revoked = await _revokeWakeHandle(
            authorizedSenderPeerId: devicePeerId,
          );
        } catch (_) {
          revoked = false;
        }
        if (!revoked) {
          _emitReconcileFailure('relay_revoke');
          removedAll = false;
          continue;
        }

        // Relay revoke is deliberately non-idempotent: an already-absent
        // sender returns false. Checkpoint each success so a restart never
        // retries an authority that this process already removed.
        record = record.copyWith(
          authorizedSenderDevicePeerIds: record.authorizedSenderDevicePeerIds
              .difference(<String>{devicePeerId}),
        );
        await _store.write(record);
        recordsByAccount[entry.key] = record;
      }
      if (!removedAll) {
        allSucceeded = false;
        continue;
      }

      if (!_sameSet(
        record.authorizedSenderDevicePeerIds,
        desired.authorizedSenderDevicePeerIds,
      )) {
        final addedDevices = desired.authorizedSenderDevicePeerIds.difference(
          record.authorizedSenderDevicePeerIds,
        );
        record = record.copyWith(
          authorizedSenderDevicePeerIds: desired.authorizedSenderDevicePeerIds,
          distributionPending:
              record.distributionPending || addedDevices.isNotEmpty,
        );
        await _store.write(record);
        recordsByAccount[entry.key] = record;
      }

      try {
        await _publishNativeContact(
          wakeHandle: record.grant.handle,
          displayName: desired.displayName,
        );
      } catch (_) {
        _emitReconcileFailure('native_publish');
        allSucceeded = false;
        continue;
      }

      final senderDevices = record.authorizedSenderDevicePeerIds.toList()
        ..sort();
      for (final devicePeerId in senderDevices) {
        try {
          final accepted = await _setWakeHandle(
            CallWakeHandleRecord(
              authorizedSenderPeerId: devicePeerId,
              wakeHandle: record.grant.handle,
              expiresAtMs: record.grant.expiresAtMs,
            ),
          );
          if (!accepted) {
            _emitReconcileFailure('relay_set_rejected');
            allSucceeded = false;
          }
        } catch (_) {
          _emitReconcileFailure('relay_set_error');
          allSucceeded = false;
        }
      }
    }
    return allSucceeded;
  }

  void _emitReconcileFailure(String stage) {
    try {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_WAKE_RECONCILE_FAILURE',
        details: <String, Object?>{'stage': stage},
      );
    } catch (_) {
      // Identifier-free diagnostics cannot change wake authority.
    }
  }

  Future<CallWakeHandleGrant?> _resolveOrIssueGrantForContact({
    required CallWakeEligibleContact contact,
    required String localRecipientDevicePeerId,
    required int localDeviceKeyEpoch,
  }) async {
    final context = _validatedContext(
      localRecipientDevicePeerId,
      localDeviceKeyEpoch,
    );
    if (context == null) return null;

    final loaded = await _store.readAll();
    final currentMatches = loaded
        .where(
          (record) =>
              record.contactAccountPeerId == contact.contactAccountPeerId,
        )
        .toList(growable: false);
    if (currentMatches.length > 1) return null;
    if (currentMatches.isNotEmpty) {
      final current = currentMatches.single;
      if (current.revokePending) return null;
      if (current.grant.recipientDevicePeerId ==
              context.localRecipientDevicePeerId &&
          current.grant.deviceKeyEpoch == context.localDeviceKeyEpoch &&
          _hasMinimumRemainingLifetime(current.grant, context.nowMs)) {
        return current.grant;
      }
      await _store.write(current.copyWith(revokePending: true));
      return null;
    }
    if (loaded.length >= maxEligibleContacts) return null;

    final issued = _newRecord(
      contact: contact,
      localRecipientDevicePeerId: context.localRecipientDevicePeerId,
      localDeviceKeyEpoch: context.localDeviceKeyEpoch,
      generation: _freshGeneration(context.nowMs),
      nowMs: context.nowMs,
      reservedHandles: loaded.map((record) => record.grant.handle).toSet(),
    );
    if (issued == null) return null;
    await _store.write(issued);
    return issued.grant;
  }

  Future<_CallWakeRevocationProgress> _revokeRecord(
    CallIssuedWakeHandleRecord record,
  ) async {
    var succeeded = true;
    final senderDevices = record.authorizedSenderDevicePeerIds.toList()..sort();
    for (final devicePeerId in senderDevices) {
      var revoked = false;
      try {
        revoked = await _revokeWakeHandle(authorizedSenderPeerId: devicePeerId);
      } catch (_) {
        revoked = false;
      }
      if (!revoked) {
        succeeded = false;
        continue;
      }

      record = record.copyWith(
        authorizedSenderDevicePeerIds: record.authorizedSenderDevicePeerIds
            .difference(<String>{devicePeerId}),
      );
      await _store.write(record);
    }
    if (!succeeded) {
      return _CallWakeRevocationProgress(record: record, succeeded: false);
    }
    try {
      await _revokeNativeContact(record.grant.handle);
    } catch (_) {
      succeeded = false;
    }
    return _CallWakeRevocationProgress(record: record, succeeded: succeeded);
  }

  CallIssuedWakeHandleRecord? _newRecord({
    required CallWakeEligibleContact contact,
    required String localRecipientDevicePeerId,
    required int localDeviceKeyEpoch,
    required int generation,
    required int nowMs,
    required Set<String> reservedHandles,
  }) {
    if (generation <= 0 || generation > CallWakeHandleGrant.maxSafeInteger) {
      return null;
    }
    final expiresAtMs = nowMs + grantLifetime.inMilliseconds;
    if (expiresAtMs <= nowMs ||
        expiresAtMs > CallWakeHandleGrant.maxSafeInteger) {
      return null;
    }
    for (var attempt = 0; attempt < maxHandleGenerationAttempts; attempt++) {
      final handle = _canonicalHandle(_generateHandle());
      if (handle == null || reservedHandles.contains(handle)) continue;
      try {
        return CallIssuedWakeHandleRecord(
          contactAccountPeerId: contact.contactAccountPeerId,
          grant: CallWakeHandleGrant(
            handle: handle,
            recipientDevicePeerId: localRecipientDevicePeerId,
            deviceKeyEpoch: localDeviceKeyEpoch,
            generation: generation,
            issuedAtMs: nowMs,
            expiresAtMs: expiresAtMs,
          ),
          authorizedSenderDevicePeerIds: contact.authorizedSenderDevicePeerIds,
        );
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }

  _CallWakeContext? _validatedContext(
    String localRecipientDevicePeerId,
    int localDeviceKeyEpoch,
  ) {
    if (!CallWakeHandleGrant.hasValidPeerIdGrammar(
          localRecipientDevicePeerId,
        ) ||
        localDeviceKeyEpoch <= 0 ||
        localDeviceKeyEpoch > CallWakeHandleGrant.maxSafeInteger) {
      return null;
    }
    final nowMs = _nowMs();
    if (nowMs <= 0 || nowMs > CallWakeHandleGrant.maxSafeInteger) {
      return null;
    }
    return _CallWakeContext(
      localRecipientDevicePeerId: localRecipientDevicePeerId,
      localDeviceKeyEpoch: localDeviceKeyEpoch,
      nowMs: nowMs,
    );
  }

  static int? _nextGeneration({required CallWakeHandleGrant prior}) {
    if (prior.generation >= CallWakeHandleGrant.maxSafeInteger) {
      return null;
    }
    return prior.generation + 1;
  }

  /// A fresh grant starts at the issuer's clock rather than at 1. The
  /// issuer's record is deleted when a contact is removed, but the receiver
  /// keeps the last generation it accepted and ignores anything not strictly
  /// newer, so a re-added contact restarting at 1 could never wake this
  /// device again.
  static int _freshGeneration(int nowMs) => nowMs > 1 ? nowMs : 1;

  static bool _sameSet(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  static bool _hasMinimumRemainingLifetime(
    CallWakeHandleGrant grant,
    int nowMs,
  ) =>
      grant.isValidAt(nowMs) &&
      grant.expiresAtMs - nowMs >= minimumRemainingGrantLifetime.inMilliseconds;

  static String? _canonicalHandle(String candidate) {
    if (_hexHandlePattern.hasMatch(candidate)) return candidate;
    if (_uuidV4HandlePattern.hasMatch(candidate)) {
      return candidate.replaceAll('-', '');
    }
    return null;
  }

  Future<T> _schedule<T>(
    Future<T> Function() action, {
    required T closedValue,
  }) {
    if (_closed) return Future<T>.value(closedValue);
    final completer = Completer<T>();
    _tail = _tail.then<void>((_) async {
      try {
        completer.complete(await action());
      } catch (_) {
        completer.complete(closedValue);
      }
    });
    return completer.future;
  }

  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    _closed = true;
    return _closeFuture = _tail;
  }

  static final RegExp _hexHandlePattern = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _uuidV4HandlePattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
}

final class _CallWakeContext {
  const _CallWakeContext({
    required this.localRecipientDevicePeerId,
    required this.localDeviceKeyEpoch,
    required this.nowMs,
  });

  final String localRecipientDevicePeerId;
  final int localDeviceKeyEpoch;
  final int nowMs;
}

final class _CallWakeRevocationProgress {
  const _CallWakeRevocationProgress({
    required this.record,
    required this.succeeded,
  });

  final CallIssuedWakeHandleRecord record;
  final bool succeeded;
}
