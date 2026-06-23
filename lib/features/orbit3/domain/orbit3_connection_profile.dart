import 'dart:math';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';

/// How a connection entered your orbit: you added them directly, or a mutual
/// friend introduced you.
enum Orbit3Origin { personal, intro }

/// Deterministic per-connection metrics for the Orbit3 "constellation" modes.
///
/// Orbit3-OWNED: no shipped model (ContactModel / OrbitFriend / Orbit2*) carries
/// acquaintance order, origin, send-vs-receive split, or recency, so this record
/// composes an [Orbit2InnerItem] (the renderable member) and adds the raw metric
/// fields the fingerprint is computed from. Pure data — no Flutter widgets — so
/// the mapping math stays unit-testable, mirroring orbit3_one_circle_layout.dart.
class Orbit3ConnectionProfile {
  /// The renderable member (a friend or a group) — reused by the same avatar
  /// leaf widgets as the One Circle view.
  final Orbit2InnerItem item;

  /// 1 = your oldest friendship … N = the newest. The spine of every mode.
  final int acquaintanceOrder;

  /// Personal add vs introduced-by-a-mutual.
  final Orbit3Origin origin;

  /// Non-null iff [origin] == intro. ALWAYS the [item] id of a member with a
  /// LOWER [acquaintanceOrder], so intro arcs/tethers point backward in time and
  /// never dangle or form a cycle.
  final String? introducerId;

  /// Messages you sent them.
  final int messagesSent;

  /// Messages they sent you.
  final int messagesReceived;

  /// Age of the friendship, in days.
  final int daysKnown;

  /// Days since the last interaction (0 = today).
  final int recencyDays;

  const Orbit3ConnectionProfile({
    required this.item,
    required this.acquaintanceOrder,
    required this.origin,
    this.introducerId,
    required this.messagesSent,
    required this.messagesReceived,
    required this.daysKnown,
    required this.recencyDays,
  });

  String get id => item.id;
  String get displayName => item.displayName;
  bool get isGroup => item.isGroup;

  /// Chattiness.
  int get totalVolume => messagesSent + messagesReceived;

  /// 0 = pure listener (you only receive), 1 = pure talker (you only send),
  /// 0.5 = balanced.
  double get reciprocity =>
      messagesSent / (totalVolume == 0 ? 1 : totalVolume);
}

/// Stable FNV-1a hash — the ONLY source of "randomness" in the constellation.
/// No `Random()`, no clock: a member's stable id always hashes the same, so the
/// fingerprint is reproducible on every device. [salt] varies the channel
/// (jitter vs scatter vs twinkle phase) so independent uses don't correlate.
int orbit3Hash(String id, int salt) {
  var h = 0x811c9dc5 ^ salt;
  for (final c in id.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h;
}

/// [orbit3Hash] folded into the unit interval [0, 1).
double orbit3Hash01(String id, int salt) =>
    (orbit3Hash(id, salt) % 100000) / 100000.0;

/// The normalized 0..1 driver values a single connection contributes to every
/// mode. The painters read ONLY these (never the raw ints) — that is what makes
/// "same algorithm for everyone" literal: the formulas live here, once.
class Orbit3Drivers {
  final Orbit3ConnectionProfile profile;

  /// 0 = oldest friendship … 1 = newest (acquaintanceOrder rank).
  final double orderT;

  /// 0..1 log-volume — star brightness / planetary mass.
  final double magnitude;

  /// 0..1 emotional closeness = 0.6·magnitude + 0.4·recencyFresh (inner = close).
  final double closeness;

  /// 0..1 — 1 = interacted today, 0 = stale (≥90 days).
  final double recencyT;

  /// 0..1 — daysKnown normalized against the population (1 = the most ancient).
  final double ageT;

  /// 0..1 — 0 = listener … 1 = talker (passes [profile.reciprocity] through).
  final double reciprocity;

  /// The SHARED reciprocity legend across all three modes: teal (listener) →
  /// white-gold (balanced) → coral (talker).
  final Color reciprocityHue;

  const Orbit3Drivers({
    required this.profile,
    required this.orderT,
    required this.magnitude,
    required this.closeness,
    required this.recencyT,
    required this.ageT,
    required this.reciprocity,
    required this.reciprocityHue,
  });

  String get id => profile.id;
}

/// The whole population's drivers, computed ONCE and deterministically. Holds
/// the per-member [drivers] plus a [byId] index the painters use to look up an
/// introducer's placement.
class Orbit3DriverSet {
  final List<Orbit3Drivers> drivers;
  final Map<String, Orbit3Drivers> byId;
  final int n;

  const Orbit3DriverSet(this.drivers, this.byId, this.n);

  factory Orbit3DriverSet.from(List<Orbit3ConnectionProfile> ps) {
    final n = ps.length;
    // Population constants, computed once, deterministically.
    final maxVol = ps.fold<int>(1, (a, p) => max(a, p.totalVolume));
    final maxDays = ps.fold<int>(1, (a, p) => max(a, p.daysKnown));
    final lnMaxVol = log(1 + maxVol);

    final out = <Orbit3Drivers>[];
    for (final p in ps) {
      final orderT =
          n <= 1 ? 0.0 : (p.acquaintanceOrder - 1) / (n - 1);
      final magnitude =
          lnMaxVol == 0 ? 0.0 : log(1 + p.totalVolume) / lnMaxVol;
      final recencyT = 1.0 - (p.recencyDays.clamp(0, 90)) / 90.0;
      final closeness = (0.6 * magnitude + 0.4 * recencyT).clamp(0.0, 1.0);
      final ageT = (p.daysKnown / maxDays).clamp(0.0, 1.0);
      final recip = p.reciprocity;
      out.add(Orbit3Drivers(
        profile: p,
        orderT: orderT.toDouble(),
        magnitude: magnitude,
        closeness: closeness,
        recencyT: recencyT,
        ageT: ageT.toDouble(),
        reciprocity: recip,
        reciprocityHue: orbit3ReciprocityHue(recip),
      ));
    }
    return Orbit3DriverSet(out, {for (final d in out) d.id: d}, n);
  }
}

/// teal (#4ECDC4 listener) → white-gold (#FFF1C0 balanced) → coral (#FF6B6B
/// talker). The one shared temperature axis; brand green is reserved strictly
/// for the central "You" node so this member axis stays green-free.
Color orbit3ReciprocityHue(double r) {
  const teal = Color(0xFF4ECDC4);
  const gold = Color(0xFFFFF1C0);
  const coral = Color(0xFFFF6B6B);
  return r < 0.5
      ? Color.lerp(teal, gold, r / 0.5)!
      : Color.lerp(gold, coral, (r - 0.5) / 0.5)!;
}
