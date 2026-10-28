import 'dart:typed_data';

import 'package:flutter_app/features/translate_preview/gemma_preview_prompts.dart';
import 'package:flutter_app/features/translate_preview/language_heuristic.dart';
import 'package:flutter_app/features/translate_preview/wav_16k_mono.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Arabizi', () {
    for (final text in [
      'ana mesh 3aref',
      '7abibi wallah',
      'Shlonak? inshallah zain',
      'ezayak ya basha, 3amel eh?',
      'yalla bina delwa2ty',
      'ma3lesh',
      'la2 msh keda',
    ]) {
      test('"$text" is Arabizi and gets no Translate', () {
        expect(looksLikeArabizi(text), isTrue);
        expect(shouldOfferTranslate(text, 'en'), isFalse);
        expect(shouldOfferTranslate(text, 'ar'), isFalse);
        expect(shouldOfferTranslate(text, 'de'), isFalse);
      });
    }

    for (final text in [
      'Meet me at 3pm on the 2nd floor',
      'Ana is coming tomorrow with the kids',
      'See you 2day, gr8 news',
      'I bought a PS5 and a 3D printer',
      'Guten Morgen, wie geht es dir?',
      'Good morning everyone',
    ]) {
      test('"$text" is not Arabizi', () {
        expect(looksLikeArabizi(text), isFalse);
      });
    }

    test('Arabic script is never Arabizi', () {
      expect(looksLikeArabizi('أنا مش عارف'), isFalse);
    });
  });

  group('same-language hiding', () {
    test('Arabic text: hidden on an Arabic phone, offered elsewhere', () {
      const text = 'مرحبا، كيف حالك اليوم؟';
      expect(shouldOfferTranslate(text, 'ar'), isFalse);
      expect(shouldOfferTranslate(text, 'de'), isTrue);
      expect(shouldOfferTranslate(text, 'en'), isTrue);
    });

    test('German text: hidden on a German phone, offered on English', () {
      const text = 'Guten Morgen, wie geht es dir heute?';
      expect(guessLatinLanguage(text), 'de');
      expect(shouldOfferTranslate(text, 'de'), isFalse);
      expect(shouldOfferTranslate(text, 'en'), isTrue);
      expect(shouldOfferTranslate(text, 'ar'), isTrue);
    });

    test('English text: hidden on an English phone, offered on German', () {
      const text = 'How are you doing today?';
      expect(guessLatinLanguage(text), 'en');
      expect(shouldOfferTranslate(text, 'en'), isFalse);
      expect(shouldOfferTranslate(text, 'de'), isTrue);
    });

    test('a mostly Arabic text with one English word is Arabic', () {
      expect(dominantScript('شفت الـ video امبارح؟'), TextScript.arabic);
      expect(shouldOfferTranslate('شفت الـ video امبارح؟', 'ar'), isFalse);
    });

    test('Russian is hidden on a Russian phone', () {
      expect(shouldOfferTranslate('Привет, как дела?', 'ru'), isFalse);
      expect(shouldOfferTranslate('Привет, как дела?', 'en'), isTrue);
    });

    test('Japanese kanji and kana count as one language', () {
      expect(shouldOfferTranslate('今日はいい天気ですね', 'ja'), isFalse);
      expect(shouldOfferTranslate('今日はいい天気ですね', 'en'), isTrue);
    });

    test('Latin text of no known language is offered', () {
      expect(guessLatinLanguage('Zdravo prijatelju'), isNull);
      expect(shouldOfferTranslate('Zdravo prijatelju', 'en'), isTrue);
    });

    test('nothing to translate: emoji, digits, empty', () {
      expect(shouldOfferTranslate('😀🎉', 'en'), isFalse);
      expect(shouldOfferTranslate('12:30', 'ar'), isFalse);
      expect(shouldOfferTranslate('', 'en'), isFalse);
    });

    test('a phone language without a prompt name gets no Translate', () {
      expect(translateLanguageName('xx'), isNull);
      expect(shouldOfferTranslate('مرحبا', 'xx'), isFalse);
    });

    test('the prompt names languages the way the benchmark did', () {
      expect(translateLanguageName('ar'), 'Arabic');
      expect(translateLanguageName('de'), 'German');
      expect(translateLanguageName('en'), 'English');
      expect(
        gemmaTranslatePrompt('German', 'hello'),
        'Translate this chat message to German. Output only the translation.\nhello',
      );
    });
  });

  group('wav16kMono', () {
    test('writes a 16 kHz mono 16-bit header and averages stereo', () {
      final pcm = ByteData(8)
        ..setInt16(0, 1000, Endian.little)
        ..setInt16(2, 3000, Endian.little)
        ..setInt16(4, -2000, Endian.little)
        ..setInt16(6, -4000, Endian.little);
      final wav = ByteData.sublistView(
        wav16kMono(pcm.buffer.asUint8List(), sampleRate: 16000, channels: 2),
      );
      expect(String.fromCharCodes(wav.buffer.asUint8List(0, 4)), 'RIFF');
      expect(wav.getUint16(22, Endian.little), 1);
      expect(wav.getUint32(24, Endian.little), 16000);
      expect(wav.getUint16(34, Endian.little), 16);
      expect(wav.getUint32(40, Endian.little), 4);
      expect(wav.getInt16(44, Endian.little), 2000);
      expect(wav.getInt16(46, Endian.little), -3000);
    });

    test('downsamples 48 kHz to 16 kHz by averaging each window', () {
      final pcm = ByteData(12);
      for (var i = 0; i < 6; i++) {
        pcm.setInt16(i * 2, i < 3 ? 300 : 600, Endian.little);
      }
      final wav = ByteData.sublistView(
        wav16kMono(pcm.buffer.asUint8List(), sampleRate: 48000, channels: 1),
      );
      expect(wav.getUint32(40, Endian.little), 4);
      expect(wav.getInt16(44, Endian.little), 300);
      expect(wav.getInt16(46, Endian.little), 600);
    });
  });
}
