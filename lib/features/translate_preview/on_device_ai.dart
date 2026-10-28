import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_service.dart';

/// Owner preview: on-device translation of Thoughts and transcription of
/// received voice messages. Off unless built with
/// `--dart-define=TRANSLATE_PREVIEW=true`.
const bool kTranslatePreviewEnabled = bool.fromEnvironment('TRANSLATE_PREVIEW');

@visibleForTesting
bool? debugTranslatePreviewEnabledOverride;

bool get translatePreviewEnabled =>
    debugTranslatePreviewEnabledOverride ?? kTranslatePreviewEnabled;

/// What the preview widgets need from the on-device model. Everything runs on
/// the phone; nothing is sent anywhere.
abstract interface class OnDeviceAi {
  /// [text] translated to [languageName], an English language name such as
  /// "German".
  Future<String> translate(String text, {required String languageName});

  /// The words spoken in the voice message stored at [audioPath].
  Future<String> transcribe(String audioPath);
}

@visibleForTesting
OnDeviceAi? debugOnDeviceAiOverride;

/// The one model the app keeps for the preview. Read only where
/// [translatePreviewEnabled] is true, so a build without the flag never
/// touches the plugin.
OnDeviceAi get translatePreviewAi =>
    debugOnDeviceAiOverride ?? GemmaPreviewService.instance;
