/// Decides whether to offer "Translate" for a text, from its script and a few
/// common words. Pure Dart, no model. When it cannot tell the language of
/// Latin-script text, it offers the link.
library;

enum TextScript {
  latin,
  arabic,
  cyrillic,
  greek,
  hebrew,
  devanagari,
  thai,
  hangul,
  kana,
  han,
}

/// English names the benchmark prompt uses ("Arabic", "German", "English"),
/// keyed by ISO 639-1 code, with the script each language is written in.
const _languages = <String, (String, TextScript)>{
  'ar': ('Arabic', TextScript.arabic),
  'fa': ('Persian', TextScript.arabic),
  'ur': ('Urdu', TextScript.arabic),
  'en': ('English', TextScript.latin),
  'de': ('German', TextScript.latin),
  'fr': ('French', TextScript.latin),
  'es': ('Spanish', TextScript.latin),
  'it': ('Italian', TextScript.latin),
  'pt': ('Portuguese', TextScript.latin),
  'nl': ('Dutch', TextScript.latin),
  'tr': ('Turkish', TextScript.latin),
  'pl': ('Polish', TextScript.latin),
  'sv': ('Swedish', TextScript.latin),
  'id': ('Indonesian', TextScript.latin),
  'ru': ('Russian', TextScript.cyrillic),
  'uk': ('Ukrainian', TextScript.cyrillic),
  'el': ('Greek', TextScript.greek),
  'he': ('Hebrew', TextScript.hebrew),
  'hi': ('Hindi', TextScript.devanagari),
  'th': ('Thai', TextScript.thai),
  'ko': ('Korean', TextScript.hangul),
  'ja': ('Japanese', TextScript.kana),
  'zh': ('Chinese', TextScript.han),
};

/// The English language name for a locale's language code, or null when the
/// preview has no prompt name for it.
String? translateLanguageName(String languageCode) =>
    _languages[languageCode.toLowerCase()]?.$1;

/// Whether to show "Translate" for [text] on a phone whose system language is
/// [targetLanguageCode].
bool shouldOfferTranslate(String text, String targetLanguageCode) {
  final target = _languages[targetLanguageCode.toLowerCase()];
  if (target == null) return false;
  final script = dominantScript(text);
  if (script == null) return false;
  if (script != TextScript.latin) {
    return !_sameScriptFamily(script, target.$2);
  }
  if (looksLikeArabizi(text)) return false;
  if (target.$2 != TextScript.latin) return true;
  final guess = guessLatinLanguage(text);
  return guess != targetLanguageCode.toLowerCase();
}

/// Arabic script is shared by Arabic, Persian and Urdu, Han by Chinese and
/// Japanese; the heuristic cannot tell them apart, so it treats them as one.
bool _sameScriptFamily(TextScript text, TextScript target) {
  if (text == target) return true;
  const japanese = {TextScript.kana, TextScript.han};
  return japanese.contains(text) && japanese.contains(target);
}

TextScript? _scriptOf(int c) {
  if ((c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0xC0 && c <= 0x24F && c != 0xD7 && c != 0xF7) ||
      (c >= 0x1E00 && c <= 0x1EFF)) {
    return TextScript.latin;
  }
  if ((c >= 0x0620 && c <= 0x064A) ||
      (c >= 0x066E && c <= 0x06D3) ||
      (c >= 0x06FA && c <= 0x06FF) ||
      (c >= 0x0750 && c <= 0x077F) ||
      (c >= 0x08A0 && c <= 0x08FF) ||
      (c >= 0xFB50 && c <= 0xFDFF) ||
      (c >= 0xFE70 && c <= 0xFEFF)) {
    return TextScript.arabic;
  }
  if (c >= 0x0400 && c <= 0x04FF) return TextScript.cyrillic;
  if (c >= 0x0370 && c <= 0x03FF) return TextScript.greek;
  if (c >= 0x05D0 && c <= 0x05EA) return TextScript.hebrew;
  if (c >= 0x0900 && c <= 0x097F) return TextScript.devanagari;
  if (c >= 0x0E00 && c <= 0x0E7F) return TextScript.thai;
  if ((c >= 0xAC00 && c <= 0xD7AF) || (c >= 0x1100 && c <= 0x11FF)) {
    return TextScript.hangul;
  }
  if (c >= 0x3040 && c <= 0x30FF) return TextScript.kana;
  if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF)) {
    return TextScript.han;
  }
  return null;
}

/// The script most letters of [text] are written in, or null when it has no
/// letters (emoji, digits, punctuation). Any kana makes Han text Japanese.
TextScript? dominantScript(String text) {
  final counts = <TextScript, int>{};
  for (final rune in text.runes) {
    final script = _scriptOf(rune);
    if (script != null) counts[script] = (counts[script] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  if ((counts[TextScript.kana] ?? 0) > 0 && (counts[TextScript.han] ?? 0) > 0) {
    counts[TextScript.kana] =
        counts[TextScript.kana]! + counts.remove(TextScript.han)!;
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

final _wordPattern = RegExp(r"[a-z0-9À-ɏ']+");

List<String> _latinWords(String text) => _wordPattern
    .allMatches(text.toLowerCase())
    .map((m) => m.group(0)!.replaceAll("'", ''))
    .where((w) => w.contains(RegExp(r'[a-zÀ-ɏ]')))
    .toList(growable: false);

/// A digit standing for an Arabic letter: 2 (hamza), 3 (ain), 5 (kha),
/// 6 (taa), 7 (haa), 8 (qaf/ghain), 9 (sad). Either it starts a word
/// ("3aref", "7abibi") or sits between letters ("ma3lesh", "delwa2ty").
final _arabiziDigit = RegExp(r'^[2356789][a-z]{2,}|[a-z][2356789][a-z]');

/// Latin-letter words with a digit that are not Arabizi.
final _notArabiziDigit = RegExp(
  r'^\d+(st|nd|rd|th|am|pm|h|min|k|km|kg|g|m|mb|gb|x|d|s)$|^(2day|2nite|2morrow|2moro|gr8|l8r|l8|m8|h2o|b2b|b2c|p2p|mp3|mp4|g7|g8|3d|2d)$',
);

/// Romanised Egyptian, Levantine and Gulf words that are not common English,
/// German or French words.
const _arabiziWords = {
  'ana',
  'enta',
  'enti',
  'inta',
  'inti',
  'ento',
  'into',
  'intu',
  'ehna',
  'e7na',
  'i7na',
  'howa',
  'huwa',
  'heya',
  'hiya',
  'mesh',
  'mish',
  'msh',
  'mush',
  'ezay',
  'ezayak',
  'ezayek',
  'izayak',
  'izzay',
  'ezzay',
  'keda',
  'kida',
  'kda',
  'leh',
  'leih',
  'leesh',
  'lesh',
  'shlonak',
  'shlonik',
  'shloonak',
  'shlon',
  'shu',
  'shoo',
  'yalla',
  'yallah',
  'habibi',
  'habibti',
  '7abibi',
  '7abibti',
  'inshallah',
  'inshalla',
  'wallah',
  'wallahi',
  'walla',
  'akeed',
  'shukran',
  'shokran',
  'khalas',
  '5alas',
  'mafi',
  'mafeesh',
  'mafish',
  'mafesh',
  'kaman',
  'kmn',
  'tamam',
  'tmam',
  'ahlan',
  'aywa',
  'aiwa',
  'la2',
  'la2a',
  'ya3ni',
  'yaani',
  'yani',
  '3ashan',
  '3shan',
  'alashan',
  '3lshan',
  'alhamdulillah',
  'hamdulillah',
  'hamdella',
  'mashallah',
  'mashalla',
  'ma3lesh',
  'maalesh',
  'ma3lish',
  'delwa2ty',
  'dilwa2ti',
  'delwa2t',
  'bokra',
  'bukra',
  'awy',
  'awi',
  '2awy',
  'kteer',
  'ktir',
  'kter',
  'ba2a',
  'zay',
  'zayy',
  'el5eir',
  'elkheir',
  '5eer',
  'kheir',
  '3aref',
  '3arfa',
  'ba7ebak',
  'ba7bek',
  'behebak',
  'bahebak',
  'eshta',
  'ishta',
  '7aga',
  'haga',
  '3omri',
  'omri',
  'elly',
  'illi',
  'mafhemtsh',
  'fahem',
  'fahma',
  'yasta',
  '3ayez',
  '3ayza',
  '3awez',
  'ayez',
  '3ndi',
  '3andi',
  'ma3a',
  'm3a',
  'm3ak',
  'ma3ak',
  '3alek',
  '3aleik',
  '7elw',
  'helw',
  '7ilw',
  'hilwa',
  '7elwa',
  'mabrook',
  'mabrouk',
  'salam',
  'salamtak',
  'marhaba',
  'mar7aba',
  'keefak',
  'kifak',
  'kifik',
  'hek',
  'heik',
  'hayda',
  'hayde',
  'hala2',
  'halla2',
  'baddi',
  'beddi',
  'wayn',
  'wein',
  'zain',
  'zein',
  'wayed',
  'shino',
  'shinu',
  'abi',
  'abgha',
  'ab8a',
  'agool',
  'ga3d',
  'ga3da',
  'gaa3d',
  'ya3tik',
  'el3afia',
  'allah',
  'yarab',
  'yarabb',
};

/// Whether Latin-letter [text] reads as Arabic written in Latin letters.
///
/// Needs two signals (an Arabizi word or a digit used as a letter) making up a
/// quarter of the words, or one signal in a message of one or two words. A
/// single "Ana" in an English sentence stays English.
bool looksLikeArabizi(String text) {
  if (dominantScript(text) != TextScript.latin) return false;
  final words = _latinWords(text);
  if (words.isEmpty) return false;
  var signals = 0;
  for (final word in words) {
    final digitLetter =
        _arabiziDigit.hasMatch(word) && !_notArabiziDigit.hasMatch(word);
    if (digitLetter || _arabiziWords.contains(word)) signals++;
  }
  if (words.length <= 2) return signals >= 1;
  return signals >= 2 && signals * 4 >= words.length;
}

/// Short common words of the Latin-script languages the app's people write
/// in. A word listed under two languages counts for both.
const _latinStopwords = <String, Set<String>>{
  'en': {
    'the',
    'and',
    'is',
    'are',
    'you',
    'what',
    'this',
    'that',
    'with',
    'have',
    'for',
    'not',
    'how',
    'was',
    'it',
    'my',
    'me',
    'we',
    'they',
    'your',
    'good',
    'today',
    'tomorrow',
    'morning',
    'thanks',
    'thank',
    'hello',
    'please',
    'love',
    'just',
    'see',
    'will',
    'can',
    'of',
    'to',
    'i',
    'am',
    'do',
    'be',
    'at',
    'on',
    'so',
    'all',
    'everyone',
    'night',
    'great',
  },
  'de': {
    'der',
    'die',
    'das',
    'und',
    'ist',
    'nicht',
    'ich',
    'du',
    'wir',
    'ihr',
    'sie',
    'es',
    'ein',
    'eine',
    'mit',
    'auf',
    'für',
    'wie',
    'geht',
    'dir',
    'mir',
    'auch',
    'noch',
    'heute',
    'morgen',
    'guten',
    'gute',
    'danke',
    'bitte',
    'hallo',
    'schön',
    'bin',
    'bist',
    'sind',
    'was',
    'wer',
    'zu',
    'den',
    'dem',
    'nacht',
    'liebe',
    'alle',
    'aber',
    'oder',
    'mein',
  },
  'fr': {
    'le',
    'la',
    'les',
    'et',
    'est',
    'je',
    'tu',
    'nous',
    'vous',
    'il',
    'elle',
    'un',
    'une',
    'des',
    'pour',
    'avec',
    'pas',
    'que',
    'qui',
    'bonjour',
    'merci',
    'comment',
    'ça',
    'va',
    'très',
    'bien',
    'suis',
    'mon',
    'ma',
    'aujourdhui',
    'demain',
    'salut',
    'bonne',
    'nuit',
    'tout',
  },
  'es': {
    'el',
    'la',
    'los',
    'las',
    'y',
    'es',
    'yo',
    'tú',
    'que',
    'de',
    'en',
    'un',
    'una',
    'por',
    'para',
    'con',
    'no',
    'hola',
    'gracias',
    'cómo',
    'estás',
    'bien',
    'muy',
    'hoy',
    'mañana',
    'buenos',
    'buenas',
    'días',
    'noches',
    'todo',
    'todos',
  },
  'it': {
    'il',
    'lo',
    'la',
    'gli',
    'le',
    'e',
    'è',
    'io',
    'tu',
    'che',
    'di',
    'un',
    'una',
    'per',
    'con',
    'non',
    'ciao',
    'grazie',
    'come',
    'stai',
    'bene',
    'molto',
    'oggi',
    'domani',
    'buongiorno',
    'buonanotte',
    'tutto',
    'sono',
  },
  'pt': {
    'o',
    'a',
    'os',
    'as',
    'e',
    'é',
    'eu',
    'você',
    'que',
    'de',
    'um',
    'uma',
    'para',
    'com',
    'não',
    'olá',
    'obrigado',
    'obrigada',
    'como',
    'está',
    'bem',
    'muito',
    'hoje',
    'amanhã',
    'bom',
    'dia',
    'boa',
    'noite',
    'tudo',
  },
  'nl': {
    'de',
    'het',
    'een',
    'en',
    'is',
    'ik',
    'jij',
    'je',
    'wij',
    'we',
    'niet',
    'met',
    'voor',
    'hoe',
    'gaat',
    'dank',
    'bedankt',
    'hallo',
    'goed',
    'vandaag',
    'morgen',
    'goedemorgen',
    'welterusten',
    'alles',
    'ben',
  },
  'tr': {
    've',
    'bir',
    'bu',
    'ben',
    'sen',
    'biz',
    'siz',
    'değil',
    'ne',
    'nasıl',
    'nasılsın',
    'merhaba',
    'teşekkürler',
    'teşekkür',
    'ederim',
    'iyi',
    'çok',
    'bugün',
    'yarın',
    'günaydın',
    'geceler',
    'evet',
    'hayır',
    'için',
  },
};

/// The Latin-script language most of [text]'s common words belong to, or null
/// when no language leads.
String? guessLatinLanguage(String text) {
  final words = _latinWords(text);
  final scores = <String, int>{};
  for (final word in words) {
    for (final entry in _latinStopwords.entries) {
      if (entry.value.contains(word)) {
        scores[entry.key] = (scores[entry.key] ?? 0) + 1;
      }
    }
  }
  if (scores.isEmpty) return null;
  final ranked = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (ranked.length > 1 && ranked[0].value == ranked[1].value) return null;
  return ranked.first.key;
}
