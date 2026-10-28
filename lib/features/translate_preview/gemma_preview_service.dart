import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_prompts.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import 'package:flutter_app/features/translate_preview/wav_16k_mono.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:path_provider/path_provider.dart';

/// Gemma 4 E2B on the CPU through LiteRT-LM. Loads the model from the app's
/// Documents directory on first use, keeps it, and runs one request at a time.
/// Each request is a fresh session, as in the benchmark.
final class GemmaPreviewService implements OnDeviceAi {
  GemmaPreviewService._();

  static final instance = GemmaPreviewService._();

  static const _channel = MethodChannel('mknoon/gemma_preview');

  Future<InferenceModel>? _model;
  bool _engineRegistered = false;
  Future<void> _tail = Future.value();

  @override
  Future<String> translate(String text, {required String languageName}) =>
      _serial(() async {
        final model = await _loadedModel();
        return _measure('text', () async {
          final session = await model.createSession(
            temperature: gemmaTemperature,
            randomSeed: gemmaSeed,
            topK: gemmaTopK,
            topP: gemmaTopP,
            maxOutputTokens: gemmaTextMaxOutputTokens,
          );
          try {
            await session.addQueryChunk(
              Message.text(
                text: gemmaTranslatePrompt(languageName, text),
                isUser: true,
              ),
            );
            return _reply(await session.getResponse());
          } finally {
            await session.close();
          }
        });
      });

  @override
  Future<String> transcribe(String audioPath) => _serial(() async {
    final model = await _loadedModel();
    return _measure('audio', () async {
      final decoded = await _channel.invokeMapMethod<String, Object?>(
        'decodePcm',
        {'path': audioPath},
      );
      final wav = wav16kMono(
        decoded!['pcm']! as Uint8List,
        sampleRate: decoded['sampleRate']! as int,
        channels: decoded['channels']! as int,
      );
      final session = await model.createSession(
        temperature: gemmaTemperature,
        randomSeed: gemmaSeed,
        topK: gemmaTopK,
        topP: gemmaTopP,
        enableAudioModality: true,
        maxOutputTokens: gemmaAudioMaxOutputTokens,
      );
      try {
        await session.addQueryChunk(
          Message.withAudio(
            text: gemmaTranscribePrompt,
            audioBytes: wav,
            isUser: true,
          ),
        );
        return _reply(await session.getResponse());
      } finally {
        await session.close();
      }
    });
  });

  Future<T> _serial<T>(Future<T> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// A failed load is forgotten, so Try again loads afresh.
  Future<InferenceModel> _loadedModel() {
    final loading = _model ??= _measure('load', _load);
    return loading.catchError((Object error, StackTrace stack) {
      if (identical(_model, loading)) _model = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<InferenceModel> _load() async {
    final documents = await getApplicationDocumentsDirectory();
    final path = '${documents.path}/$gemmaModelFileName';
    final length = await File(path).length();
    if (length != gemmaModelBytes) {
      throw StateError(
        '$gemmaModelFileName is $length bytes, not $gemmaModelBytes',
      );
    }
    if (!_engineRegistered) {
      await FlutterEdgeAi.initialize(inferenceEngines: [LiteRtLmEngine()]);
      _engineRegistered = true;
    }
    await FlutterEdgeAi.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromFile(path).install();
    return FlutterEdgeAi.getActiveModel(
      maxTokens: gemmaContextTokens,
      preferredBackend: PreferredBackend.cpu,
      preferredAudioBackend: PreferredBackend.cpu,
      supportImage: false,
      supportAudio: true,
      // The benchmark sent the audio before the instruction.
      multimodalOrder: MultimodalOrder.imagesAudioText,
    );
  }

  String _reply(String reply) {
    final text = reply.trim();
    if (text.isEmpty) throw StateError('empty reply');
    return text;
  }

  Future<T> _measure<T>(String kind, Future<T> Function() work) async {
    final watch = Stopwatch()..start();
    var ok = false;
    try {
      final result = await work();
      ok = true;
      return result;
    } finally {
      final memory = await _memory();
      debugPrint(
        'GEMMA_PREVIEW kind=$kind ms=${watch.elapsedMilliseconds} ok=$ok '
        'availableMemoryMB=${_mb(memory['availableBytes'])} '
        'footprintMB=${_mb(memory['footprintBytes'])} '
        'peakFootprintMB=${_mb(memory['peakFootprintBytes'])}',
      );
    }
  }

  Future<Map<String, Object?>> _memory() async {
    try {
      return await _channel.invokeMapMethod<String, Object?>('memory') ??
          const {};
    } on Object {
      return const {};
    }
  }

  String _mb(Object? bytes) =>
      bytes is int ? (bytes / (1024 * 1024)).round().toString() : 'na';
}
