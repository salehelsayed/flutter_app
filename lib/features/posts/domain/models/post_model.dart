import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';

class PostModel {
  final String id;
  final String eventId;
  final String senderPeerId;
  final String authorPeerId;
  final String authorUsername;
  final String text;
  final PostAudience audience;
  final String createdAt;
  final String visibleAt;
  final String expiresAt;
  final String? lastEngagementAt;
  final bool keepAvailable;
  final String mediaKind;
  final List<PostMediaAttachmentModel> media;
  final int commentCount;
  final int heartCount;
  final bool viewerHasHearted;
  final int? nearbyDistanceM;
  final int? nearbySenderLatE3;
  final int? nearbySenderLngE3;
  final String? nearbySenderCapturedAt;
  final double? nearbySenderAccuracyM;
  final String? nearbyDistanceLabel;
  final bool isIncoming;
  final bool isFocused;
  final String deliveryStatus;
  final String? passedByPeerId;
  final String? passedByUsername;
  final String? passedAt;
  final int shareCount;

  const PostModel({
    required this.id,
    required this.eventId,
    required this.senderPeerId,
    required this.authorPeerId,
    required this.authorUsername,
    required this.text,
    required this.audience,
    required this.createdAt,
    required this.visibleAt,
    required this.expiresAt,
    this.lastEngagementAt,
    this.keepAvailable = false,
    this.mediaKind = 'none',
    this.media = const <PostMediaAttachmentModel>[],
    this.commentCount = 0,
    this.heartCount = 0,
    this.viewerHasHearted = false,
    this.nearbyDistanceM,
    this.nearbySenderLatE3,
    this.nearbySenderLngE3,
    this.nearbySenderCapturedAt,
    this.nearbySenderAccuracyM,
    this.nearbyDistanceLabel,
    this.isIncoming = true,
    this.isFocused = false,
    this.deliveryStatus = 'available',
    this.passedByPeerId,
    this.passedByUsername,
    this.passedAt,
    this.shareCount = 0,
  });

  factory PostModel.fromMap(Map<String, Object?> map) {
    return PostModel(
      id: map['post_id'] as String,
      eventId: map['event_id'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      authorPeerId: map['author_peer_id'] as String,
      authorUsername: map['author_username'] as String,
      text: map['text'] as String? ?? '',
      audience: PostAudience.fromMap(map),
      createdAt: map['post_created_at'] as String,
      visibleAt:
          map['visible_at'] as String? ?? map['post_created_at'] as String,
      expiresAt: map['expires_at'] as String,
      lastEngagementAt: map['last_engagement_at'] as String?,
      keepAvailable: (map['keep_available'] as int? ?? 0) == 1,
      mediaKind: map['media_kind'] as String? ?? 'none',
      commentCount: map['comment_count'] as int? ?? 0,
      heartCount: map['heart_count'] as int? ?? 0,
      viewerHasHearted: (map['viewer_has_hearted'] as int? ?? 0) == 1,
      nearbyDistanceM: (map['nearby_distance_m'] as num?)?.toInt(),
      nearbySenderLatE3: map['nearby_sender_lat_e3'] as int?,
      nearbySenderLngE3: map['nearby_sender_lng_e3'] as int?,
      nearbySenderCapturedAt: map['nearby_sender_captured_at'] as String?,
      nearbySenderAccuracyM: (map['nearby_sender_accuracy_m'] as num?)
          ?.toDouble(),
      nearbyDistanceLabel: map['nearby_distance_label'] as String?,
      isIncoming: (map['is_incoming'] as int? ?? 1) == 1,
      isFocused: (map['is_focused'] as int? ?? 0) == 1,
      deliveryStatus:
          map['delivery_status'] as String? ??
          map['local_status'] as String? ??
          'available',
      passedByPeerId: map['passer_peer_id'] as String?,
      passedByUsername: map['passer_username'] as String?,
      passedAt: map['pass_created_at'] as String?,
      shareCount: (map['share_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'post_id': id,
      'event_id': eventId,
      'sender_peer_id': senderPeerId,
      'author_peer_id': authorPeerId,
      'author_username': authorUsername,
      'text': text,
      ...audience.toMap(),
      'post_created_at': createdAt,
      'visible_at': visibleAt,
      'expires_at': expiresAt,
      'last_engagement_at': lastEngagementAt,
      'keep_available': keepAvailable ? 1 : 0,
      'media_kind': mediaKind,
      'nearby_distance_m': nearbyDistanceM,
      'nearby_sender_lat_e3': nearbySenderLatE3,
      'nearby_sender_lng_e3': nearbySenderLngE3,
      'nearby_sender_captured_at': nearbySenderCapturedAt,
      'nearby_sender_accuracy_m': nearbySenderAccuracyM,
      'is_incoming': isIncoming ? 1 : 0,
      'is_focused': isFocused ? 1 : 0,
      'delivery_status': deliveryStatus,
    };
  }

  PostModel copyWith({
    String? authorUsername,
    String? text,
    PostAudience? audience,
    String? expiresAt,
    String? lastEngagementAt,
    String? mediaKind,
    List<PostMediaAttachmentModel>? media,
    int? commentCount,
    int? heartCount,
    bool? viewerHasHearted,
    int? nearbyDistanceM,
    int? nearbySenderLatE3,
    int? nearbySenderLngE3,
    String? nearbySenderCapturedAt,
    double? nearbySenderAccuracyM,
    String? nearbyDistanceLabel,
    bool? isFocused,
    String? deliveryStatus,
    String? passedByPeerId,
    String? passedByUsername,
    String? passedAt,
    int? shareCount,
  }) {
    return PostModel(
      id: id,
      eventId: eventId,
      senderPeerId: senderPeerId,
      authorPeerId: authorPeerId,
      authorUsername: authorUsername ?? this.authorUsername,
      text: text ?? this.text,
      audience: audience ?? this.audience,
      createdAt: createdAt,
      visibleAt: visibleAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastEngagementAt: lastEngagementAt ?? this.lastEngagementAt,
      keepAvailable: keepAvailable,
      mediaKind: mediaKind ?? this.mediaKind,
      media: media ?? this.media,
      commentCount: commentCount ?? this.commentCount,
      heartCount: heartCount ?? this.heartCount,
      viewerHasHearted: viewerHasHearted ?? this.viewerHasHearted,
      nearbyDistanceM: nearbyDistanceM ?? this.nearbyDistanceM,
      nearbySenderLatE3: nearbySenderLatE3 ?? this.nearbySenderLatE3,
      nearbySenderLngE3: nearbySenderLngE3 ?? this.nearbySenderLngE3,
      nearbySenderCapturedAt:
          nearbySenderCapturedAt ?? this.nearbySenderCapturedAt,
      nearbySenderAccuracyM:
          nearbySenderAccuracyM ?? this.nearbySenderAccuracyM,
      nearbyDistanceLabel: nearbyDistanceLabel ?? this.nearbyDistanceLabel,
      isIncoming: isIncoming,
      isFocused: isFocused ?? this.isFocused,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      passedByPeerId: passedByPeerId ?? this.passedByPeerId,
      passedByUsername: passedByUsername ?? this.passedByUsername,
      passedAt: passedAt ?? this.passedAt,
      shareCount: shareCount ?? this.shareCount,
    );
  }
}
