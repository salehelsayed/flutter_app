import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_prompts.dart';
import 'package:path_provider/path_provider.dart';

/// Nonshipping file/receipt adapter for the explicitly enabled BL15 replay.
final class Bl15DebugWavReplay {
  Bl15DebugWavReplay._(this.fixture, this.directory, this._receipt);

  final File fixture;
  final Directory directory;
  final Map<String, Object?> _receipt;

  static Future<Bl15DebugWavReplay> open(String fileName) async {
    if (!kDebugMode) throw StateError('BL15 replay is debug-only');
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*\.wav$').hasMatch(fileName)) {
      throw ArgumentError.value(
        fileName,
        'BL15_REPLAY_WAV',
        'WAV basename required',
      );
    }
    final documents = await getApplicationDocumentsDirectory();
    final fixture = File('${documents.path}/bl15/$fileName');
    final bytes = await fixture.readAsBytes();
    final directory = Directory(
      '${fixture.parent.path}/receipts/${DateTime.now().toUtc().microsecondsSinceEpoch}',
    );
    await directory.create(recursive: true);
    return Bl15DebugWavReplay._(fixture, directory, {
      'schema': 1,
      'debugOnly': true,
      'buildHead': const String.fromEnvironment('BL15_REPLAY_HEAD'),
      'variant': const String.fromEnvironment('BL15_REPLAY_VARIANT'),
      'fixtureName': fileName,
      'fixtureBytes': bytes.length,
      'fixtureSha256': sha256.convert(bytes).toString(),
      'model': gemmaModelFileName,
      'modelBytes': gemmaModelBytes,
      'contextTokens': gemmaContextTokens,
      'maxOutputTokens': gemmaAudioMaxOutputTokens,
      'temperature': gemmaTemperature,
      'topK': gemmaTopK,
      'topP': gemmaTopP,
      'seed': gemmaSeed,
      'backend': 'cpu',
      'audioBackend': 'cpu',
      'promptSha256': sha256
          .convert(utf8.encode(gemmaTranscribePrompt))
          .toString(),
    });
  }

  Future<void> prepare(
    Uint8List normalized,
    Uint8List modelInput, {
    required int sampleRate,
    required int channels,
  }) async {
    await File('${directory.path}/normalized.wav')
        .writeAsBytes(normalized, flush: true);
    await File('${directory.path}/model-input.wav')
        .writeAsBytes(modelInput, flush: true);
    _receipt.addAll({
      'phase': 'prepared',
      'preparedAt': DateTime.now().toUtc().toIso8601String(),
      'decodedSampleRate': sampleRate,
      'decodedChannels': channels,
      'normalizedBytes': normalized.length,
      'normalizedFrames': (normalized.length - 44) ~/ 2,
      'normalizedSha256': sha256.convert(normalized).toString(),
      'modelInputBytes': modelInput.length,
      'modelInputFrames': (modelInput.length - 44) ~/ 2,
      'modelInputSha256': sha256.convert(modelInput).toString(),
      'retainedPcmIsPrefix':
          modelInput.length <= normalized.length &&
          listEquals(
            modelInput.sublist(44),
            normalized.sublist(44, modelInput.length),
          ),
    });
    await _write();
  }

  Future<void> recordResponse(String text) async {
    _receipt.addAll({
      'phase': 'response',
      'responseAt': DateTime.now().toUtc().toIso8601String(),
      'rawText': text,
    });
    await _write();
  }

  Future<void> _write() async {
    final temporary = File('${directory.path}/receipt.json.tmp');
    await temporary.writeAsString(jsonEncode(_receipt), flush: true);
    await temporary.rename('${directory.path}/receipt.json');
  }
}
