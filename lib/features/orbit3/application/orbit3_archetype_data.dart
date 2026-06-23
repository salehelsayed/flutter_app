import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_connection_profile.dart';

/// Five sample interaction histories whose constellation fingerprints look
/// OBVIOUSLY different — the prototype's way of showing "each person, through
/// their own interactions, sees their own pattern". Every field is a pure
/// function of a stable per-member slug (via [orbit3Hash]), so the same
/// archetype always renders the same fingerprint.
enum Orbit3Archetype { connector, chatterbox, listener, oldSoul, newArrival }

extension Orbit3ArchetypeLabel on Orbit3Archetype {
  String get label => switch (this) {
        Orbit3Archetype.connector => 'Connector',
        Orbit3Archetype.chatterbox => 'Chatterbox',
        Orbit3Archetype.listener => 'Listener',
        Orbit3Archetype.oldSoul => 'Old Soul',
        Orbit3Archetype.newArrival => 'New Arrival',
      };

  /// A one-line read of what the fingerprint shows, surfaced under the dial.
  String get blurb => switch (this) {
        Orbit3Archetype.connector =>
          'Hub-recruited: most friends arrived through one super-introducer.',
        Orbit3Archetype.chatterbox =>
          'A few loud outgoing threads — big, bright, coral.',
        Orbit3Archetype.listener =>
          'You mostly receive — the same giants, but cool teal.',
        Orbit3Archetype.oldSoul =>
          'A small, ancient, balanced inner circle.',
        Orbit3Archetype.newArrival =>
          'Young, sparse and intro-heavy — a network still forming.',
      };
}

/// Deterministic population builder for the Orbit3 constellation modes. Mirrors
/// orbit3_mock_data.dart's abstract-final + name-pool + factory style, but emits
/// [Orbit3ConnectionProfile]s carrying the full metric record.
abstract final class Orbit3ArchetypeData {
  static const List<String> _names = [
    'Layla', 'Karim', 'Mina', 'Tariq', 'Sara', 'Hadi', 'Dana', 'Faris',
    'Rana', 'Sami', 'Lina', 'Zaid', 'Hana', 'Yara', 'Nael', 'Reem',
    'Maya', 'Idris', 'Lena', 'Omar', 'Sofia', 'Yuki', 'Theo', 'Noor',
    'Bao', 'Aria', 'Priya', 'Elena', 'Marcus', 'Jin', 'Salma', 'Tom',
    'Nadia', 'Kofi', 'Ines', 'Rui', 'Vera', 'Hugo', 'Mira', 'Adam',
  ];

  static int _h(String slug, int salt) => orbit3Hash(slug, salt);

  static Orbit2InnerItem _item(String slug, String name, int volume) {
    return Orbit2InnerItem.friend(OrbitFriend(
      contact: ContactModel(
        peerId: 'orbit3-star-$slug',
        publicKey: 'pk-$slug',
        rendezvous: '/ip4/127.0.0.1/tcp/4001',
        username: name,
        signature: 'sig-$slug',
        scannedAt: '2026-01-10T10:00:00.000Z',
      ),
      messageCount: volume,
    ));
  }

  static String _name(int i) => _names[(i - 1) % _names.length];

  /// Builds the profile list (sorted by acquaintanceOrder asc) for [a]. Every
  /// intro's introducerId references an EARLIER member, so geometry placement is
  /// acyclic and arcs/tethers never dangle.
  static List<Orbit3ConnectionProfile> build(Orbit3Archetype a) {
    switch (a) {
      case Orbit3Archetype.connector:
        return _connector();
      case Orbit3Archetype.chatterbox:
        return _loud(receiverHeavy: false);
      case Orbit3Archetype.listener:
        return _loud(receiverHeavy: true);
      case Orbit3Archetype.oldSoul:
        return _oldSoul();
      case Orbit3Archetype.newArrival:
        return _newArrival();
    }
  }

  // One early member ("the hub") introduces a large fan of later members.
  static List<Orbit3ConnectionProfile> _connector() {
    const n = 30;
    final ids = <String>[];
    final out = <Orbit3ConnectionProfile>[];
    String? hubId;
    for (var i = 1; i <= n; i++) {
      final slug = 'conn-$i';
      final pid = 'orbit3-star-$slug';
      var origin = Orbit3Origin.personal;
      String? introducerId;
      if (i > 2 && _h(slug, 3) % 100 < 70) {
        origin = Orbit3Origin.intro;
        if (hubId == null) {
          introducerId = ids[_h(slug, 11) % ids.length];
          hubId = pid; // the first intro member becomes the hub
        } else {
          introducerId =
              _h(slug, 4) % 100 < 60 ? hubId : ids[_h(slug, 12) % ids.length];
        }
      }
      final sent = 40 + _h(slug, 5) % 120;
      final recv = 40 + _h(slug, 6) % 120;
      out.add(Orbit3ConnectionProfile(
        item: _item(slug, _name(i), sent + recv),
        acquaintanceOrder: i,
        origin: origin,
        introducerId: introducerId,
        messagesSent: sent,
        messagesReceived: recv,
        daysKnown: 100 + (n - i) * 20 + _h(slug, 7) % 60,
        recencyDays: 5 + _h(slug, 8) % 60,
      ));
      ids.add(pid);
    }
    return out;
  }

  // A handful of very loud relationships dominate. [receiverHeavy] flips the
  // whole picture from coral talkers (Chatterbox) to teal listeners (Listener)
  // while keeping the same magnitudes — proving reciprocity is decorrelated
  // from volume.
  static List<Orbit3ConnectionProfile> _loud({required bool receiverHeavy}) {
    const n = 30;
    const loud = {2, 5, 9, 14, 20};
    final prefix = receiverHeavy ? 'lis' : 'chat';
    final ids = <String>[];
    final out = <Orbit3ConnectionProfile>[];
    for (var i = 1; i <= n; i++) {
      final slug = '$prefix-$i';
      final pid = 'orbit3-star-$slug';
      var origin = Orbit3Origin.personal;
      String? introducerId;
      if (i > 1 && _h(slug, 3) % 100 < 15) {
        origin = Orbit3Origin.intro;
        introducerId = ids[_h(slug, 11) % ids.length];
      }
      int sent;
      int recv;
      int recency;
      if (loud.contains(i)) {
        final big = 300 + _h(slug, 5) % 150;
        final small = 20 + _h(slug, 6) % 30;
        sent = receiverHeavy ? small : big;
        recv = receiverHeavy ? big : small;
        recency = 3 + _h(slug, 8) % 15;
      } else {
        sent = 5 + _h(slug, 5) % 20;
        recv = 5 + _h(slug, 6) % 20;
        recency = 10 + _h(slug, 8) % 50;
      }
      out.add(Orbit3ConnectionProfile(
        item: _item(slug, _name(i), sent + recv),
        acquaintanceOrder: i,
        origin: origin,
        introducerId: introducerId,
        messagesSent: sent,
        messagesReceived: recv,
        daysKnown: 50 + (n - i) * 15 + _h(slug, 7) % 40,
        recencyDays: recency,
      ));
      ids.add(pid);
    }
    return out;
  }

  // Few, ancient, balanced, mostly personal, still active — a sparse warm core.
  static List<Orbit3ConnectionProfile> _oldSoul() {
    const n = 13;
    final ids = <String>[];
    final out = <Orbit3ConnectionProfile>[];
    for (var i = 1; i <= n; i++) {
      final slug = 'old-$i';
      final pid = 'orbit3-star-$slug';
      var origin = Orbit3Origin.personal;
      String? introducerId;
      if (i > 1 && _h(slug, 3) % 100 < 10) {
        origin = Orbit3Origin.intro;
        introducerId = ids[_h(slug, 11) % ids.length];
      }
      final sent = 80 + _h(slug, 5) % 80;
      final recv = 80 + _h(slug, 6) % 80;
      out.add(Orbit3ConnectionProfile(
        item: _item(slug, _name(i), sent + recv),
        acquaintanceOrder: i,
        origin: origin,
        introducerId: introducerId,
        messagesSent: sent,
        messagesReceived: recv,
        daysKnown: 1500 + (n - i) * 60 + _h(slug, 7) % 90,
        recencyDays: 10 + _h(slug, 8) % 20,
      ));
      ids.add(pid);
    }
    return out;
  }

  // Many, young, sparse, intro-heavy with no single hub; several already stale.
  static List<Orbit3ConnectionProfile> _newArrival() {
    const n = 30;
    final ids = <String>[];
    final out = <Orbit3ConnectionProfile>[];
    for (var i = 1; i <= n; i++) {
      final slug = 'new-$i';
      final pid = 'orbit3-star-$slug';
      var origin = Orbit3Origin.personal;
      String? introducerId;
      if (i > 1 && _h(slug, 3) % 100 < 55) {
        origin = Orbit3Origin.intro;
        introducerId = ids[_h(slug, 11) % ids.length]; // scattered, no hub
      }
      final sent = 3 + _h(slug, 5) % 40;
      final recv = 3 + _h(slug, 6) % 40;
      final stale = _h(slug, 9) % 100 < 40;
      out.add(Orbit3ConnectionProfile(
        item: _item(slug, _name(i), sent + recv),
        acquaintanceOrder: i,
        origin: origin,
        introducerId: introducerId,
        messagesSent: sent,
        messagesReceived: recv,
        daysKnown: 5 + i * 4 + _h(slug, 7) % 10,
        recencyDays: stale ? 60 + _h(slug, 8) % 30 : _h(slug, 8) % 15,
      ));
      ids.add(pid);
    }
    return out;
  }
}
