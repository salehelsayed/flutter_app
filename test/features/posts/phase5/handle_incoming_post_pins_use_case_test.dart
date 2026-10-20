import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/dismiss_pin_use_case.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_pins_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import 'support/post_pin_fixtures.dart';

import '../support/legacy_post_state.dart';

void main() {
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;

  setUp(() {
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
  });

  tearDown(() {
    posts.dispose();
  });

  test(
    'rejects legacy pin: stages orphan post_pin_update events before the parent exists',
    () async {
      contacts.addTestContact(postPinContact('peer-bob', 'Bob'));

      final before = await snapshotLegacyPostState(posts);
      final rejection = await handleIncomingPostPinUpdate(
        message: postPinUpdateMessage(),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(rejection.$1, HandleIncomingPostPinUpdateResult.notPostPinUpdate);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
    },
  );

  test(
    'rejects legacy pin: reconciles staged pin updates after the parent post is ingested',
    () async {
      contacts.addTestContact(postPinContact('peer-bob', 'Bob'));

      final before = await snapshotLegacyPostState(posts);
      final rejection = await handleIncomingPostPinUpdate(
        message: postPinUpdateMessage(
          text: 'Bring extra blankets if you can.',
          expiresAt: '2026-03-19T10:15:30.000Z',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(rejection.$1, HandleIncomingPostPinUpdateResult.notPostPinUpdate);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
    },
  );

  test(
    'rejects legacy pin: keeps the latest valid pin event when a remove beats an earlier update',
    () async {
      contacts.addTestContact(postPinContact('peer-bob', 'Bob'));
      await posts.savePost(postPinBasePost(keepAvailable: true));

      final before = await snapshotLegacyPostState(posts);
      final rejection = await handleIncomingPostPinUpdate(
        message: postPinUpdateMessage(
          eventId: 'evt-pin-old',
          pinEventId: 'pin-old',
          createdAt: '2026-03-15T11:20:00.000Z',
          pinnedAt: '2026-03-15T11:20:00.000Z',
          text: 'Older active snapshot',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(rejection.$1, HandleIncomingPostPinUpdateResult.notPostPinUpdate);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
    },
  );

  test(
    'rejects legacy pin: applies a newer edit update even when pinned_at stays unchanged',
    () async {
      contacts.addTestContact(postPinContact('peer-bob', 'Bob'));
      await posts.savePost(postPinBasePost(keepAvailable: true));

      final before = await snapshotLegacyPostState(posts);
      final rejection = await handleIncomingPostPinUpdate(
        message: postPinUpdateMessage(
          eventId: 'evt-pin-initial',
          pinEventId: 'pin-z',
          createdAt: '2026-03-15T11:20:00.000Z',
          effectiveAt: '2026-03-15T11:20:00.000Z',
          pinnedAt: '2026-03-15T11:20:00.000Z',
          text: 'Original pinned snapshot',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(rejection.$1, HandleIncomingPostPinUpdateResult.notPostPinUpdate);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
    },
  );

  test(
    'rejects legacy pin: sanitizes dangerous bidi controls in incoming pin update snapshots',
    () async {
      contacts.addTestContact(postPinContact('peer-bob', 'Bob'));
      await posts.savePost(postPinBasePost(keepAvailable: true));

      final before = await snapshotLegacyPostState(posts);
      final rejection = await handleIncomingPostPinUpdate(
        message: postPinUpdateMessage(
          eventId: 'evt-pin-sanitized',
          pinEventId: 'pin-sanitized',
          createdAt: '2026-03-15T11:35:00.000Z',
          effectiveAt: '2026-03-15T11:35:00.000Z',
          pinnedAt: '2026-03-15T11:20:00.000Z',
          authorUsername: 'A\u202Eli\u200Fce',
          text: 'Fresh \u202Eblankets\u200F available',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(rejection.$1, HandleIncomingPostPinUpdateResult.notPostPinUpdate);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
    },
  );

  test(
    'rejects legacy pin: clears a prior local dismissal when a fresh active pin update arrives',
    () async {
      contacts.addTestContact(postPinContact('peer-bob', 'Bob'));
      await posts.savePost(postPinBasePost(keepAvailable: true));
      await posts.savePostPinState(
        const PostPinStateModel(
          postId: 'post-1',
          eventId: 'evt-pin-old',
          pinEventId: 'pin-old',
          senderPeerId: 'peer-bob',
          state: 'active',
          effectiveAt: '2026-03-15T11:20:00.000Z',
          pinnedAt: '2026-03-15T11:20:00.000Z',
          createdAt: '2026-03-15T11:20:00.000Z',
        ),
      );
      await dismissPin(
        postRepo: posts,
        postId: 'post-1',
        nowProvider: () => DateTime.parse('2026-03-15T11:30:00.000Z'),
      );

      final before = await snapshotLegacyPostState(posts);
      final rejection = await handleIncomingPostPinUpdate(
        message: postPinUpdateMessage(
          eventId: 'evt-pin-new',
          pinEventId: 'pin-new',
          createdAt: '2026-03-15T11:40:00.000Z',
          effectiveAt: '2026-03-15T11:40:00.000Z',
          pinnedAt: '2026-03-15T11:40:00.000Z',
          text: 'Offer is back again',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(rejection.$1, HandleIncomingPostPinUpdateResult.notPostPinUpdate);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
    },
  );

  test(
    'rejects legacy pin: applies repeated pin and remove cycles for the same received post',
    () async {
      contacts.addTestContact(postPinContact('peer-bob', 'Bob'));
      await posts.savePost(postPinBasePost(keepAvailable: false));

      final before = await snapshotLegacyPostState(posts);
      final rejection = await handleIncomingPostPinUpdate(
        message: postPinUpdateMessage(
          eventId: 'evt-pin-1',
          pinEventId: 'pin-1',
          createdAt: '2026-03-15T11:20:00.000Z',
          effectiveAt: '2026-03-15T11:20:00.000Z',
          pinnedAt: '2026-03-15T11:20:00.000Z',
          text: 'Offer is up',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(rejection.$1, HandleIncomingPostPinUpdateResult.notPostPinUpdate);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      final repeated = await handleIncomingPostPinUpdate(
        message: postPinUpdateMessage(
          eventId: 'evt-pin-1',
          pinEventId: 'pin-1',
          createdAt: '2026-03-15T11:20:00.000Z',
          effectiveAt: '2026-03-15T11:20:00.000Z',
          pinnedAt: '2026-03-15T11:20:00.000Z',
          text: 'Offer is up',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(repeated.$1, HandleIncomingPostPinUpdateResult.notPostPinUpdate);
      expect(await snapshotLegacyPostState(posts), before);
    },
  );
}
