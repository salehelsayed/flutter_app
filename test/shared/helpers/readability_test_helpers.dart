import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrastRatio(Color foreground, Color background) {
  final effectiveForeground = Color.alphaBlend(foreground, background);
  final foregroundLuminance = effectiveForeground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void expectTextContrast(
  Color foreground,
  Color background, {
  double minRatio = 4.5,
  String? reason,
}) {
  expect(
    contrastRatio(foreground, background),
    greaterThanOrEqualTo(minRatio),
    reason: reason,
  );
}

void expectComponentContrast(
  Color foreground,
  Color background, {
  double minRatio = 3,
  String? reason,
}) {
  expect(
    contrastRatio(foreground, background),
    greaterThanOrEqualTo(minRatio),
    reason: reason,
  );
}
