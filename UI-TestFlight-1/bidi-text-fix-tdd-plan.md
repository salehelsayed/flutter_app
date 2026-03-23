# BiDi Text Rendering Fix — TDD Implementation Plan

**Issue:** Mixed Arabic (RTL) and English (LTR) text renders with scrambled word order.
**Root Cause:** Flutter does not auto-detect text direction from content. The app never sets `textDirection` on any `Text` or `TextField` widget, so everything defaults to LTR. Additionally, the text sanitizer strips all Unicode BiDi control characters (including helpful ones like LRM/RLM) that the OS keyboard inserts to help the rendering engine.

---

## Phase 1: Text Direction Detection Utility

**Goal:** Create a `detectTextDirection()` function using the first-strong-character heuristic (same approach WhatsApp and Android `TextView` use).

### 1.1 Write Tests First

**File:** `test/core/utils/text_direction_utils_test.dart` (new)

```dart
import 'dart:ui' show TextDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';

void main() {
  group('detectTextDirection', () {
    // --- Pure single-script ---
    test('pure English text returns LTR', () {
      expect(detectTextDirection('Hello world'), TextDirection.ltr);
    });

    test('pure Arabic text returns RTL', () {
      expect(detectTextDirection('مرحبا بالعالم'), TextDirection.rtl);
    });

    test('pure Hebrew text returns RTL', () {
      expect(detectTextDirection('שלום עולם'), TextDirection.rtl);
    });

    // --- Mixed text: first-strong-character wins ---
    test('Arabic then English returns RTL', () {
      expect(
        detectTextDirection('مرحبا Hello كيف حالك'),
        TextDirection.rtl,
      );
    });

    test('English then Arabic returns LTR', () {
      expect(
        detectTextDirection('Hello مرحبا World'),
        TextDirection.ltr,
      );
    });

    test('leading spaces then Arabic returns RTL', () {
      expect(detectTextDirection('   مرحبا hello'), TextDirection.rtl);
    });

    test('leading digits then Arabic returns RTL (digits are neutral)', () {
      expect(detectTextDirection('123 مرحبا'), TextDirection.rtl);
    });

    test('leading digits then English returns LTR (digits are neutral)', () {
      expect(detectTextDirection('123 hello'), TextDirection.ltr);
    });

    test('leading punctuation then Arabic returns RTL (punctuation is neutral)', () {
      expect(detectTextDirection('... مرحبا'), TextDirection.rtl);
    });

    test('leading emoji then English returns LTR (emoji is neutral)', () {
      expect(detectTextDirection('😀 hello'), TextDirection.ltr);
    });

    test('leading emoji then Arabic returns RTL (emoji is neutral)', () {
      expect(detectTextDirection('😀 مرحبا'), TextDirection.rtl);
    });

    // --- Edge cases ---
    test('empty string defaults to LTR', () {
      expect(detectTextDirection(''), TextDirection.ltr);
    });

    test('only whitespace defaults to LTR', () {
      expect(detectTextDirection('   '), TextDirection.ltr);
    });

    test('only digits defaults to LTR', () {
      expect(detectTextDirection('12345'), TextDirection.ltr);
    });

    test('only punctuation defaults to LTR', () {
      expect(detectTextDirection('...!?'), TextDirection.ltr);
    });

    test('only emoji defaults to LTR', () {
      expect(detectTextDirection('😀🎉'), TextDirection.ltr);
    });

    // --- Extended Arabic ranges ---
    test('Arabic Supplement (U+0750-077F) returns RTL', () {
      expect(detectTextDirection('\u0750'), TextDirection.rtl);
    });

    test('Arabic Extended-A (U+08A0-08FF) returns RTL', () {
      expect(detectTextDirection('\u08A0'), TextDirection.rtl);
    });

    test('Arabic Presentation Forms-A returns RTL', () {
      expect(detectTextDirection('\uFB50'), TextDirection.rtl);
    });

    test('Arabic Presentation Forms-B returns RTL', () {
      expect(detectTextDirection('\uFE70'), TextDirection.rtl);
    });

    // --- Extended Latin still LTR ---
    test('Extended Latin (German umlauts) returns LTR', () {
      expect(detectTextDirection('Ärger öffnen über'), TextDirection.ltr);
    });

    // --- Real-world mixed messages ---
    test('Arabic sentence with embedded English brand name', () {
      expect(
        detectTextDirection('أنا أستخدم WhatsApp يوميا'),
        TextDirection.rtl,
      );
    });

    test('English sentence with embedded Arabic word', () {
      expect(
        detectTextDirection('The word مرحبا means hello'),
        TextDirection.ltr,
      );
    });

    test('Arabic with numbers and English', () {
      expect(
        detectTextDirection('سأكون هناك الساعة 5 مساء at the café'),
        TextDirection.rtl,
      );
    });
  });
}
```

### 1.2 Implement the Utility

**File:** `lib/core/utils/text_direction_utils.dart` (new)

```dart
import 'dart:ui' show TextDirection;

/// Detects text direction using the first-strong-character heuristic.
///
/// Scans the string for the first character with a strong Unicode
/// directionality (Arabic/Hebrew/Syriac/Thaana -> RTL; Latin/Greek/
/// Cyrillic/CJK -> LTR). Neutral characters (digits, punctuation,
/// spaces, emoji) are skipped. Defaults to LTR if no strong character
/// is found.
///
/// This matches the behavior of Android's `textDirection="firstStrong"`
/// and WhatsApp's per-message direction detection.
TextDirection detectTextDirection(String text) {
  for (final codeUnit in text.runes) {
    if (_isRtlChar(codeUnit)) return TextDirection.rtl;
    if (_isLtrChar(codeUnit)) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

/// Returns true if [codePoint] belongs to an RTL script.
bool _isRtlChar(int codePoint) {
  return
      // Hebrew (U+0590-05FF)
      (codePoint >= 0x0590 && codePoint <= 0x05FF) ||
      // Arabic (U+0600-06FF)
      (codePoint >= 0x0600 && codePoint <= 0x06FF) ||
      // Syriac (U+0700-074F)
      (codePoint >= 0x0700 && codePoint <= 0x074F) ||
      // Arabic Supplement (U+0750-077F)
      (codePoint >= 0x0750 && codePoint <= 0x077F) ||
      // Thaana (U+0780-07BF)
      (codePoint >= 0x0780 && codePoint <= 0x07BF) ||
      // NKo (U+07C0-07FF)
      (codePoint >= 0x07C0 && codePoint <= 0x07FF) ||
      // Arabic Extended-A (U+08A0-08FF)
      (codePoint >= 0x08A0 && codePoint <= 0x08FF) ||
      // Arabic Presentation Forms-A (U+FB50-FDFF)
      (codePoint >= 0xFB50 && codePoint <= 0xFDFF) ||
      // Arabic Presentation Forms-B (U+FE70-FEFF)
      (codePoint >= 0xFE70 && codePoint <= 0xFEFF) ||
      // Hebrew Presentation Forms (U+FB1D-FB4F)
      (codePoint >= 0xFB1D && codePoint <= 0xFB4F);
}

/// Returns true if [codePoint] belongs to an LTR script.
bool _isLtrChar(int codePoint) {
  return
      // Basic Latin letters (A-Z, a-z)
      (codePoint >= 0x0041 && codePoint <= 0x005A) ||
      (codePoint >= 0x0061 && codePoint <= 0x007A) ||
      // Latin Extended (U+00C0-024F)
      (codePoint >= 0x00C0 && codePoint <= 0x024F) ||
      // Greek and Coptic (U+0370-03FF)
      (codePoint >= 0x0370 && codePoint <= 0x03FF) ||
      // Cyrillic (U+0400-04FF)
      (codePoint >= 0x0400 && codePoint <= 0x04FF) ||
      // CJK Unified Ideographs (U+4E00-9FFF)
      (codePoint >= 0x4E00 && codePoint <= 0x9FFF);
}
```

### 1.3 Run Tests

```bash
flutter test test/core/utils/text_direction_utils_test.dart
```

All tests must pass before moving to Phase 2.

---

## Phase 2: Update Text Sanitizer — Preserve Helpful BiDi Markers

**Goal:** Stop stripping LRM (U+200E) and RLM (U+200F) which are essential for correct mixed-text rendering. Only strip dangerous override/embedding characters that can be used for text spoofing.

### 2.1 Write Tests First

**File:** `test/core/utils/text_sanitizer_test.dart` (add new group)

```dart
group('stripBidiCharacters — BiDi marker preservation', () {
  test('preserves LRM (U+200E) in mixed text', () {
    expect(
      stripBidiCharacters('hello\u200Eworld'),
      'hello\u200Eworld',
    );
  });

  test('preserves RLM (U+200F) in mixed text', () {
    expect(
      stripBidiCharacters('hello\u200Fworld'),
      'hello\u200Fworld',
    );
  });

  test('preserves FSI (U+2068) and PDI (U+2069) isolates', () {
    expect(
      stripBidiCharacters('ab\u2068hello\u2069cd'),
      'ab\u2068hello\u2069cd',
    );
  });

  test('preserves LRI (U+2066) and RLI (U+2067) isolates', () {
    expect(
      stripBidiCharacters('ab\u2066hello\u2069cd'),
      'ab\u2066hello\u2069cd',
    );
  });

  test('still strips dangerous LRO (U+202D) override', () {
    expect(stripBidiCharacters('ab\u202Dcd'), 'abcd');
  });

  test('still strips dangerous RLO (U+202E) override', () {
    expect(stripBidiCharacters('ab\u202Ecd'), 'abcd');
  });

  test('still strips zero-width space (U+200B)', () {
    expect(stripBidiCharacters('hello\u200Bworld'), 'helloworld');
  });

  test('still strips ZWNJ (U+200C)', () {
    expect(stripBidiCharacters('hello\u200Cworld'), 'helloworld');
  });

  test('still strips BOM (U+FEFF)', () {
    expect(stripBidiCharacters('\uFEFFhello'), 'hello');
  });

  test('preserves ALM (U+061C) for Arabic numeric context', () {
    expect(stripBidiCharacters('hello\u061Cworld'), 'hello\u061Cworld');
  });

  test('still preserves ZWJ (U+200D) for emoji', () {
    const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
    expect(stripBidiCharacters(family), family);
  });

  test('mixed Arabic/English with LRM preserved', () {
    const mixed = 'Hello \u200Eمرحبا\u200E World';
    expect(stripBidiCharacters(mixed), mixed);
  });
});
```

> **Note:** Some of these tests will initially FAIL against the current implementation (which strips LRM/RLM/isolates). This is expected — the tests define the desired behavior.

### 2.2 Update the Sanitizer

**File:** `lib/core/utils/text_sanitizer.dart`

**Change:** Replace `_bidiPattern` to only strip dangerous characters, preserving helpful markers.

```dart
/// Regex matching DANGEROUS bidi control characters and invisible formatting.
///
/// Strips: U+200B (zero-width space), U+200C (ZWNJ),
/// U+202A (LRE), U+202B (RLE), U+202C (PDF), U+202D (LRO), U+202E (RLO),
/// U+FEFF (BOM/ZWNBS).
///
/// Preserves (safe & helpful for BiDi rendering):
/// - U+200D (ZWJ) for emoji sequences
/// - U+200E (LRM) and U+200F (RLM) for mixed-direction text
/// - U+061C (ALM) for Arabic numeric/context handling (Unicode 6.3)
/// - U+2066 (LRI), U+2067 (RLI), U+2068 (FSI), U+2069 (PDI) — modern isolates
final _bidiPattern = RegExp(
  '[\u200B\u200C'      // zero-width space, ZWNJ
  '\u202A-\u202E'      // legacy bidi embedding + override (LRE/RLE/PDF/LRO/RLO)
  '\uFEFF]',           // BOM
);
```

### 2.3 Update Existing Tests

Four existing tests must be updated to match the new behavior:

**File:** `test/core/utils/text_sanitizer_test.dart`

**Change test at line 14-16:**
```dart
// BEFORE:
test('removes LRM (U+200E) and RLM (U+200F)', () {
  expect(stripBidiCharacters('hello\u200E\u200Fworld'), 'helloworld');
});

// AFTER:
test('preserves LRM (U+200E) and RLM (U+200F)', () {
  expect(stripBidiCharacters('hello\u200E\u200Fworld'), 'hello\u200E\u200Fworld');
});
```

**Change test at line 25-29:**
```dart
// BEFORE:
test('removes bidi isolate (U+2066-2069)', () {
  expect(
    stripBidiCharacters('ab\u2066\u2067\u2068\u2069cd'),
    'abcd',
  );
});

// AFTER:
test('preserves bidi isolates (U+2066-2069)', () {
  expect(
    stripBidiCharacters('ab\u2066\u2067\u2068\u2069cd'),
    'ab\u2066\u2067\u2068\u2069cd',
  );
});
```

**Change test at line 50-52:**
```dart
// BEFORE:
test('handles string of only bidi characters', () {
  expect(stripBidiCharacters('\u200B\u200C\u200E\u202A\uFEFF'), '');
});

// AFTER:
test('handles string of only bidi characters', () {
  // U+200E (LRM) is now preserved; U+200B, U+200C, U+202A, U+FEFF stripped
  expect(stripBidiCharacters('\u200B\u200C\u200E\u202A\uFEFF'), '\u200E');
});
```

**Change test at line 32-34:**
```dart
// BEFORE:
test('removes ALM (U+061C)', () {
  expect(stripBidiCharacters('hello\u061Cworld'), 'helloworld');
});

// AFTER:
test('preserves ALM (U+061C)', () {
  expect(stripBidiCharacters('hello\u061Cworld'), 'hello\u061Cworld');
});
```

### 2.4 Run Tests

```bash
flutter test test/core/utils/text_sanitizer_test.dart
```

All tests (existing + new) must pass before moving to Phase 3.

---

## Phase 3: Add `textDirection` to LinkableText Widget

**Goal:** Accept an optional `textDirection` parameter and forward it to `Text.rich()`.

### 3.1 Write Tests First

**File:** `test/shared/widgets/linkable_text_test.dart` (new)

```dart
import 'dart:ui' show TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';

void main() {
  group('LinkableText textDirection', () {
    Widget buildTestWidget({
      required String text,
      TextDirection? textDirection,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.ltr, // app default
            child: LinkableText(
              text: text,
              textDirection: textDirection,
            ),
          ),
        ),
      );
    }

    testWidgets('renders without textDirection (backward compat)', (tester) async {
      await tester.pumpWidget(buildTestWidget(text: 'Hello'));
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('passes RTL textDirection to underlying Text.rich', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        text: 'مرحبا',
        textDirection: TextDirection.rtl,
      ));

      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.textDirection, TextDirection.rtl);
    });

    testWidgets('passes LTR textDirection to underlying Text.rich', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        text: 'Hello',
        textDirection: TextDirection.ltr,
      ));

      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.textDirection, TextDirection.ltr);
    });

    testWidgets('null textDirection inherits from Directionality', (tester) async {
      await tester.pumpWidget(buildTestWidget(text: 'Hello'));
      final richText = tester.widget<RichText>(find.byType(RichText));
      // When null, Text.rich defers to the ambient Directionality
      expect(richText.textDirection, isNull);
    });

    testWidgets('works with prefixSpans and textDirection', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.ltr,
            child: LinkableText(
              text: 'مرحبا',
              textDirection: TextDirection.rtl,
              prefixSpans: [
                const TextSpan(text: 'Name: '),
              ],
            ),
          ),
        ),
      ));

      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.textDirection, TextDirection.rtl);
    });
  });
}
```

### 3.2 Implement the Change

**File:** `lib/shared/widgets/linkable_text.dart`

**Changes:**

1. Add field (after `suffixSpans` on line 20):
```dart
final TextDirection? textDirection;
```

2. Add to constructor (after `this.suffixSpans` on line 30):
```dart
this.textDirection,
```

3. Update `build()` method (lines 127-131):
```dart
// BEFORE:
return Text.rich(
  TextSpan(children: allSpans),
  maxLines: widget.maxLines,
  overflow: widget.overflow ?? TextOverflow.clip,
);

// AFTER:
return Text.rich(
  TextSpan(children: allSpans),
  maxLines: widget.maxLines,
  overflow: widget.overflow ?? TextOverflow.clip,
  textDirection: widget.textDirection,
);
```

### 3.3 Run Tests

```bash
flutter test test/shared/widgets/linkable_text_test.dart
```

---

## Phase 4: Wire Direction Detection into Display Widgets

**Goal:** LetterCard, MessageBubble, and QuotePreviewBar auto-detect text direction and pass it through. Tests verify the wiring by pumping the real widget and inspecting the rendered `RichText.textDirection`.

### 4.1 LetterCard — extend existing tests

**File:** `test/features/conversation/presentation/widgets/letter_card_test.dart` (extend)

**Prerequisite:** The existing `buildTestWidget` helper (line 9) does not accept `quotedText` or `isQuoteUnavailable`. Extend it first:

```dart
// BEFORE (letter_card_test.dart line 9):
Widget buildTestWidget({
  bool isIncoming = true,
  String? status,
  String senderName = 'Alice',
  String text = 'Hello, this is a test message.',
  String time = '3:30 PM',
  String? transport,
  List<MessageReaction> reactions = const [],
  String? ownPeerId,
  VoidCallback? onLongPress,
  void Function(String emoji)? onReactionTap,
}) {

// AFTER — add two parameters and pass them to LetterCard:
Widget buildTestWidget({
  bool isIncoming = true,
  String? status,
  String senderName = 'Alice',
  String text = 'Hello, this is a test message.',
  String time = '3:30 PM',
  String? transport,
  String? quotedText,
  bool isQuoteUnavailable = false,
  List<MessageReaction> reactions = const [],
  String? ownPeerId,
  VoidCallback? onLongPress,
  void Function(String emoji)? onReactionTap,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: LetterCard(
          senderPeerId: '12D3KooWTestPeerId1234567890',
          senderName: senderName,
          text: text,
          time: time,
          isIncoming: isIncoming,
          status: status,
          transport: transport,
          quotedText: quotedText,
          isQuoteUnavailable: isQuoteUnavailable,
          reactions: reactions,
          ownPeerId: ownPeerId,
          onLongPress: onLongPress,
          onReactionTap: onReactionTap,
        ),
      ),
    ),
  );
}
```

Then add a new group at the end of the existing `group('LetterCard', ...)`:

```dart
group('BiDi text direction', () {
  testWidgets('Arabic text sets RTL on underlying RichText', (tester) async {
    await tester.pumpWidget(buildTestWidget(text: 'مرحبا بالعالم'));

    // Find the RichText inside LinkableText
    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(LinkableText),
        matching: find.byType(RichText),
      ),
    );
    expect(richText.textDirection, TextDirection.rtl);
  });

  testWidgets('English text sets LTR on underlying RichText', (tester) async {
    await tester.pumpWidget(buildTestWidget(text: 'Hello world'));

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(LinkableText),
        matching: find.byType(RichText),
      ),
    );
    expect(richText.textDirection, TextDirection.ltr);
  });

  testWidgets('Arabic-first mixed text sets RTL on underlying RichText', (tester) async {
    await tester.pumpWidget(buildTestWidget(text: 'مرحبا Hello كيف حالك'));

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(LinkableText),
        matching: find.byType(RichText),
      ),
    );
    expect(richText.textDirection, TextDirection.rtl);
  });

  testWidgets('English-first mixed text sets LTR on underlying RichText', (tester) async {
    await tester.pumpWidget(buildTestWidget(text: 'Hello مرحبا World'));

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(LinkableText),
        matching: find.byType(RichText),
      ),
    );
    expect(richText.textDirection, TextDirection.ltr);
  });

  testWidgets('Arabic quoted text sets RTL on quote bar Text widget', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      text: 'Reply body',
      quotedText: 'مرحبا بالعالم',
    ));

    // Find the Text widget displaying the quoted text (not the body)
    final textWidgets = tester.widgetList<Text>(find.byType(Text));
    final quoteTextWidget = textWidgets.where(
      (t) => t.data == 'مرحبا بالعالم',
    ).first;
    expect(quoteTextWidget.textDirection, TextDirection.rtl);
  });

  testWidgets('English quoted text sets LTR on quote bar Text widget', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      text: 'Reply body',
      quotedText: 'Hello world',
    ));

    final textWidgets = tester.widgetList<Text>(find.byType(Text));
    final quoteTextWidget = textWidgets.where(
      (t) => t.data == 'Hello world',
    ).first;
    expect(quoteTextWidget.textDirection, TextDirection.ltr);
  });

  testWidgets('Arabic-first mixed quoted text sets RTL on quote bar', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      text: 'Reply body',
      quotedText: 'مرحبا Hello كيف',
    ));

    final textWidgets = tester.widgetList<Text>(find.byType(Text));
    final quoteTextWidget = textWidgets.where(
      (t) => t.data == 'مرحبا Hello كيف',
    ).first;
    expect(quoteTextWidget.textDirection, TextDirection.rtl);
  });
});
```

> **Why this catches missing wiring:** These tests pump a real `LetterCard` and then inspect the `RichText` widget that Flutter renders from `LinkableText`. If `letter_card.dart:217` does not pass `textDirection: detectTextDirection(text)` to `LinkableText`, the `RichText.textDirection` will be `null` (inherited from `Directionality`) instead of the expected explicit `TextDirection.rtl` or `TextDirection.ltr` value. The quote bar tests similarly catch missing `textDirection` on the plain `Text` widget inside `_buildQuoteBar()` at line 330.

### 4.2 MessageBubble — extend existing tests

**File:** `test/features/feed/presentation/widgets/message_bubble_test.dart` (extend)

Add a new group at the end:

```dart
group('BiDi text direction', () {
  testWidgets('Arabic text sets RTL on underlying RichText', (tester) async {
    await tester.pumpWidget(wrap(const MessageBubble(
      text: 'مرحبا بالعالم',
      time: '3:00 PM',
      isIncoming: true,
    )));

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(LinkableText),
        matching: find.byType(RichText),
      ),
    );
    expect(richText.textDirection, TextDirection.rtl);
  });

  testWidgets('English text sets LTR on underlying RichText', (tester) async {
    await tester.pumpWidget(wrap(const MessageBubble(
      text: 'Hello world',
      time: '3:00 PM',
      isIncoming: true,
    )));

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(LinkableText),
        matching: find.byType(RichText),
      ),
    );
    expect(richText.textDirection, TextDirection.ltr);
  });

  testWidgets('Arabic-first mixed text sets RTL', (tester) async {
    await tester.pumpWidget(wrap(const MessageBubble(
      text: 'أهلا Hello كيف الحال',
      time: '3:00 PM',
      isIncoming: true,
    )));

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(LinkableText),
        matching: find.byType(RichText),
      ),
    );
    expect(richText.textDirection, TextDirection.rtl);
  });

  testWidgets('sent message with name prefix detects direction from body', (tester) async {
    await tester.pumpWidget(wrap(const MessageBubble(
      text: 'مرحبا بالعالم',
      time: '3:00 PM',
      isIncoming: false,
      senderLabel: 'You',
    )));

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(LinkableText),
        matching: find.byType(RichText),
      ),
    );
    expect(richText.textDirection, TextDirection.rtl);
  });

  testWidgets('Arabic quoted text sets RTL on quote bar Text widget', (tester) async {
    await tester.pumpWidget(wrap(const MessageBubble(
      text: 'Reply body',
      time: '3:00 PM',
      isIncoming: true,
      quotedText: 'مرحبا بالعالم',
    )));

    final textWidgets = tester.widgetList<Text>(find.byType(Text));
    final quoteTextWidget = textWidgets.where(
      (t) => t.data == 'مرحبا بالعالم',
    ).first;
    expect(quoteTextWidget.textDirection, TextDirection.rtl);
  });

  testWidgets('English quoted text sets LTR on quote bar Text widget', (tester) async {
    await tester.pumpWidget(wrap(const MessageBubble(
      text: 'Reply body',
      time: '3:00 PM',
      isIncoming: true,
      quotedText: 'Hello world',
    )));

    final textWidgets = tester.widgetList<Text>(find.byType(Text));
    final quoteTextWidget = textWidgets.where(
      (t) => t.data == 'Hello world',
    ).first;
    expect(quoteTextWidget.textDirection, TextDirection.ltr);
  });
});
```

### 4.3 QuotePreviewBar — extend existing tests

**File:** `test/features/feed/presentation/widgets/quote_preview_bar_test.dart` (extend)

Add a new group at the end:

```dart
group('BiDi text direction', () {
  testWidgets('Arabic quoted text sets RTL on Text widget', (tester) async {
    await tester.pumpWidget(wrap(const QuotePreviewBar(text: 'مرحبا بالعالم')));

    // Find the Text widget that displays the quoted text (not the "Replying to" label)
    final textWidgets = tester.widgetList<Text>(find.byType(Text));
    final quotedTextWidget = textWidgets.where(
      (t) => t.data == 'مرحبا بالعالم',
    ).first;
    expect(quotedTextWidget.textDirection, TextDirection.rtl);
  });

  testWidgets('English quoted text sets LTR on Text widget', (tester) async {
    await tester.pumpWidget(wrap(const QuotePreviewBar(text: 'Hello world')));

    final textWidgets = tester.widgetList<Text>(find.byType(Text));
    final quotedTextWidget = textWidgets.where(
      (t) => t.data == 'Hello world',
    ).first;
    expect(quotedTextWidget.textDirection, TextDirection.ltr);
  });

  testWidgets('Arabic-first mixed quoted text sets RTL', (tester) async {
    await tester.pumpWidget(wrap(const QuotePreviewBar(text: 'مرحبا Hello')));

    final textWidgets = tester.widgetList<Text>(find.byType(Text));
    final quotedTextWidget = textWidgets.where(
      (t) => t.data == 'مرحبا Hello',
    ).first;
    expect(quotedTextWidget.textDirection, TextDirection.rtl);
  });
});
```

### 4.4 Implement the Changes

**File:** `lib/features/conversation/presentation/widgets/letter_card.dart`

1. Add import at top:
```dart
import 'package:flutter_app/core/utils/text_direction_utils.dart';
```

2. Update LinkableText at line 217:
```dart
// BEFORE:
child: LinkableText(
  text: text,
  style: TextStyle(...),
),

// AFTER:
child: LinkableText(
  text: text,
  textDirection: detectTextDirection(text),
  style: TextStyle(...),
),
```

3. Update `_buildQuoteBar()` at line 330 — this is a plain `Text` widget inside the `_buildQuoteBar` method (line 314). Add `textDirection` to it:
```dart
// BEFORE (letter_card.dart line 330):
child: Text(
  displayText,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(...),
),

// AFTER:
child: Text(
  displayText,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  textDirection: detectTextDirection(displayText),
  style: TextStyle(...),
),
```

**File:** `lib/features/feed/presentation/widgets/message_bubble.dart`

1. Add import at top:
```dart
import 'package:flutter_app/core/utils/text_direction_utils.dart';
```

2. Update LinkableText at line 253:
```dart
// BEFORE:
textWidget = LinkableText(
  text: text,
  style: bodyStyle,
  prefixSpans: name.isNotEmpty
      ? [TextSpan(text: '$name: ', style: nameStyle)]
      : null,
  suffixSpans: [trailingSpacer],
);

// AFTER:
textWidget = LinkableText(
  text: text,
  textDirection: detectTextDirection(text),
  style: bodyStyle,
  prefixSpans: name.isNotEmpty
      ? [TextSpan(text: '$name: ', style: nameStyle)]
      : null,
  suffixSpans: [trailingSpacer],
);
```

3. Update `_buildQuoteBar()` at line 353 — this is a plain `Text` widget inside the `_buildQuoteBar` method (line 337). Add `textDirection` to it:
```dart
// BEFORE (message_bubble.dart line 353):
child: Text(
  displayText,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(...),
),

// AFTER:
child: Text(
  displayText,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  textDirection: detectTextDirection(displayText),
  style: TextStyle(...),
),
```

**File:** `lib/features/feed/presentation/widgets/quote_preview_bar.dart`

The quote preview uses a plain `Text` widget (not `LinkableText`), so `textDirection` must be set directly on the `Text` widget.

1. Add import at top:
```dart
import 'package:flutter_app/core/utils/text_direction_utils.dart';
```

2. Update the `Text` widget at line 48:
```dart
// BEFORE:
Text(
  text,
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
  style: const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: Color.fromRGBO(255, 255, 255, 0.50),
  ),
),

// AFTER:
Text(
  text,
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
  textDirection: detectTextDirection(text),
  style: const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: Color.fromRGBO(255, 255, 255, 0.50),
  ),
),
```

### 4.5 Run Tests

```bash
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart
flutter test test/features/feed/presentation/widgets/message_bubble_test.dart
flutter test test/features/feed/presentation/widgets/quote_preview_bar_test.dart
```

---

## Phase 5: Auto-Detect Direction on Compose Input Fields

**Goal:** The compose `TextField` dynamically switches direction as the user types, so Arabic-first input renders RTL in the input field itself. Tests pump the real widget and inspect the `TextField.textDirection`.

### 5.1 ComposeArea — extend existing tests

**File:** `test/features/conversation/presentation/widgets/compose_area_test.dart` (extend)

Add a new group inside the existing test structure (uses the existing `buildTestWidget` helper and `_TestAppLocalizationsDelegate`):

```dart
group('BiDi input direction', () {
  testWidgets('TextField defaults to LTR when empty', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    // Initially LTR (default) or null — either is acceptable
    expect(
      textField.textDirection,
      anyOf(isNull, equals(TextDirection.ltr)),
    );
  });

  testWidgets('TextField switches to RTL when Arabic is typed', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'مرحبا');
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.textDirection, TextDirection.rtl);
  });

  testWidgets('TextField stays LTR when English is typed', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.textDirection, TextDirection.ltr);
  });

  testWidgets('TextField switches to RTL for Arabic-first mixed text', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'مرحبا Hello');
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.textDirection, TextDirection.rtl);
  });

  testWidgets('TextField resets to LTR when cleared and English typed', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Type Arabic
    await tester.enterText(find.byType(TextField), 'مرحبا');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.rtl,
    );

    // Clear and type English
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.ltr,
    );
  });
});
```

### 5.2 InlineReplyInput — extend existing tests

**File:** `test/features/feed/presentation/widgets/inline_reply_input_test.dart` (extend)

Add a new group:

```dart
group('BiDi input direction', () {
  testWidgets('TextField switches to RTL when Arabic is typed', (tester) async {
    await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));

    await tester.enterText(find.byType(TextField), 'مرحبا');
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.textDirection, TextDirection.rtl);
  });

  testWidgets('TextField stays LTR when English is typed', (tester) async {
    await tester.pumpWidget(wrap(InlineReplyInput(onSend: (_) {})));

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.textDirection, TextDirection.ltr);
  });
});
```

### 5.3 ExpandedComposeInput — extend existing tests

**File:** `test/features/feed/presentation/widgets/expanded_compose_input_test.dart` (extend)

Add a new group using the existing `wrap()` helper:

```dart
group('BiDi input direction', () {
  testWidgets('TextField switches to RTL when Arabic is typed', (tester) async {
    await tester.pumpWidget(wrap(ExpandedComposeInput(onSend: (_) {})));

    await tester.enterText(find.byType(TextField), 'مرحبا');
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.textDirection, TextDirection.rtl);
  });

  testWidgets('TextField stays LTR when English is typed', (tester) async {
    await tester.pumpWidget(wrap(ExpandedComposeInput(onSend: (_) {})));

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.textDirection, TextDirection.ltr);
  });
});
```

### 5.4 Implement the Changes

Apply the same pattern to all three input widgets: **ComposeArea**, **InlineReplyInput**, and **ExpandedComposeInput**.

**Pattern (shown for ComposeArea, repeat for others):**

**File:** `lib/features/conversation/presentation/widgets/compose_area.dart`

1. Add import:
```dart
import 'package:flutter_app/core/utils/text_direction_utils.dart';
```

2. Add state variable in `_ComposeAreaState`:
```dart
TextDirection _inputDirection = TextDirection.ltr;
```

3. Add listener in `initState()` (alongside existing `_controller` listener):
```dart
_controller.addListener(_updateInputDirection);
```

4. Add method:
```dart
void _updateInputDirection() {
  final dir = detectTextDirection(_controller.text);
  if (dir != _inputDirection) {
    setState(() => _inputDirection = dir);
  }
}
```

5. Remove listener in `dispose()`:
```dart
_controller.removeListener(_updateInputDirection);
```

6. Add `textDirection` to the `TextField` (line 295):
```dart
child: TextField(
  controller: _controller,
  focusNode: _focusNode,
  textDirection: _inputDirection,
  // ... rest unchanged
),
```

**File:** `lib/features/feed/presentation/widgets/inline_reply_input.dart`

Same pattern (steps 1-6) applied to `_InlineReplyInputState` and its `TextField` at line 226.

**File:** `lib/features/feed/presentation/widgets/expanded_compose_input.dart`

Same pattern (steps 1-6) applied to its State class and TextField.

### 5.5 Run Tests

```bash
flutter test test/features/conversation/presentation/widgets/compose_area_test.dart
flutter test test/features/feed/presentation/widgets/inline_reply_input_test.dart
flutter test test/features/feed/presentation/widgets/expanded_compose_input_test.dart
```

---

## Phase 6: Symmetric Sanitization — Send + Group Paths

**Goal:** Apply `sanitizeMessageText()` on both send and receive paths, and close the group message gap. The group path must sanitize text **once at the top** and use the sanitized value consistently for dedupe, save, publish, and inbox store.

### 6.1 Chat Send Path — extend existing tests

**File:** `test/features/conversation/application/send_chat_message_use_case_test.dart` (extend)

Add a new group that verifies sanitization is applied to **both** the saved message and the wire payload. The existing suite already exposes the outgoing JSON via `p2pService.lastSentMessage` (see line 354), so we assert against both sinks. This mirrors the group send pattern in Phase 6.2.

```dart
group('BiDi sanitization on send', () {
  test('strips dangerous override characters from saved message and wire payload', () async {
    final (result, message) = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: 'target-peer',
      text: 'Hello\u202E world!',  // U+202E = RLO (dangerous)
      senderPeerId: 'my-peer',
      senderUsername: 'Me',
    );

    expect(result, SendChatMessageResult.success);

    // 1. Saved message text is sanitized
    expect(message!.text, 'Hello world!');
    expect(messageRepo.saved.first.text, 'Hello world!');

    // 2. Wire payload JSON is also sanitized
    expect(p2pService.lastSentMessage, isNotNull);
    expect(p2pService.lastSentMessage, contains('"text":"Hello world!"'));
    expect(p2pService.lastSentMessage, isNot(contains('\u202E')));
  });

  test('preserves LRM/RLM in saved message and wire payload', () async {
    final (result, message) = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: 'target-peer',
      text: 'Hello\u200E مرحبا\u200F',  // LRM + RLM (safe, helpful)
      senderPeerId: 'my-peer',
      senderUsername: 'Me',
    );

    expect(result, SendChatMessageResult.success);

    // 1. Saved message preserves LRM/RLM
    expect(message!.text, 'Hello\u200E مرحبا\u200F');
    expect(messageRepo.saved.first.text, 'Hello\u200E مرحبا\u200F');

    // 2. Wire payload preserves LRM/RLM
    expect(p2pService.lastSentMessage, isNotNull);
    expect(p2pService.lastSentMessage, contains('Hello\u200E'));
    expect(p2pService.lastSentMessage, contains('\u200F'));
  });
});
```

### 6.2 Group Send Path — extend existing tests

**File:** `test/features/groups/application/send_group_message_use_case_test.dart` (extend)

The existing suite at line 176 already asserts that `quotedMessageId` propagates through publish, inbox, and saved message. Mirror that pattern for sanitization. Add a new group:

```dart
group('BiDi sanitization on send', () {
  test('strips dangerous override characters and propagates sanitized text', () async {
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello\u202E group!',  // U+202E = RLO (dangerous)
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.success);

    // 1. Saved GroupMessage.text is sanitized
    expect(message!.text, 'Hello group!');
    final saved = await msgRepo.getMessage(message.id);
    expect(saved!.text, 'Hello group!');

    // 2. group:publish received sanitized text
    final publishMsg = bridge.sentMessages.firstWhere(
      (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
    );
    final publishPayload =
        (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
    expect(publishPayload['text'], 'Hello group!');

    // 3. group:inboxStore received sanitized text
    final inboxMsg = bridge.sentMessages.firstWhere(
      (m) => (jsonDecode(m) as Map)['cmd'] == 'group:inboxStore',
    );
    final inboxPayload =
        (jsonDecode(inboxMsg) as Map)['payload'] as Map<String, dynamic>;
    final innerPayload =
        jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
    expect(innerPayload['text'], 'Hello group!');
  });

  test('preserves LRM/RLM through publish, inbox, and save', () async {
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello\u200E مرحبا\u200F',  // LRM + RLM preserved
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.success);

    // Saved message preserves LRM/RLM
    expect(message!.text, 'Hello\u200E مرحبا\u200F');
    final saved = await msgRepo.getMessage(message.id);
    expect(saved!.text, 'Hello\u200E مرحبا\u200F');

    // Publish preserves LRM/RLM
    final publishMsg = bridge.sentMessages.firstWhere(
      (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
    );
    final publishPayload =
        (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
    expect(publishPayload['text'], 'Hello\u200E مرحبا\u200F');
  });
});
```

### 6.3 Group Receive Path — extend existing tests

**File:** `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` (extend)

```dart
group('BiDi sanitization on receive', () {
  test('strips dangerous chars from incoming group message text', () async {
    // Call handleIncomingGroupMessage with text containing U+202E (RLO)
    // Assert the saved GroupMessage.text does NOT contain U+202E
  });

  test('preserves LRM in incoming group message text', () async {
    // Call handleIncomingGroupMessage with text containing U+200E (LRM)
    // Assert the saved GroupMessage.text still contains U+200E
  });

  test('sanitized text used for content-based dedupe', () async {
    // Send the same message twice — once with U+200B injected, once without
    // Both should be considered duplicates after sanitization
  });
});
```

### 6.4 Implement the Changes

#### Chat Send Path

**File:** `lib/features/conversation/application/send_chat_message_use_case.dart`

Add import and sanitize text before building the payload:

```dart
import 'package:flutter_app/core/utils/text_sanitizer.dart';

// At the top of the send function, before any usage of `text`:
final sanitizedText = sanitizeMessageText(text);
// Use `sanitizedText` everywhere below instead of raw `text`
```

#### Group Send Path (explicit line-level changes)

**File:** `lib/features/groups/application/send_group_message_use_case.dart`

The raw `text` parameter flows through **5 locations**: push body (line 134), publish (line 142), inbox store (line 157), GroupMessage entity (line 199), and inbox JSON (line 255 inside `_safeInboxStore`). Sanitize **once** and use consistently:

```dart
import 'package:flutter_app/core/utils/text_sanitizer.dart';

// At the top of the function, immediately after the early-return checks:
final sanitizedText = sanitizeMessageText(text);

// Then replace ALL 5 usages of raw `text` with `sanitizedText`:

// Line 134: push body
final pushBody = _buildGroupPushBody(
  senderUsername: senderUsername,
  text: sanitizedText,                  // was: text
  mediaAttachments: mediaAttachments,
);

// Line 142: publish to GossipSub
final publishFuture = callGroupPublish(
  bridge,
  groupId: groupId,
  text: sanitizedText,                  // was: text
  senderPeerId: senderPeerId,
  // ... rest unchanged
);

// Line 157: inbox store-and-forward
final inboxFuture = _safeInboxStore(
  bridge: bridge,
  groupId: groupId,
  senderPeerId: senderPeerId,
  senderUsername: senderUsername,
  keyEpoch: latestKey?.keyGeneration ?? 0,
  text: sanitizedText,                  // was: text
  // ... rest unchanged
);

// Line 199: local GroupMessage entity
final message = GroupMessage(
  // ...
  text: sanitizedText,                  // was: text
  // ...
);

// Line 255 (inside _safeInboxStore): JSON for Go inbox
// This automatically uses sanitizedText because the `text` parameter
// passed to _safeInboxStore is already sanitized above.
```

#### Group Receive Path (explicit line-level changes)

**File:** `lib/features/groups/application/handle_incoming_group_message_use_case.dart`

The raw `text` parameter flows through **2 locations**: content-based dedupe (line 104) and GroupMessage creation (line 131). Sanitize **once** and use for both:

```dart
import 'package:flutter_app/core/utils/text_sanitizer.dart';

// At the top of the function, before the dedupe check:
final sanitizedText = sanitizeMessageText(text);

// Line 104: content-based deduplication — use sanitized text
final isDuplicate = await msgRepo.existsByContent(
  groupId,
  senderId,
  sanitizedText,                       // was: text
  parsedTimestamp,
);

// Line 131: GroupMessage entity — use same sanitized text
final message = GroupMessage(
  id: resolvedMessageId,
  groupId: groupId,
  senderPeerId: senderId,
  senderUsername: senderUsername,
  text: sanitizedText,                 // was: text
  timestamp: parsedTimestamp,
  // ... rest unchanged
);
```

> **Why sanitize once:** If the dedupe check uses raw text but the save uses sanitized text (or vice versa), a message with `\u200B` injected would fail the dedupe against its clean twin and create a duplicate in the DB. Sanitizing once at the top ensures dedupe and save see the same string.

### 6.5 Run Tests

```bash
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/features/groups/application/send_group_message_use_case_test.dart
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart
```

---

## Summary of All Files

### New Files to Create (2)

| # | File | Purpose |
|---|------|---------|
| 1 | `lib/core/utils/text_direction_utils.dart` | `detectTextDirection()` utility |
| 2 | `test/core/utils/text_direction_utils_test.dart` | Tests for direction detection |

### New File (optional, for LinkableText unit tests) (1)

| # | File | Purpose |
|---|------|---------|
| 3 | `test/shared/widgets/linkable_text_test.dart` | Tests for LinkableText `textDirection` param |

### Existing Files to Modify — Production Code (8)

| # | File | Change |
|---|------|--------|
| 1 | `lib/core/utils/text_sanitizer.dart` | Update `_bidiPattern` regex to preserve LRM/RLM/isolates |
| 2 | `lib/shared/widgets/linkable_text.dart` | Add `textDirection` parameter, pass to `Text.rich()` |
| 3 | `lib/features/conversation/presentation/widgets/letter_card.dart` | Add `detectTextDirection()` call on text body |
| 4 | `lib/features/feed/presentation/widgets/message_bubble.dart` | Add `detectTextDirection()` call on text body + `_buildQuoteBar()` quote Text |
| 5 | `lib/features/feed/presentation/widgets/quote_preview_bar.dart` | Add `detectTextDirection()` call on quoted text `Text` widget |
| 6 | `lib/features/conversation/presentation/widgets/compose_area.dart` | Dynamic `textDirection` on TextField via controller listener |
| 7 | `lib/features/feed/presentation/widgets/inline_reply_input.dart` | Dynamic `textDirection` on TextField via controller listener |
| 8 | `lib/features/feed/presentation/widgets/expanded_compose_input.dart` | Dynamic `textDirection` on TextField via controller listener |

### Existing Files to Modify — Send/Receive Paths (3)

| # | File | Change |
|---|------|--------|
| 9 | `lib/features/conversation/application/send_chat_message_use_case.dart` | Sanitize text once at top, use sanitized value in payload |
| 10 | `lib/features/groups/application/send_group_message_use_case.dart` | Sanitize text once at top, use for publish/inbox/save/push (5 locations) |
| 11 | `lib/features/groups/application/handle_incoming_group_message_use_case.dart` | Sanitize text once at top, use for dedupe + save (2 locations) |

### Existing Test Files to Extend (10)

| # | File | New Group |
|---|------|-----------|
| 1 | `test/core/utils/text_sanitizer_test.dart` | Update 4 tests (LRM/RLM, isolates, ALM, mixed-only) + add BiDi preservation group |
| 2 | `test/features/conversation/presentation/widgets/letter_card_test.dart` | `BiDi text direction` — body RichText + quote bar Text direction |
| 3 | `test/features/feed/presentation/widgets/message_bubble_test.dart` | `BiDi text direction` — body RichText + quote bar Text direction |
| 4 | `test/features/feed/presentation/widgets/quote_preview_bar_test.dart` | `BiDi text direction` — pumps widget, inspects Text.textDirection |
| 5 | `test/features/conversation/presentation/widgets/compose_area_test.dart` | `BiDi input direction` — types text, inspects TextField.textDirection |
| 6 | `test/features/feed/presentation/widgets/inline_reply_input_test.dart` | `BiDi input direction` — types text, inspects TextField.textDirection |
| 7 | `test/features/feed/presentation/widgets/expanded_compose_input_test.dart` | `BiDi input direction` — types text, inspects TextField.textDirection |
| 8 | `test/features/conversation/application/send_chat_message_use_case_test.dart` | `BiDi sanitization on send` — verifies sanitized payload |
| 9 | `test/features/groups/application/send_group_message_use_case_test.dart` | `BiDi sanitization on send` — verifies sanitized text in publish, inbox, save |
| 10 | `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` | `BiDi sanitization on receive` — verifies sanitized save + dedupe |

---

## Execution Order

```
Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6
  │          │          │          │          │          │
  ▼          ▼          ▼          ▼          ▼          ▼
detect()   sanitizer  LinkableText LetterCard compose   send/recv
utility    update     widget      + Bubble   inputs    symmetry
                                  + QuoteBar
```

Each phase follows strict red-green TDD:
1. Write failing tests first
2. Implement minimum code to pass
3. Run full test suite to confirm no regressions
4. Move to next phase

---

## Why This Fixes the Problem

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Mixed text scrambled on display | No `textDirection` on `Text` widgets -> Flutter defaults to LTR | `detectTextDirection()` + explicit `textDirection` on every `LinkableText` and `Text` |
| OS keyboard BiDi markers discarded | `_bidiPattern` strips LRM, RLM, and isolates | Updated regex preserves safe markers |
| Quote previews scrambled | `QuotePreviewBar`, `LetterCard._buildQuoteBar`, and `MessageBubble._buildQuoteBar` `Text` widgets have no `textDirection` | Added `detectTextDirection()` on all three quote bar `Text` widgets |
| Input field doesn't flip for Arabic | No `textDirection` on `TextField` | Dynamic direction detection via controller listener on all compose fields |
| Group messages not sanitized | Missing `sanitizeMessageText()` in send + receive | Sanitize once at top, use for publish/inbox/save/dedupe |
| Outgoing messages not sanitized | Only receive path sanitizes | Added `sanitizeMessageText()` to send path |
| Group dedupe mismatch risk | Raw text for dedupe vs sanitized for save | Single `sanitizedText` variable used for both |

---

## Changelog

### v6 (audit round 5)

11. **(Medium) ALM (U+061C) moved to preserved set.** Unicode 6.3 added ALM specifically to improve bidi handling for Arabic numeric/context cases. Stripping it caused mixed Arabic + numbers/punctuation to render oddly. Removed `\u061C` from `_bidiPattern` regex, added it to the preserved doc comment alongside LRM/RLM/isolates. Flipped the Phase 2.1 test from "still strips ALM" to "preserves ALM". Added a 4th existing test update in Phase 2.3 for the source test at line 32-34.

### v5 (audit round 4)

9. **(Medium) Chat send tests now assert wire payload, not just saved message.** Phase 6.1 expanded from pseudocode to concrete tests that assert both `messageRepo.saved.first.text` and `p2pService.lastSentMessage` JSON. Dangerous chars must be absent from the wire; LRM/RLM must survive. Mirrors the group send pattern in Phase 6.2.

10. **(Low) LetterCard test helper extended with `quotedText` and `isQuoteUnavailable`.** Added a prerequisite step in Phase 4.1 showing the exact before/after diff for `buildTestWidget` (line 9 in `letter_card_test.dart`). Without this, the quote bar tests calling `buildTestWidget(quotedText: ...)` would not compile.

### v4 (audit round 3)

8. **(Medium) MessageBubble quote bar now in scope.** Added quote bar tests (Arabic/English quoted text) to the `BiDi text direction` group in `message_bubble_test.dart`. Added implementation step 3 for `MessageBubble._buildQuoteBar()` at `message_bubble.dart:353` — sets `textDirection: detectTextDirection(displayText)` on the plain `Text` widget, matching the LetterCard quote bar pattern.

### v3 (audit round 2)

5. **(Medium) Group send path now has explicit test coverage.** Added Phase 6.2 with a `BiDi sanitization on send` group in `send_group_message_use_case_test.dart`. Tests assert sanitized text reaches the saved `GroupMessage`, `group:publish` payload, and `group:inboxStore` inner payload — mirrors the existing `quotedMessageId` propagation test at line 176. Also verifies LRM/RLM are preserved through the full pipeline.

6. **(Medium) LetterCard quote bar handling is now mandatory, not conditional.** Replaced the "if the quoted text section also uses..." hedge with explicit implementation: `detectTextDirection(displayText)` on the `Text` widget in `_buildQuoteBar()` at `letter_card.dart:330`. Added 3 quote-specific widget tests (Arabic/English/mixed quoted text) to the `BiDi text direction` group in `letter_card_test.dart`.

7. **(Low) ExpandedComposeInput now has matching test coverage.** Added Phase 5.3 with 2 BiDi direction tests in `expanded_compose_input_test.dart`, and added the test file to the Phase 5.5 run command. Summary table updated from 7 to 10 test files.

### v2 (audit round 1)

1. **(High) Widget wiring tests now verify actual rendering, not just utility calls.** Phases 4 and 5 pump the real widget (`LetterCard`, `MessageBubble`, `QuotePreviewBar`, `ComposeArea`, `InlineReplyInput`) and inspect `RichText.textDirection` or `TextField.textDirection` on the rendered tree. If wiring is forgotten, these tests fail.

2. **(Medium) QuotePreviewBar explicitly in scope.** Added to Phase 4 with its own tests and implementation. The widget uses a plain `Text` (not `LinkableText`), so `textDirection` is set directly on the `Text` widget at `quote_preview_bar.dart:48`.

3. **(Medium) Phase 6 group path made explicit.** Shows exact line-level changes for `send_group_message_use_case.dart` (5 locations) and `handle_incoming_group_message_use_case.dart` (2 locations). Both sanitize once via `final sanitizedText = sanitizeMessageText(text)` at the top, then use `sanitizedText` consistently for dedupe, save, publish, inbox, and push body.

4. **Dropped Phase 7 (standalone integration test file).** All tests extend existing test files instead of creating new helper-only files, matching the project's test structure.
