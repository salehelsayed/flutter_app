import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'media_playback_adapter.dart';

/// Shared, adapter-driven video controls: play/pause, ±10s seek with duration
/// clamps, mute, elapsed/duration readout, four playback speeds, and an
/// absolute scrubber. Drives exactly the one [adapter] it is given; it never
/// reaches another page's controller.
class MediaVideoControls extends StatefulWidget {
  const MediaVideoControls({super.key, required this.adapter});

  final MediaPlaybackAdapter adapter;

  @override
  State<MediaVideoControls> createState() => _MediaVideoControlsState();
}

class _MediaVideoControlsState extends State<MediaVideoControls> {
  double? _dragValueMs;

  @override
  void initState() {
    super.initState();
    widget.adapter.addListener(_onAdapterChanged);
  }

  @override
  void didUpdateWidget(MediaVideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adapter != widget.adapter) {
      oldWidget.adapter.removeListener(_onAdapterChanged);
      widget.adapter.addListener(_onAdapterChanged);
    }
  }

  @override
  void dispose() {
    widget.adapter.removeListener(_onAdapterChanged);
    super.dispose();
  }

  void _onAdapterChanged() {
    if (mounted) setState(() {});
  }

  void _togglePlay() {
    final adapter = widget.adapter;
    if (adapter.isPlaying) {
      adapter.pause();
    } else {
      adapter.play();
    }
    setState(() {});
  }

  void _skip(Duration delta) {
    final adapter = widget.adapter;
    // Clamp happens inside the shared seekBy so both the real adapter and the
    // test fake exercise the same bounds.
    adapter.seekBy(delta);
    setState(() {});
  }

  void _cycleSpeed() {
    final adapter = widget.adapter;
    final currentIndex = kMediaPlaybackSpeeds.indexOf(adapter.speed);
    final nextIndex =
        (currentIndex < 0 ? 0 : currentIndex + 1) % kMediaPlaybackSpeeds.length;
    adapter.setSpeed(kMediaPlaybackSpeeds[nextIndex]);
    setState(() {});
  }

  void _toggleMute() {
    final adapter = widget.adapter;
    adapter.setMuted(!adapter.isMuted);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final adapter = widget.adapter;
    final position = adapter.position;
    final duration = adapter.duration;
    final timeLabel = _formatTimeLabel(position, duration);
    final speedLabel = _formatSpeedLabel(adapter.speed);

    final sliderMax = duration.inMilliseconds.toDouble();
    final sliderValue = (_dragValueMs ?? position.inMilliseconds.toDouble())
        .clamp(0.0, sliderMax <= 0 ? 1.0 : sliderMax);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color.fromRGBO(0, 0, 0, 0.35),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                timeLabel,
                key: const ValueKey('media_controls_time'),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('media_controls_scrubber'),
                  value: sliderValue.toDouble(),
                  max: sliderMax <= 0 ? 1.0 : sliderMax,
                  onChanged: sliderMax <= 0
                      ? null
                      : (value) => setState(() => _dragValueMs = value),
                  onChangeEnd: sliderMax <= 0
                      ? null
                      : (value) {
                          adapter.seekTo(Duration(milliseconds: value.round()));
                          setState(() => _dragValueMs = null);
                        },
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                key: const ValueKey('media_controls_skip_back'),
                tooltip: l10n.media_viewer_skip_back,
                color: Colors.white,
                icon: const Icon(Icons.replay_10_rounded),
                onPressed: () => _skip(-kMediaViewerSkipInterval),
              ),
              IconButton(
                key: const ValueKey('media_controls_play_pause'),
                tooltip: adapter.isPlaying
                    ? l10n.media_viewer_pause
                    : l10n.media_viewer_play,
                color: Colors.white,
                iconSize: 40,
                icon: Icon(
                  adapter.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                onPressed: _togglePlay,
              ),
              IconButton(
                key: const ValueKey('media_controls_skip_forward'),
                tooltip: l10n.media_viewer_skip_forward,
                color: Colors.white,
                icon: const Icon(Icons.forward_10_rounded),
                onPressed: () => _skip(kMediaViewerSkipInterval),
              ),
              IconButton(
                key: const ValueKey('media_controls_mute'),
                tooltip: adapter.isMuted
                    ? l10n.media_viewer_unmute
                    : l10n.media_viewer_mute,
                color: Colors.white,
                icon: Icon(
                  adapter.isMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                ),
                onPressed: _toggleMute,
              ),
              TextButton(
                key: const ValueKey('media_controls_speed'),
                onPressed: _cycleSpeed,
                child: Text(
                  speedLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "m:ss / m:ss" elapsed-over-duration. Computed (not a UI literal) so it
/// stays out of the l10n hardcoded-string gate.
String _formatTimeLabel(Duration position, Duration duration) {
  return '${_formatDuration(position)} / ${_formatDuration(duration)}';
}

String _formatDuration(Duration value) {
  final clamped = value < Duration.zero ? Duration.zero : value;
  final totalSeconds = clamped.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final mm = minutes.toString().padLeft(2, '0');
    return '$hours:$mm:$ss';
  }
  return '$minutes:$ss';
}

/// "1.5x" style speed label. Computed, not a UI literal.
String _formatSpeedLabel(double speed) {
  final rounded = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
  return '${rounded}x';
}
