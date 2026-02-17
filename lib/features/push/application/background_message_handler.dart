import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_BACKGROUND_MESSAGE_RECEIVED',
    details: {
      'messageId': message.messageId,
      'dataKeys': message.data.keys.toList(),
      'note': 'inbox drain deferred to next app resume',
    },
  );
}
