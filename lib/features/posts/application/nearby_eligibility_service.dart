import 'dart:math' as math;

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/posts/domain/models/contact_presence_snapshot.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';

const Duration nearbyEligibilityFreshnessTtl = Duration(minutes: 30);

class NearbyEligibleRecipient {
  final ContactModel contact;
  final int distanceM;

  const NearbyEligibleRecipient({
    required this.contact,
    required this.distanceM,
  });
}

Future<List<NearbyEligibleRecipient>> resolveNearbyEligibleRecipients({
  required ContactRepository contactRepo,
  required ContactPresenceSnapshotRepository snapshotRepo,
  required PostsPrivacySettingsRepository privacySettingsRepo,
  required int radiusM,
  PostsPrivacySettings? localSettings,
  DateTime Function()? now,
}) async {
  final currentTime = (now ?? () => DateTime.now().toUtc())();
  final effectiveLocalSettings =
      localSettings ?? await privacySettingsRepo.load();
  if (!hasUsableLocalNearbySnapshot(effectiveLocalSettings, now: currentTime)) {
    return const <NearbyEligibleRecipient>[];
  }

  final contacts = await contactRepo.getActiveContacts();
  final snapshots = await snapshotRepo.loadAll();
  final snapshotByPeerId = <String, ContactPresenceSnapshot>{
    for (final snapshot in snapshots) snapshot.peerId: snapshot,
  };

  final recipients = <NearbyEligibleRecipient>[];
  for (final contact in contacts) {
    if (contact.isBlocked) {
      continue;
    }
    final snapshot = snapshotByPeerId[contact.peerId];
    if (!hasUsableContactNearbySnapshot(snapshot, now: currentTime)) {
      continue;
    }
    final distanceM = calculateNearbyDistanceM(
      latE3A: effectiveLocalSettings.lastLocalLatE3!,
      lngE3A: effectiveLocalSettings.lastLocalLngE3!,
      latE3B: snapshot!.latE3!,
      lngE3B: snapshot.lngE3!,
    );
    if (distanceM <= radiusM) {
      recipients.add(
        NearbyEligibleRecipient(contact: contact, distanceM: distanceM),
      );
    }
  }

  recipients.sort((left, right) {
    final distanceCompare = left.distanceM.compareTo(right.distanceM);
    if (distanceCompare != 0) {
      return distanceCompare;
    }
    return left.contact.peerId.compareTo(right.contact.peerId);
  });
  return recipients;
}

bool hasUsableLocalNearbySnapshot(
  PostsPrivacySettings settings, {
  required DateTime now,
}) {
  return settings.sharingEnabled &&
      settings.permissionState == PostsLocationPermissionState.granted &&
      settings.hasFreshSnapshotAt(now, ttl: nearbyEligibilityFreshnessTtl);
}

bool hasUsableContactNearbySnapshot(
  ContactPresenceSnapshot? snapshot, {
  required DateTime now,
}) {
  if (snapshot == null ||
      snapshot.status != ContactPresenceSnapshotStatus.active ||
      snapshot.latE3 == null ||
      snapshot.lngE3 == null) {
    return false;
  }
  final capturedAt = DateTime.tryParse(snapshot.capturedAt)?.toUtc();
  if (capturedAt == null) {
    return false;
  }
  return now.toUtc().difference(capturedAt) <= nearbyEligibilityFreshnessTtl;
}

int calculateNearbyDistanceM({
  required int latE3A,
  required int lngE3A,
  required int latE3B,
  required int lngE3B,
}) {
  const earthRadiusM = 6371000.0;
  final latARad = _toRadians(latE3A / 1000.0);
  final latBRad = _toRadians(latE3B / 1000.0);
  final deltaLat = _toRadians((latE3B - latE3A) / 1000.0);
  final deltaLng = _toRadians((lngE3B - lngE3A) / 1000.0);

  final haversine =
      math.pow(math.sin(deltaLat / 2), 2) +
      math.cos(latARad) *
          math.cos(latBRad) *
          math.pow(math.sin(deltaLng / 2), 2);
  final c = 2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  return (earthRadiusM * c).round();
}

String formatNearbyDistanceLabel(int distanceM) {
  if (distanceM < 1000) {
    final rounded = ((distanceM + 25) ~/ 50) * 50;
    return '${math.max(50, rounded)}m away';
  }
  final km = distanceM / 1000;
  return '${km.toStringAsFixed(1)}km away';
}

double _toRadians(double degrees) => degrees * math.pi / 180.0;
