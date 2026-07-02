Map<String, dynamic> newMessageData({String senderId = 'peer-1'}) => {
  'type': 'new_message',
  'sender_id': senderId,
};

Map<String, dynamic> groupMessageData({
  String groupId = 'group-1',
  Object? messageId = 'msg-1',
}) {
  final data = <String, dynamic>{'type': 'group_message', 'groupId': groupId};
  if (messageId != null) {
    data['message_id'] = messageId;
  }
  return data;
}

Map<String, dynamic> contactRequestData({String senderId = 'peer-request-1'}) =>
    {'type': 'contact_request', 'sender_id': senderId};

Map<String, dynamic> introsData() => {'type': 'intros'};

Map<String, dynamic> groupInviteData({String groupId = 'group-1'}) => {
  'type': 'group_invite',
  'groupId': groupId,
};

Map<String, dynamic> postCreateData({String postId = 'post-1'}) => {
  'type': 'post_create',
  'post_id': postId,
};

Map<String, dynamic> payloadOnlyGroupData({String groupId = 'group-1'}) => {
  'payload': 'group:$groupId',
};

// 191: the RemoteMessage.data map EXACTLY as FLTFirebaseMessagingPlugin 15.2.10
// delivers a foreground remote message to Dart's FirebaseMessaging.onMessage —
// the flat custom key/value pairs the relay put in the APNs payload (`aps`
// stripped; `gcm.message_id` surfaced separately as RemoteMessage.messageId).
// This is the shape the AppDelegate willPresent forward (Fix N1) makes reachable.
Map<String, dynamic> pluginCanonicalNewMessageData({
  String senderId = 'peer-apns-1',
  String messageId = 'msg-apns-1',
}) => {
  'type': 'new_message',
  'sender_id': senderId,
  'message_id': messageId,
};

Map<String, dynamic> pluginCanonicalUnroutableData({
  String postId = 'post-apns-1',
}) => {
  'type': 'post_create',
  'post_id': postId,
};
