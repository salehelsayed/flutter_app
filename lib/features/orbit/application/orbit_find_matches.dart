import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart';

/// 198 "Sculpt & Summon" — pure find/summon matcher over the merged
/// inner-circle items (friends AND groups). A trimmed, case-insensitive
/// substring on the display name lights every match in place and chips the
/// first four in merged-recency order with ring/arc provenance. It never
/// expands overflow and never mutates the all-chats list projection.

/// The display name a find query matches against.
String orbitItemDisplayName(OrbitItem item) => switch (item) {
      OrbitFriendItem(:final friend) => friend.username,
      OrbitGroupItem(:final group) => group.name,
    };

/// A single chip in the find strip.
class OrbitFindMatch {
  /// Index into the merged inner-circle item list.
  final int index;
  final OrbitItem item;
  final OrbitProvenance provenance;

  const OrbitFindMatch({
    required this.index,
    required this.item,
    required this.provenance,
  });
}

/// The outcome of a find query.
class OrbitFindResult {
  /// True only when the trimmed query is non-empty.
  final bool active;

  /// Indices of every lit (matching) member.
  final Set<int> litIndices;

  /// First four matches in merged-recency order.
  final List<OrbitFindMatch> chips;

  const OrbitFindResult({
    required this.active,
    required this.litIndices,
    required this.chips,
  });

  static const OrbitFindResult inactive =
      OrbitFindResult(active: false, litIndices: <int>{}, chips: <OrbitFindMatch>[]);

  bool get hasMatches => litIndices.isNotEmpty;
}

/// Max chips shown at once.
const int kOrbitFindChipCap = 4;

/// Lights every item whose display name contains the trimmed, case-insensitive
/// [query], and chips the first [kOrbitFindChipCap] in the caller's
/// merged-recency order with layout provenance. An empty/whitespace query
/// yields [OrbitFindResult.inactive].
OrbitFindResult computeOrbitFind({
  required List<OrbitItem> items,
  required String query,
  required OrbitGeometryPrefs geometry,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return OrbitFindResult.inactive;

  final lit = <int>{};
  final chips = <OrbitFindMatch>[];
  for (var i = 0; i < items.length; i++) {
    if (!orbitItemDisplayName(items[i]).toLowerCase().contains(q)) continue;
    lit.add(i);
    if (chips.length < kOrbitFindChipCap) {
      chips.add(OrbitFindMatch(
        index: i,
        item: items[i],
        provenance: orbitProvenanceOf(geometry, i),
      ));
    }
  }
  return OrbitFindResult(active: true, litIndices: lit, chips: chips);
}
