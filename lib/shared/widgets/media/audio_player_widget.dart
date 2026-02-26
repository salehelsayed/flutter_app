import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'media_display_helpers.dart';
import 'waveform_seek_bar.dart';

/// Inline audio player with play/pause button, progress bar, and duration.
class AudioPlayerWidget extends StatefulWidget {
  final MediaAttachment attachment;

  const AudioPlayerWidget({super.key, required this.attachment});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isLoaded = false;
  String? _loadedPath;
  int _loadVersion = 0;

  bool get _isAvailable =>
      widget.attachment.localPath != null &&
      widget.attachment.downloadStatus == 'done';

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();

    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
          _position = Duration.zero;
          _player.seek(Duration.zero);
          _player.pause();
        }
      });
    });

    _player.durationStream.listen((dur) {
      if (dur != null && mounted) {
        setState(() => _duration = dur);
      }
    });

    if (_isAvailable) {
      _loadAudio();
    }
  }

  Future<void> _loadAudio() async {
    final path = widget.attachment.localPath;
    if (path == null || !_isAvailable) return;
    if (_isLoaded && _loadedPath == path) return;
    final loadVersion = ++_loadVersion;

    try {
      await _player.setFilePath(path);
      if (!mounted || loadVersion != _loadVersion) return;
      if (mounted) {
        setState(() {
          _isLoaded = true;
          _loadedPath = path;
          _position = Duration.zero;
        });
      }
    } catch (_) {
      // File may be corrupted or missing — stay in disabled state
      if (!mounted || loadVersion != _loadVersion) return;
      if (mounted) {
        setState(() {
          _isLoaded = false;
          _loadedPath = null;
        });
      }
    }
  }

  @override
  void didUpdateWidget(AudioPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.localPath != widget.attachment.localPath ||
        oldWidget.attachment.downloadStatus != widget.attachment.downloadStatus;

    if (sourceChanged) {
      unawaited(_reloadAudioForNewAttachment());
      return;
    }

    if (!_isLoaded && _isAvailable) {
      _loadAudio();
    }
  }

  Future<void> _reloadAudioForNewAttachment() async {
    _loadVersion++;

    try {
      await _player.stop();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
        _duration = Duration.zero;
        _isLoaded = false;
        _loadedPath = null;
      });
    }

    if (_isAvailable) {
      await _loadAudio();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (!_isLoaded) return;
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  void _onSeek(double value) {
    if (!_isLoaded || _duration.inMilliseconds == 0) return;
    _player.seek(
      Duration(milliseconds: (value * _duration.inMilliseconds).round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : widget.attachment.durationMs ?? 0;
    final progress = totalMs > 0 ? _position.inMilliseconds / totalMs : 0.0;

    final durationText = _isAvailable && _isLoaded
        ? (_isPlaying
              ? '${formatDurationMs(_position.inMilliseconds)} / ${formatDurationMs(totalMs)}'
              : formatDurationMs(totalMs))
        : '--:--';

    final hasWaveform = widget.attachment.waveform != null;

    return Row(
      children: [
        // Play/pause button
        GestureDetector(
          onTap: _isAvailable ? _togglePlayPause : null,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isAvailable
                  ? const Color.fromRGBO(78, 205, 196, 0.20)
                  : const Color.fromRGBO(255, 255, 255, 0.06),
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 14,
              color: _isAvailable
                  ? const Color(0xFF4ecdc4)
                  : const Color.fromRGBO(255, 255, 255, 0.25),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Progress: waveform bars or slider
        Expanded(
          child: SizedBox(
            height: 28,
            child: hasWaveform
                ? WaveformSeekBar(
                    waveform: widget.attachment.waveform,
                    progress: progress.clamp(0.0, 1.0),
                    onSeek: _isAvailable && _isLoaded ? _onSeek : null,
                  )
                : SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      activeTrackColor: const Color(0xFF4ecdc4),
                      inactiveTrackColor: const Color.fromRGBO(
                        255,
                        255,
                        255,
                        0.15,
                      ),
                      thumbColor: const Color(0xFF4ecdc4),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 10,
                      ),
                    ),
                    child: Slider(
                      value: progress.clamp(0.0, 1.0),
                      onChanged: _isAvailable && _isLoaded ? _onSeek : null,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        // Duration label
        Text(
          durationText,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: Color.fromRGBO(255, 255, 255, 0.25),
          ),
        ),
      ],
    );
  }
}
