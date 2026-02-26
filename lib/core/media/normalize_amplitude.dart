import 'dart:math';

/// Normalizes a dBFS amplitude value to [0.0, 1.0].
///
/// Maps linearly from [-60, 0] dBFS to [0.0, 1.0], then applies a power
/// curve (exponent 0.6) for perceptual spread across speech range.
/// Values below -60 clamp to 0.0, above 0 clamp to 1.0.
double normalizeAmplitude(double dBFS) {
  final linear = ((dBFS + 60) / 60).clamp(0.0, 1.0);
  return pow(linear, 0.6).toDouble();
}
