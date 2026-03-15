import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/dismiss_pin_use_case.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_pins_use_case.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_use_case.dart';
import 'package:flutter_app/features/posts/application/load_pinned_posts_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import 'support/post_pin_fixtures.dart';

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
    'stages orphan post_pin_update events before the parent exists',
    () async {
      contacts.addTestContact(postPinContact('peer-bob', 'Bob'));

      final (result, _) = await handleIncomingPostPinUpdate(
        message: postPinUpdateMessage(),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPostPinUpdateResult.stagedPendingParent);
      final staged = await posts.loadPendingChildEvents('post-1');
      expect(staged, hasLength(1));
      expect(staged.single.eventType, 'post_pin_update');
      expect(staged.single.eventId, 'evt-pin-1');
    },
  );

  test(
    'reconciles staged pin updates after the parent post is ingested',
    () async {
      contacts.addTestContact(postPinContact('peer-bob', 'Bob'));

      await handleIncomingPostPinUpdate(
        message: postPinUpdateMessage(
          text: 'Bring extra blankets if you can.',
          expiresAt: '2026-03-19T10:15:30.000Z',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      final (postResult, _) = await handleIncomingPost(
        message: postCreateMessage(
          post: postPinBasePost(
            text: 'Original offer text.',
            keepAvailable: false,
          ),
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(postResult, HandleIncomingPostResult.postCreated);
      final pinState = await posts.getPostPinState('post-1');
      final updatedPost = await posts.getPost('post-1');
      final staged = await posts.loadPendingChildEvents('post-1');

      expect(pinState, isNotNull);
      expect(pinState!.state, 'active');
      expect(pinState.pinEventId, 'pin-evt-1');
      expect(updatedPost, isNotNull);
      expect(updatedPost!.text, 'Bring extra blankets if you can.');
      expect(updatedPost.keepAvailable, isTrue);
      expect(updatedPost.expiresAt, '2026-03-19T10:15:30.000Z');
      expect(staged, isEmpty);
    },
  );

  test(
    'keeps the latest valid pin event when a remove beats an earlier update',
    () async {
      contacts.addTestContact(postPinContact('peer-bob', 'Bob'));
      await posts.savePost(postPinBasePost(keepAvailable: true));

      final (updateResult, _) = await handleIncomingPostPinUpdate(
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
      final (removeResult, _) = await handleIncomingPostPinRemove(
        message: postPinRemoveMessage(
          eventId: 'evt-pin-remove-new',
          pinEventId: 'pin-remove-new',
          createdAt: '2026-03-15T11:25:00.000Z',
          removedAt: '2026-03-15T11:25:00.000Z',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      final (staleUpdateResult, _) = await handleIncomingPostPinUpdate(
        message: postPinUpdateMessage(
          eventId: 'evt-pin-stale',
          pinEventId: 'pin-stale',
          createdAt: '2026-03-15T11:19:00.000Z',
          pinnedAt: '2026-03-15T11:19:00.000Z',
          text: 'This should be ignored',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(updateResult, HandleIncomingPostPinUpdateResult.pinApplied);
      expect(removeResult, HandleIncomingPostPinRemoveResult.pinRemoved);
      expect(staleUpdateResult, HandleIncomingPostPinUpdateResult.staleIgnored);

      final pinState = await posts.getPostPinState('post-1');
      final activePins = await posts.loadActivePinStates();
      final post = await posts.getPost('post-1');

      expect(pinState, isNotNull);
      expect(pinState!.state, 'removed');
      expect(pinState.pinEventId, 'pin-remove-new');
      expect(activePins, isEmpty);
      expect(post, isNotNull);
      expect(post!.text, 'Older active snapshot');
      expect(post.keepAvailable, isFalse);
    },
  );

  test(
    'applies a newer edit update even when pinned_at stays unchanged',
    () async {
      contacts.addTestContact(postPinContact('peer-bob', 'Bob'));
      await posts.savePost(postPinBasePost(keepAvailable: true));

      final (initialResult, _) = await handleIncomingPostPinUpdate(
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
      final (editResult, editPinState) = await handleIncomingPostPinUpdate(
        message: postPinUpdateMessage(
          eventId: 'evt-pin-edit',
          pinEventId: 'pin-a',
          createdAt: '2026-03-15T11:30:00.000Z',
          effectiveAt: '2026-03-15T11:30:00.000Z',
          pinnedAt: '2026-03-15T11:20:00.000Z',
          text: 'Edited pinned snapshot',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(initialResult, HandleIncomingPostPinUpdateResult.pinApplied);
      expect(editResult, HandleIncomingPostPinUpdateResult.pinApplied);
      expect(editPinState, isNotNull);
      expect(editPinState!.effectiveAt, '2026-03-15T11:30:00.000Z');
      expect(editPinState.pinnedAt, '2026-03-15T11:20:00.000Z');

      final updatedPost = await posts.getPost('post-1');
      expect(updatedPost, isNotNull);
      expect(updatedPost!.text, 'Edited pinned snapshot');
      expect(updatedPost.keepAvailable, isTrue);
    },
  );

  test(
    'clears a prior local dismissal when a fresh active pin update arrives',
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

      expect(await posts.loadDismissedPinPostIds(), <String>{'post-1'});
      expect(await loadPinnedPosts(postRepo: posts), isEmpty);

      final (result, pinState) = await handleIncomingPostPinUpdate(
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

      expect(result, HandleIncomingPostPinUpdateResult.pinApplied);
      expect(pinState, isNotNull);
      expect(await posts.loadDismissedPinPostIds(), isEmpty);

      final pinnedPosts = await loadPinnedPosts(postRepo: posts);
      expect(pinnedPosts.map((post) => post.id), <String>['post-1']);
      expect(pinnedPosts.single.text, 'Offer is back again');
      expect((await posts.getPostPinState('post-1'))!.state, 'active');
    },
  );

  test(
    'applies repeated pin and remove cycles for the same received post',
    () async {
      contacts.addTestContact(postPinContact('peer-bob', 'Bob'));
      await posts.savePost(postPinBasePost(keepAvailable: false));

      final (firstUpdateResult, _) = await handleIncomingPostPinUpdate(
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
      expect(firstUpdateResult, HandleIncomingPostPinUpdateResult.pinApplied);
      expect((await posts.getPostPinState('post-1'))!.state, 'active');
      expect((await posts.getPost('post-1'))!.keepAvailable, isTrue);

      final (firstRemoveResult, _) = await handleIncomingPostPinRemove(
        message: postPinRemoveMessage(
          eventId: 'evt-remove-1',
          pinEventId: 'pin-remove-1',
          createdAt: '2026-03-15T11:25:00.000Z',
          removedAt: '2026-03-15T11:25:00.000Z',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(firstRemoveResult, HandleIncomingPostPinRemoveResult.pinRemoved);
      expect((await posts.getPostPinState('post-1'))!.state, 'removed');
      expect((await posts.getPost('post-1'))!.keepAvailable, isFalse);

      final (
        secondUpdateResult,
        secondUpdateState,
      ) = await handleIncomingPostPinUpdate(
        message: postPinUpdateMessage(
          eventId: 'evt-pin-2',
          pinEventId: 'pin-2',
          createdAt: '2026-03-15T11:40:00.000Z',
          effectiveAt: '2026-03-15T11:40:00.000Z',
          pinnedAt: '2026-03-15T11:40:00.000Z',
          text: 'Offer is back up',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(secondUpdateResult, HandleIncomingPostPinUpdateResult.pinApplied);
      expect(secondUpdateState, isNotNull);
      expect(secondUpdateState!.state, 'active');
      expect(secondUpdateState.effectiveAt, '2026-03-15T11:40:00.000Z');
      expect((await posts.getPost('post-1'))!.text, 'Offer is back up');
      expect((await posts.getPost('post-1'))!.keepAvailable, isTrue);
      expect(await posts.loadActivePinStates(), hasLength(1));

      final (
        secondRemoveResult,
        secondRemoveState,
      ) = await handleIncomingPostPinRemove(
        message: postPinRemoveMessage(
          eventId: 'evt-remove-2',
          pinEventId: 'pin-remove-2',
          createdAt: '2026-03-15T11:50:00.000Z',
          removedAt: '2026-03-15T11:50:00.000Z',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(secondRemoveResult, HandleIncomingPostPinRemoveResult.pinRemoved);
      expect(secondRemoveState, isNotNull);
      expect(secondRemoveState!.state, 'removed');
      expect(secondRemoveState.effectiveAt, '2026-03-15T11:50:00.000Z');
      expect(await posts.loadActivePinStates(), isEmpty);
      expect((await posts.getPost('post-1'))!.keepAvailable, isFalse);
    },
  );
}
