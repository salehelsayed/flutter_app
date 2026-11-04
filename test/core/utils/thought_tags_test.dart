import 'package:flutter_app/core/utils/thought_tags.dart';
import 'package:flutter_test/flutter_test.dart';

List<(String, String)> _tags(String text) => [
  for (final tag in parseThoughtTags(text))
    (text.substring(tag.start, tag.end), tag.key),
];

void main() {
  test('an English tag ends at punctuation or space', () {
    expect(_tags('sunset at the falls #Walks, worth the climb'), [
      ('#Walks', 'walks'),
    ]);
    expect(_tags('#walks.'), [('#walks', 'walks')]);
    expect(_tags('#walks!#runs and #long_run2'), [
      ('#walks', 'walks'),
      ('#runs', 'runs'),
      ('#long_run2', 'long_run2'),
    ]);
    expect(_tags('#dog-walks'), [('#dog', 'dog')]);
  });

  test('a German tag keeps its umlauts and sharp s', () {
    expect(_tags('Übung macht den Meister #Übung #Straße'), [
      ('#Übung', 'übung'),
      ('#Straße', 'straße'),
    ]);
    expect(hasThoughtTag('Heute: #ÜBUNG', 'übung'), isTrue);
  });

  test('an Arabic tag keeps its letters, marks and digits', () {
    expect(_tags('غروب الشمس #مشي_طويل، جميل'), [
      ('#مشي_طويل', 'مشي_طويل'),
    ]);
    expect(_tags('#مَشي #٢٠٢٦'), [('#مَشي', 'مَشي'), ('#٢٠٢٦', '٢٠٢٦')]);
  });

  test('a # inside a word, a link or on its own is not a tag', () {
    expect(_tags('a lone # sign'), isEmpty);
    expect(_tags('##'), isEmpty);
    expect(_tags('mail me at me#walks'), isEmpty);
    expect(_tags('https://example.com/page#top'), isEmpty);
  });

  test('matching ignores case but not the rest of the word', () {
    expect(hasThoughtTag('Morning #Walks', 'walks'), isTrue);
    expect(hasThoughtTag('Morning #walksies', 'walks'), isFalse);
    expect(hasThoughtTag('Morning walks', 'walks'), isFalse);
  });
}
