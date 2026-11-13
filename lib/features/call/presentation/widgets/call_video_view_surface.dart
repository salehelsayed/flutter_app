import 'package:flutter/material.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';

/// Displays one immutable view supplied by the existing call/media owner.
class CallVideoViewSurface extends StatelessWidget {
  const CallVideoViewSurface({
    super.key,
    required this.projection,
    required this.slot,
  });

  final ForegroundCallProjection projection;
  final CallVideoRendererSlot slot;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
