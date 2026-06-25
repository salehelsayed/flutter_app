import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit2/domain/models/avatar_tier.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_friend.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_group.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';

/// Deterministic mock population for the Orbit3 "One Circle" prototype.
///
/// Reuses the shared [OrbitFriend] / [Orbit2InnerItem] / [Orbit2Group] models so
/// Orbit3 can render with the same avatar leaf widgets as Orbit2, but owns its
/// own generator so it can reach the ~50-member target the One Circle exists to
/// exercise (Orbit2's mock caps far below that).
abstract final class Orbit3MockData {
  /// A deep, distinct name pool (>= the 50 target). The first two entries never
  /// substring-collide, so search/glow tests can match one without the other.
  static const List<String> _names = [
    'Layla', 'Karim', 'Mina', 'Tariq', 'Sara', 'Hadi', 'Dana', 'Faris',
    'Rana', 'Sami', 'Lina', 'Zaid', 'Hana', 'Yara', 'Nael', 'Reem',
    'Maya', 'Idris', 'Lena', 'Omar', 'Sofia', 'Yuki', 'Theo', 'Noor',
    'Bao', 'Aria', 'Priya', 'Elena', 'Marcus', 'Jin', 'Salma', 'Tom',
    'Nadia', 'Kofi', 'Ines', 'Rui', 'Vera', 'Hugo', 'Mira', 'Adam',
    'Nora', 'Zane', 'Lila', 'Emir', 'Tahir', 'Kian', 'Roya', 'Sven',
    'Yusuf', 'Dalia', 'Owen', 'Petra',
  ];

  static OrbitFriend _orbitFriend(String slug, String name, int messageCount) {
    return OrbitFriend(
      contact: ContactModel(
        peerId: 'orbit3-$slug',
        publicKey: 'pk-$slug',
        rendezvous: '/ip4/127.0.0.1/tcp/4001',
        username: name,
        signature: 'sig-$slug',
        scannedAt: '2026-01-10T10:00:00.000Z',
      ),
      messageCount: messageCount,
    );
  }

  static Orbit2Friend _member(String slug, String name) => Orbit2Friend(
        friend: _orbitFriend('grp-$slug', name, 0),
        tier: AvatarTier.sizeB,
      );

  static List<Orbit2Group> _groups() => [
        Orbit2Group(
          id: 'orbit3-group-trip',
          name: 'Weekend Trip',
          members: [
            _member('t1', 'Tess'),
            _member('t2', 'Omar'),
            _member('t3', 'Kim'),
          ],
        ),
        Orbit2Group(
          id: 'orbit3-group-work',
          name: 'Work Crew',
          members: [
            _member('w1', 'Dana'),
            _member('w2', 'Sam'),
          ],
        ),
      ];

  /// Builds exactly [count] inner-circle items: friends first (deterministic,
  /// from [_names]), then a couple of groups once the circle is big enough to
  /// be worth showing them. The total length is always [count] so the
  /// population control maps 1:1 to seated members.
  static List<Orbit2InnerItem> build({required int count}) {
    // Supports up to 100 (168 C5): names beyond the pool get a deterministic
    // 'User N' so search/glow still works and counts stay exact.
    final n = count.clamp(0, 100);
    // Show 2 groups only once the circle overflows two rings (>13); the 1-ring
    // and 2-full-ring views stay friends-only.
    final groupCount = n >= 14 ? 2 : 0;
    final friendCount = n - groupCount;

    final items = <Orbit2InnerItem>[
      for (var i = 0; i < friendCount; i++)
        Orbit2InnerItem.friend(
          _orbitFriend(
            'friend-$i',
            i < _names.length ? _names[i] : 'User ${i + 1}',
            200 - i * 3,
          ),
        ),
      for (final g in _groups().take(groupCount)) Orbit2InnerItem.group(g),
    ];
    return items;
  }
}
