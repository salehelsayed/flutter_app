import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../thought_photo_framing.dart';

/// The picked photos inside the Thought composer. One shows at a time in a
/// square frame, framed the way friends will see it: a pinch zooms and a
/// drag places it, and Fit and Fill under it show the whole photo or cover
/// the square. With several, a tap on a thumbnail below shows that one;
/// each keeps its own framing. The X takes the shown photo out.
class ThoughtPhotoDraftPreview extends StatefulWidget {
  const ThoughtPhotoDraftPreview({
    super.key,
    required this.paths,
    required this.onRemove,
    this.framings = const {},
    this.onFramed,
  });

  final List<String> paths;
  final ValueChanged<int> onRemove;

  /// Each photo's framing by path; centred cover when absent.
  final Map<String, PhotoFraming> framings;
  final void Function(String path, PhotoFraming framing)? onFramed;

  @override
  State<ThoughtPhotoDraftPreview> createState() =>
      _ThoughtPhotoDraftPreviewState();
}

class _ThoughtPhotoDraftPreviewState extends State<ThoughtPhotoDraftPreview> {
  int _shown = 0;

  @override
  Widget build(BuildContext context) {
    final shown = math.min(_shown, widget.paths.length - 1);
    final path = widget.paths[shown];
    final rc = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FramedPhoto(
          key: ValueKey('thought-photo-draft-$path'),
          path: path,
          framing: widget.framings[path] ?? PhotoFraming.cover,
          onFramed: (framing) => widget.onFramed?.call(path, framing),
          hint: l10n.thought_photo_frame_hint,
          fitLabel: l10n.thought_photo_fit,
          fillLabel: l10n.thought_photo_fill,
          removeLabel: MaterialLocalizations.of(context).deleteButtonTooltip,
          onRemove: () => widget.onRemove(shown),
        ),
        if (widget.paths.length > 1) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: _thumbSide,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.paths.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => Semantics(
                key: ValueKey('thought-photo-thumb-$index'),
                button: true,
                selected: index == shown,
                label: l10n.thought_photo_position(
                  index + 1,
                  widget.paths.length,
                ),
                onTap: () => setState(() => _shown = index),
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => setState(() => _shown = index),
                  child: Container(
                    width: _thumbSide,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: index == shown ? rc.accent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image(
                        image: ResizeImage.resizeIfNeeded(
                          168,
                          null,
                          FileImage(File(widget.paths[index])),
                        ),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

const _thumbSide = 56.0;
const _maxFrameSide = 360.0;

class _FramedPhoto extends StatefulWidget {
  const _FramedPhoto({
    super.key,
    required this.path,
    required this.framing,
    required this.onFramed,
    required this.hint,
    required this.fitLabel,
    required this.fillLabel,
    required this.removeLabel,
    required this.onRemove,
  });

  final String path;
  final PhotoFraming framing;
  final ValueChanged<PhotoFraming> onFramed;
  final String hint;
  final String fitLabel;
  final String fillLabel;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  State<_FramedPhoto> createState() => _FramedPhotoState();
}

class _FramedPhotoState extends State<_FramedPhoto>
    with SingleTickerProviderStateMixin {
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Where the photo was when Fit or Fill was tapped; it glides from there.
  Rect? _movedFrom;

  late final ImageProvider _image = _FramePhotoImage(widget.path);
  ImageStream? _stream;
  late final _listener = ImageStreamListener(_onImage, onError: _onError);
  Size? _photo;
  Color? _fill;
  bool _failed = false;
  PhotoFraming _gestureStart = PhotoFraming.cover;
  Offset _gestureFrom = Offset.zero;

  @override
  void initState() {
    super.initState();
    photoEdgeColor(widget.path).then((fill) {
      if (mounted) setState(() => _fill = fill);
    }, onError: (Object _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stream = _image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _move.dispose();
    super.dispose();
  }

  Rect _shownCrop(Size photo) {
    final target = widget.framing.cropRect(photo);
    final from = _movedFrom;
    if (from == null || !_move.isAnimating) return target;
    // Each step of the glide is a framing the photo could hold, so a finger
    // landing on it carries on from exactly what is shown.
    return PhotoFraming.ofCrop(
      Rect.lerp(from, target, Curves.easeOutCubic.transform(_move.value))!,
      photo,
    ).cropRect(photo);
  }

  void _choose(Size photo, PhotoFraming target) {
    final from = _shownCrop(photo);
    widget.onFramed(target);
    if (MediaQuery.disableAnimationsOf(context)) {
      _move.stop();
      _movedFrom = null;
      return;
    }
    _movedFrom = from;
    _move.forward(from: 0);
  }

  void _onImage(ImageInfo info, bool _) {
    final size = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    info.dispose();
    if (!mounted) return;
    setState(() => _photo = size);
  }

  void _onError(Object _, StackTrace? _) {
    if (mounted) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, _maxFrameSide);
        final photo = _photo;
        final frame = Center(
          child: SizedBox.square(
            key: const ValueKey('thought-photo-frame-box'),
            dimension: side,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_fill case final fill?)
                    ColoredBox(
                      key: const ValueKey('thought-photo-frame-fill'),
                      color: fill,
                    )
                  else
                    const ColoredBox(color: Colors.black),
                  if (photo != null)
                    AnimatedBuilder(
                      animation: _move,
                      builder: (context, _) =>
                          _placed(photo, _shownCrop(photo), side),
                    )
                  else if (_failed)
                    const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                    ),
                  const IgnorePointer(
                    child: CustomPaint(painter: _ThirdsPainter()),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          key: const ValueKey('thought-photo-frame-hint'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: const ShapeDecoration(
                            color: Color(0x8C000000),
                            shape: StadiumBorder(),
                          ),
                          child: Text(
                            widget.hint,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      key: const ValueKey('thought-photo-draft-remove'),
                      tooltip: widget.removeLabel,
                      onPressed: widget.onRemove,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0x99000000),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (photo == null || PhotoFraming.wholeScale(photo) > 1 - 1e-6) {
          return frame;
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            frame,
            const SizedBox(height: 10),
            _FitFill(
              fitLabel: widget.fitLabel,
              fillLabel: widget.fillLabel,
              isFit: widget.framing.isWhole(photo),
              isFill: widget.framing.isCover,
              onFit: () => _choose(photo, PhotoFraming.whole(photo)),
              onFill: () => _choose(photo, PhotoFraming.cover),
            ),
          ],
        );
      },
    );
  }

  /// The photo at [crop], under a gesture layer that owns every pointer
  /// landing on it, so the sheet neither scrolls nor closes.
  Widget _placed(Size photo, Rect crop, double side) {
    final zoom = side / crop.width;
    return RawGestureDetector(
      key: const ValueKey('thought-photo-frame'),
      behavior: HitTestBehavior.opaque,
      gestures: {
        _EagerScaleGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_EagerScaleGestureRecognizer>(
              _EagerScaleGestureRecognizer.new,
              (recognizer) => recognizer
                ..onStart = (details) {
                  // A finger landing mid-glide holds the photo where it is
                  // shown and frames on from there.
                  if (_move.isAnimating) {
                    final shown = PhotoFraming.ofCrop(_shownCrop(photo), photo);
                    _move.stop();
                    _movedFrom = null;
                    widget.onFramed(shown);
                    _gestureStart = shown;
                  } else {
                    _gestureStart = widget.framing;
                  }
                  _gestureFrom = details.localFocalPoint;
                }
                ..onUpdate = (details) => widget.onFramed(
                  _gestureStart.pinched(
                    photo,
                    side,
                    from: _gestureFrom,
                    to: details.localFocalPoint,
                    zoom: details.scale,
                  ),
                ),
            ),
      },
      child: Stack(
        children: [
          Positioned(
            left: -crop.left * zoom,
            top: -crop.top * zoom,
            width: photo.width * zoom,
            height: photo.height * zoom,
            child: Image(
              key: const ValueKey('thought-photo-framed-image'),
              image: _image,
              fit: BoxFit.fill,
              excludeFromSemantics: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Two quiet choices in one pill under the frame: the whole photo, or the
/// photo covering the square. Neither is selected once the user has
/// pinched or dragged the photo elsewhere.
class _FitFill extends StatelessWidget {
  const _FitFill({
    required this.fitLabel,
    required this.fillLabel,
    required this.isFit,
    required this.isFill,
    required this.onFit,
    required this.onFill,
  });

  final String fitLabel;
  final String fillLabel;
  final bool isFit;
  final bool isFill;
  final VoidCallback onFit;
  final VoidCallback onFill;

  @override
  Widget build(BuildContext context) {
    final rc = context.backgroundReadableColors;
    final still = MediaQuery.disableAnimationsOf(context);
    Widget choice(String key, String label, bool selected, VoidCallback tap) =>
        Semantics(
          key: ValueKey(key),
          button: true,
          selected: selected,
          inMutuallyExclusiveGroup: true,
          label: label,
          onTap: tap,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tap,
            child: AnimatedContainer(
              duration: still
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minWidth: 84, minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                shape: const StadiumBorder(),
                color: selected
                    ? rc.textPrimary
                    : rc.textPrimary.withValues(alpha: 0),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? rc.surfaceBase : rc.textSecondary,
                ),
              ),
            ),
          ),
        );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: rc.glassBorder)),
        color: rc.surfaceSubtle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            choice('thought-photo-fit', fitLabel, isFit, onFit),
            choice('thought-photo-fill', fillLabel, isFill, onFill),
          ],
        ),
      ),
    );
  }
}

/// Wins the arena as soon as a finger lands, so a drag on the photo frames
/// it instead of scrolling or dismissing the sheet.
class _EagerScaleGestureRecognizer extends ScaleGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _ThirdsPainter extends CustomPainter {
  const _ThirdsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x59FFFFFF)
      ..strokeWidth = 1;
    for (final third in [1 / 3, 2 / 3]) {
      canvas
        ..drawLine(
          Offset(size.width * third, 0),
          Offset(size.width * third, size.height),
          paint,
        )
        ..drawLine(
          Offset(0, size.height * third),
          Offset(size.width, size.height * third),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_ThirdsPainter oldDelegate) => false;
}

/// The photo in the frame, decoded at most 1440 pixels long with
/// [thoughtDecodeSize], the sizing the bake uses, so a long thin strip
/// keeps its shape instead of decoding to an empty size.
class _FramePhotoImage extends ImageProvider<_FramePhotoImage> {
  const _FramePhotoImage(this.path);

  final String path;

  @override
  Future<_FramePhotoImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _FramePhotoImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(() async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(
        await File(path).readAsBytes(),
      );
      final codec = await decode(
        buffer,
        getTargetSize: (width, height) =>
            thoughtDecodeSize(width, height, 1440 / math.max(width, height)),
      );
      try {
        return ImageInfo(image: (await codec.getNextFrame()).image);
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // A failed load stays cached under this path otherwise, so the same
      // file could never open again once it is readable.
      PaintingBinding.instance.imageCache.evict(key);
      rethrow;
    }
  }());

  @override
  bool operator ==(Object other) =>
      other is _FramePhotoImage && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
