// Prompts and decoding settings copied verbatim from the Gemma 4 E2B benchmark
// harness, so the preview runs what was measured:
// .audit/translate-preview/spike/harness/app/src/main/java/com/mknoon/translatespike/MainActivity.java
//   line 224 (text):  "Translate this chat message to " + language + ". Output only the translation.\n" + input.getString("text")
//   line 282 (audio): "Transcribe this Arabic voice message verbatim in Arabic. Preserve English words as spoken. Output only the transcript."
//   line 292 (transcript translation): same text prompt, applied to the transcript.
//   lines 209-218 / 256-265: CPU 4 threads, context 2048 / output 256 (text),
//   audio encoder CPU, context 4096 / output 512 (audio),
//   SamplerConfig(topK 1, topP 1.0, temperature 0.0, seed 0).

String gemmaTranslatePrompt(String languageName, String text) =>
    'Translate this chat message to $languageName. Output only the translation.\n$text';

// Departs from the benchmark line 282, which forced Arabic: the owner asked
// not to assume a language. The hint names common languages without
// requiring one.
const gemmaTranscribePrompt =
    'Transcribe this voice message verbatim, in the language or languages '
    'actually spoken. It is often Arabic, English or German, but do not '
    'assume a language. Keep words from different languages exactly as '
    'spoken. Do not translate. Output only the transcript.';

const gemmaModelFileName = 'gemma-4-E2B-it.litertlm';
const gemmaModelBytes = 2588147712;

const gemmaTextMaxOutputTokens = 256;
const gemmaAudioMaxOutputTokens = 512;

/// The benchmark used 2048 for text and 4096 for audio. One loaded model
/// serves both, and LiteRT-LM fixes the context when the engine is created, so
/// the preview loads the larger one.
const gemmaContextTokens = 4096;

const gemmaTopK = 1;
const gemmaTopP = 1.0;
const gemmaTemperature = 0.0;
const gemmaSeed = 0;
