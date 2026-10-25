import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';

final depthNow = DateTime.utc(2026, 10, 24, 12);
OrbitFriend depthFriend(int i) => OrbitFriend(
  contact: ContactModel(
    peerId: 'peer-$i',
    publicKey: 'pk',
    rendezvous: '',
    username: 'Friend $i',
    signature: '',
    scannedAt: depthNow.toIso8601String(),
  ),
  messageCount: 0,
);
PostModel depthThought(
  int i, {
  bool read = false,
  String? id,
  DateTime? expiry,
  String mediaKind = 'none',
  String? text,
}) => PostModel(
  id: id ?? 'post-$i',
  eventId: 'event-$i',
  senderPeerId: 'peer-$i',
  authorPeerId: 'peer-$i',
  authorUsername: 'Friend $i',
  text: text ?? 'Thought $i',
  audience: PostAudience.allFriends(),
  createdAt: depthNow.subtract(const Duration(minutes: 7)).toIso8601String(),
  visibleAt: depthNow.toIso8601String(),
  expiresAt: (expiry ?? depthNow.add(const Duration(hours: 2)))
      .toIso8601String(),
  isRead: read,
  mediaKind: mediaKind,
);
