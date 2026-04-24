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
