import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/load_orbit_thoughts_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  final now = DateTime.utc(2026, 10, 21, 12);
  late InMemoryPostRepository posts;
  late FakeContactRepository contacts;
  late LoadOrbitThoughtsUseCase query;

  setUp(() {
    posts = InMemoryPostRepository();
    contacts = FakeContactRepository();
    query = LoadOrbitThoughtsUseCase(
      postRepo: posts,
      contactRepo: contacts,
      nowProvider: () => now,
    );
  });

  tearDown(() => posts.dispose());

  test(
    'selects the newest creation per author, regardless of visible time',
    () async {
      contacts.seed([_contact('alice'), _contact('bob')]);
      await posts.savePost(
        _post(
          'alice-old',
          'alice',
          createdAt: '2026-10-21T09:00:00Z',
        ).copyWith(visibleAt: '2026-10-21T11:30:00Z'),
      );
      await posts.savePost(
        _post('alice-new', 'alice', createdAt: '2026-10-21T10:00:00Z'),
      );
      await posts.savePost(
        _post('bob-new', 'bob', createdAt: '2026-10-21T11:00:00Z'),
      );

      expect(
        (await query.execute(localPeerId: 'local')).map((post) => post.id),
        ['bob-new', 'alice-new'],
      );
    },
  );

  test(
    'orders unseen authors first without reviving an older unseen thought',
    () async {
      contacts.seed([_contact('alice'), _contact('bob'), _contact('cara')]);
      await posts.savePost(_post('alice-old-unseen', 'alice'));
      await posts.savePost(
        _post(
          'alice-new-seen',
          'alice',
          createdAt: '2026-10-21T11:00:00Z',
        ).copyWith(isRead: true),
      );
      await posts.savePost(_post('bob-unseen', 'bob'));
      await posts.savePost(
        _post(
          'cara-seen',
          'cara',
          createdAt: '2026-10-21T11:30:00Z',
        ).copyWith(isRead: true),
      );

      expect(
        (await query.execute(localPeerId: 'local')).map((post) => post.id),
        ['bob-unseen', 'cara-seen', 'alice-new-seen'],
      );
    },
  );

  test(
    'excludes own, outgoing, absent, blocked and archived authors',
    () async {
      contacts.seed([
        _contact('local'),
        _contact('alice'),
        _contact('bob').copyWith(isBlocked: true),
        _contact('cara').copyWith(isArchived: true),
        _contact('outgoing'),
      ]);
      for (final author in ['local', 'alice', 'bob', 'cara', 'deleted']) {
        await posts.savePost(_post('thought-$author', author));
      }
      await posts.savePost(
        _post('outgoing', 'outgoing').copyWith(isIncoming: false),
      );

      expect(
        (await query.execute(localPeerId: 'local')).map((post) => post.id),
        ['thought-alice'],
      );
    },
  );

  test(
    'rechecks later block, archive and deletion against persisted thoughts',
    () async {
      contacts.seed([_contact('alice'), _contact('bob'), _contact('cara')]);
      for (final author in ['alice', 'bob', 'cara']) {
        await posts.savePost(_post('thought-$author', author));
      }
      expect(await query.execute(localPeerId: 'local'), hasLength(3));

      await contacts.blockContact('alice');
      await contacts.archiveContact('bob');
      await contacts.deleteContact('cara');

      expect(await query.execute(localPeerId: 'local'), isEmpty);
      expect(await posts.loadFeed(), hasLength(3));
    },
  );

  test('excludes exact-boundary and expired thoughts before cleanup', () async {
    contacts.seed([
      _contact('boundary'),
      _contact('expired'),
      _contact('live'),
    ]);
    await posts.savePost(
      _post('boundary', 'boundary').copyWith(expiresAt: now.toIso8601String()),
    );
    await posts.savePost(
      _post('expired', 'expired').copyWith(
        expiresAt: now
            .subtract(const Duration(microseconds: 1))
            .toIso8601String(),
        keepAvailable: true,
      ),
    );
    await posts.savePost(
      _post('live', 'live').copyWith(
        expiresAt: now.add(const Duration(microseconds: 1)).toIso8601String(),
      ),
    );

    expect((await query.execute(localPeerId: 'local')).map((post) => post.id), [
      'live',
    ]);
  });

  test(
    'uses actual instants and deterministic ID ties for selection and order',
    () async {
      contacts.seed([_contact('alice'), _contact('bob'), _contact('cara')]);
      await posts.savePost(
        _post(
          'alice-millisecond',
          'alice',
          createdAt: '2026-10-21T10:00:00.100Z',
        ),
      );
      await posts.savePost(
        _post(
          'b-alice',
          'alice',
          createdAt: '2026-10-21T12:00:00.100001+02:00',
        ),
      );
      await posts.savePost(
        _post('a-alice', 'alice', createdAt: '2026-10-21T10:00:00.100001Z'),
      );
      await posts.savePost(
        _post('c-bob', 'bob', createdAt: '2026-10-21T10:00:00.100001Z'),
      );
      await posts.savePost(
        _post('d-cara', 'cara', createdAt: '2026-10-21T10:00:00.100002Z'),
      );

      expect(
        (await query.execute(localPeerId: 'local')).map((post) => post.id),
        ['d-cara', 'a-alice', 'c-bob'],
      );
    },
  );

  test(
    'does not expose thoughts with invalid creation or expiry timestamps',
    () async {
      contacts.seed([_contact('alice'), _contact('bob')]);
      await posts.savePost(
        _post('invalid-created', 'alice').copyWith(createdAt: 'invalid'),
      );
      await posts.savePost(
        _post('invalid-expiry', 'bob').copyWith(expiresAt: 'invalid'),
      );

      expect(await query.execute(localPeerId: 'local'), isEmpty);
    },
  );

  test('checks expiry after awaited repository reads', () async {
    var currentTime = now;
    final advancingContacts = _BeforeContactsReturnRepository(() {
      currentTime = now.add(const Duration(seconds: 1));
    })..seed([_contact('alice')]);
    await posts.savePost(
      _post('expires-during-load', 'alice').copyWith(
        expiresAt: now.add(const Duration(seconds: 1)).toIso8601String(),
      ),
    );
    final lateQuery = LoadOrbitThoughtsUseCase(
      postRepo: posts,
      contactRepo: advancingContacts,
      nowProvider: () => currentTime,
    );

    expect(await lateQuery.execute(localPeerId: 'local'), isEmpty);
  });

  test(
    'maps joined read state, preserves copies and excludes it from write maps',
    () {
      final unread = _post('thought', 'alice');
      final read = PostModel.fromMap({...unread.toMap(), 'is_read': 1});

      expect(unread.isRead, isFalse);
      expect(PostModel.fromMap(unread.toMap()).isRead, isFalse);
      expect(read.isRead, isTrue);
      expect(read.copyWith(text: 'edited').isRead, isTrue);
      expect(read.copyWith(isRead: false).isRead, isFalse);
      expect(read.toMap(), isNot(contains('is_read')));
    },
  );
}

ContactModel _contact(String peerId) => ContactModel(
  peerId: peerId,
  publicKey: 'public-key',
  rendezvous: 'relay',
  username: peerId,
  signature: 'signature',
  scannedAt: '2026-10-20T12:00:00Z',
);

PostModel _post(
  String id,
  String authorPeerId, {
  String createdAt = '2026-10-21T10:00:00Z',
}) => PostModel(
  id: id,
  eventId: 'event-$id',
  senderPeerId: authorPeerId,
  authorPeerId: authorPeerId,
  authorUsername: authorPeerId,
  text: 'thought',
  audience: PostAudience.allFriends(),
  createdAt: createdAt,
  visibleAt: createdAt,
  expiresAt: '2026-10-22T10:00:00Z',
);

class _BeforeContactsReturnRepository extends FakeContactRepository {
  final void Function() beforeReturn;

  _BeforeContactsReturnRepository(this.beforeReturn);

  @override
  Future<List<ContactModel>> getActiveContacts() async {
    final contacts = await super.getActiveContacts();
    beforeReturn();
    return contacts;
  }
}
