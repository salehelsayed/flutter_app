import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_prompts.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import 'package:flutter_app/features/translate_preview/wav_16k_mono.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

/// Gemma 4 E2B on the CPU through LiteRT-LM. Loads the model from the app's
/// verified delivery path on first use, keeps it, and runs one request at a time.
/// Each request is a fresh session, as in the benchmark.
final class GemmaPreviewService implements OnDeviceAi {
  GemmaPreviewService._();

  static final instance = GemmaPreviewService._();

  static const _channel = MethodChannel('mknoon/gemma_preview');
  static const _diagnosticsEnabled =
      kDebugMode && bool.fromEnvironment('TRANSLATE_PREVIEW_DIAG');

  Future<InferenceModel>? _model;
  bool _engineRegistered = false;
  Future<void> _tail = Future.value();
  Future<String> Function()? _downloadedModelPath;

  void setDownloadedModelPathResolver(Future<String> Function() resolve) {
    _downloadedModelPath = resolve;
  }

  Future<void> removeDownloadedModel(
    Future<void> Function() deleteOwnedFiles,
  ) => _serial(() async {
    final held = _model;
    if (held != null) {
      final model = await held;
      await model.close();
      if (identical(_model, held)) _model = null;
    }
    await _ensureEngineRegistered();
    if (await FlutterEdgeAi.isModelInstalled(gemmaModelFileName)) {
      await FlutterEdgeAi.uninstallModel(gemmaModelFileName);
    }
    await deleteOwnedFiles();
  });

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
            return _reply(await session.getResponse(), operation: 'translate');
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
      final pcm = decoded!['pcm']! as Uint8List;
      final sampleRate = decoded['sampleRate']! as int;
      final channels = decoded['channels']! as int;
      if (_diagnosticsEnabled) {
        final input = File(audioPath);
        final inputBytes = await input.length();
        final header = await input
            .openRead(0, inputBytes < 16 ? inputBytes : 16)
            .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
        final digest = await sha256.bind(input.openRead()).first;
        final sampleCount = pcm.lengthInBytes ~/ 2;
        final frameCount = channels > 0 ? sampleCount ~/ channels : null;
        debugPrint(
          'TRANSLATE_PREVIEW_DIAG ${jsonEncode({
            'event': 'decoded_audio',
            'operation': 'transcribe',
            'inputBasename': input.uri.pathSegments.last,
            'inputBytes': inputBytes,
            'inputSha256': digest.toString(),
            'inputHeaderHex': header
                .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
                .join(),
            'sourceContainer': decoded['sourceContainer'],
            'sourceCodec': decoded['sourceCodec'],
            'pcmBytes': pcm.lengthInBytes,
            'sampleRate': sampleRate,
            'channels': channels,
            'sampleCount': sampleCount,
            'frameCount': frameCount,
            'durationMs': frameCount != null && sampleRate > 0
                ? frameCount * 1000 / sampleRate
                : null,
          })}',
        );
      }
      final wav = wav16kMono(pcm, sampleRate: sampleRate, channels: channels);
      if (_diagnosticsEnabled) {
        final wavHeader = ByteData.sublistView(wav);
        final wavSampleRate = wavHeader.getUint32(24, Endian.little);
        final wavSampleCount = wavHeader.getUint32(40, Endian.little) ~/ 2;
        debugPrint(
          'TRANSLATE_PREVIEW_DIAG ${jsonEncode({
            'event': 'normalized_wav',
            'operation': 'transcribe',
            'wavSampleRate': wavSampleRate,
            'wavSampleCount': wavSampleCount,
            'wavDurationMs': wavSampleCount * 1000 / wavSampleRate,
          })}',
        );
      }
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
        return _reply(await session.getResponse(), operation: 'transcribe');
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
    final resolve = _downloadedModelPath;
    if (resolve == null) {
      throw StateError('Translator delivery is not configured');
    }
    final path = await resolve();
    final length = await File(path).length();
    if (length != gemmaModelBytes) {
      throw StateError(
        '$gemmaModelFileName is $length bytes, not $gemmaModelBytes',
      );
    }
    await _ensureEngineRegistered();
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

  Future<void> _ensureEngineRegistered() async {
    if (_engineRegistered) return;
    await FlutterEdgeAi.initialize(inferenceEngines: [LiteRtLmEngine()]);
    _engineRegistered = true;
  }

  String _reply(String reply, {required String operation}) {
    if (_diagnosticsEnabled) {
      debugPrint(
        'TRANSLATE_PREVIEW_DIAG ${jsonEncode({
          'event': 'raw_model_output',
          'operation': operation,
          'lengthCodeUnits': reply.length,
          'text': reply,
        })}',
      );
    }
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
