import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';

enum CallEnvelopeErrorCode {
  invalidSchema,
  unsupportedVersion,
  invalidIdentifier,
  invalidTimestamp,
  expired,
  excessiveClockSkew,
  oversized,
  invalidCryptoFields,
  invalidSignature,
  decryptionFailed,
  cryptoUnavailable,
  authorityMismatch,
  replay,
  messageIdConflict,
  nonMonotonicSequence,
  replayStateCapacity,
  ttlExceeded,
  inviteContainsSessionDescription,
  missingFingerprint,
}

/// A deliberately detail-free failure. Wire values and peer identities are
/// never copied into diagnostics.
final class CallEnvelopeException implements Exception {
  const CallEnvelopeException(this.code);

  final CallEnvelopeErrorCode code;

  @override
  String toString() => 'Call envelope rejected: ${code.name}';
}

final class CallCiphertext {
  const CallCiphertext({
    required this.kem,
    required this.ciphertext,
    required this.nonce,
  });

  final String kem;
  final String ciphertext;
  final String nonce;
}

/// Generic secure-envelope crypto. The production adapter uses the existing
/// native ML-KEM/AES-GCM and Ed25519 bridge primitives. It is not a chat
/// serializer and has no persistence or retry behavior.
abstract interface class CallEnvelopeCrypto {
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  });

  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  });

  Future<String> sign({
    required String senderSigningPrivateKey,
    required String canonicalData,
  });

  Future<bool> verify({
    required String senderSigningPublicKey,
    required String canonicalData,
    required String signature,
  });
}

final class BridgeCallEnvelopeCrypto implements CallEnvelopeCrypto {
  const BridgeCallEnvelopeCrypto({
    required this.bridge,
    this.timeout = const Duration(seconds: 10),
  });

  final Bridge bridge;
  final Duration timeout;

  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async {
    final result = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      plaintext: plaintext,
      timeout: timeout,
    );
    if (result['ok'] != true ||
        result['kem'] is! String ||
        result['ciphertext'] is! String ||
        result['nonce'] is! String) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.decryptionFailed);
    }
    return CallCiphertext(
      kem: result['kem'] as String,
      ciphertext: result['ciphertext'] as String,
      nonce: result['nonce'] as String,
    );
  }

  @override
  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  }) async {
    final result = await callDecryptMessage(
      bridge: bridge,
      ownMlKemSecretKey: ownMlKemSecretKey,
      kem: ciphertext.kem,
      ciphertext: ciphertext.ciphertext,
      nonce: ciphertext.nonce,
      timeout: timeout,
      throwOnBridgeUnavailable: true,
    );
    if (result['ok'] != true || result['plaintext'] is! String) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.decryptionFailed);
    }
    return result['plaintext'] as String;
  }

  @override
  Future<String> sign({
    required String senderSigningPrivateKey,
    required String canonicalData,
  }) async {
    final result = await callSignPayload(
      bridge: bridge,
      dataToSign: canonicalData,
      privateKey: senderSigningPrivateKey,
      timeout: timeout,
    );
    if (result['ok'] != true || result['signature'] is! String) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.invalidSignature);
    }
    return result['signature'] as String;
  }

  @override
  Future<bool> verify({
    required String senderSigningPublicKey,
    required String canonicalData,
    required String signature,
  }) {
    return callVerifyPayload(
      bridge: bridge,
      publicKey: senderSigningPublicKey,
      data: canonicalData,
      signature: signature,
      timeout: timeout,
      throwOnBridgeUnavailable: true,
    );
  }
}

final class CallEnvelopeAuthority {
  const CallEnvelopeAuthority({
    required this.authenticatedTransportPeerId,
    required this.expectedSenderAccountPeerId,
    required this.expectedSenderDevicePeerId,
    required this.expectedRecipientAccountPeerId,
    required this.expectedRecipientDevicePeerId,
    required this.senderSigningPublicKey,
    required this.ownMlKemSecretKey,
  });

  final String authenticatedTransportPeerId;
  final String expectedSenderAccountPeerId;
  final String expectedSenderDevicePeerId;
  final String expectedRecipientAccountPeerId;
  final String expectedRecipientDevicePeerId;
  final String senderSigningPublicKey;
  final String ownMlKemSecretKey;
}

/// The authenticated domain signal plus the opaque outer routing handle.
/// Product call state remains exclusively in [CallSignal]/CallCoordinator.
final class DecodedSecureCallEnvelope {
  DecodedSecureCallEnvelope({
    required this.signal,
    required this.callHandle,
    required CallReplayProtectionReservation replayReservation,
  }) : _replayReservation = replayReservation;

  final CallSignal signal;
  final String callHandle;
  final CallReplayProtectionReservation _replayReservation;

  /// Makes this authenticated signal a replay tombstone only after the call
  /// coordinator has accepted or permanently rejected its state transition.
  void commitReplay() => _replayReservation.commit();

  /// Releases a provisional admission after a local/transient failure so the
  /// mailbox can retry the exact signal without losing the call.
  void rollbackReplay() => _replayReservation.rollback();

  @override
  String toString() => 'DecodedSecureCallEnvelope(redacted)';
}

abstract interface class CallReplayProtectionStore {
  CallReplayProtectionReservation reserve({
    required CallSignal signal,
    required String envelopeDigest,
    required int nowMs,
    required Duration tombstoneTtl,
  });
}

abstract interface class CallReplayProtectionReservation {
  void commit();

  void rollback();
}

final class _ReplayEntry {
  const _ReplayEntry({
    required this.sequenceKey,
    required this.sequence,
    required this.event,
    required this.iceGeneration,
    required this.envelopeDigest,
    required this.expiresAtMs,
    this.committed = false,
  });

  final String sequenceKey;
  final int sequence;
  final CallSignalType event;
  final int iceGeneration;
  final String envelopeDigest;
  final int expiresAtMs;
  final bool committed;

  _ReplayEntry commit() => _ReplayEntry(
    sequenceKey: sequenceKey,
    sequence: sequence,
    event: event,
    iceGeneration: iceGeneration,
    envelopeDigest: envelopeDigest,
    expiresAtMs: expiresAtMs,
    committed: true,
  );
}

/// A fixed-capacity replay/sequence store. It removes only expired entries and
/// fails closed when live tombstones fill the bound.
final class InMemoryBoundedCallReplayProtectionStore
    implements CallReplayProtectionStore {
  InMemoryBoundedCallReplayProtectionStore({this.maxEntries = 4096}) {
    if (maxEntries < 2) {
      throw ArgumentError.value(maxEntries, 'maxEntries');
    }
  }

  final int maxEntries;
  final Map<String, _ReplayEntry> _entries = <String, _ReplayEntry>{};

  @override
  CallReplayProtectionReservation reserve({
    required CallSignal signal,
    required String envelopeDigest,
    required int nowMs,
    required Duration tombstoneTtl,
  }) {
    _entries.removeWhere((_, entry) => entry.expiresAtMs <= nowMs);
    final existing = _entries[signal.messageId];
    if (existing != null) {
      throw CallEnvelopeException(
        existing.envelopeDigest == envelopeDigest
            ? CallEnvelopeErrorCode.replay
            : CallEnvelopeErrorCode.messageIdConflict,
      );
    }
    final sequenceKey = <String>[
      signal.senderAccountPeerId,
      signal.senderDevicePeerId,
      signal.callId.value,
    ].join('\u0000');
    var sequenceAlreadyReserved = false;
    _ReplayEntry? highestSequenceEntry;
    final sequenceKeys = <String>{};
    for (final entry in _entries.values) {
      sequenceKeys.add(entry.sequenceKey);
      if (entry.sequenceKey == sequenceKey) {
        if (entry.sequence == signal.senderSequence) {
          sequenceAlreadyReserved = true;
        }
        if (highestSequenceEntry == null ||
            entry.sequence > highestSequenceEntry.sequence) {
          highestSequenceEntry = entry;
        }
      }
    }
    if (sequenceAlreadyReserved) {
      throw const CallEnvelopeException(
        CallEnvelopeErrorCode.nonMonotonicSequence,
      );
    }
    final priorHighWater = highestSequenceEntry;
    if (priorHighWater != null &&
        signal.senderSequence < priorHighWater.sequence) {
      // Negotiation frames use independent authenticated transport streams.
      // Admit a small same-generation reorder window (for example ICE N+1
      // racing ahead of SDP N), while control signals and stale generations
      // retain strict sender ordering.
      final distance = priorHighWater.sequence - signal.senderSequence;
      final reorderable =
          distance <= CallSignal.maximumNegotiationReorderingDistance &&
          signal.iceGeneration == priorHighWater.iceGeneration &&
          _isNegotiationSignal(signal.event) &&
          _isNegotiationSignal(priorHighWater.event);
      if (!reorderable) {
        throw const CallEnvelopeException(
          CallEnvelopeErrorCode.nonMonotonicSequence,
        );
      }
    }
    final newEntryCount = 1 + (sequenceKeys.contains(sequenceKey) ? 0 : 1);
    if (_entries.length + sequenceKeys.length + newEntryCount > maxEntries) {
      throw const CallEnvelopeException(
        CallEnvelopeErrorCode.replayStateCapacity,
      );
    }
    final minimumTombstoneExpiry = nowMs + tombstoneTtl.inMilliseconds;
    final tombstoneExpiresAt = signal.expiresAtMs > minimumTombstoneExpiry
        ? signal.expiresAtMs
        : minimumTombstoneExpiry;
    _entries[signal.messageId] = _ReplayEntry(
      sequenceKey: sequenceKey,
      sequence: signal.senderSequence,
      event: signal.event,
      iceGeneration: signal.iceGeneration,
      envelopeDigest: envelopeDigest,
      expiresAtMs: tombstoneExpiresAt,
    );
    return _InMemoryCallReplayReservation(this, signal.messageId);
  }

  void _commit(String messageId) {
    final entry = _entries[messageId];
    if (entry != null && !entry.committed) {
      _entries[messageId] = entry.commit();
    }
  }

  void _rollback(String messageId) {
    final entry = _entries[messageId];
    if (entry != null && !entry.committed) {
      _entries.remove(messageId);
    }
  }

  static bool _isNegotiationSignal(CallSignalType event) => switch (event) {
    CallSignalType.offer || CallSignalType.answer || CallSignalType.ice => true,
    _ => false,
  };
}

final class _InMemoryCallReplayReservation
    implements CallReplayProtectionReservation {
  _InMemoryCallReplayReservation(this._store, this._messageId);

  final InMemoryBoundedCallReplayProtectionStore _store;
  final String _messageId;
  bool _resolved = false;

  @override
  void commit() {
    if (_resolved) return;
    _store._commit(_messageId);
    _resolved = true;
  }

  @override
  void rollback() {
    if (_resolved) return;
    _store._rollback(_messageId);
    _resolved = true;
  }
}

final class SecureCallEnvelopeCodec {
  SecureCallEnvelopeCodec({
    required CallEnvelopeCrypto crypto,
    required int Function() nowMs,
    this.maxFutureClockSkew = const Duration(seconds: 30),
    this.replayTombstoneTtl = const Duration(minutes: 10),
    CallReplayProtectionStore? replayStore,
  }) : _crypto = crypto,
       _nowMs = nowMs,
       _replayStore =
           replayStore ?? InMemoryBoundedCallReplayProtectionStore() {
    if (replayTombstoneTtl < const Duration(minutes: 10)) {
      throw ArgumentError.value(replayTombstoneTtl, 'replayTombstoneTtl');
    }
    if (maxFutureClockSkew.isNegative) {
      throw ArgumentError.value(maxFutureClockSkew, 'maxFutureClockSkew');
    }
  }

  static const int maxSignalBytes = CallSignal.maximumEncodedBytes;
  static const String innerSchema = CallSignal.schema;
  static const Duration maximumPostconnectLifetime = Duration(minutes: 10);
  static const Set<String> _outerKeys = <String>{
    'type',
    'version',
    'message_id',
    'call_handle',
    'expires_at_ms',
    'kem',
    'ciphertext',
    'nonce',
    'signature',
  };
  static final RegExp _random128 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  final CallEnvelopeCrypto _crypto;
  final int Function() _nowMs;
  final Duration maxFutureClockSkew;
  final Duration replayTombstoneTtl;
  final CallReplayProtectionStore _replayStore;

  Future<String> encode({
    required CallSignal signal,
    required String callHandle,
    required String recipientMlKemPublicKey,
    required String senderSigningPrivateKey,
  }) async {
    _validateSignal(signal, enforceFreshness: true);
    if (!_random128.hasMatch(callHandle)) {
      throw const CallEnvelopeException(
        CallEnvelopeErrorCode.invalidIdentifier,
      );
    }
    if (recipientMlKemPublicKey.trim().isEmpty ||
        senderSigningPrivateKey.trim().isEmpty) {
      throw const CallEnvelopeException(
        CallEnvelopeErrorCode.invalidCryptoFields,
      );
    }

    late final CallCiphertext encrypted;
    try {
      encrypted = await _crypto.encrypt(
        recipientMlKemPublicKey: recipientMlKemPublicKey,
        plaintext: _canonicalJson(signal.toMap()),
      );
    } on CallEnvelopeException {
      rethrow;
    } catch (_) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.decryptionFailed);
    }
    _validateBase64Fields(encrypted);

    final unsigned = <String, Object?>{
      'type': 'call_signal',
      'version': '1',
      'message_id': signal.messageId,
      'call_handle': callHandle,
      'expires_at_ms': signal.expiresAtMs,
      'kem': encrypted.kem,
      'ciphertext': encrypted.ciphertext,
      'nonce': encrypted.nonce,
    };
    late final String signature;
    try {
      signature = await _crypto.sign(
        senderSigningPrivateKey: senderSigningPrivateKey,
        canonicalData: _canonicalJson(unsigned),
      );
    } on CallEnvelopeException {
      rethrow;
    } catch (_) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.invalidSignature);
    }
    if (!_isValidBase64(signature)) {
      throw const CallEnvelopeException(
        CallEnvelopeErrorCode.invalidCryptoFields,
      );
    }
    final encoded = _canonicalJson(<String, Object?>{
      ...unsigned,
      'signature': signature,
    });
    _enforceSize(encoded);
    return encoded;
  }

  Future<DecodedSecureCallEnvelope> decode({
    required String envelopeJson,
    required CallEnvelopeAuthority authority,
  }) async {
    _enforceSize(envelopeJson);
    final outer = _decodeObject(envelopeJson);
    _requireExactKeys(outer, _outerKeys);
    if (outer['type'] != 'call_signal') {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.invalidSchema);
    }
    if (outer['version'] != '1') {
      throw const CallEnvelopeException(
        CallEnvelopeErrorCode.unsupportedVersion,
      );
    }

    final messageId = _requiredString(outer, 'message_id');
    final callHandle = _requiredString(outer, 'call_handle');
    final expiresAtMs = _requiredInt(outer, 'expires_at_ms');
    if (!_random128.hasMatch(messageId) || !_random128.hasMatch(callHandle)) {
      throw const CallEnvelopeException(
        CallEnvelopeErrorCode.invalidIdentifier,
      );
    }
    final outerNow = _nowMs();
    if (expiresAtMs <= outerNow) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.expired);
    }
    if (expiresAtMs >
        outerNow +
            maxFutureClockSkew.inMilliseconds +
            maximumPostconnectLifetime.inMilliseconds) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.ttlExceeded);
    }

    final encrypted = CallCiphertext(
      kem: _requiredString(outer, 'kem'),
      ciphertext: _requiredString(outer, 'ciphertext'),
      nonce: _requiredString(outer, 'nonce'),
    );
    final signature = _requiredString(outer, 'signature');
    _validateBase64Fields(encrypted);
    if (!_isValidBase64(signature)) {
      throw const CallEnvelopeException(
        CallEnvelopeErrorCode.invalidCryptoFields,
      );
    }

    final unsigned = <String, Object?>{
      'type': 'call_signal',
      'version': '1',
      'message_id': messageId,
      'call_handle': callHandle,
      'expires_at_ms': expiresAtMs,
      'kem': encrypted.kem,
      'ciphertext': encrypted.ciphertext,
      'nonce': encrypted.nonce,
    };
    late final bool signatureValid;
    try {
      signatureValid = await _crypto.verify(
        senderSigningPublicKey: authority.senderSigningPublicKey,
        canonicalData: _canonicalJson(unsigned),
        signature: signature,
      );
    } on CallEnvelopeException {
      rethrow;
    } catch (_) {
      throw const CallEnvelopeException(
        CallEnvelopeErrorCode.cryptoUnavailable,
      );
    }
    if (!signatureValid) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.invalidSignature);
    }

    late final String plaintext;
    try {
      plaintext = await _crypto.decrypt(
        ownMlKemSecretKey: authority.ownMlKemSecretKey,
        ciphertext: encrypted,
      );
    } on CallEnvelopeException {
      rethrow;
    } catch (_) {
      throw const CallEnvelopeException(
        CallEnvelopeErrorCode.cryptoUnavailable,
      );
    }

    final inner = _decodeObject(plaintext);
    late final CallSignal signal;
    try {
      signal = CallSignal.fromMap(Map<String, Object?>.from(inner));
    } catch (_) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.invalidSchema);
    }
    _validateSignal(signal, enforceFreshness: true);
    if (signal.messageId != messageId || signal.expiresAtMs != expiresAtMs) {
      throw const CallEnvelopeException(
        CallEnvelopeErrorCode.authorityMismatch,
      );
    }
    _validateAuthority(signal, authority);
    final replayReservation = _replayStore.reserve(
      signal: signal,
      envelopeDigest: sha256.convert(utf8.encode(envelopeJson)).toString(),
      nowMs: _nowMs(),
      tombstoneTtl: replayTombstoneTtl,
    );
    return DecodedSecureCallEnvelope(
      signal: signal,
      callHandle: callHandle,
      replayReservation: replayReservation,
    );
  }

  void _validateSignal(CallSignal signal, {required bool enforceFreshness}) {
    final maximumLifetime = switch (signal.event) {
      CallSignalType.invite ||
      CallSignalType.ringing ||
      CallSignalType.accept ||
      CallSignalType.reject => const Duration(
        milliseconds: CallSignal.maximumPreconnectLifetimeMs,
      ),
      _ => maximumPostconnectLifetime,
    };
    if (signal.expiresAtMs - signal.createdAtMs >
        maximumLifetime.inMilliseconds) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.ttlExceeded);
    }
    if (enforceFreshness) {
      final now = _nowMs();
      if (signal.expiresAtMs <= now) {
        throw const CallEnvelopeException(CallEnvelopeErrorCode.expired);
      }
      if (signal.createdAtMs > now + maxFutureClockSkew.inMilliseconds) {
        throw const CallEnvelopeException(
          CallEnvelopeErrorCode.excessiveClockSkew,
        );
      }
    }
    try {
      _canonicalJson(signal.toMap());
    } catch (_) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.invalidSchema);
    }
  }

  void _validateAuthority(CallSignal signal, CallEnvelopeAuthority authority) {
    if (authority.authenticatedTransportPeerId.trim().isEmpty ||
        authority.expectedSenderAccountPeerId.trim().isEmpty ||
        authority.expectedSenderDevicePeerId.trim().isEmpty ||
        authority.expectedRecipientAccountPeerId.trim().isEmpty ||
        authority.expectedRecipientDevicePeerId.trim().isEmpty ||
        authority.senderSigningPublicKey.trim().isEmpty ||
        authority.ownMlKemSecretKey.trim().isEmpty ||
        authority.authenticatedTransportPeerId != signal.senderDevicePeerId ||
        authority.expectedSenderAccountPeerId != signal.senderAccountPeerId ||
        authority.expectedSenderDevicePeerId != signal.senderDevicePeerId ||
        authority.expectedRecipientAccountPeerId !=
            signal.recipientAccountPeerId ||
        authority.expectedRecipientDevicePeerId !=
            signal.recipientDevicePeerId) {
      throw const CallEnvelopeException(
        CallEnvelopeErrorCode.authorityMismatch,
      );
    }
  }

  static Map<String, dynamic> _decodeObject(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Converted to the fixed error below.
    }
    throw const CallEnvelopeException(CallEnvelopeErrorCode.invalidSchema);
  }

  static void _requireExactKeys(
    Map<String, dynamic> value,
    Set<String> expected,
  ) {
    if (value.keys.toSet().length != expected.length ||
        !value.keys.toSet().containsAll(expected)) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.invalidSchema);
    }
  }

  static String _requiredString(Map<String, dynamic> value, String key) {
    final field = value[key];
    if (field is! String || field.isEmpty) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.invalidSchema);
    }
    return field;
  }

  static int _requiredInt(Map<String, dynamic> value, String key) {
    final field = value[key];
    if (field is! int) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.invalidSchema);
    }
    return field;
  }

  static void _validateBase64Fields(CallCiphertext encrypted) {
    if (!_isValidBase64(encrypted.kem) ||
        !_isValidBase64(encrypted.ciphertext) ||
        !_isValidBase64(encrypted.nonce)) {
      throw const CallEnvelopeException(
        CallEnvelopeErrorCode.invalidCryptoFields,
      );
    }
  }

  static bool _isValidBase64(String value) {
    if (value.isEmpty) return false;
    try {
      base64Decode(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _enforceSize(String envelopeJson) {
    if (utf8.encode(envelopeJson).length > maxSignalBytes) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.oversized);
    }
  }

  static String _canonicalJson(Object? value) =>
      jsonEncode(_canonicalize(value));

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) {
      return <Object?>[for (final item in value) _canonicalize(item)];
    }
    if (value == null || value is String || value is bool || value is num) {
      return value;
    }
    throw const CallEnvelopeException(CallEnvelopeErrorCode.invalidSchema);
  }
}
