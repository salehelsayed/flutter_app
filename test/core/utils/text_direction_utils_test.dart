import 'dart:ui' show TextDirection;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';

void main() {
  group('detectTextDirection', () {
    test('pure English text returns LTR', () {
      expect(detectTextDirection('Hello world'), TextDirection.ltr);
    });

    test('pure Arabic text returns RTL', () {
      expect(detectTextDirection('مرحبا بالعالم'), TextDirection.rtl);
    });

    test('pure Hebrew text returns RTL', () {
      expect(detectTextDirection('שלום עולם'), TextDirection.rtl);
    });

    test('Arabic then English returns RTL', () {
      expect(detectTextDirection('مرحبا Hello كيف حالك'), TextDirection.rtl);
    });

    test('English then Arabic returns LTR', () {
      expect(detectTextDirection('Hello مرحبا World'), TextDirection.ltr);
    });

    test('leading spaces then Arabic returns RTL', () {
      expect(detectTextDirection('   مرحبا hello'), TextDirection.rtl);
    });

    test('leading digits then Arabic returns RTL', () {
      expect(detectTextDirection('123 مرحبا'), TextDirection.rtl);
    });

    test('leading digits then English returns LTR', () {
      expect(detectTextDirection('123 hello'), TextDirection.ltr);
    });

    test('leading punctuation then Arabic returns RTL', () {
      expect(detectTextDirection('... مرحبا'), TextDirection.rtl);
    });

    test('leading emoji then English returns LTR', () {
      expect(detectTextDirection('😀 hello'), TextDirection.ltr);
    });

    test('leading emoji then Arabic returns RTL', () {
      expect(detectTextDirection('😀 مرحبا'), TextDirection.rtl);
    });

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

    test('Arabic Supplement returns RTL', () {
      expect(detectTextDirection('\u0750'), TextDirection.rtl);
    });

    test('Arabic Extended-A returns RTL', () {
      expect(detectTextDirection('\u08A0'), TextDirection.rtl);
    });

    test('Arabic Presentation Forms-A returns RTL', () {
      expect(detectTextDirection('\uFB50'), TextDirection.rtl);
    });

    test('Arabic Presentation Forms-B returns RTL', () {
      expect(detectTextDirection('\uFE70'), TextDirection.rtl);
    });

    test('extended Latin returns LTR', () {
      expect(detectTextDirection('Ärger öffnen über'), TextDirection.ltr);
    });

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
