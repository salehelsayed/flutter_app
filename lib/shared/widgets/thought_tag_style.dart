import 'package:flutter/painting.dart';

/// A #tag inside Thought text: the terminal type, a little smaller, regular
/// weight, and in [color] or softer than the words around it.
TextStyle thoughtTagStyle(TextStyle base, {Color? color}) => base.copyWith(
  fontFamily: 'Menlo',
  fontFamilyFallback: const ['SF Mono', 'Courier', 'monospace'],
  fontSize: (base.fontSize ?? 14) - 2,
  fontWeight: FontWeight.w400,
  color:
      color ?? (base.color ?? const Color(0xFFFFFFFF)).withValues(alpha: 0.6),
);
