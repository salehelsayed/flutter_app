/// The newest eligible live thought for one Orbit friend.
///
/// The host owns author eligibility and read state; the surface additionally
/// enforces [expiresAt] so a delayed cleanup sweep cannot leave a stale note.
class OrbitThoughtNote {
  final String postId;
  final String text;
  final bool isRead;
  final DateTime expiresAt;

  const OrbitThoughtNote({
    required this.postId,
    required this.text,
    required this.isRead,
    required this.expiresAt,
  });
}
