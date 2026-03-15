import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/nearby_eligibility_service.dart';
import 'package:flutter_app/features/posts/domain/models/contact_presence_snapshot.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';

import '../../../shared/fakes/in_memory_contact_presence_snapshot_repository.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';

ContactModel _contact(
  String peerId,
  String username, {
  bool archived = false,
  bool blocked = false,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    isArchived: archived,
    isBlocked: blocked,
  );
}

void main() {
  late InMemoryContactRepository contacts;
  late InMemoryContactPresenceSnapshotRepository snapshots;
  late InMemoryPostsPrivacySettingsRepository privacySettings;
  late String freshIso;

  setUp(() async {
    freshIso = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 5))
        .toIso8601String();
    contacts = InMemoryContactRepository();
    snapshots = InMemoryContactPresenceSnapshotRepository();
    privacySettings = InMemoryPostsPrivacySettingsRepository(
      initialSettings: PostsPrivacySettings(
        sharingEnabled: true,
        permissionState: PostsLocationPermissionState.granted,
        lastLocalLatE3: 52520,
        lastLocalLngE3: 13405,
        lastLocalCapturedAt: freshIso,
        lastLocalAccuracyM: 120,
      ),
    );
  });

  tearDown(() {
    snapshots.dispose();
    privacySettings.dispose();
  });

  test(
    'qualifies only active direct friends inside the selected radius',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      contacts.addTestContact(_contact('peer-carol', 'Carol'));
      contacts.addTestContact(
        _contact('peer-archived', 'Archived', archived: true),
      );
      contacts.addTestContact(
        _contact('peer-blocked', 'Blocked', blocked: true),
      );

      await snapshots.save(
        ContactPresenceSnapshot(
          peerId: 'peer-bob',
          status: ContactPresenceSnapshotStatus.active,
          latE3: 52524,
          lngE3: 13405,
          capturedAt: freshIso,
          accuracyM: 80,
          updatedAt: freshIso,
        ),
      );
      await snapshots.save(
        ContactPresenceSnapshot(
          peerId: 'peer-carol',
          status: ContactPresenceSnapshotStatus.active,
          latE3: 52525,
          lngE3: 13405,
          capturedAt: freshIso,
          accuracyM: 80,
          updatedAt: freshIso,
        ),
      );
      await snapshots.save(
        ContactPresenceSnapshot(
          peerId: 'peer-archived',
          status: ContactPresenceSnapshotStatus.active,
          latE3: 52524,
          lngE3: 13405,
          capturedAt: freshIso,
          accuracyM: 80,
          updatedAt: freshIso,
        ),
      );
      await snapshots.save(
        ContactPresenceSnapshot(
          peerId: 'peer-blocked',
          status: ContactPresenceSnapshotStatus.active,
          latE3: 52524,
          lngE3: 13405,
          capturedAt: freshIso,
          accuracyM: 80,
          updatedAt: freshIso,
        ),
      );

      final recipients = await resolveNearbyEligibleRecipients(
        contactRepo: contacts,
        snapshotRepo: snapshots,
        privacySettingsRepo: privacySettings,
        radiusM: 500,
      );

      expect(recipients.map((entry) => entry.contact.peerId), <String>[
        'peer-bob',
      ]);
    },
  );

  test(
    'returns no recipients when the local nearby snapshot is stale',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      await privacySettings.save(
        PostsPrivacySettings(
          sharingEnabled: true,
          permissionState: PostsLocationPermissionState.granted,
          lastLocalLatE3: 52520,
          lastLocalLngE3: 13405,
          lastLocalCapturedAt: DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
          lastLocalAccuracyM: 120,
        ),
      );
      await snapshots.save(
        ContactPresenceSnapshot(
          peerId: 'peer-bob',
          status: ContactPresenceSnapshotStatus.active,
          latE3: 52524,
          lngE3: 13405,
          capturedAt: freshIso,
          accuracyM: 80,
          updatedAt: freshIso,
        ),
      );

      final recipients = await resolveNearbyEligibleRecipients(
        contactRepo: contacts,
        snapshotRepo: snapshots,
        privacySettingsRepo: privacySettings,
        radiusM: 500,
      );

      expect(recipients, isEmpty);
    },
  );

  test('applies the 500m rounded-distance boundary', () async {
    contacts.addTestContact(_contact('peer-inside', 'Inside'));
    contacts.addTestContact(_contact('peer-outside', 'Outside'));

    await snapshots.save(
      ContactPresenceSnapshot(
        peerId: 'peer-inside',
        status: ContactPresenceSnapshotStatus.active,
        latE3: 52520,
        lngE3: 13412,
        capturedAt: freshIso,
        accuracyM: 80,
        updatedAt: freshIso,
      ),
    );
    await snapshots.save(
      ContactPresenceSnapshot(
        peerId: 'peer-outside',
        status: ContactPresenceSnapshotStatus.active,
        latE3: 52520,
        lngE3: 13413,
        capturedAt: freshIso,
        accuracyM: 80,
        updatedAt: freshIso,
      ),
    );

    final recipients = await resolveNearbyEligibleRecipients(
      contactRepo: contacts,
      snapshotRepo: snapshots,
      privacySettingsRepo: privacySettings,
      radiusM: 500,
    );

    expect(recipients.map((entry) => entry.contact.peerId), <String>[
      'peer-inside',
    ]);
    expect(recipients.single.distanceM, 474);
  });

  test('applies the 1km rounded-distance boundary', () async {
    contacts.addTestContact(_contact('peer-inside', 'Inside'));
    contacts.addTestContact(_contact('peer-outside', 'Outside'));

    await snapshots.save(
      ContactPresenceSnapshot(
        peerId: 'peer-inside',
        status: ContactPresenceSnapshotStatus.active,
        latE3: 52520,
        lngE3: 13419,
        capturedAt: freshIso,
        accuracyM: 80,
        updatedAt: freshIso,
      ),
    );
    await snapshots.save(
      ContactPresenceSnapshot(
        peerId: 'peer-outside',
        status: ContactPresenceSnapshotStatus.active,
        latE3: 52520,
        lngE3: 13420,
        capturedAt: freshIso,
        accuracyM: 80,
        updatedAt: freshIso,
      ),
    );

    final recipients = await resolveNearbyEligibleRecipients(
      contactRepo: contacts,
      snapshotRepo: snapshots,
      privacySettingsRepo: privacySettings,
      radiusM: 1000,
    );

    expect(recipients.map((entry) => entry.contact.peerId), <String>[
      'peer-inside',
    ]);
    expect(recipients.single.distanceM, 947);
  });
}
