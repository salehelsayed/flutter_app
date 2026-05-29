import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('l10n integrity', () {
    final locales = <String>['en', 'de', 'ar'];

    test('ARB files have identical non-empty key and placeholder sets', () {
      final bundles = {for (final locale in locales) locale: _loadArb(locale)};
      final baseKeys = _messageKeys(bundles['en']!);

      for (final locale in locales.skip(1)) {
        final localeKeys = _messageKeys(bundles[locale]!);
        expect(
          localeKeys.difference(baseKeys),
          isEmpty,
          reason: '$locale has keys not present in English ARB',
        );
        expect(
          baseKeys.difference(localeKeys),
          isEmpty,
          reason: '$locale is missing English ARB keys',
        );
      }

      for (final locale in locales) {
        final bundle = bundles[locale]!;
        for (final key in _messageKeys(bundle)) {
          expect(
            (bundle[key] as String).trim(),
            isNotEmpty,
            reason: '$locale:$key is empty',
          );
          expect(
            _placeholdersFor(bundle, key),
            _placeholdersFor(bundles['en']!, key),
            reason: '$locale:$key placeholder set diverges from English',
          );
        }
      }
    });

    test('simple hardcoded UI literals stay out of feature/shared widgets', () {
      final roots = <Directory>[
        Directory('lib/features'),
        Directory('lib/shared'),
      ];
      final violations = <String>[];

      for (final file in roots.expand(_dartFiles)) {
        if (file.path.contains('/l10n/')) continue;
        final source = file.readAsStringSync();
        for (final match in _uiLiteralPattern.allMatches(source)) {
          final literal = _firstCapture(match);
          if (literal == null || _allowedLiteral(literal)) continue;
          final line = _lineNumber(source, match.start);
          violations.add('${file.path}:$line -> $literal');
        }
      }

      expect(violations, isEmpty);
    });
  });
}

Map<String, Object?> _loadArb(String locale) {
  final file = File('lib/l10n/app_$locale.arb');
  return (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
      .cast<String, Object?>();
}

Set<String> _messageKeys(Map<String, Object?> bundle) {
  return bundle.entries
      .where((entry) => !entry.key.startsWith('@') && entry.value is String)
      .map((entry) => entry.key)
      .toSet();
}

Set<String> _placeholdersFor(Map<String, Object?> bundle, String key) {
  final placeholders = <String>{};
  final message = bundle[key] as String? ?? '';
  placeholders.addAll(
    RegExp(
      r'\{([A-Za-z_][A-Za-z0-9_]*)(?=[},])',
    ).allMatches(message).map((match) => match.group(1)!),
  );

  final metadata = bundle['@$key'];
  if (metadata is Map<String, Object?>) {
    final declared = metadata['placeholders'];
    if (declared is Map<String, Object?>) {
      placeholders.addAll(declared.keys);
    }
  }

  return placeholders;
}

Iterable<File> _dartFiles(Directory root) sync* {
  if (!root.existsSync()) return;
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

final _uiLiteralPattern = RegExp(
  r"(?:const\s+)?Text\(\s*'([^'\n]*[A-Za-z][^'\n]*)'"
  r"|(?:title|content|label|child):\s*(?:const\s+)?Text\(\s*'([^'\n]*[A-Za-z][^'\n]*)'"
  r"|(?:label|hintText|tooltip):\s*'([^'\n]*[A-Za-z][^'\n]*)'",
  multiLine: true,
  dotAll: true,
);

String? _firstCapture(RegExpMatch match) {
  for (var i = 1; i <= match.groupCount; i++) {
    final value = match.group(i);
    if (value != null) return value;
  }
  return null;
}

bool _allowedLiteral(String literal) {
  const exactAllowed = {
    'GIF',
    'mknoon',
    'mknoon/',
    '{"pk":"...","ns":"...","rv":"...","ts":"...","sig":"..."}',
  };
  if (exactAllowed.contains(literal)) return true;

  final withoutInterpolations = literal
      .replaceAll(RegExp(r'\$\{[^}]+\}'), '')
      .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_\.]*'), '');
  return !RegExp(r'[A-Za-z]').hasMatch(withoutInterpolations);
}

int _lineNumber(String source, int offset) {
  return '\n'.allMatches(source.substring(0, offset)).length + 1;
}
