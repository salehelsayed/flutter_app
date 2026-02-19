import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

enum RegisterPushTokenResult { success, noToken, failed }

Future<RegisterPushTokenResult> registerPushToken({
  required P2PService p2pService,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_REGISTER_TOKEN_BEGIN',
    details: {},
  );

  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_REGISTER_TOKEN_NO_TOKEN',
      details: {},
    );
    return RegisterPushTokenResult.noToken;
  }

  final platform = Platform.isIOS ? 'ios' : 'android';

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
