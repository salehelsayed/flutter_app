import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/contact_presence_snapshot.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_presence_snapshot_repository.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';

ContactModel _contact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
  );
}

class _SequencedPrivacySettingsRepository
    implements PostsPrivacySettingsRepository {
  final List<PostsPrivacySettings> _sequence;
  int _loadCount = 0;

  _SequencedPrivacySettingsRepository(this._sequence);

  @override
  Stream<PostsPrivacySettings> get settingsChanges =>
      const Stream<PostsPrivacySettings>.empty();

  @override
  Future<PostsPrivacySettings> load() async {
    final index = _loadCount < _sequence.length
        ? _loadCount
        : _sequence.length - 1;
    _loadCount++;
    return _sequence[index];
  }

  @override
  Future<void> save(PostsPrivacySettings settings) async {}

  @override
  Future<void> setSharingEnabled(bool enabled) async {}

  @override
  void dispose() {}
}

void main() {
  late FakeP2PNetwork network;
  late FakeP2PService p2pService;
  late InMemoryPostRepository posts;
  late InMemoryContactRepository contacts;
  late InMemoryContactPresenceSnapshotRepository snapshots;
  late InMemoryPostsPrivacySettingsRepository privacySettings;
  late String freshIso;

  setUp(() {
    network = FakeP2PNetwork();
    p2pService = FakeP2PService(peerId: 'peer-self', network: network);
    posts = InMemoryPostRepository();
    contacts = InMemoryContactRepository();
    snapshots = InMemoryContactPresenceSnapshotRepository();
    freshIso = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 5))
        .toIso8601String();
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
    posts.dispose();
    snapshots.dispose();
    privacySettings.dispose();
  });

  test('locks nearby recipients at send time', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    contacts.addTestContact(_contact('peer-carol', 'Carol'));
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
        latE3: 52529,
        lngE3: 13405,
        capturedAt: freshIso,
        accuracyM: 80,
        updatedAt: freshIso,
      ),
    );

    final (result, post) = await sendPost(
      p2pService: p2pService,
      postRepo: posts,
      contactRepo: contacts,
      senderPeerId: 'peer-self',
      senderUsername: 'Alice',
      text: 'Anyone nearby?',
      audience: PostAudience.peopleNearby(radiusM: 500),
      contactPresenceSnapshotRepository: snapshots,
      postsPrivacySettingsRepository: privacySettings,
    );

    expect(result, SendPostResult.success);
    expect(post, isNotNull);
    final initialDeliveries = await posts.getRecipientDeliveries(post!.id);
    expect(initialDeliveries.map((entry) => entry.recipientPeerId), <String>[
      'peer-bob',
    ]);

    await snapshots.save(
      ContactPresenceSnapshot(
        peerId: 'peer-carol',
        status: ContactPresenceSnapshotStatus.active,
        latE3: 52524,
        lngE3: 13405,
        capturedAt: freshIso,
        accuracyM: 80,
        updatedAt: freshIso,
      ),
    );

    final lockedDeliveries = await posts.getRecipientDeliveries(post.id);
    expect(lockedDeliveries.map((entry) => entry.recipientPeerId), <String>[
      'peer-bob',
    ]);
  });

  test('persists the same sender snapshot used for qualification', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    await snapshots.save(
      ContactPresenceSnapshot(
        peerId: 'peer-bob',
        status: ContactPresenceSnapshotStatus.active,
        latE3: 52520,
        lngE3: 13412,
        capturedAt: freshIso,
        accuracyM: 80,
        updatedAt: freshIso,
      ),
    );
    final settingsSequence =
        _SequencedPrivacySettingsRepository(<PostsPrivacySettings>[
          PostsPrivacySettings(
            sharingEnabled: true,
            permissionState: PostsLocationPermissionState.granted,
            lastLocalLatE3: 52520,
            lastLocalLngE3: 13405,
            lastLocalCapturedAt: freshIso,
            lastLocalAccuracyM: 120,
          ),
          PostsPrivacySettings(
            sharingEnabled: true,
            permissionState: PostsLocationPermissionState.granted,
            lastLocalLatE3: 52520,
            lastLocalLngE3: 13420,
            lastLocalCapturedAt: freshIso,
            lastLocalAccuracyM: 120,
          ),
        ]);

    final (result, post) = await sendPost(
      p2pService: p2pService,
      postRepo: posts,
      contactRepo: contacts,
      senderPeerId: 'peer-self',
      senderUsername: 'Alice',
      text: 'Anyone nearby?',
      audience: PostAudience.peopleNearby(radiusM: 500),
      contactPresenceSnapshotRepository: snapshots,
      postsPrivacySettingsRepository: settingsSequence,
    );

    expect(result, SendPostResult.success);
    expect(post, isNotNull);
    expect(post!.nearbySenderLatE3, 52520);
    expect(post.nearbySenderLngE3, 13405);
  });
}
