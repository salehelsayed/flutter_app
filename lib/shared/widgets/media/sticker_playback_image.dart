import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/shared/widgets/press_feedback.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

enum StickerReplay { none, tap, button }

class StickerPlaybackImage extends StatefulWidget {
  const StickerPlaybackImage({
    super.key,
    required this.path,
    this.posterPath,
    this.fit = BoxFit.contain,
    this.decodeWidth = 256,
    this.autoPlay = true,
    this.skipIdenticalAutoplay = false,
    this.replay = StickerReplay.none,
    this.frameCount,
    this.placeholder,
    this.error,
    this.renderedSemanticsLabel,
  });

  final String path;
  final String? posterPath;
  final BoxFit fit;
  final int decodeWidth;
  final bool autoPlay;
  final bool skipIdenticalAutoplay;
  final StickerReplay replay;

  /// Admitted sticker metadata. With a poster this avoids opening the animation
  /// just to discover whether to show a play action.
  final int? frameCount;
  final Widget? placeholder;
  final Widget? error;
  final String? renderedSemanticsLabel;

  @override
  State<StickerPlaybackImage> createState() => _StickerPlaybackImageState();
}

const _maxFrames = 24;
const _maxFrameSide = 256;
const _maxSourceSide = 512;
const _maxSourceDuration = Duration(seconds: 2);
const _maxActiveAnimations = 3;
const _playbackTick = Duration(milliseconds: 100);
const _maxLoops = 3;
final _playback = _StickerPlaybackPool();

bool _canAnimate(int count) => count > 1 && count <= _maxFrames;

class _StickerPlaybackImageState extends State<StickerPlaybackImage> {
  final _scrollPositions = <ScrollPosition>{};
  ui.Image? _still;
  _StickerSequence? _sequence;
  Timer? _timer;
  bool? _animated;
  bool _failed = false;
  bool _scopeAllowsMotion = false;
  bool _reduceMotion = false;
  bool _visible = false;
  bool _autoplayAttempted = false;
  bool _visibilityCheckQueued = false;
  int _sourceGeneration = 0;
  int _frame = 0;
  int _loops = 0;

  String get _path => MediaFileManager.resolveStoredPathSync(widget.path);
  int get _decodeWidth => widget.decodeWidth.clamp(1, _maxFrameSide);
  bool get _wantsMotion =>
      widget.autoPlay || widget.replay != StickerReplay.none;
  bool get _canPlay => _visible && _scopeAllowsMotion && _playback.appActive;
  bool get _canAutoplay =>
      widget.autoPlay &&
      !_reduceMotion &&
      _canPlay &&
      _animated == true &&
      !_failed;

  @override
  void initState() {
    super.initState();
    _playback.register(this);
    _loadStill();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scopeAllowsMotion =
        TickerMode.valuesOf(context).enabled &&
        ModalRoute.isCurrentOf(context) != false;
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_scopeAllowsMotion) {
      _hide(rebuild: false);
    } else if (_reduceMotion && !_playback.isExplicit(this)) {
      _stop(rebuild: false);
    }

    final positions = <ScrollPosition>{};
    var ancestor = context;
    var scrollable = Scrollable.maybeOf(ancestor);
    while (scrollable != null) {
      positions.add(scrollable.position);
      ancestor = scrollable.context;
      scrollable = Scrollable.maybeOf(ancestor);
    }
    for (final position in _scrollPositions.difference(positions)) {
      position.removeListener(_queueVisibilityCheck);
    }
    for (final position in positions.difference(_scrollPositions)) {
      position.addListener(_queueVisibilityCheck);
    }
    _scrollPositions
      ..clear()
      ..addAll(positions);
    _queueVisibilityCheck();
  }

  @override
  void didUpdateWidget(StickerPlaybackImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path ||
        widget.posterPath != oldWidget.posterPath ||
        widget.decodeWidth != oldWidget.decodeWidth ||
        widget.frameCount != oldWidget.frameCount) {
      _hide(rebuild: false);
      _still?.dispose();
      _still = null;
      _loadStill();
    } else if (widget.autoPlay != oldWidget.autoPlay ||
        widget.skipIdenticalAutoplay != oldWidget.skipIdenticalAutoplay ||
        widget.replay != oldWidget.replay) {
      _autoplayAttempted = false;
      _stop(rebuild: false);
      if (_animated == null && _wantsMotion) _loadStill();
    }
    _queueVisibilityCheck();
  }

  void _loadStill() {
    final generation = ++_sourceGeneration;
    final path = _path;
    final width = _decodeWidth;
    final posterPath = widget.posterPath;
    final hint = widget.frameCount;
    final needsMetadata = _wantsMotion && hint == null;
    _animated = hint == null ? null : _canAnimate(hint);
    _failed = false;
    bool isCurrent() => mounted && generation == _sourceGeneration;

    unawaited(() async {
      try {
        final poster = posterPath == null || posterPath.isEmpty
            ? path
            : MediaFileManager.resolveStoredPathSync(posterPath);
        final posterFrame = await _playback.firstFrame(
          poster,
          width,
          isCurrent,
        );
        final first =
            posterFrame ??
            (poster == path || !isCurrent()
                ? null
                : await _playback.firstFrame(path, width, isCurrent));
        if (!isCurrent()) {
          first?.image.dispose();
          return;
        }
        if (first == null) {
          _hide();
          setState(() => _failed = true);
          return;
        }
        final previous = _still;
        setState(() {
          _still = first.image;
          if (first.path == path) _animated = _canAnimate(first.count);
        });
        previous?.dispose();
        if (first.path != path && needsMetadata) {
          final count = await _playback.countFrames(path, width, isCurrent);
          if (isCurrent()) setState(() => _animated = _canAnimate(count));
        }
      } on Exception {
        if (isCurrent()) {
          _hide();
          setState(() => _failed = true);
        }
      }
    }());
  }

  void _queueVisibilityCheck() {
    if (_visibilityCheckQueued || !_wantsMotion || _animated == false) return;
    _visibilityCheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckQueued = false;
      if (!mounted) return;
      if (!_scopeAllowsMotion || !_playback.appActive || !_hasPaintArea()) {
        _hide();
        return;
      }
      _visible = true;
      if (_canAutoplay && !_autoplayAttempted) {
        _autoplayAttempted = true;
        _play(explicit: false);
      }
    });
  }

  bool _hasPaintArea() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    var region = box.paintBounds;
    RenderObject child = box;
    var parent = child.parent;
    final transform = Matrix4.identity();
    while (parent != null) {
      if (!parent.paintsChild(child)) return false;
      transform.setIdentity();
      parent.applyPaintTransform(child, transform);
      region = MatrixUtils.transformRect(transform, region);
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) region = region.intersect(clip);
      if (region.isEmpty || !region.isFinite) return false;
      child = parent;
      parent = child.parent;
    }
    return region.overlaps(child.paintBounds);
  }

  void _play({required bool explicit}) {
    if (!_canPlay || _animated != true || _failed) return;
    if (explicit) _stop();
    final lease = _playback.claim(this, explicit: explicit);
    if (lease == null) return;
    _autoplayAttempted = true;
    bool isCurrent() => mounted && _playback.holds(lease) && _canPlay;
    unawaited(() async {
      final sequence = await _playback.sequence(
        _path,
        _decodeWidth,
        lease,
        isCurrent,
      );
      if (!isCurrent()) return;
      if (sequence == null) {
        _stop();
        if (_animated == true) setState(() => _animated = false);
        return;
      }
      if (lease.checkingMotion) {
        final identicalFrames = sequence.hasMotion == false;
        _playback.finishMotionCheck(lease, identicalFrames: identicalFrames);
        if (identicalFrames) return;
      }
      setState(() {
        _sequence = sequence;
        _frame = 0;
        _loops = 0;
      });
      _scheduleNextFrame();
    }());
  }

  void _scheduleNextFrame() {
    final sequence = _sequence!;
    _timer = Timer(sequence.frames[_frame].duration, () {
      if (!_canPlay || !_hasPaintArea()) {
        _hide();
        return;
      }
      final next = (_frame + 1) % sequence.frames.length;
      if (next == 0 && ++_loops == _maxLoops) {
        _stop();
        return;
      }
      setState(() => _frame = next);
      _scheduleNextFrame();
    });
  }

  void _hide({bool rebuild = true}) {
    _visible = false;
    _autoplayAttempted = false;
    _stop(rebuild: rebuild);
  }

  void _stop({bool rebuild = true}) {
    _timer?.cancel();
    _timer = null;
    final hadSequence = _sequence != null;
    _sequence = null;
    _playback.release(this);
    if (rebuild && hadSequence) setState(() {});
  }

  void _appStateChanged() {
    if (!_playback.appActive) {
      _hide();
    } else {
      _queueVisibilityCheck();
    }
  }

  @override
  void deactivate() {
    _hide(rebuild: false);
    super.deactivate();
  }

  @override
  void dispose() {
    _sourceGeneration++;
    _stop(rebuild: false);
    _playback.unregister(this);
    for (final position in _scrollPositions) {
      position.removeListener(_queueVisibilityCheck);
    }
    _still?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _queueVisibilityCheck();
    final image = _sequence?.frames[_frame].image ?? _still;
    if (image == null) {
      return (_failed ? widget.error : null) ??
          widget.placeholder ??
          const SizedBox.shrink();
    }

    Widget result = RawImage(image: image, fit: widget.fit);
    if (widget.renderedSemanticsLabel case final label?) {
      result = Semantics(container: true, label: label, child: result);
    }
    if (_animated == true && !_failed) {
      void replay() => _play(explicit: true);
      result = switch (widget.replay) {
        StickerReplay.none => result,
        StickerReplay.tap => GestureDetector(onTap: replay, child: result).withPressFeedback(),
        StickerReplay.button => Stack(
          fit: StackFit.passthrough,
          children: [
            result,
            PositionedDirectional(
              end: 0,
              bottom: 0,
              child: IconButton(
                tooltip: AppLocalizations.of(context)?.media_viewer_play,
                icon: const Icon(Icons.play_arrow_rounded),
                iconSize: 18,
                color: Colors.white,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(24),
                  minimumSize: const Size.square(24),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                onPressed: replay,
              ),
            ),
          ],
        ),
      };
    }
    return _wantsMotion && _animated != false
        ? _StickerPaintObserver(onPaint: _queueVisibilityCheck, child: result)
        : result;
  }
}

// Paint can resume without a widget rebuild, for example when an ancestor
// stops hiding or clipping this render object.
class _StickerPaintObserver extends SingleChildRenderObjectWidget {
  const _StickerPaintObserver({required this.onPaint, required super.child});

  final VoidCallback onPaint;

  @override
  _RenderStickerPaintObserver createRenderObject(BuildContext context) =>
      _RenderStickerPaintObserver(onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStickerPaintObserver renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

class _RenderStickerPaintObserver extends RenderProxyBox {
  _RenderStickerPaintObserver(this.onPaint);

  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}

typedef _StickerFrame = ({ui.Image image, Duration duration});
typedef _FirstStickerFrame = ({String path, ui.Image image, int count});
typedef _StickerFile = ({
  String path,
  int width,
  int length,
  DateTime modified,
  DateTime changed,
});

class _StickerSequence {
  _StickerSequence(this.frames)
    : bytes = frames.fold(0, (sum, frame) => sum + _imageBytes(frame.image));

  final List<_StickerFrame> frames;
  final int bytes;
  bool? hasMotion;

  Future<void> checkMotion(bool Function() isCurrent) async {
    if (hasMotion != null || !isCurrent()) return;
    try {
      final firstImage = frames.first.image;
      final first = await _framePixels(firstImage);
      if (first == null) return;
      for (final frame in frames.skip(1)) {
        if (!isCurrent()) return;
        final image = frame.image;
        if (image.width != firstImage.width ||
            image.height != firstImage.height) {
          hasMotion = true;
          return;
        }
        final other = await _framePixels(image);
        if (other == null || !isCurrent()) return;
        if (!listEquals(first, other)) {
          hasMotion = true;
          return;
        }
      }
      if (isCurrent()) hasMotion = false;
    } on Object {
      // Keep autoplay if the engine cannot read the pixels.
    }
  }

  Future<Uint32List?> _framePixels(ui.Image image) async {
    final retained = image.clone();
    try {
      final rgba = await retained.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      return rgba == null ? null : Uint32List.sublistView(rgba);
    } finally {
      retained.dispose();
    }
  }

  void dispose() {
    for (final frame in frames) {
      frame.image.dispose();
    }
  }
}

int _imageBytes(ui.Image image) => image.width * image.height * 4;

class _PlaybackLease {
  _PlaybackLease(
    this.owner, {
    required this.explicit,
    required this.checkingMotion,
  });

  final _StickerPlaybackImageState owner;
  final bool explicit;
  bool checkingMotion;
  _StickerSequence? sequence;
}

class _StickerPlaybackPool with WidgetsBindingObserver {
  // Decoding is serial. Reserve native compositing/current frames and the
  // previously displayed clones that have yet to leave their render objects.
  static const _sequenceBytes = _maxFrames * _maxFrameSide * _maxFrameSide * 4;
  static const _maxSequences = _maxActiveAnimations > 2
      ? _maxActiveAnimations
      : 2;
  static const _scratchBytes =
      2 * _maxSourceSide * _maxSourceSide * 4 +
      _maxActiveAnimations * _maxFrameSide * _maxFrameSide * 4;
  static const _byteLimit = _maxSequences * _sequenceBytes + _scratchBytes;

  final _states = <_StickerPlaybackImageState>{};
  final _leases = <_StickerPlaybackImageState, _PlaybackLease>{};
  final _deniedAutoplay = <_StickerPlaybackImageState>{};
  final _cache = <_StickerFile, _StickerSequence>{};
  Future<void>? _decodeTail;
  int _cachedBytes = 0;
  bool _observing = false;

  bool get _checkingMotion =>
      _leases.values.any((lease) => lease.checkingMotion);

  bool get appActive {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void register(_StickerPlaybackImageState state) {
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    _states.add(state);
  }

  void unregister(_StickerPlaybackImageState state) => _states.remove(state);

  _PlaybackLease? claim(
    _StickerPlaybackImageState state, {
    required bool explicit,
  }) {
    final checkingMotion = !explicit && state.widget.skipIdenticalAutoplay;
    if (_leases.length == _maxActiveAnimations) {
      if (!explicit) {
        if (checkingMotion && _checkingMotion) _deniedAutoplay.add(state);
        return null;
      }
      final victim = _leases.values.firstWhere(
        (lease) => !lease.explicit,
        orElse: () => _leases.values.first,
      );
      victim.owner._stop();
    }
    return _leases[state] = _PlaybackLease(
      state,
      explicit: explicit,
      checkingMotion: checkingMotion,
    );
  }

  void release(_StickerPlaybackImageState state) {
    _deniedAutoplay.remove(state);
    _leases.remove(state);
    if (!_checkingMotion) _deniedAutoplay.clear();
  }

  void finishMotionCheck(
    _PlaybackLease lease, {
    required bool identicalFrames,
  }) {
    lease.checkingMotion = false;
    if (identicalFrames) {
      _leases.remove(lease.owner);
      while (_deniedAutoplay.isNotEmpty) {
        final next = _deniedAutoplay.first;
        _deniedAutoplay.remove(next);
        if (next.mounted && next._canAutoplay && next._hasPaintArea()) {
          next._play(explicit: false);
          break;
        }
      }
    }
    if (!_checkingMotion) _deniedAutoplay.clear();
  }

  bool holds(_PlaybackLease lease) => identical(_leases[lease.owner], lease);

  bool isExplicit(_StickerPlaybackImageState state) =>
      _leases[state]?.explicit ?? false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    for (final renderer in _states) {
      renderer._appStateChanged();
    }
  }

  @override
  void didHaveMemoryPressure() {
    for (final lease in _leases.values.toList()) {
      lease.owner._stop();
    }
    for (final sequence in _cache.values) {
      sequence.dispose();
    }
    _cache.clear();
    _cachedBytes = 0;
  }

  Future<T> _serial<T>(Future<T> Function() decode) {
    final previous = _decodeTail;
    final next = previous == null
        ? Future<T>.sync(decode)
        : previous.then((_) => decode());
    late final Future<void> tail;
    void clearTail() {
      if (identical(_decodeTail, tail)) _decodeTail = null;
    }

    tail = next.then<void>(
      (_) => clearTail(),
      onError: (Object _) => clearTail(),
    );
    _decodeTail = tail;
    return next;
  }

  Future<_FirstStickerFrame?> firstFrame(
    String path,
    int width,
    bool Function() isCurrent,
  ) => _serial(() async {
    if (!isCurrent()) return null;
    ui.Codec? codec;
    try {
      codec = await _openCodec(path, width);
      if (!isCurrent()) return null;
      final frame = await codec.getNextFrame();
      return (
        path: path,
        image: await _scaleFrame(frame.image, width),
        count: codec.frameCount,
      );
    } on Exception {
      return null;
    } finally {
      codec?.dispose();
    }
  });

  Future<int> countFrames(String path, int width, bool Function() isCurrent) =>
      _serial(() async {
        if (!isCurrent()) return 0;
        ui.Codec? codec;
        try {
          codec = await _openCodec(path, width);
          return codec.frameCount;
        } on Exception {
          return 0;
        } finally {
          codec?.dispose();
        }
      });

  Future<_StickerSequence?> sequence(
    String path,
    int width,
    _PlaybackLease lease,
    bool Function() isCurrent,
  ) => _serial(() async {
    if (!isCurrent()) return null;
    ui.Codec? codec;
    final frames = <_StickerFrame>[];
    var retained = false;
    try {
      final key = await _fileIdentity(path, width);
      if (key == null || !isCurrent()) return null;
      final cached = _cache.remove(key);
      if (cached != null) {
        _cache[key] = cached;
        lease.sequence = cached;
        if (lease.checkingMotion) await cached.checkMotion(isCurrent);
        return cached;
      }
      while (_cache.length >= _maxSequences ||
          _cachedBytes + _sequenceBytes + _scratchBytes > _byteLimit) {
        final evicted = _cache.entries.where((entry) {
          return !_leases.values.any(
            (lease) => identical(lease.sequence, entry.value),
          );
        }).firstOrNull;
        if (evicted == null) return null;
        _cache.remove(evicted.key);
        _cachedBytes -= evicted.value.bytes;
        evicted.value.dispose();
      }
      codec = await _openCodec(path, width);
      if (!_canAnimate(codec.frameCount)) return null;
      final tickUs = _playbackTick.inMicroseconds;
      var sourceEnd = 0;
      var sampledTicks = 0;
      for (var i = 0; i < codec.frameCount; i++) {
        if (!isCurrent()) return null;
        final frame = await codec.getNextFrame();
        if (!isCurrent()) {
          frame.image.dispose();
          return null;
        }
        sourceEnd += math.max(1, frame.duration.inMicroseconds);
        if (sourceEnd > _maxSourceDuration.inMicroseconds) {
          frame.image.dispose();
          return null;
        }
        final endTick = (sourceEnd + tickUs - 1) ~/ tickUs;
        final ticks = endTick - sampledTicks;
        sampledTicks = endTick;
        // Keep a second frame if sampling would otherwise flatten the clip.
        final fallback = frames.length == 1 && i == codec.frameCount - 1;
        if (ticks == 0 && !fallback) {
          frame.image.dispose();
          continue;
        }
        frames.add((
          image: await _scaleFrame(frame.image, width),
          duration: _playbackTick * math.max(1, ticks),
        ));
      }
      codec.dispose();
      codec = null;
      if (!isCurrent()) return null;
      final sequence = _StickerSequence(frames);
      if (lease.checkingMotion) await sequence.checkMotion(isCurrent);
      if (!isCurrent()) return null;
      final loadedIdentity = await _fileIdentity(path, width);
      if (loadedIdentity != key || !isCurrent()) return null;
      _cache[key] = sequence;
      _cachedBytes += sequence.bytes;
      lease.sequence = sequence;
      retained = true;
      return sequence;
    } on Exception {
      return null;
    } finally {
      codec?.dispose();
      if (!retained) {
        for (final frame in frames) {
          frame.image.dispose();
        }
      }
    }
  });
}

Future<_StickerFile?> _fileIdentity(String path, int width) async {
  final stat = await File(path).stat();
  if (stat.type != FileSystemEntityType.file) return null;
  return (
    path: path,
    width: width,
    length: stat.size,
    modified: stat.modified,
    changed: stat.changed,
  );
}

({int width, int height}) _boundedSize(int width, int height, int maxWidth) {
  final scale = math.min(
    1.0,
    math.min(maxWidth / width, _maxFrameSide / height),
  );
  return (
    width: math.max(1, (width * scale).floor()),
    height: math.max(1, (height * scale).floor()),
  );
}

Future<ui.Codec> _openCodec(String path, int width) async {
  final buffer = await ui.ImmutableBuffer.fromFilePath(path);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width > _maxSourceSide ||
        descriptor.height > _maxSourceSide) {
      throw const FormatException('Sticker dimensions exceed playback bounds');
    }
    final size = _boundedSize(descriptor.width, descriptor.height, width);
    return await descriptor.instantiateCodec(
      targetWidth: size.width,
      targetHeight: size.height,
    );
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}

Future<ui.Image> _scaleFrame(ui.Image image, int width) async {
  final size = _boundedSize(image.width, image.height, width);
  if (size.width == image.width && size.height == image.height) return image;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromLTWH(0, 0, size.width.toDouble(), size.height.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size.width, size.height);
  } finally {
    picture.dispose();
    image.dispose();
  }
}
