import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _voicePlaybackSpeedKey = 'media.voice_playback_speed';
const _speeds = <double>[1.0, 1.5, 2.0];

String voicePlaybackSpeedLabel(double speed) =>
    speed == speed.round() ? '${speed.toInt()}' : '$speed';

final class VoicePlaybackSpeedStore {
  VoicePlaybackSpeedStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  static final shared = VoicePlaybackSpeedStore();

  final Future<SharedPreferences> Function() _preferences;
  final _value = ValueNotifier<double>(1.0);
  late final Future<void> _ready = _load();

  ValueListenable<double> get value {
    unawaited(_ready);
    return _value;
  }

  Future<void> get ready => _ready;

  Future<void> cycle() async {
    await _ready;
    final index = _speeds.indexOf(_value.value);
    final next = _speeds[(index + 1) % _speeds.length];
    _value.value = next;
    try {
      await (await _preferences()).setDouble(_voicePlaybackSpeedKey, next);
    } on Object {
      // Keep the user's choice for this run when persistence is unavailable.
    }
  }

  Future<void> _load() async {
    try {
      final stored = (await _preferences()).getDouble(_voicePlaybackSpeedKey);
      if (stored != null && _speeds.contains(stored)) _value.value = stored;
    } on Object {
      // Use the normal-speed default when preferences are unavailable.
    }
  }
}
