enum PostOriginKind { direct, pass }

class PostOriginModel {
  final String postId;
  final PostOriginKind originKind;
  final String? passId;
  final String? passerPeerId;
  final String? passerUsername;
  final String? passCreatedAt;

  const PostOriginModel({
    required this.postId,
    required this.originKind,
    this.passId,
    this.passerPeerId,
    this.passerUsername,
    this.passCreatedAt,
  });

  factory PostOriginModel.fromMap(Map<String, Object?> map) {
    final originValue = map['origin_kind'] as String? ?? 'direct';
    return PostOriginModel(
      postId: map['post_id'] as String,
      originKind: originValue == 'pass'
          ? PostOriginKind.pass
          : PostOriginKind.direct,
      passId: map['pass_id'] as String?,
      passerPeerId: map['passer_peer_id'] as String?,
      passerUsername: map['passer_username'] as String?,
      passCreatedAt: map['pass_created_at'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'post_id': postId,
      'origin_kind': originKind == PostOriginKind.pass ? 'pass' : 'direct',
      'pass_id': passId,
      'passer_peer_id': passerPeerId,
      'passer_username': passerUsername,
      'pass_created_at': passCreatedAt,
    };
  }
}
