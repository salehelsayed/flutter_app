import 'orbit2_friend.dart';

/// A mock group chat ("orbit") on the floating canvas — a cluster of members.
/// Visuals-only: no backend, no real membership.
class Orbit2Group {
  final String id;
  final String name;
  final List<Orbit2Friend> members;

  const Orbit2Group({
    required this.id,
    required this.name,
    required this.members,
  });
}
