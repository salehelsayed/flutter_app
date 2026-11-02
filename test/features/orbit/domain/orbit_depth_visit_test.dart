import 'package:flutter_app/features/orbit/domain/orbit_depth_visit.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const visit = OrbitDepthVisit.empty;

  test('a reaction sends its glyph once per thought and glyph', () {
    final first = visit.react('post-1', ThoughtReaction.love, 'm1')!;
    expect(first.send.text, '❤️');
    expect(first.send.postId, 'post-1');
    expect(first.send.messageId, 'm1');
    expect(first.send.inFlight, isTrue);
    final sent = first.visit.settle('m1', ThoughtReplyStatus.sent);
    expect(first.visit.pressed('post-1', ThoughtReaction.love), isTrue);
    expect(sent.pressed('post-1', ThoughtReaction.love), isTrue);
    expect(sent.pressed('post-1', ThoughtReaction.fire), isFalse);
    expect(sent.react('post-1', ThoughtReaction.love, 'm2'), isNull);
    expect(first.visit.react('post-1', ThoughtReaction.love, 'm2'), isNull);
    expect(sent.react('post-1', ThoughtReaction.fire, 'm3')!.send.text, '🔥');
    expect(sent.react('post-2', ThoughtReaction.love, 'm4')!.send.text, '❤️');
  });

  test('a failed reaction is retried with the same message id', () {
    final failed = visit
        .react('post-1', ThoughtReaction.laugh, 'm1')!
        .visit
        .settle('m1', ThoughtReplyStatus.failed);
    expect(failed.latestFor('post-1')!.canRetry, isTrue);
    expect(failed.pressed('post-1', ThoughtReaction.laugh), isFalse);
    final again = failed.react('post-1', ThoughtReaction.laugh, 'm9')!;
    expect(again.send.messageId, 'm1');
    expect(again.send.text, '😂');
    expect(again.send.inFlight, isTrue);
    expect(again.visit.retry('m1'), isNull);
    final retried = failed.retry('m1')!;
    expect(retried.send.messageId, 'm1');
    expect(retried.visit.sends.length, 1);
  });

  test('a later delivery update keeps an in-flight send unretryable', () {
    final queued = visit
        .reply('post-1', 'hello', 'm1')!
        .visit
        .settle('m1', ThoughtReplyStatus.failed, finished: false);
    expect(queued.latestFor('post-1')!.inFlight, isTrue);
    expect(queued.latestFor('post-1')!.status, ThoughtReplyStatus.failed);
    expect(queued.retry('m1'), isNull);
    expect(queued.settle('unknown', ThoughtReplyStatus.sent), same(queued));
  });

  for (final lateResult in [
    ThoughtReplyStatus.queued,
    ThoughtReplyStatus.failed,
  ]) {
    test('a confirmed sent survives an older send result of '
        '${lateResult.name}', () {
      final completed = visit
          .react('post-1', ThoughtReaction.love, 'm1')!
          .visit
          .settle('m1', ThoughtReplyStatus.sent, finished: false)
          .settle('m1', lateResult);
      final send = completed.latestFor('post-1')!;
      expect(send.status, ThoughtReplyStatus.sent);
      expect(send.inFlight, isFalse);
      expect(send.canRetry, isFalse);
      expect(completed.react('post-1', ThoughtReaction.love, 'm2'), isNull);
    });
  }

  test('a typed reply closes the composer, clears its draft and trims', () {
    final open = visit
        .openComposer('post-1')
        .closeComposer('draft one')
        .openComposer('post-1');
    expect(open.composingPostId, 'post-1');
    expect(open.drafts, {'post-1': 'draft one'});
    final sent = open.reply('post-1', '  hi there  ', 'm1')!;
    expect(sent.send.text, 'hi there');
    expect(sent.send.reaction, isNull);
    expect(sent.visit.composingPostId, isNull);
    expect(sent.visit.drafts, isEmpty);
    expect(open.reply('post-1', '   ', 'm2'), isNull);
    expect(sent.visit.reply('post-1', 'again', 'm3'), isNull);
  });

  test('the latest send on a thought is the one its status line shows', () {
    final both = visit
        .react('post-1', ThoughtReaction.love, 'm1')!
        .visit
        .settle('m1', ThoughtReplyStatus.failed)
        .react('post-1', ThoughtReaction.applause, 'm2')!
        .visit;
    expect(both.latestFor('post-1')!.messageId, 'm2');
    expect(both.latestFor('post-2'), isNull);
    final retried = both.retry('m1')!.visit;
    expect(retried.latestFor('post-1')!.messageId, 'm1');
  });

  test('closing the composer keeps its draft per thought', () {
    final drafts = visit
        .openComposer('post-1')
        .closeComposer('for one')
        .openComposer('post-2')
        .closeComposer('');
    expect(drafts.composingPostId, isNull);
    expect(drafts.drafts, {'post-1': 'for one'});
  });
}
