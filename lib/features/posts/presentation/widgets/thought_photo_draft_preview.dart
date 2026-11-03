import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../thought_photo_framing.dart';

/// The picked photos inside the Thought composer. One shows at a time in a
/// square frame, framed the way friends will see it: a pinch zooms and a
/// drag places it. With several, a tap on a thumbnail below shows that
/// one; each keeps its own framing. The X takes the shown photo out.
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FramedPhoto(
          key: ValueKey('thought-photo-draft-$path'),
          path: path,
          framing: widget.framings[path] ?? PhotoFraming.cover,
          onFramed: (framing) => widget.onFramed?.call(path, framing),
          hint: AppLocalizations.of(context)!.thought_photo_frame_hint,
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
              itemBuilder: (context, index) => GestureDetector(
                key: ValueKey('thought-photo-thumb-$index'),
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
    required this.removeLabel,
    required this.onRemove,
  });

  final String path;
  final PhotoFraming framing;
  final ValueChanged<PhotoFraming> onFramed;
  final String hint;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  State<_FramedPhoto> createState() => _FramedPhotoState();
}

class _FramedPhotoState extends State<_FramedPhoto> {
  late final ImageProvider _image = ResizeImage.resizeIfNeeded(
    1440,
    null,
    FileImage(File(widget.path)),
  );
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
    super.dispose();
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
        return Center(
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
                    _placed(photo, widget.framing, side)
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
      },
    );
  }

  /// The photo at its framing, under a gesture layer that owns every
  /// pointer landing on it, so the sheet neither scrolls nor closes.
  Widget _placed(Size photo, PhotoFraming framing, double side) {
    final crop = framing.cropRect(photo);
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
                  _gestureStart = widget.framing;
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
            ),
          ),
        ],
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
