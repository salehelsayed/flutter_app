import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a thought quote id round-trips to its post id', () {
    expect(thoughtQuoteId('post-1'), 'thought:post-1');
    expect(thoughtIdFromQuote('thought:post-1'), 'post-1');
  });

  test('message quotes and empty ids are not thoughts', () {
    expect(thoughtIdFromQuote(null), isNull);
    expect(thoughtIdFromQuote('3f2a-message-id'), isNull);
    expect(thoughtIdFromQuote('thought:'), isNull);
  });

  test('only a lone reaction glyph counts as a reaction', () {
    expect(ThoughtReaction.fromText('❤️'), ThoughtReaction.love);
    expect(ThoughtReaction.fromText(' 🔥 '), ThoughtReaction.fire);
    expect(ThoughtReaction.fromText('👏'), ThoughtReaction.applause);
    expect(ThoughtReaction.fromText('😂'), ThoughtReaction.laugh);
    expect(ThoughtReaction.fromText('❤️ see you'), isNull);
    expect(ThoughtReaction.fromText('😮'), isNull);
  });
}
