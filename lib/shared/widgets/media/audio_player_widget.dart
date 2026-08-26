import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'media_display_helpers.dart';
import 'waveform_seek_bar.dart';

/// Cross-platform audio-session rules for voice messages whose playback was
/// explicitly started by the user.
///
/// iOS mixes system/notification audio into the playback session instead of
/// interrupting it. Android classifies the content as speech/media and allows
/// notification-style focus changes to duck without converting them to a
/// pause. [AudioPlayer] interruption handling is disabled and the narrower
/// app-owned policy below handles genuine pause interruptions, permanent loss,
/// and unplugged outputs.
class UserInitiatedVoicePlaybackPolicy {
  const UserInitiatedVoicePlaybackPolicy._();

  static const bool handlePluginInterruptions = false;

  static const AudioSessionConfiguration audioSessionConfiguration =
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      );

  static AudioPlayer createPlayer() =>
      AudioPlayer(handleInterruptions: handlePluginInterruptions);
}

/// Preserves user playback ownership across audio-session interruptions.
///
/// Duck interruptions leave playback state unchanged. A pause interruption
/// pauses only active playback and owns one resume after the pause command has
/// settled. User actions and completion can revoke that ownership. Unknown
/// loss and unplugged outputs pause fail-safe without any automatic resume.
class UserInitiatedVoiceInterruptionHandler {
  UserInitiatedVoiceInterruptionHandler({
    required this.isPlaying,
    required this.pause,
    required this.resume,
    this.onPlaybackRetentionChanged,
  });

  final bool Function() isPlaying;
  final Future<void> Function() pause;
  final Future<void> Function() resume;
  final void Function()? onPlaybackRetentionChanged;

  bool _ownsPauseResume = false;
  bool _pauseCommandSettled = false;
  bool _pauseEndReceived = false;
  int _pauseGeneration = 0;
  int? _resumeInFlightGeneration;
  Future<void>? _resumeInFlightTask;

  /// True while a reversible interruption still owns playback continuity,
  /// including while its asynchronous resume command is settling.
  bool get retainsUserPlayback =>
      _ownsPauseResume || _resumeInFlightTask != null;

  void handle(AudioInterruptionEvent event) {
    switch (event.type) {
      case AudioInterruptionType.duck:
        return;
      case AudioInterruptionType.pause:
        if (event.begin) {
          _beginPauseInterruption();
        } else {
          _endPauseInterruption();
        }
        return;
      case AudioInterruptionType.unknown:
        if (event.begin) {
          cancelPendingResume();
          _pauseWithoutResumeIfPlaying();
        }
        return;
    }
  }

  void handleBecomingNoisy() {
    cancelPendingResume();
    _pauseWithoutResumeIfPlaying();
  }

  /// Revokes interruption-owned resume authority after a user action,
  /// completion, source change, or disposal.
  void cancelPendingResume() {
    final retainedBefore = retainsUserPlayback;
    final hadInFlightResume = _resumeInFlightTask != null;
    _resumeInFlightGeneration = null;
    _resumeInFlightTask = null;
    _ownsPauseResume = false;
    _pauseCommandSettled = false;
    _pauseEndReceived = false;
    _pauseGeneration++;
    _notifyRetentionChange(retainedBefore);
    if (hadInFlightResume) unawaited(_pauseSafely());
  }

  void _beginPauseInterruption() {
    final resumeToReconcile = _resumeInFlightTask;
    if (_ownsPauseResume || (!isPlaying() && resumeToReconcile == null)) {
      return;
    }
    final retainedBefore = retainsUserPlayback;
    _ownsPauseResume = true;
    _pauseCommandSettled = false;
    _pauseEndReceived = false;
    final generation = ++_pauseGeneration;
    _notifyRetentionChange(retainedBefore);
    unawaited(
      _pauseForInterruption(generation, resumeToReconcile: resumeToReconcile),
    );
  }

  Future<void> _pauseForInterruption(
    int generation, {
    required Future<void>? resumeToReconcile,
  }) async {
    try {
      await pause();
    } catch (_) {
      if (generation == _pauseGeneration) cancelPendingResume();
      return;
    }
    // A newer transient loss cannot settle until the older resume command has
    // either stayed paused or been re-paused by its generation fence.
    if (resumeToReconcile != null) await resumeToReconcile;
    if (generation != _pauseGeneration || !_ownsPauseResume) return;
    _pauseCommandSettled = true;
    _resumeAfterPauseEndIfOwned();
  }

  void _endPauseInterruption() {
    if (!_ownsPauseResume) return;
    _pauseEndReceived = true;
    _resumeAfterPauseEndIfOwned();
  }

  void _resumeAfterPauseEndIfOwned() {
    if (!_ownsPauseResume || !_pauseCommandSettled || !_pauseEndReceived) {
      return;
    }
    final retainedBefore = retainsUserPlayback;
    _ownsPauseResume = false;
    _pauseCommandSettled = false;
    _pauseEndReceived = false;
    final generation = ++_pauseGeneration;
    if (!isPlaying()) {
      final task = _resumeSafely(generation);
      _resumeInFlightTask = task;
      unawaited(task);
    }
    _notifyRetentionChange(retainedBefore);
  }

  void _pauseWithoutResumeIfPlaying() {
    if (isPlaying()) unawaited(_pauseSafely());
  }

  Future<void> _pauseSafely() async {
    try {
      await pause();
    } catch (_) {}
  }

  Future<void> _resumeSafely(int generation) async {
    if (generation != _pauseGeneration) return;
    _resumeInFlightGeneration = generation;
    try {
      await resume();
    } catch (_) {}
    // A source change, disposal, completion, or user action may invalidate an
    // already-started platform play command. Reassert the newer paused state
    // after that stale asynchronous command settles.
    if (generation != _pauseGeneration && isPlaying()) {
      await _pauseSafely();
    }
    if (_resumeInFlightGeneration == generation) {
      final retainedBefore = retainsUserPlayback;
      _resumeInFlightGeneration = null;
      _resumeInFlightTask = null;
      _notifyRetentionChange(retainedBefore);
    }
  }

  void _notifyRetentionChange(bool retainedBefore) {
    if (retainedBefore != retainsUserPlayback) {
      onPlaybackRetentionChanged?.call();
    }
  }
}

/// Inline audio player with play/pause button, progress bar, and duration.
class AudioPlayerWidget extends StatefulWidget {
  final MediaAttachment attachment;
  final bool requireVerifiedContentHash;
  final VoidCallback? onRetryUnavailableMedia;
  final String? renderedSemanticsLabel;

  @visibleForTesting
  final Stream<AudioInterruptionEvent>? interruptionEvents;

  const AudioPlayerWidget({
    super.key,
    required this.attachment,
    this.requireVerifiedContentHash = false,
    this.onRetryUnavailableMedia,
    this.renderedSemanticsLabel,
    this.interruptionEvents,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget>
    with AutomaticKeepAliveClientMixin<AudioPlayerWidget> {
  late final AudioPlayer _player;
  late final StreamSubscription<PlayerState> _playerStateSubscription;
  late final StreamSubscription<Duration?> _durationSubscription;
  late final UserInitiatedVoiceInterruptionHandler _interruptionHandler;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _becomingNoisySubscription;
  Timer? _positionTimer;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isLoaded = false;
  String? _loadedPath;
  String? _loadingPath;
  int _loadVersion = 0;
  bool _playStartPending = false;
  bool _isDisposing = false;
  bool _retainsInterruptedPlayback = false;

  /// Retain only active or reversibly interrupted user playback. User-paused,
  /// completed, failed, and never-started rows remain normally recyclable.
  @override
  bool get wantKeepAlive => _isPlaying || _retainsInterruptedPlayback;

  bool get _isAvailable =>
      widget.attachment.localPath != null &&
      widget.attachment.downloadStatus == kMediaDownloadStatusDone &&
      (!widget.requireVerifiedContentHash ||
          GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(
            widget.attachment,
          ));

  bool get _showsUnavailableMedia =>
      GroupMediaIntegrityPolicy.isUnavailableMedia(
        widget.attachment,
        requireVerifiedContentHash: widget.requireVerifiedContentHash,
      );

  bool get _canRetryUnavailableMedia =>
      widget.onRetryUnavailableMedia != null &&
      GroupMediaIntegrityPolicy.isRetryableDownloadFailure(widget.attachment);

  /// 229: user-removed local copy — renders a truthful removed state (never
  /// a disabled forever-player) with a user-authoritative explicit Retry.
  bool get _isEvicted =>
      widget.attachment.downloadStatus == kMediaDownloadStatusEvicted;

  @override
  void initState() {
    super.initState();
    _player = UserInitiatedVoicePlaybackPolicy.createPlayer();
    _interruptionHandler = UserInitiatedVoiceInterruptionHandler(
      isPlaying: () => mounted && _player.playing,
      pause: () async {
        if (mounted) await _player.pause();
      },
      resume: () async {
        if (!mounted ||
            !_isLoaded ||
            _player.processingState == ProcessingState.completed) {
          return;
        }
        await _player.play();
      },
      onPlaybackRetentionChanged: () {
        _retainsInterruptedPlayback = _interruptionHandler.retainsUserPlayback;
        if (mounted && !_isDisposing) updateKeepAlive();
      },
    );

    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        _interruptionHandler.cancelPendingResume();
      }
      if (state.playing && state.processingState != ProcessingState.completed) {
        _startPositionTimer();
      } else {
        _stopPositionTimer();
      }
      setState(() {
        _isPlaying = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
          _position = Duration.zero;
          _player.seek(Duration.zero);
          _player.pause();
        }
      });
      updateKeepAlive();
    });

    _durationSubscription = _player.durationStream.listen((dur) {
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
    if ((_isLoaded && _loadedPath == path) || _loadingPath == path) return;
    final loadVersion = ++_loadVersion;
    _loadingPath = path;

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
    } finally {
      if (loadVersion == _loadVersion) _loadingPath = null;
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
    _loadingPath = null;
    _stopPositionTimer();
    _interruptionHandler.cancelPendingResume();

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
      updateKeepAlive();
    }

    if (_isAvailable) {
      await _loadAudio();
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    _stopPositionTimer();
    _interruptionHandler.cancelPendingResume();
    unawaited(_playerStateSubscription.cancel());
    unawaited(_durationSubscription.cancel());
    unawaited(_interruptionSubscription?.cancel());
    unawaited(_becomingNoisySubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  void _startPositionTimer() {
    if (_positionTimer != null) return;
    _positionTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() => _position = _player.position);
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void _togglePlayPause() {
    if (!_isLoaded) return;
    _interruptionHandler.cancelPendingResume();
    if (_isPlaying) {
      unawaited(_player.pause());
    } else {
      unawaited(_startUserInitiatedPlayback());
    }
  }

  Future<void> _startUserInitiatedPlayback() async {
    if (_playStartPending || !_isLoaded || _isPlaying) return;
    _playStartPending = true;
    final loadVersion = _loadVersion;
    try {
      final session = await AudioSession.instance;
      if (!mounted) return;

      _interruptionSubscription ??=
          (widget.interruptionEvents ?? session.interruptionEventStream).listen(
            _interruptionHandler.handle,
          );
      _becomingNoisySubscription ??= session.becomingNoisyEventStream.listen((
        _,
      ) {
        if (mounted) _interruptionHandler.handleBecomingNoisy();
      });
      await session.configure(
        UserInitiatedVoicePlaybackPolicy.audioSessionConfiguration,
      );

      if (!mounted || loadVersion != _loadVersion || !_isLoaded || _isPlaying) {
        return;
      }
      unawaited(_player.play());
    } finally {
      _playStartPending = false;
    }
  }

  void _onSeek(double value) {
    if (!_isLoaded || _duration.inMilliseconds == 0) return;
    final position = Duration(
      milliseconds: (value * _duration.inMilliseconds).round(),
    );
    setState(() => _position = position);
    unawaited(_player.seek(position));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isEvicted) {
      return _buildEvictedAudio();
    }
    if (_showsUnavailableMedia) {
      return _buildUnavailableAudio();
    }

    final totalMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : widget.attachment.durationMs ?? 0;
    final progress = totalMs > 0 ? _position.inMilliseconds / totalMs : 0.0;

    final durationText = _isAvailable && totalMs > 0
        ? (_isPlaying
              ? '${formatDurationMs(_position.inMilliseconds)} / ${formatDurationMs(totalMs)}'
              : formatDurationMs(totalMs))
        : '--:--';

    final hasWaveform = widget.attachment.waveform != null;

    final player = Row(
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
    final label = widget.renderedSemanticsLabel;
    if (label == null || !_isLoaded) return player;
    return Semantics(container: true, label: label, child: player);
  }

  /// 229: "local copy removed" pill. Retry is user-authoritative (never
  /// gated by the bounded auto-retry budget or the auto-download
  /// preference) and settles truthfully — done, or terminal unavailable
  /// once the relay copy has expired.
  Widget _buildEvictedAudio() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      key: ValueKey('evicted-media-audio-${widget.attachment.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.08)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.file_download_off_outlined,
            size: 18,
            color: Color.fromRGBO(255, 255, 255, 0.42),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.media_local_copy_removed,
              style: const TextStyle(
                color: Color.fromRGBO(255, 255, 255, 0.66),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (widget.onRetryUnavailableMedia != null)
            Semantics(
              container: true,
              label: l10n.media_retry_unavailable,
              button: true,
              child: IconButton(
                key: ValueKey(
                  'evicted-media-retry-${widget.attachment.messageId}-${widget.attachment.id}',
                ),
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                color: const Color(0xFF4ecdc4),
                onPressed: widget.onRetryUnavailableMedia,
                tooltip: l10n.media_retry_unavailable,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUnavailableAudio() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      key: ValueKey('unavailable-media-audio-${widget.attachment.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.08)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.volume_off_rounded,
            size: 18,
            color: Color.fromRGBO(255, 255, 255, 0.42),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              // Tamper (integrity_failed) gets an honest "couldn't verify"
              // label, distinct from the generic unavailable/terminal copy.
              GroupMediaIntegrityPolicy.isQuarantinedGroupMedia(
                    widget.attachment,
                  )
                  ? l10n.media_could_not_verify
                  : l10n.media_unavailable,
              style: const TextStyle(
                color: Color.fromRGBO(255, 255, 255, 0.66),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_canRetryUnavailableMedia)
            Semantics(
              container: true,
              label: l10n.media_retry_unavailable,
              button: true,
              child: IconButton(
                key: ValueKey(
                  'unavailable-media-retry-${widget.attachment.messageId}-${widget.attachment.id}',
                ),
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                color: const Color(0xFF4ecdc4),
                onPressed: widget.onRetryUnavailableMedia,
                tooltip: l10n.media_retry_unavailable,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
        ],
      ),
    );
  }
}
