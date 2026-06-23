import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';

import '../domain/orbit3_connection_profile.dart';

/// Derives a deterministic [Orbit3ConnectionProfile] for every mock member so
/// the Inner-Orbit prototype's "Sky" (constellation) view renders the SAME
/// people as its Inner Orbit — no separate archetype population.
///
/// All metric fields come from the stable [orbit3Hash] of the member id (never a
/// clock or Random), so the fingerprint is reproducible on every device, exactly
/// like the shipped constellation. Acquaintance order follows list order, which
/// the mock builds closeness-first (most-messaged first).
List<Orbit3ConnectionProfile> orbit3ProfilesFromItems(
    List<Orbit2InnerItem> items) {
  final out = <Orbit3ConnectionProfile>[];
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final id = it.id;
    final sent = 4 + orbit3Hash(id, 11) % 260;
    final received = 4 + orbit3Hash(id, 23) % 260;
    final daysKnown = 20 + orbit3Hash(id, 31) % 1600;
    final recencyDays = orbit3Hash(id, 41) % 110;

    // ~1 in 5 (never the first three, who anchor your timeline) were introduced
    // by an earlier-known member, so intro tethers always point backward.
    final isIntro = i > 2 && (orbit3Hash(id, 7) % 5 == 0);
    final introducerId = isIntro ? items[orbit3Hash(id, 13) % i].id : null;

    out.add(Orbit3ConnectionProfile(
      item: it,
      acquaintanceOrder: i + 1,
      origin: isIntro ? Orbit3Origin.intro : Orbit3Origin.personal,
      introducerId: introducerId,
      messagesSent: sent,
      messagesReceived: received,
      daysKnown: daysKnown,
      recencyDays: recencyDays,
    ));
  }
  return out;
}
