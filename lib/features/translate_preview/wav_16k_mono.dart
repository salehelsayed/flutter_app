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
  final mono = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0;
    for (var c = 0; c < channels; c++) {
      sum += input.getInt16((f * channels + c) * 2, Endian.little);
    }
    mono[f] = sum / channels;
  }
  final outFrames = frames == 0
      ? 0
      : (frames * targetRate / sampleRate).floor();
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
