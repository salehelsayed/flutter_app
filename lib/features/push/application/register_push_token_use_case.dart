import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

enum RegisterPushTokenResult { success, noToken, failed }

Future<RegisterPushTokenResult> registerPushToken({
  required P2PService p2pService,
  Future<String?> Function()? getTokenFn,
  String Function()? getPlatformFn,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_REGISTER_TOKEN_BEGIN',
    details: {},
  );

  final effectiveGetPlatform = getPlatformFn ?? () => Platform.isIOS ? 'ios' : 'android';

  // On iOS, the APNS token must be available before FCM can issue a token.
  // Poll briefly to give the OS time to deliver the APNS token after
  // the user grants notification permission.
  if (getTokenFn == null && Platform.isIOS) {
    String? apnsToken;
    for (var i = 0; i < 10; i++) {
      apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      if (apnsToken != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (apnsToken == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_APNS_TOKEN_UNAVAILABLE',
        details: {'waitedMs': 5000},
      );
      return RegisterPushTokenResult.noToken;
    }
  }

  final effectiveGetToken = getTokenFn ?? () => FirebaseMessaging.instance.getToken();
  final token = await effectiveGetToken();
  if (token == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_REGISTER_TOKEN_NO_TOKEN',
      details: {},
    );
    return RegisterPushTokenResult.noToken;
  }

  final platform = effectiveGetPlatform();

  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_REGISTER_TOKEN_SENDING',
    details: {'platform': platform, 'tokenLength': token.length},
  );

  final ok = await p2pService.registerPushToken(token, platform);

  emitFlowEvent(
    layer: 'FL',
    event: ok ? 'PUSH_REGISTER_TOKEN_SUCCESS' : 'PUSH_REGISTER_TOKEN_FAILED',
    details: {'platform': platform},
  );

  return ok ? RegisterPushTokenResult.success : RegisterPushTokenResult.failed;
}
