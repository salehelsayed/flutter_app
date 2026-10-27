import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// A mixed-direction sentence, the base direction the first strong letter
/// gives it, and a run of the other script inside it.
class BidiCase {
  const BidiCase(this.label, this.text, this.base, this.embedded);

  final String label;
  final String text;
  final TextDirection base;
  final String embedded;
}

const bidiCases = [
  BidiCase(
    'Arabic with an English brand name',
    'اشتريت iPhone جديد اليوم!',
    TextDirection.rtl,
    'iPhone',
  ),
  BidiCase(
    'English with an Arabic name',
    'Dinner with أحمد tonight?',
    TextDirection.ltr,
    'أحمد',
  ),
  BidiCase(
    'Arabic with a number, an emoji and Latin',
    'موعدنا 5 🙂 في Starbucks.',
    TextDirection.rtl,
    'Starbucks',
  ),
  BidiCase(
    'English with a number, an emoji and Arabic',
    'Meet at 7 PM 🎉 بالتوفيق.',
    TextDirection.ltr,
    'بالتوفيق',
  ),
  // Owner decision: the first strong letter decides, so this line is LTR.
  BidiCase(
    'starts with an English word, mostly Arabic',
    'iPhone الجديد وصل اليوم!',
    TextDirection.ltr,
    'الجديد',
  ),
];

/// Checks how [c] was laid out, from the paragraph's own glyph boxes.
///
/// [boxes] returns the boxes of one code-unit range. When [area] is given (in
/// global coordinates, with [toGlobal] mapping the paragraph's own), the line
/// has to begin on its base direction's side of that area. A
/// surface that cuts text with an ellipsis passes [mayTruncate]: positions it
/// did not draw are skipped.
void expectBidiLayout(
  BidiCase c, {
  required TextDirection direction,
  required List<TextBox> Function(TextSelection selection) boxes,
  Rect? area,
  Offset Function(Offset local)? toGlobal,
  double tolerance = 2,
  bool mayTruncate = false,
}) {
  TextBox? box(int index) {
    final found = boxes(
      TextSelection(baseOffset: index, extentOffset: index + 1),
    ).where((b) => b.right > b.left);
    if (found.isEmpty && !mayTruncate) {
      fail('${c.label}: character $index was not laid out');
    }
    return found.firstOrNull;
  }

  bool sameLine(TextBox a, TextBox b) => (a.top - b.top).abs() < 1;
  final rtl = c.base == TextDirection.rtl;

  expect(direction, c.base, reason: '${c.label}: base direction');

  final last = c.text.length - 1;
  final punctuation = box(last);
  final beforeIt = box(last - 1);
  if (punctuation != null &&
      beforeIt != null &&
      sameLine(punctuation, beforeIt)) {
    expect(
      rtl ? punctuation.left < beforeIt.left : punctuation.left > beforeIt.left,
      isTrue,
      reason: '${c.label}: "${c.text[last]}" belongs at the line end',
    );
  } else if (!mayTruncate) {
    fail('${c.label}: the last two characters are not on one line');
  }

  final from = c.text.indexOf(c.embedded);
  final first = box(from);
  final lastOfRun = box(from + c.embedded.length - 1);
  if (first != null && lastOfRun != null && sameLine(first, lastOfRun)) {
    final embeddedIsRtl = c.base == TextDirection.ltr;
    expect(
      embeddedIsRtl ? first.left > lastOfRun.left : first.left < lastOfRun.left,
      isTrue,
      reason: '${c.label}: "${c.embedded}" keeps its own reading order',
    );
  } else if (!mayTruncate) {
    fail('${c.label}: "${c.embedded}" is split over two lines');
  }

  if (area != null) {
    final start = box(0)!;
    final map = toGlobal ?? (Offset local) => local;
    if (rtl) {
      expect(
        map(Offset(start.right, start.top)).dx,
        closeTo(area.right, tolerance),
        reason: '${c.label}: starts on the right side',
      );
    } else {
      expect(
        map(Offset(start.left, start.top)).dx,
        closeTo(area.left, tolerance),
        reason: '${c.label}: starts on the left side',
      );
    }
  }
}
