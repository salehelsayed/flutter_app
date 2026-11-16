import 'dart:typed_data';

/// Builds the WAV file LiteRT-LM takes as audio input: 16 kHz, mono, 16-bit
/// PCM, header included. [pcm] is interleaved little-endian 16-bit samples at
/// [sampleRate] with [channels] channels, as the platform decoder returns it.
Uint8List wav16kMono(
  Uint8List pcm, {
  required int sampleRate,
  required int channels,
}) {
  const targetRate = 16000;
  final input = ByteData.sublistView(pcm);
  final frames = pcm.lengthInBytes ~/ (2 * channels);
  if (frames < 1) {
    throw ArgumentError('PCM must contain at least one complete audio frame');
  }
  final outFrames = (frames * targetRate / sampleRate).floor();
  if (outFrames < 1) {
    throw ArgumentError('PCM must produce at least one normalized audio frame');
  }
  final mono = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0;
    for (var c = 0; c < channels; c++) {
      sum += input.getInt16((f * channels + c) * 2, Endian.little);
    }
    mono[f] = sum / channels;
  }
  final out = ByteData(44 + outFrames * 2);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      out.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + outFrames * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little);
  out.setUint16(22, 1, Endian.little);
  out.setUint32(24, targetRate, Endian.little);
  out.setUint32(28, targetRate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  out.setUint32(40, outFrames * 2, Endian.little);
  final step = sampleRate / targetRate;
  for (var i = 0; i < outFrames; i++) {
    final double value;
    if (step > 1) {
      // Averaging each output sample's input window filters out what 16 kHz
      // cannot hold, which plain interpolation would fold back as noise.
      final start = (i * step).floor();
      final end = ((i + 1) * step).floor().clamp(start + 1, frames);
      var sum = 0.0;
      for (var f = start; f < end; f++) {
        sum += mono[f];
      }
      value = sum / (end - start);
    } else {
      final position = i * step;
      final left = position.floor();
      final right = left + 1 < frames ? left + 1 : left;
      value = mono[left] + (mono[right] - mono[left]) * (position - left);
    }
    out.setInt16(44 + i * 2, value.round().clamp(-32768, 32767), Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Conditions only the canonical WAV produced by [wav16kMono] for transcription.
/// Keep a short pad after activity, and preserve inputs with no active window.
/// Energy is a conservative input heuristic, not word or segment confidence.
Uint8List trimTrailingQuietWav16kMono(Uint8List wav) {
  const headerBytes = 44;
  const rate = 16000;
  const windowFrames = rate * 20 ~/ 1000;
  const minimumQuietFrames = rate * 600 ~/ 1000;
  const retainedQuietFrames = rate * 250 ~/ 1000;
  // -50 dBFS RMS: (32768 * 10^(-50/20)) squared.
  const quietMeanSquare = 32768.0 * 32768.0 * 0.00001;
  final data = ByteData.sublistView(wav);
  final frames = (wav.lengthInBytes - headerBytes) ~/ 2;
  var lastActiveEnd = frames;
  while (lastActiveEnd > 0) {
    // Anchor 20 ms windows at frame zero, including a partial final window.
    final start = ((lastActiveEnd - 1) ~/ windowFrames) * windowFrames;
    var energy = 0;
    for (var frame = start; frame < lastActiveEnd; frame++) {
      final sample = data.getInt16(headerBytes + frame * 2, Endian.little);
      energy += sample * sample;
    }
    if (energy >= quietMeanSquare * (lastActiveEnd - start)) break;
    lastActiveEnd = start;
  }
  if (lastActiveEnd == 0 || frames - lastActiveEnd < minimumQuietFrames) {
    return wav;
  }

  final outputBytes = headerBytes + (lastActiveEnd + retainedQuietFrames) * 2;
  final output = Uint8List(outputBytes)..setRange(0, outputBytes, wav);
  final header = ByteData.sublistView(output);
  header.setUint32(4, outputBytes - 8, Endian.little);
  header.setUint32(40, outputBytes - headerBytes, Endian.little);
  return output;
}
