import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/widgets/call_controls.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// Foreground active-call presentation driven by the canonical reducer state.
///
/// The local timer only schedules repaints. It does not own or transition call
/// state, and duration remains anchored to [connectedAt].
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({
    super.key,
    required this.contactPeerId,
    required this.contactUsername,
    required this.state,
    required this.connectedAt,
    required this.now,
    required this.controls,
  });

  final String contactPeerId;
  final String contactUsername;
  final CallState state;
  final DateTime? connectedAt;
  final DateTime Function() now;
  final CallControls controls;

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  Timer? _ticker;

  bool get _showsDuration =>
      widget.connectedAt != null &&
      (widget.state == CallState.connected ||
          widget.state == CallState.reconnecting);

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ActiveCallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectedAt != widget.connectedAt ||
        oldWidget.state != widget.state ||
        oldWidget.now != widget.now) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = _showsDuration
        ? Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final formattedDuration = _showsDuration ? _formattedDuration : null;

    return ColoredBox(
      color: colors.surfaceBase,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useCompactLandscape =
                constraints.maxWidth > constraints.maxHeight &&
                constraints.maxHeight < 600;

            if (useCompactLandscape) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildProfile(
                        colors,
                        formattedDuration,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(child: widget.controls),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
              child: Column(
                children: [
                  const Spacer(),
                  _buildProfile(colors, formattedDuration),
                  const Spacer(),
                  widget.controls,
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfile(
    BackgroundReadableColors colors,
    String? formattedDuration, {
    bool compact = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        UserAvatar(peerId: widget.contactPeerId, size: compact ? 88 : 112),
        SizedBox(height: compact ? 12 : 24),
        Text(
          widget.contactUsername,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: compact ? 24 : 28,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: compact ? 6 : 10),
        Semantics(
          container: true,
          liveRegion: true,
          label: _status,
          excludeSemantics: true,
          child: Text(
            _status,
            style: TextStyle(
              color: widget.state == CallState.connected
                  ? colors.connectedHeading
                  : colors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (formattedDuration != null) ...[
          SizedBox(height: compact ? 6 : 8),
          Text(
            formattedDuration,
            semanticsLabel: 'Call duration $formattedDuration',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }

  String get _status => switch (widget.state) {
    CallState.reconnecting => 'Reconnecting',
    CallState.connected => 'Connected',
    CallState.ending || CallState.ended => 'Ending',
    _ => 'Connecting',
  };

  String get _formattedDuration {
    final connectedAt = widget.connectedAt;
    if (connectedAt == null) return '00:00';
    final difference = widget.now().toUtc().difference(connectedAt.toUtc());
    final elapsed = difference.isNegative ? Duration.zero : difference;
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours == 0
        ? '$minutes:$seconds'
        : '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }
}
