import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/push/domain/received_wake_token_store.dart';

import 'package:flutter_app/core/debug/android_notification_payload_e2e_protocol.dart';

export 'package:flutter_app/core/debug/android_notification_payload_e2e_protocol.dart'
    show
        notificationDualPathSenderSchema,
        notificationDualPathSenderAction,
        notificationDualPathReleaseFileName;

bool allowsNotificationDualPathSender({
  required bool debugMode,
  required bool e2eTestMode,
  required bool productionFcm,
  required String installedProfileId,
}) =>
    debugMode &&
    e2eTestMode &&
    productionFcm &&
    installedProfileId == 'android.production_fcm';

final class NotificationDualPathFailure implements Exception {
  const NotificationDualPathFailure(this.code, {this.cleanupErrorCode});
  final String code;
  final String? cleanupErrorCode;
  @override
  String toString() => 'NotificationDualPathFailure($code)';
}

final class NotificationDualPathRequest {
  NotificationDualPathRequest.fromConfig(Map<String, dynamic> config)
    : stepId = _token(config, 'stepId'),
      runId = _token(config, 'runId'),
      nonce = _token(config, 'nonce'),
      targetPeerId = _token(config, 'targetPeerId'),
      text = _text(config) {
    if (!_keys(config, const {
          'transport_action',
          'stepId',
          'runId',
          'nonce',
          'targetPeerId',
          'text',
          'timeoutMs',
        }) ||
        config['transport_action'] != notificationDualPathSenderAction ||
        config['timeoutMs'] != 180000) {
      throw const NotificationDualPathFailure('request_rejected');
    }
  }
  final String stepId, runId, nonce, targetPeerId, text;
  static const timeout = Duration(minutes: 3);
  Map<String, Object?> get binding => {
    'schema': notificationDualPathSenderSchema,
    'stepId': stepId,
    'runId': runId,
    'nonce': nonce,
  };
  bool owns(Map<String, dynamic> control) =>
      binding.entries.every((e) => control[e.key] == e.value);
}

bool _keys(Map<String, dynamic> value, Set<String> expected) =>
    value.length == expected.length && value.keys.toSet().containsAll(expected);
String _token(Map<String, dynamic> config, String key) {
  final value = config[key];
  if (value is! String ||
      !RegExp(r'^[a-zA-Z0-9._:-]{1,160}$').hasMatch(value)) {
    throw const NotificationDualPathFailure('request_rejected');
  }
  return value;
}

String _text(Map<String, dynamic> config) {
  final value = config['text'];
  if (value is! String || value.isEmpty || utf8.encode(value).length > 4096) {
    throw const NotificationDualPathFailure('request_rejected');
  }
  return value;
}

String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

/// Contains public authority plus a one-way wake-token binding, never secrets
/// or wire data in diagnostics. A fresh snapshot is required before each send.
final class NotificationDualPathAuthority {
  const NotificationDualPathAuthority({
    required this.senderPeerId,
    required this.senderUsername,
    required this.recipientMlKemKey,
    required this.fingerprint,
  });
  final String senderPeerId, senderUsername, recipientMlKemKey, fingerprint;
  @override
  String toString() => 'NotificationDualPathAuthority(redacted)';
}

typedef NotificationDualPathControlReader =
    Future<Map<String, dynamic>?> Function();
typedef NotificationDualPathWriter =
    Future<void> Function(Map<String, Object?>);

/// Fixture-owned action only. It creates one real encrypted envelope and stores
/// it before exposing a hash-only prepared receipt. The host must independently
/// observe provider acceptance before releasing the exact same bytes to Go.
/// No production message sender, retry policy, or receiver behavior is changed.
final class NotificationDualPathSender {
  NotificationDualPathSender({
    required this.enabled,
    required this.readAuthority,
    required this.encrypt,
    required this.store,
    required this.sendLive,
    DateTime Function()? wallNow,
    Duration Function()? elapsed,
    String Function()? newMessageId,
  }) : _wallNow = wallNow ?? DateTime.now,
       _elapsed = elapsed ?? (Stopwatch()..start()).elapsedGetter,
       _newMessageId = newMessageId ?? const Uuid().v4;

  final bool enabled;
  final Future<NotificationDualPathAuthority> Function(String peer)
  readAuthority;
  final Future<Map<String, dynamic>> Function(
    String key,
    String plaintext,
    Duration remaining,
  )
  encrypt;
  final Future<InboxStoreOutcome> Function(
    String peer,
    String wire,
    Duration remaining,
  )
  store;
  final Future<SendMessageResult> Function(
    String peer,
    String wire,
    Duration remaining,
  )
  sendLive;
  final DateTime Function() _wallNow;
  final Duration Function() _elapsed;
  final String Function() _newMessageId;
  final Set<String> _consumed = {};
  bool _running = false;
  bool _closed = false;

  void close() {
    _closed = true;
  }

  Future<Map<String, Object?>> run({
    required NotificationDualPathRequest request,
    required NotificationDualPathWriter writePrepared,
    required NotificationDualPathControlReader readControl,
    required Future<void> Function(NotificationDualPathRequest) cleanupControl,
  }) async {
    if (!enabled || _closed) {
      throw const NotificationDualPathFailure('disabled');
    }
    final replayKey = _hash(
      '${request.runId}:${request.nonce}:${request.stepId}',
    );
    if (_running || _consumed.length >= 64 || !_consumed.add(replayKey)) {
      throw const NotificationDualPathFailure('replayed_or_busy');
    }
    _running = true;
    final end = _elapsed() + NotificationDualPathRequest.timeout;
    final expiresAtMs = _wallNow()
        .add(NotificationDualPathRequest.timeout)
        .millisecondsSinceEpoch;
    Map<String, Object?>? prepared;
    bool released = false;
    bool canceled = false;
    String? wire;
    Object? primaryFailure;
    StackTrace? primaryStack;
    Duration remaining() {
      if (_closed || canceled) {
        throw const NotificationDualPathFailure('canceled');
      }
      final value = end - _elapsed();
      if (value <= Duration.zero) {
        throw const NotificationDualPathFailure('deadline');
      }
      return value;
    }

    Future<void> control() async {
      remaining();
      final done = readControl().then<_Completion<Map<String, dynamic>?>>(
        (value) => _Completion<Map<String, dynamic>?>.value(value),
        onError: (Object error, StackTrace stack) =>
            _Completion<Map<String, dynamic>?>.error(error, stack),
      );
      Map<String, dynamic>? value;
      while (true) {
        final result = await Future.any<_Completion<Map<String, dynamic>?>?>([
          done,
          Future<void>.delayed(
            const Duration(milliseconds: 50),
          ).then((_) => null),
        ]).timeout(remaining());
        remaining();
        if (result != null) {
          value = result.unwrap();
          break;
        }
      }
      if (value == null) return;
      if (!request.owns(value)) {
        throw const NotificationDualPathFailure('control_binding');
      }
      if (_keys(value, const {
            'schema',
            'stepId',
            'runId',
            'nonce',
            'decision',
          }) &&
          value['decision'] == 'cancel') {
        canceled = true;
        throw const NotificationDualPathFailure('canceled');
      }
      if (prepared == null ||
          !_keys(value, const {
            'schema',
            'stepId',
            'runId',
            'nonce',
            'messageId',
            'wireSha256',
          }) ||
          value['messageId'] != prepared['messageId'] ||
          value['wireSha256'] != prepared['wireSha256']) {
        throw const NotificationDualPathFailure('control_binding');
      }
      released = true;
    }

    Future<T> bounded<T>(Future<T> Function(Duration) operation) async {
      await control();
      final duration = remaining();
      final pending = operation(duration);
      // Observe cancellation while native encryption/store/send is pending.
      // No permanent cancellation future retains completed crypto/read values.
      // A late completion has no continuation capable of publishing or sending.
      final done = pending.then<_Completion<T>>(
        (v) => _Completion<T>.value(v),
        onError: (Object e, StackTrace s) => _Completion<T>.error(e, s),
      );
      while (true) {
        final result = await Future.any<_Completion<T>?>([
          done,
          Future<void>.delayed(
            const Duration(milliseconds: 50),
          ).then((_) => null),
        ]).timeout(remaining());
        await control();
        remaining();
        if (result != null) return result.unwrap();
      }
    }

    try {
      final authority = await bounded(
        (_) => readAuthority(request.targetPeerId),
      );
      Future<void> requireAuthority() async {
        final current = await bounded(
          (_) => readAuthority(request.targetPeerId),
        );
        if (current.fingerprint != authority.fingerprint) {
          throw const NotificationDualPathFailure('authority_changed');
        }
      }

      final messageId = _newMessageId();
      final payload = MessagePayload(
        id: messageId,
        text: request.text,
        senderPeerId: authority.senderPeerId,
        senderUsername: authority.senderUsername,
        timestamp: _wallNow().toUtc().toIso8601String(),
      );
      final encrypted = await bounded(
        (budget) =>
            encrypt(authority.recipientMlKemKey, payload.toInnerJson(), budget),
      );
      if (encrypted['ok'] != true ||
          ['kem', 'ciphertext', 'nonce'].any(
            (k) => encrypted[k] is! String || (encrypted[k] as String).isEmpty,
          )) {
        throw const NotificationDualPathFailure('encryption_failed');
      }
      wire = MessagePayload.buildEncryptedEnvelope(
        id: messageId,
        senderPeerId: authority.senderPeerId,
        senderUsername: authority.senderUsername,
        kem: encrypted['kem'] as String,
        ciphertext: encrypted['ciphertext'] as String,
        nonce: encrypted['nonce'] as String,
      );
      await requireAuthority();
      final stored = await bounded(
        (budget) => store(request.targetPeerId, wire!, budget),
      );
      if (!stored.ackOrExpiryAccepted ||
          stored.status != InboxStoreStatus.stored ||
          stored.storeStatus != 'stored') {
        throw const NotificationDualPathFailure('custody_not_fresh');
      }
      await requireAuthority();
      prepared = Map<String, Object?>.unmodifiable({
        ...request.binding,
        'status': 'prepared',
        'success': true,
        'targetPeerId': request.targetPeerId,
        'messageId': messageId,
        'wireSha256': _hash(wire),
        'ciphertextSha256': _hash(encrypted['ciphertext'] as String),
        'expiresAtMs': expiresAtMs,
      });
      await bounded((_) => writePrepared(prepared!));
      while (!released) {
        await bounded(
          (_) => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      await requireAuthority();
      // Last control/deadline fence is inside bounded, immediately before the
      // only real live submission. No retry or regenerated envelope exists.
      final live = await bounded(
        (budget) => sendLive(request.targetPeerId, wire!, budget),
      );
      if (!live.sent ||
          live.acked != true ||
          !const {'direct', 'relay', 'local'}.contains(live.transport)) {
        throw const NotificationDualPathFailure('live_not_acked');
      }
      return {
        ...prepared,
        'status': 'complete',
        'transport': live.transport,
        'acked': true,
      };
    } on TimeoutException catch (_, stack) {
      primaryFailure = const NotificationDualPathFailure('deadline');
      primaryStack = stack;
      Error.throwWithStackTrace(primaryFailure, stack);
    } catch (error, stack) {
      primaryFailure = error;
      primaryStack = stack;
      rethrow;
    } finally {
      wire = null;
      prepared = null;
      try {
        await cleanupControl(request).timeout(const Duration(seconds: 2));
        // Cleanup belongs to the original action budget as well.
        if (primaryFailure == null) remaining();
      } catch (cleanupError, cleanupStack) {
        if (cleanupError is NotificationDualPathFailure &&
            const {'deadline', 'canceled'}.contains(cleanupError.code) &&
            primaryFailure == null) {
          rethrow;
        }
        close();
        final original = primaryFailure;
        Error.throwWithStackTrace(
          NotificationDualPathFailure(
            original is NotificationDualPathFailure
                ? original.code
                : original == null
                ? 'control_cleanup_failed'
                : 'operation_failed',
            cleanupErrorCode: 'control_cleanup_failed',
          ),
          primaryStack ?? cleanupStack,
        );
      } finally {
        _running = false;
      }
    }
  }
}

extension on Stopwatch {
  Duration Function() get elapsedGetter =>
      () => elapsed;
}

final class _Completion<T> {
  _Completion.value(this.value) : error = null, stack = null;
  _Completion.error(this.error, this.stack) : value = null;
  final T? value;
  final Object? error;
  final StackTrace? stack;
  T unwrap() {
    if (error != null) Error.throwWithStackTrace(error!, stack!);
    return value as T;
  }
}

/// Application wiring uses the real authenticated service and crypto bridge.
NotificationDualPathSender createNotificationDualPathSender({
  required bool enabled,
  required P2PService service,
  required Bridge bridge,
  required IdentityRepository identities,
  required ContactRepository contacts,
  required ReceivedWakeTokenStore wakeTokens,
}) => NotificationDualPathSender(
  enabled: enabled,
  readAuthority: (peer) async {
    final identity = await identities.loadIdentity();
    final contact = await contacts.getContact(peer);
    final wake = await wakeTokens.readTokenFor(peer);
    final finalIdentity = await identities.loadIdentity();
    if (identity == null ||
        finalIdentity != identity ||
        contact == null ||
        contact.peerId != peer ||
        contact.isBlocked ||
        contact.isArchived ||
        (contact.mlKemPublicKey?.isEmpty ?? true) ||
        contact.publicKey.isEmpty ||
        identity.publicKey.isEmpty ||
        (identity.mlKemPublicKey?.isEmpty ?? true) ||
        wake == null ||
        (wake['tok']?.isEmpty ?? true) ||
        !service.currentState.isStarted ||
        service.currentState.peerId != identity.peerId ||
        !service.currentState.sendCapabilityReady ||
        !service.currentState.inboxCapabilityReady) {
      throw const NotificationDualPathFailure('authority_unavailable');
    }
    return NotificationDualPathAuthority(
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      recipientMlKemKey: contact.mlKemPublicKey!,
      fingerprint: _hash(
        jsonEncode([
          identity.peerId,
          identity.publicKey,
          identity.mlKemPublicKey,
          contact.peerId,
          contact.publicKey,
          contact.mlKemPublicKey,
          contact.signature,
          wake['tok'],
        ]),
      ),
    );
  },
  encrypt: (key, plaintext, remaining) => callEncryptMessage(
    bridge: bridge,
    recipientMlKemPublicKey: key,
    plaintext: plaintext,
    timeout: remaining < const Duration(seconds: 10)
        ? remaining
        : const Duration(seconds: 10),
  ),
  store: (peer, wire, remaining) {
    if (service is! AckOrExpiryInboxStore) {
      throw const NotificationDualPathFailure('custody_unavailable');
    }
    return (service as AckOrExpiryInboxStore).storeInAckCustodyInboxDetailed(
      peer,
      wire,
      custodyKind: AckCustodyKind.directTextV108,
      timeoutMs: remaining.inMilliseconds,
    );
  },
  sendLive: (peer, wire, remaining) => service.sendMessageWithReply(
    peer,
    wire,
    timeoutMs: remaining.inMilliseconds,
  ),
);

/// Only an exact request-owned control is removed; another action's file is
/// never erased by a retired action. The control contains hashes, never wire.
final class NotificationDualPathFileControl {
  NotificationDualPathFileControl(this.file);
  final File file;
  Future<Map<String, dynamic>?> read() async {
    if (!await file.exists()) return null;
    if (await file.length() > 4096) {
      throw const NotificationDualPathFailure('control_malformed');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const NotificationDualPathFailure('control_malformed');
    }
    return decoded;
  }

  Future<void> cleanup(NotificationDualPathRequest request) async {
    final control = await read();
    if (control != null && request.owns(control)) await file.delete();
  }
}

Map<String, Object?> notificationDualPathFailureReceipt(
  Map<String, dynamic> config,
  Object error,
) => {
  'schema': notificationDualPathSenderSchema,
  'status': 'failed',
  'success': false,
  for (final key in ['stepId', 'runId', 'nonce', 'targetPeerId'])
    key:
        config[key] is String &&
            RegExp(r'^[a-zA-Z0-9._:-]{1,160}$').hasMatch(config[key] as String)
        ? config[key]
        : 'invalid',
  'errorCode': error is NotificationDualPathFailure
      ? error.code
      : 'operation_failed',
  if (error is NotificationDualPathFailure && error.cleanupErrorCode != null)
    'cleanupErrorCode': error.cleanupErrorCode,
};
