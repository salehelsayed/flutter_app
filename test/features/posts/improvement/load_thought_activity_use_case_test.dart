import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/thought_reaction_message_repository.dart';
import 'package:flutter_app/features/posts/application/load_thought_activity_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/thought_view_receipt.dart';
import 'package:flutter_app/features/posts/domain/repositories/thought_view_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';

const _created = '2026-10-27T10:00:00.000Z';
const _expires = '2026-10-28T10:00:00.000Z';

void main() {
  late _Views posts;
  late _Replies messages;
  late FakeContactRepository contacts;
  late DateTime now;
  final mine = PostModel(
    id: 'mine',
    eventId: 'event-mine',
    senderPeerId: 'me',
    authorPeerId: 'me',
    authorUsername: 'Me',
    text: 'At the lake',
    audience: const PostAudience(kind: PostAudienceKind.allFriends),
    createdAt: _created,
    visibleAt: _created,
    expiresAt: _expires,
    isIncoming: false,
  );

  setUp(() async {
    now = DateTime.utc(2026, 10, 27, 12);
    posts = _Views();
    messages = _Replies();
    contacts = FakeContactRepository();
    await posts.savePost(mine);
    for (final id in ['sam', 'mo', 'blocked', 'archived', 'removed']) {
      await posts.saveRecipientDelivery(
        PostRecipientDelivery(
          postId: mine.id,
          recipientPeerId: id,
          deliveryStatus: 'inbox',
          lastAttemptAt: _created,
          deliveryPath: 'inbox',
          createdAt: _created,
          updatedAt: _created,
        ),
      );
    }
    contacts.seed([
      for (final id in ['sam', 'mo', 'blocked', 'archived', 'new-friend'])
        ContactModel(
          peerId: id,
          publicKey: 'public-$id',
          rendezvous: 'test',
          username: id == 'sam' ? 'Sam now' : id,
          signature: 'signature',
          scannedAt: _created,
        ),
    ]);
    await contacts.blockContact('blocked');
    await contacts.archiveContact('archived');
    posts.receipts.addAll([
      for (final id in ['sam', 'blocked', 'archived', 'removed', 'new-friend'])
        ThoughtViewReceipt(
          postId: 'mine',
          viewerPeerId: id,
          viewedAt: _created,
        ),
      const ThoughtViewReceipt(
        postId: 'other',
        viewerPeerId: 'mo',
        viewedAt: _created,
      ),
    ]);
    messages.replies.addAll([
      for (final (id, actor) in [
        ('sam-1', 'sam'),
        ('sam-2', 'sam'),
        ('mo', 'mo'),
        ('blocked', 'blocked'),
        ('archived', 'archived'),
        ('removed', 'removed'),
        ('new-friend', 'new-friend'),
      ])
        ConversationMessage(
          id: id,
          contactPeerId: actor,
          senderPeerId: actor,
          text: '❤️',
          timestamp: _created,
          createdAt: _created,
          status: 'delivered',
          isIncoming: true,
          quotedMessageId: 'thought:mine',
        ),
    ]);
  });
  tearDown(() => posts.dispose());

  Future<ThoughtActivity> load() => loadThoughtActivity(
    postId: 'mine',
    localPeerId: 'me',
    postRepo: posts,
    messageRepo: messages,
    contactRepo: contacts,
    nowProvider: () => now,
  );

  test(
    'only explicit original eligible viewer receipts count; chat actors group once',
    () async {
      final activity = await load();
      expect(activity.viewers, [(peerId: 'sam', name: 'Sam now')]);
      expect(
        activity.reactions.single.participants.map((actor) => actor.peerId),
        ['mo', 'sam'],
      );
      expect(activity.reactions.single.participants.last.name, 'Sam now');
      expect(messages.requested, ['mine']);
    },
  );

  test('later blocking or removal removes stale names from activity', () async {
    await load();
    await contacts.blockContact('sam');
    await contacts.deleteContact('mo');
    final activity = await load();
    expect(activity.viewers, isEmpty);
    expect(activity.reactions, isEmpty);
  });

  test(
    'expired, missing or someone else’s thought exposes no activity',
    () async {
      now = DateTime.parse(_expires);
      expect((await load()).viewers, isEmpty);
      expect(messages.requested, isEmpty);
      now = DateTime.utc(2026, 10, 27, 12);
      await posts.savePost(mine.copyWith(authorPeerId: 'other'));
      expect((await load()).reactions, isEmpty);
      expect(messages.requested, isEmpty);
      await posts.deletePostCascade('mine');
      expect((await load()).viewers, isEmpty);
    },
  );

  test('a missing activity capability is not reported as zero views', () async {
    await expectLater(
      loadThoughtActivity(
        postId: 'mine',
        localPeerId: 'me',
        postRepo: posts,
        messageRepo: InMemoryMessageRepository(),
        contactRepo: contacts,
        nowProvider: () => now,
      ),
      throwsStateError,
    );
  });
}

class _Replies extends InMemoryMessageRepository
    implements ThoughtReactionMessageRepository {
  final replies = <ConversationMessage>[];
  final requested = <String>[];
  @override
  Future<List<ConversationMessage>> loadThoughtReactionMessages(
    String postId,
  ) async {
    requested.add(postId);
    return replies;
  }
}

class _Views extends InMemoryPostRepository implements ThoughtViewRepository {
  final receipts = <ThoughtViewReceipt>[];
  @override
  Future<List<ThoughtViewReceipt>> loadThoughtViews(String postId) async =>
      receipts;
  @override
  Future<bool> queueThoughtView({
    required ThoughtViewReceipt receipt,
    required PostFollowOnOutboxEvent event,
    required PostFollowOnOutboxRecipientDelivery recipient,
    required String authorPeerId,
    required String nowIso,
  }) => throw UnimplementedError();
  @override
  Future<bool> recordIncomingThoughtView({
    required ThoughtViewReceipt receipt,
    required String localPeerId,
    required String nowIso,
  }) => throw UnimplementedError();
}
