import 'package:flutter_app/core/utils/text_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('textSearchRanges', () {
    test('finds every match, ignoring upper and lower case', () {
      expect(textSearchRanges('Dahab, then dahab again', 'DAHAB'), [
        (start: 0, end: 5),
        (start: 12, end: 17),
      ]);
    });

    test('trims the query and finds nothing for an empty one', () {
      expect(textSearchRanges('back in dahab', '  dahab '), [
        (start: 8, end: 13),
      ]);
      expect(textSearchRanges('back in dahab', '   '), isEmpty);
    });

    test('matches Arabic words inside a sentence', () {
      expect(textSearchRanges('هل نعود إلى دهب في مارس؟', 'دهب'), [
        (start: 12, end: 15),
      ]);
    });

    test('matches do not overlap', () {
      expect(textSearchRanges('aaaa', 'aa'), [
        (start: 0, end: 2),
        (start: 2, end: 4),
      ]);
    });
  });

  test('chat hits come back newest first, by message id', () {
    final oldestFirst = [
      (id: 'm1', text: 'Still thinking about Dahab'),
      (id: 'm2', text: 'The reef at the Blue Hole'),
      (id: 'm3', text: 'back to dahab in March?'),
      (id: 'm4', text: ''),
    ];
    expect(newestFirstSearchHits(oldestFirst, 'dahab'), ['m3', 'm1']);
    expect(newestFirstSearchHits(oldestFirst, 'lighthouse'), isEmpty);
    expect(newestFirstSearchHits(oldestFirst, ' '), isEmpty);
  });
}
