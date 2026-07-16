/// Pure-Dart protocol shared by the production-app endpoint and the bare-Dart
/// host orchestrator. Keep this file free of Flutter/plugin imports so Sims can
/// run the host adapter without a `dart:ui` runtime.
const String androidVoiceMessageE2EAction = 'voice_message_e2e';
const String androidVoiceMessageE2ERequestSchema =
    'mknoon.sims.android-voice-message-request.v1';
const String androidVoiceMessageE2EEndpointResultSchema =
    'mknoon.sims.android-voice-message-endpoint.v1';
const String androidVoiceMessageE2EScenario = 'android.voice_message_e2e';
const String androidVoiceMessageE2EBuildProfile = 'android.e2e.main';
const String androidVoiceMessageSenderRole = 'sender';
const String androidVoiceMessageReceiverRole = 'receiver';
