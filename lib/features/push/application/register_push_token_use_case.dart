import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/push_diagnostics_logger.dart';
import 'package:flutter_app/features/push/domain/push_token_store.dart';

enum RegisterPushTokenResult { success, noToken, failed }

/// Timeout for waiting on [FirebaseMessaging.getAPNSToken] on iOS.
///
/// TestFlight / release builds can take noticeably longer than debug builds to
/// receive the APNs device token from the OS. Wait explicitly for APNs first
/// so FCM token lookup does not race a still-missing APNs token.
const _getApnsTokenTimeout = Duration(seconds: 15);
const _getApnsTokenPollInterval = Duration(milliseconds: 500);

/// Timeout for [FirebaseMessaging.getToken] on iOS.
///
/// On iOS, `getToken()` can block until the APNS device token is delivered
/// by the OS.  In release builds this sometimes takes much longer than in
/// debug, so we cap the wait and let the coordinator retry later — or let the
/// `onTokenRefresh` stream trigger a fresh attempt once the token is ready.
const _getTokenTimeout = Duration(seconds: 15);

Future<RegisterPushTokenResult> registerPushToken({
  required P2PService p2pService,
  PushTokenStore? pushTokenStore,
  Future<String?> Function()? getTokenFn,
  Future<String?> Function()? getApnsTokenFn,
  Future<String?> Function(
    Future<String?> Function() getToken,
    Duration timeout,
  )?
  getTokenWithTimeoutFn,
  String Function()? getPlatformFn,
  bool Function()? isIOSFn,
  Duration getApnsTokenTimeout = _getApnsTokenTimeout,
  Duration getApnsTokenPollInterval = _getApnsTokenPollInterval,
  Duration getTokenTimeout = _getTokenTimeout,
  DateTime Function()? nowFn,
  Future<void> Function(Duration duration)? delayFn,
}) async {
  final platform =
      (getPlatformFn ?? () => Platform.isIOS ? 'ios' : 'android')();
  logPushDiagnostic('register_token_begin', details: {'platform': platform});
  emitFlowEvent(layer: 'FL', event: 'PUSH_REGISTER_TOKEN_BEGIN', details: {});

  final effectiveGetPlatform =
      getPlatformFn ?? () => Platform.isIOS ? 'ios' : 'android';
  final effectiveIsIOS = isIOSFn ?? () => Platform.isIOS;
  final effectiveGetApnsToken =
      getApnsTokenFn ?? () => FirebaseMessaging.instance.getAPNSToken();

  final effectiveGetToken =
      getTokenFn ?? () => FirebaseMessaging.instance.getToken();
  final effectiveGetTokenWithTimeout =
      getTokenWithTimeoutFn ?? _getTokenWithTimeout;

  if (effectiveIsIOS()) {
    final apnsToken = await _waitForApnsToken(
      getApnsToken: effectiveGetApnsToken,
      timeout: getApnsTokenTimeout,
      pollInterval: getApnsTokenPollInterval,
      nowFn: nowFn,
      delayFn: delayFn,
    );
    if (apnsToken == null) {
      logPushDiagnostic(
        'apns_token_missing',
        details: {
          'platform': effectiveGetPlatform(),
          'timeoutMs': getApnsTokenTimeout.inMilliseconds,
        },
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_REGISTER_TOKEN_NO_APNS',
        details: {
          'platform': effectiveGetPlatform(),
          'timeoutMs': getApnsTokenTimeout.inMilliseconds,
        },
      );
      return RegisterPushTokenResult.noToken;
    }

    logPushDiagnostic(
      'apns_token_ready',
      details: {
        'platform': effectiveGetPlatform(),
        'token': summarizePushToken(apnsToken),
      },
    );
  }

  // On iOS, getToken() may block waiting for the APNS device token.
  // Apply a timeout so we don't hang forever — the coordinator will
  // retry, and the onTokenRefresh stream will trigger when the token
  // eventually becomes available.
  String? token;
  try {
    if (effectiveIsIOS()) {
      // On iOS, getToken() can block waiting for the APNS device token.
      // Cap the wait so we don't hang forever.
      token = await effectiveGetTokenWithTimeout(
        effectiveGetToken,
        getTokenTimeout,
      );
    } else {
      token = await effectiveGetToken();
    }
  } catch (_) {
    token = null;
  }

  if (token == null) {
    logPushDiagnostic(
      'fcm_token_missing',
      details: {'platform': effectiveGetPlatform()},
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_REGISTER_TOKEN_NO_TOKEN',
      details: {'platform': effectiveGetPlatform()},
    );
    return RegisterPushTokenResult.noToken;
  }

  final registeredPlatform = effectiveGetPlatform();

  logPushDiagnostic(
    'fcm_token_ready',
    details: {
      'platform': registeredPlatform,
      'token': summarizePushToken(token),
    },
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_REGISTER_TOKEN_SENDING',
    details: {'platform': registeredPlatform, 'tokenLength': token.length},
  );

  final ok = await p2pService.registerPushToken(token, registeredPlatform);

  logPushDiagnostic(
    ok ? 'relay_push_registration_success' : 'relay_push_registration_failed',
    details: {'platform': registeredPlatform},
  );

  emitFlowEvent(
    layer: 'FL',
    event: ok ? 'PUSH_REGISTER_TOKEN_SUCCESS' : 'PUSH_REGISTER_TOKEN_FAILED',
    details: {'platform': registeredPlatform},
  );

  if (!ok) {
    return RegisterPushTokenResult.failed;
  }

  if (pushTokenStore != null) {
    try {
      await pushTokenStore.writeToken(token, registeredPlatform);
      logPushDiagnostic(
        'push_token_persisted',
        details: {'platform': registeredPlatform},
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_REGISTER_TOKEN_PERSISTED',
        details: {'platform': registeredPlatform},
      );
    } catch (e) {
      logPushDiagnostic(
        'push_token_persist_failed',
        details: {'platform': registeredPlatform, 'error': e.toString()},
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_REGISTER_TOKEN_PERSIST_FAILED',
        details: {'platform': registeredPlatform, 'error': e.toString()},
      );
      return RegisterPushTokenResult.failed;
    }
  }

  return RegisterPushTokenResult.success;
}

Future<String?> _waitForApnsToken({
  required Future<String?> Function() getApnsToken,
  required Duration timeout,
  required Duration pollInterval,
  DateTime Function()? nowFn,
  Future<void> Function(Duration duration)? delayFn,
}) async {
  final effectiveNow = nowFn ?? DateTime.now;
  final effectiveDelay = delayFn ?? Future<void>.delayed;
  final deadline = effectiveNow().add(timeout);

  while (true) {
    try {
      final token = await getApnsToken();
      if (token != null && token.isNotEmpty) {
        return token;
      }
    } catch (_) {}

    final remaining = deadline.difference(effectiveNow());
    if (remaining <= Duration.zero) {
      return null;
    }

    final delay = remaining < pollInterval ? remaining : pollInterval;
    await effectiveDelay(delay);
  }
}

Future<String?> _getTokenWithTimeout(
  Future<String?> Function() getToken,
  Duration timeout,
) {
  return getToken().timeout(timeout, onTimeout: () => null);
}
