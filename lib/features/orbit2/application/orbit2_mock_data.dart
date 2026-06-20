import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';

import '../domain/models/avatar_tier.dart';
import '../domain/models/orbit2_friend.dart';
import '../domain/models/orbit2_group.dart';
import '../domain/models/orbit2_inner_item.dart';

/// One read-only row in the Messages/Inbox view: an avatar + the last incoming
/// line. [isGroup] picks the avatar/route.
class Orbit2InboxEntry {
  final String id;
  final String title;
  final bool isGroup;
  final Orbit2Friend? friend;
  final Orbit2Group? group;
  final Orbit2ChatLine lastLine;
  const Orbit2InboxEntry({
    required this.id,
    required this.title,
    required this.isGroup,
    required this.lastLine,
    this.friend,
    this.group,
  });
}

/// One line in a mock conversation (no transport / no real time). In a group,
/// [senderName] names the member who sent an incoming line.
class Orbit2ChatLine {
  final String text;
  final bool isMe;
  final String timeLabel;
  final String? senderName;
  const Orbit2ChatLine({
    required this.text,
    required this.isMe,
    required this.timeLabel,
    this.senderName,
  });
}

/// A disjoint mock population: the Inner Circle (top friends), the floating
/// canvas (the wider circle), and a couple of mock groups. Visuals-only.
class Orbit2MockSet {
  final List<OrbitFriend> innerCircle;
  final List<Orbit2Friend> canvas;
  final List<Orbit2Group> groups;
  const Orbit2MockSet({
    required this.innerCircle,
    required this.canvas,
    required this.groups,
  });
}

abstract final class Orbit2MockData {
  /// Names for the Inner Circle (your closest). >13 so the overflow shows.
  static const List<String> _innerNames = [
    'Layla', 'Karim', 'Mina', 'Tariq', 'Sara', 'Hadi', 'Dana', 'Faris',
    'Rana', 'Sami', 'Lina', 'Zaid', 'Hana', 'Yara', 'Nael', 'Reem',
  ];

  /// Pool for the floating canvas (the wider circle). The long name exercises
  /// label clamping.
  static const List<String> _canvasNames = [
    'Maya', 'Idris', 'Lena', 'Abdurrahman Al-Mansouri', 'Omar', 'Sofia',
    'Yuki', 'Theo', 'Noor', 'Bao', 'Aria', 'Priya', 'Elena', 'Marcus',
    'Jin', 'Salma', 'Tom', 'Nadia', 'Kofi', 'Ines', 'Rui', 'Vera',
    'Hugo', 'Mira',
  ];

  static OrbitFriend _orbitFriend(String slug, String name, int messageCount) {
    return OrbitFriend(
      contact: ContactModel(
        peerId: 'orbit2-$slug',
        publicKey: 'pk-$slug',
        rendezvous: '/ip4/127.0.0.1/tcp/4001',
        username: name,
        signature: 'sig-$slug',
        scannedAt: '2026-01-10T10:00:00.000Z',
      ),
      messageCount: messageCount,
    );
  }

  /// Builds the mock set. [canvasCount] controls how many floating friends are
  /// shown (for the "feel the scale" toggle); clamped to the available pool.
  static Orbit2MockSet build({int canvasCount = 11}) {
    final innerCircle = <OrbitFriend>[];
    for (var i = 0; i < _innerNames.length; i++) {
      innerCircle.add(_orbitFriend('inner-$i', _innerNames[i], 200 - i * 6));
    }

    final count = canvasCount.clamp(0, _canvasNames.length);
    final canvas = <Orbit2Friend>[];
    for (var i = 0; i < count; i++) {
      final tier = (i % 3 == 0) ? AvatarTier.sizeA : AvatarTier.sizeB;
      final messageCount = tier == AvatarTier.sizeA ? 40 - i : 8;
      canvas.add(
        Orbit2Friend(
          friend: _orbitFriend('canvas-$i', _canvasNames[i], messageCount),
          tier: tier,
        ),
      );
    }

    return Orbit2MockSet(
      innerCircle: innerCircle,
      canvas: canvas,
      groups: _buildGroups(),
    );
  }

  static Orbit2Friend _member(String slug, String name) => Orbit2Friend(
        friend: _orbitFriend('grp-$slug', name, 0),
        tier: AvatarTier.sizeB,
      );

  static List<Orbit2Group> _buildGroups() => [
        Orbit2Group(
          id: 'orbit2-group-trip',
          name: 'Weekend Trip',
          members: [
            _member('t1', 'Tess'),
            _member('t2', 'Omar'),
            _member('t3', 'Kim'),
          ],
        ),
        Orbit2Group(
          id: 'orbit2-group-work',
          name: 'Work Crew',
          members: [
            _member('w1', 'Dana'),
            _member('w2', 'Sam'),
          ],
        ),
      ];

  /// A STABLE, deterministic variant index for a key (NOT String.hashCode,
  /// which is not guaranteed stable across release builds).
  static int _variantOf(String key, int mod) {
    var sum = 0;
    for (final c in key.codeUnits) {
      sum += c;
    }
    return sum % mod;
  }

  /// A per-group sample thread (members as senders). The last line's time label
  /// varies by group so the inbox has a real recency gradient.
  static List<Orbit2ChatLine> groupThread(Orbit2Group group) {
    final m = group.members;
    final n1 = m.isNotEmpty ? m[0].username : 'Sam';
    final n2 = m.length > 1 ? m[1].username : 'Alex';
    final lastLabel = _variantOf(group.id, 2) == 0 ? 'now' : '14:30';
    return [
      Orbit2ChatLine(senderName: n1, text: 'hey everyone! 👋', isMe: false, timeLabel: '10:01'),
      Orbit2ChatLine(senderName: n2, text: 'morning all', isMe: false, timeLabel: '10:02'),
      const Orbit2ChatLine(text: 'morning! ☕', isMe: true, timeLabel: '10:03'),
      Orbit2ChatLine(senderName: n1, text: 'are we still on for Saturday? 🏔️', isMe: false, timeLabel: lastLabel),
    ];
  }

  /// A per-friend distinct sample thread (3 canned variants, stable by peerId).
  /// The variants end at different time labels ('now' / 'HH:MM' / weekday) so
  /// the inbox's recency ordering does real work.
  static List<Orbit2ChatLine> thread(Orbit2Friend friend) {
    final variant = _variantOf(friend.peerId, 3);
    switch (variant) {
      case 0:
        return const [
          Orbit2ChatLine(text: 'morning ☀️', isMe: false, timeLabel: '09:02'),
          Orbit2ChatLine(text: 'morning! how did it go yesterday?', isMe: true, timeLabel: '09:05'),
          Orbit2ChatLine(text: 'really well actually', isMe: false, timeLabel: '09:06'),
          Orbit2ChatLine(text: 'so… are we still on for tonight?', isMe: false, timeLabel: 'now'),
        ];
      case 1:
        return const [
          Orbit2ChatLine(text: 'did you get the photos?', isMe: false, timeLabel: '12:40'),
          Orbit2ChatLine(text: 'not yet — resend?', isMe: true, timeLabel: '12:41'),
          Orbit2ChatLine(text: 'sent a photo 📷', isMe: false, timeLabel: '12:45'),
        ];
      default:
        return const [
          Orbit2ChatLine(text: 'hey, long time!', isMe: false, timeLabel: 'Sun'),
          Orbit2ChatLine(text: 'I know! how are you?', isMe: true, timeLabel: 'Sun'),
          Orbit2ChatLine(text: 'we should catch up properly soon', isMe: false, timeLabel: 'Mon'),
        ];
    }
  }

  /// The last line of a friend's / group's thread (the inbox preview).
  static Orbit2ChatLine latestLine(Orbit2Friend friend) => thread(friend).last;
  static Orbit2ChatLine latestGroupLine(Orbit2Group group) =>
      groupThread(group).last;

  static final RegExp _clockLabel = RegExp(r'^\d{1,2}:\d{2}$');

  /// A synthetic recency rank over the static [timeLabel]: 'now' (0) is most
  /// recent, an 'HH:MM' clock time (1) next, a weekday/older label (2) last.
  /// This is an HONEST, documented order over mock data — not a real timestamp.
  static int recencyRank(Orbit2ChatLine line) {
    if (line.timeLabel == 'now') return 0;
    if (_clockLabel.hasMatch(line.timeLabel)) return 1;
    return 2;
  }

  /// Builds the Messages/Inbox rows from the live populations, de-duped by id
  /// and ordered by (recency, then title) — deterministic, no real time.
  static List<Orbit2InboxEntry> inboxEntries({
    required List<Orbit2InnerItem> inner,
    required List<Orbit2Friend> canvas,
    required List<Orbit2Group> groups,
  }) {
    final seen = <String>{};
    final entries = <Orbit2InboxEntry>[];

    void addFriend(Orbit2Friend f) {
      if (!seen.add(f.peerId)) return;
      entries.add(Orbit2InboxEntry(
        id: f.peerId,
        title: f.username,
        isGroup: false,
        friend: f,
        lastLine: latestLine(f),
      ));
    }

    void addGroup(Orbit2Group g) {
      if (!seen.add(g.id)) return;
      entries.add(Orbit2InboxEntry(
        id: g.id,
        title: g.name,
        isGroup: true,
        group: g,
        lastLine: latestGroupLine(g),
      ));
    }

    for (final it in inner) {
      if (it.isGroup) {
        addGroup(it.group!);
      } else {
        addFriend(Orbit2Friend(friend: it.friend!, tier: AvatarTier.sizeA));
      }
    }
    for (final f in canvas) {
      addFriend(f);
    }
    for (final g in groups) {
      addGroup(g);
    }

    entries.sort((a, b) {
      final r = recencyRank(a.lastLine).compareTo(recencyRank(b.lastLine));
      return r != 0 ? r : a.title.compareTo(b.title);
    });
    return entries;
  }
}
