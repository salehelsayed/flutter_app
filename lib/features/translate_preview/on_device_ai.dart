import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_service.dart';

@visibleForTesting
bool? debugTranslatePreviewEnabledOverride;

/// On-device translation is available in ordinary builds. Device eligibility
/// is enforced by model delivery; the chat icon additionally requires ModelReady.
bool get translatePreviewEnabled =>
    debugTranslatePreviewEnabledOverride ?? true;

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

/// The one on-device model. Download consent, device eligibility and inference
/// safety remain owned by model delivery and the service.
OnDeviceAi get translatePreviewAi =>
    debugOnDeviceAiOverride ?? GemmaPreviewService.instance;
