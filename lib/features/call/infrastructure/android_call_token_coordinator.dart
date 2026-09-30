import 'dart:async';

import '../domain/call_authority_lifetime.dart';
import 'call_authority_client.dart';

typedef AndroidCallTokenReader = Future<String?> Function();
typedef CallTokenPublicationAllowed = Future<bool> Function();

/// One bootstrap-owned FCM token reader shared by chat and call registration.
/// A cached token can remain on the device after FCM has unregistered it. The
/// first eligible registration deletes that token before either relay route is
/// published; concurrent readers join the same replacement.
final class AndroidFcmTokenReader {
  AndroidFcmTokenReader({
    required Future<String?> Function() getToken,
    required Future<void> Function() deleteToken,
    this.rotateOnFirstRead = true,
  }) : _getToken = getToken,
       _deleteToken = deleteToken;

  final Future<String?> Function() _getToken;
  final Future<void> Function() _deleteToken;
  final bool rotateOnFirstRead;
  Future<String?>? _firstRead;
  bool _firstReadSettled = false;

  Future<String?> read() {
    final firstRead = _firstRead;
    if (firstRead != null) {
      return _firstReadSettled ? _getToken() : firstRead;
    }
    return _firstRead = _readFirst();
  }

  Future<String?> _readFirst() async {
    try {
      if (rotateOnFirstRead) await _deleteToken();
      final token = await _getToken();
      _firstReadSettled = true;
      return token;
    } catch (_) {
      // A transient Firebase failure must leave the replacement retryable.
      _firstRead = null;
      rethrow;
    }
  }
}

/// Outcome wire names: `published`, `no_token`, `deferred`,
/// `rejected`, `failed`.
typedef AndroidCallTokenResultObserver = void Function(String outcome);

/// Publishes the device's FCM token to the relay's call authority as the
/// `standard_call` token: the only route the relay has to wake an Android
/// callee whose live connection is gone. Mirrors the iOS VoIP token
/// coordinator without its epoch machinery, because a standard token carries
/// no environment, topic or refresh epoch (the relay's `validCallTokenFields`).
///
/// The token is never revoked on close. The relay must keep waking the app
/// after the process is gone; that is the whole point of the record.
final class AndroidCallTokenCoordinator {
  AndroidCallTokenCoordinator({
    required CallAuthorityClient authorityClient,
    required DateTime Function() clock,
    required AndroidCallTokenReader readToken,
    required Stream<String> tokenRefreshes,
    required CallTokenPublicationAllowed publicationAllowed,
    this.registrationTtl = callBackgroundReachabilityLifetime,
    AndroidCallTokenResultObserver? onResult,
  }) : _authorityClient = authorityClient,
       _clock = clock,
       _readToken = readToken,
       _tokenRefreshes = tokenRefreshes,
       _publicationAllowed = publicationAllowed,
       _onResult = onResult;

  final CallAuthorityClient _authorityClient;
  final DateTime Function() _clock;
  final AndroidCallTokenReader _readToken;
  final Stream<String> _tokenRefreshes;
  final CallTokenPublicationAllowed _publicationAllowed;
  final AndroidCallTokenResultObserver? _onResult;

  /// How long one publication stays valid on the relay. Every start, resume or
  /// advertisement republishes it because a failed wake may revoke the record
  /// without notifying this process.
  final Duration registrationTtl;

  Future<void>? _startFuture;
  StreamSubscription<String>? _refreshes;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  /// Completes once every publication issued so far has settled, including
  /// one a refresh event enqueued just before this was read.
  Future<void> get settled async {
    await Future<void>.delayed(Duration.zero);
    await _tail;
  }

  /// Subscribes to token refreshes and publishes the current token once.
  Future<void> start() => _startFuture ??= _startOnce();

  Future<void> _startOnce() async {
    if (_closed) return;
    await ensurePublished();
  }

  /// Subscribes to token refreshes. A stream that throws on `listen` (Firebase
  /// not initialised yet, or absent on a test host) is not a call failure:
  /// the subscription is retried on every later publication attempt, and the
  /// next start, resume or advertisement publishes the current token anyway.
  void _ensureListening() {
    if (_closed || _refreshes != null) return;
    try {
      _refreshes = _tokenRefreshes.listen(
        (token) => _enqueue(() => _publish(token)),
        onError: (Object _) {},
      );
    } catch (_) {
      _refreshes = null;
    }
  }

  /// Publishes the current token again even if it has not changed. A previous
  /// success says nothing about whether the relay still has the record.
  /// Never throws: the endpoint advertisement must not depend on it.
  Future<bool> ensurePublished() {
    if (_closed) return Future<bool>.value(false);
    _ensureListening();
    return _enqueue(() async {
      if (!await _allowed()) {
        _report('deferred');
        return false;
      }
      String? token;
      try {
        token = await _readToken();
      } catch (_) {
        token = null;
      }
      if (token == null || token.trim().isEmpty) {
        _report('no_token');
        return false;
      }
      return _publish(token);
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final refreshes = _refreshes;
    _refreshes = null;
    await refreshes?.cancel();
    await _tail;
  }

  Future<bool> _allowed() async {
    try {
      return await _publicationAllowed();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _enqueue(Future<bool> Function() action) {
    final run = _tail.then<bool>((_) => action());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<bool> _publish(String token) async {
    if (_closed) return false;
    final now = _clock();
    try {
      final publication = await _authorityClient.publishToken(
        CallTokenRecord(
          kind: CallTokenKind.standardCall,
          platform: CallEndpointPlatform.android,
          token: token,
          expiresAtMs: now.add(registrationTtl).millisecondsSinceEpoch,
        ),
      );
      if (!publication.accepted) {
        _report('rejected');
        return false;
      }
      _report('published');
      return true;
    } catch (_) {
      _report('failed');
      return false;
    }
  }

  void _report(String outcome) {
    try {
      _onResult?.call(outcome);
    } catch (_) {
      // Diagnostics never disturb the publication.
    }
  }
}
