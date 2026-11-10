import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/features/translate_preview/language_heuristic.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _targetKey = 'translate_preview.target';
const _chatsKey = 'translate_preview.shown_in_chats';

/// The language translations are read in, and the 1:1 chats that show a
/// translation under each received message. Kept on this phone only.
final class TranslationPreferences {
  TranslationPreferences({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferences;
  final _target = ValueNotifier<String?>(null);
  final _chats = ValueNotifier<Set<String>>(const {});
  late final Future<void> _ready = _load();

  /// A supported language code, or null to follow the app language.
  ValueListenable<String?> get target {
    unawaited(_ready);
    return _target;
  }

  /// Notifies whenever a chat's "Show translation" switch flips.
  ValueListenable<Set<String>> get chats {
    unawaited(_ready);
    return _chats;
  }

  bool showsTranslationIn(String peerId) =>
      chats.value.contains(_chatKey(peerId));

  Future<void> setTarget(String? languageCode) async {
    if (languageCode != null && translateLanguageName(languageCode) == null) {
      return;
    }
    await _ready;
    _target.value = languageCode;
    await _write(
      (prefs) => languageCode == null
          ? prefs.remove(_targetKey)
          : prefs.setString(_targetKey, languageCode),
    );
  }

  Future<void> setShowTranslation(String peerId, bool show) async {
    await _ready;
    final key = _chatKey(peerId);
    _chats.value = show
        ? {..._chats.value, key}
        : ({..._chats.value}..remove(key));
    final keys = _chats.value.toList();
    await _write((prefs) => prefs.setStringList(_chatsKey, keys));
  }

  Future<void> _load() async {
    try {
      final prefs = await _preferences();
      final code = prefs.getString(_targetKey);
      _target.value = code != null && translateLanguageName(code) != null
          ? code
          : null;
      _chats.value = {...?prefs.getStringList(_chatsKey)};
    } on Object {
      // Nothing stored or no storage: follow the app language, every chat off.
    }
  }

  Future<void> _write(Future<bool> Function(SharedPreferences) write) async {
    try {
      await write(await _preferences());
    } on Object {
      // The choice still holds for this run.
    }
  }
}

/// Peer IDs stay out of the unencrypted preferences file.
String _chatKey(String peerId) =>
    sha256.convert(utf8.encode(peerId)).toString();

/// The language code a translation is requested in for [chosen].
String translationTargetOf(BuildContext context, String? chosen) =>
    chosen ?? Localizations.localeOf(context).languageCode;

@visibleForTesting
TranslationPreferences? debugTranslationPreferencesOverride;

TranslationPreferences? _shared;

TranslationPreferences get translationPreferences =>
    debugTranslationPreferencesOverride ??
    (_shared ??= TranslationPreferences());
