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

    test(
      'DTR-04 retired settings keys are absent from every locale and generated API',
      () {
        const retiredKeys = <String>{
          'settings_move_account_desc',
          'settings_move_account_action',
          'settings_peer_id_desc',
        };
        const retainedKeys = <String>{
          'settings_move_account_title',
          'settings_peer_id_title',
        };
        final violations = <String>[];

        for (final locale in locales) {
          final keys = _messageKeys(_loadArb(locale));
          violations.addAll(
            retiredKeys.intersection(keys).map((key) => 'app_$locale.arb:$key'),
          );
          expect(keys, containsAll(retainedKeys));
        }

        final generatedFiles = <File>[
          File('lib/l10n/app_localizations.dart'),
          ...locales.map(
            (locale) => File('lib/l10n/app_localizations_$locale.dart'),
          ),
        ];
        for (final file in generatedFiles) {
          final source = file.readAsStringSync();
          violations.addAll(
            retiredKeys
                .where((key) => RegExp('\\b$key\\b').hasMatch(source))
                .map((key) => '${file.path}:$key'),
          );
          for (final key in retainedKeys) {
            expect(source, contains(key), reason: '${file.path}:$key missing');
          }
        }

        expect(
          violations,
          isEmpty,
          reason: 'DTR04-L10N-RED: retired settings keys remain',
        );
      },
    );

    test(
      'DTR-07 retired group-list keys are absent from every locale and generated API',
      () {
        const retiredKeys = <String>{
          'group_card_no_messages',
          'groups_title',
          'groups_joined',
          'groups_no_joined',
          'groups_empty_title',
          'groups_empty_desc',
          'groups_pending_invites',
          'groups_unknown_sender',
        };
        const retainedKeys = <String>{
          'orbit_view_toggle_to_list',
          'orbit_view_toggle_to_circle',
        };
        final violations = <String>[];

        for (final locale in locales) {
          final keys = _messageKeys(_loadArb(locale));
          violations.addAll(
            retiredKeys.intersection(keys).map((key) => 'app_$locale.arb:$key'),
          );
          violations.addAll(
            retainedKeys
                .difference(keys)
                .map((key) => 'app_$locale.arb:missing:$key'),
          );
        }

        final generatedFiles = <File>[
          File('lib/l10n/app_localizations.dart'),
          ...locales.map(
            (locale) => File('lib/l10n/app_localizations_$locale.dart'),
          ),
        ];
        for (final file in generatedFiles) {
          final source = file.readAsStringSync();
          violations.addAll(
            retiredKeys
                .where((key) => RegExp('\\b$key\\b').hasMatch(source))
                .map((key) => '${file.path}:$key'),
          );
          violations.addAll(
            retainedKeys
                .where((key) => !RegExp('\\b$key\\b').hasMatch(source))
                .map((key) => '${file.path}:missing:$key'),
          );
        }

        expect(
          violations,
          isEmpty,
          reason:
              'DTR07-L10N-RED: retired group-list keys remain or Orbit '
              'replacement keys are missing',
        );
      },
    );

    test(
      'DTR-11 retired backlog list-summary keys are absent while live notice copy remains',
      () {
        const retiredKeys = <String>{
          'group_backlog_mixed_list_summary',
          'group_backlog_expired_list_summary',
        };
        const retainedKeys = <String>{
          'group_backlog_mixed_banner',
          'group_backlog_mixed_empty_title',
          'group_backlog_mixed_empty_subtitle',
          'group_backlog_expired_banner',
          'group_backlog_expired_empty_title',
          'group_backlog_expired_empty_subtitle',
        };
        final violations = <String>[];

        for (final locale in locales) {
          final bundle = _loadArb(locale);
          final keys = _messageKeys(bundle);
          violations.addAll(
            retiredKeys.intersection(keys).map((key) => 'app_$locale.arb:$key'),
          );
          violations.addAll(
            retiredKeys
                .where((key) => bundle.containsKey('@$key'))
                .map((key) => 'app_$locale.arb:@$key'),
          );
          violations.addAll(
            retainedKeys
                .difference(keys)
                .map((key) => 'app_$locale.arb:missing:$key'),
          );
        }

        final generatedFiles = <File>[
          File('lib/l10n/app_localizations.dart'),
          ...locales.map(
            (locale) => File('lib/l10n/app_localizations_$locale.dart'),
          ),
        ];
        for (final file in generatedFiles) {
          final source = file.readAsStringSync();
          violations.addAll(
            retiredKeys
                .where((key) => RegExp('\\b$key\\b').hasMatch(source))
                .map((key) => '${file.path}:$key'),
          );
          violations.addAll(
            retainedKeys
                .where((key) => !RegExp('\\b$key\\b').hasMatch(source))
                .map((key) => '${file.path}:missing:$key'),
          );
        }

        expect(
          violations,
          isEmpty,
          reason:
              'DTR11-L10N-RED: retired list-summary keys remain or live '
              'backlog notice copy is missing',
        );
      },
    );

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
  final metadata = bundle['@$key'];
  if (metadata is Map<String, Object?>) {
    final declared = metadata['placeholders'];
    if (declared is Map<String, Object?>) {
      return declared.keys.toSet();
    }
  }

  final message = bundle[key] as String? ?? '';
  return RegExp(
    r'\{([A-Za-z_][A-Za-z0-9_]*)\}',
  ).allMatches(message).map((match) => match.group(1)!).toSet();
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
