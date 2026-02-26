/// Downsamples (or pads) a list of normalized amplitude values to a fixed
/// [targetSize].
///
/// - If [samples] is shorter than [targetSize], pads with zeros on the left.
/// - If [samples] is exactly [targetSize], returns a copy.
/// - If [samples] is longer, divides into [targetSize] equal buckets and
///   averages each.
///
/// Returns exactly [targetSize] values in [0.0, 1.0].
List<double> downsampleWaveform(List<double> samples, int targetSize) {
  if (targetSize <= 0) return [];

  if (samples.isEmpty) {
    return List.filled(targetSize, 0.0);
  }

  if (samples.length <= targetSize) {
    final padding = targetSize - samples.length;
    return [
      ...List.filled(padding, 0.0),
      ...samples,
    ];
  }

  // Downsample: divide into targetSize buckets and average each
  final result = List<double>.filled(targetSize, 0.0);
  final bucketSize = samples.length / targetSize;

  for (var i = 0; i < targetSize; i++) {
    final start = (i * bucketSize).floor();
    final end = ((i + 1) * bucketSize).floor();
    var sum = 0.0;
    final count = end - start;
    for (var j = start; j < end; j++) {
      sum += samples[j];
    }
    result[i] = count > 0 ? sum / count : 0.0;
  }

  return result;
}
