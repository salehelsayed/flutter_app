import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/camera_video_recorder.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/application/sticker_clip_exporter.dart';
import 'package:flutter_app/features/stickers/application/sticker_cutout.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_still_export.dart';
import 'package:flutter_app/features/stickers/custom/editor/sticker_text_editor_screen.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/sticker_editor_result.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'sticker_create_flow.dart';

/// The largest centred pixel square of [frame], normalized to 0..1, which is
/// the crop shape the clip exporter accepts.
Rect centeredSquareCrop(Size frame) {
  final side = math.min(frame.width, frame.height);
  final left = (frame.width - side) / 2 / frame.width;
  final top = (frame.height - side) / 2 / frame.height;
  return Rect.fromLTRB(
    left,
    top,
    left + side / frame.width,
    top + side / frame.height,
  );
}

/// The clip exporter returns its WebP inside its own job folder together with
/// a poster; once admitted, the whole folder belongs to the caller.
const _clipJobPrefix = 'mknoon-sticker-animation-';

Future<void> deleteStickerTemp(String path) async {
  final parent = Directory(p.dirname(path));
  try {
    if (p.basename(parent.path).startsWith(_clipJobPrefix)) {
      await parent.delete(recursive: true);
    } else {
      await File(path).delete();
    }
  } on FileSystemException {
    // Already gone.
  }
}

Future<StickerCreateSource?> showStickerCreateSourceSheet(
  BuildContext context,
) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<StickerCreateSource>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              l10n.stickers_new,
              style: Theme.of(sheet).textTheme.titleMedium,
            ),
          ),
          for (final (source, icon, label) in [
            (
              StickerCreateSource.cameraPhoto,
              Icons.photo_camera_outlined,
              l10n.stickers_take_photo,
            ),
            (
              StickerCreateSource.galleryPhoto,
              Icons.photo_library_outlined,
              l10n.stickers_gallery,
            ),
            (
              StickerCreateSource.cameraClip,
              Icons.videocam_outlined,
              l10n.stickers_record_clip,
            ),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.of(sheet).pop(source),
            ),
        ],
      ),
    ),
  );
}

String? stickerCreateMessage(
  AppLocalizations l10n,
  StickerCreateOutcome outcome,
) => switch (outcome) {
  StickerCreateSaved() => l10n.stickers_saved,
  StickerCreateCancelled() => null,
  StickerCreateFailed(
    code: CustomStickerErrorCode.countQuota || CustomStickerErrorCode.byteQuota,
  ) =>
    l10n.stickers_library_full,
  StickerCreateFailed() => l10n.stickers_save_failed,
};

class _ShapeToggle extends StatelessWidget {
  const _ShapeToggle({required this.circle, required this.onChanged});

  final bool circle;

  /// Null disables the toggle.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SegmentedButton<bool>(
      segments: [
        ButtonSegment(value: false, label: Text(l10n.stickers_square)),
        ButtonSegment(value: true, label: Text(l10n.stickers_circle)),
      ],
      selected: {circle},
      onSelectionChanged: onChanged == null
          ? null
          : (selection) => onChanged!(selection.single),
    );
  }
}

/// Square crop over a still photo. Pops a [StickerStillCrop]; the circle mask
/// itself is applied by the editor's export.
class StickerCropScreen extends StatefulWidget {
  const StickerCropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<StickerCropScreen> createState() => _StickerCropScreenState();
}

class _StickerCropScreenState extends State<StickerCropScreen> {
  final _controller = CropController();
  bool _circle = false;
  CropStatus _status = CropStatus.nothing;

  bool get _ready => _status == CropStatus.ready;

  void _onCropped(CropResult result) {
    if (!mounted) return;
    switch (result) {
      case CropSuccess(:final croppedImage):
        Navigator.of(context).pop<StickerStillCrop>((
          bytes: croppedImage,
          shape: _circle ? StickerShape.circle : StickerShape.square,
        ));
      case CropFailure():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.stickers_new),
        actions: [
          TextButton(
            onPressed: _ready ? _controller.crop : null,
            child: Text(l10n.stickers_crop),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              image: widget.imageBytes,
              controller: _controller,
              aspectRatio: 1,
              withCircleUi: _circle,
              onCropped: _onCropped,
              onStatusChanged: (status) {
                if (mounted) setState(() => _status = status);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _ShapeToggle(
              circle: _circle,
              onChanged: _ready
                  ? (circle) {
                      setState(() => _circle = circle);
                      _controller.withCircleUi = circle;
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Plays the captured clip with the centred square it will be cut to.
/// Pops a [StickerClipCrop].
class StickerClipCropScreen extends StatefulWidget {
  const StickerClipCropScreen({super.key, required this.clipPath});

  final String clipPath;

  @override
  State<StickerClipCropScreen> createState() => _StickerClipCropScreenState();
}

class _StickerClipCropScreenState extends State<StickerClipCropScreen> {
  late final VideoPlayerController _video = VideoPlayerController.file(
    File(widget.clipPath),
  );
  bool _circle = false;

  @override
  void initState() {
    super.initState();
    _video
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _video.play();
      });
  }

  @override
  void dispose() {
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ready = _video.value.isInitialized;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.stickers_new),
        actions: [
          TextButton(
            onPressed: ready
                ? () => Navigator.of(context).pop<StickerClipCrop>((
                    crop: centeredSquareCrop(_video.value.size),
                    circle: _circle,
                  ))
                : null,
            child: Text(l10n.stickers_crop),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ready
                  ? AspectRatio(
                      aspectRatio: 1,
                      child: ClipPath(
                        clipper: _circle ? const _CircleClip() : null,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox.fromSize(
                            size: _video.value.size,
                            child: VideoPlayer(_video),
                          ),
                        ),
                      ),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _ShapeToggle(
              circle: _circle,
              onChanged: (circle) => setState(() => _circle = circle),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleClip extends CustomClipper<Path> {
  const _CircleClip();

  @override
  Path getClip(Size size) => Path()..addOval(Offset.zero & size);

  @override
  bool shouldReclip(_CircleClip oldClipper) => false;
}

/// A device without subject extraction: every photo goes straight to crop.
final class UnsupportedStickerCutout implements StickerCutoutService {
  const UnsupportedStickerCutout();

  @override
  Future<StickerCutoutAvailability> availability() async =>
      StickerCutoutAvailability.unsupported;

  @override
  Future<StickerCutout?> extract(String sourceImagePath) async => null;

  @override
  Future<void> cancel() async {}
}

/// Opens the Create flow from My stickers: source sheet, cut-out or crop,
/// editor, save, then one result message.
Future<void> openStickerCreate(
  BuildContext context, {
  required CustomStickerLibrary library,
  StickerCutoutService cutout = const UnsupportedStickerCutout(),
  MediaPicker? picker,
  StickerClipExporter? exporter,
  Future<Directory> Function() temporaryDirectory = getTemporaryDirectory,
}) async {
  final source = await showStickerCreateSourceSheet(context);
  if (source == null || !context.mounted) return;
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context)!;
  final media = picker ?? SystemMediaPicker();
  final clips = exporter ?? StickerClipExporter();

  final flow = StickerCreateFlow(
    library: library,
    cutout: cutout,
    // Some pickers return the user's original file; the flow deletes its
    // input, so it only ever gets an owned copy.
    pickPhoto: (source) async {
      final picked = await media.pickImage(
        source: source == StickerCreateSource.galleryPhoto
            ? ImageSource.gallery
            : ImageSource.camera,
      );
      if (picked == null) return null;
      final copy = p.join(
        (await temporaryDirectory()).path,
        'sticker-source-${DateTime.now().microsecondsSinceEpoch}'
        '${p.extension(picked.path)}',
      );
      await File(picked.path).copy(copy);
      return copy;
    },
    captureClip: () async {
      if (!context.mounted) return null;
      return (await captureStickerCameraClip(context))?.path;
    },
    readBytes: (path) => File(path).readAsBytes(),
    deleteFile: deleteStickerTemp,
    cropStill: (path) async => navigator.push<StickerStillCrop>(
      MaterialPageRoute(
        builder: (_) =>
            StickerCropScreen(imageBytes: File(path).readAsBytesSync()),
      ),
    ),
    cropClip: (path) => navigator.push<StickerClipCrop>(
      MaterialPageRoute(builder: (_) => StickerClipCropScreen(clipPath: path)),
    ),
    editStill: (bytes, shape) async =>
        _editInto(navigator, bytes, shape, await temporaryDirectory()),
    exportClip: (path, crop) =>
        clips.export(clipPath: path, crop: crop.crop, circle: crop.circle),
    showNoSubject: () => messenger.showSnackBar(
      SnackBar(content: Text(l10n.stickers_no_subject)),
    ),
  );

  StickerCreateOutcome outcome;
  try {
    outcome = await flow.run(source);
  } on Exception {
    outcome = const StickerCreateFailed(CustomStickerErrorCode.storageFailure);
  }
  final message = stickerCreateMessage(l10n, outcome);
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The text editor over [bytes], writing its PNG to a new file in [directory].
Future<StickerEditorResult> _editInto(
  NavigatorState navigator,
  Uint8List bytes,
  StickerShape shape,
  Directory directory,
) async {
  final output = File(
    p.join(
      directory.path,
      'sticker-${DateTime.now().microsecondsSinceEpoch}.png',
    ),
  );
  final result = await navigator.push<StickerEditorResult>(
    MaterialPageRoute(
      builder: (_) => StickerTextEditorScreen(
        sourceBytes: bytes,
        outputFile: output,
        shape: shape,
      ),
    ),
  );
  return result ?? const StickerEditorResult.cancelled();
}

/// Crops and edits a received photo that core lends for "Use as sticker".
/// The source stays untouched and the ready sticker is written only inside
/// [outputDirectory], which core cleans after admission.
Future<StickerEditorResult> editReceivedStickerPhoto(
  NavigatorState navigator, {
  required String sourceImagePath,
  required Directory outputDirectory,
}) async {
  final bytes = await File(sourceImagePath).readAsBytes();
  final crop = await navigator.push<StickerStillCrop>(
    MaterialPageRoute(builder: (_) => StickerCropScreen(imageBytes: bytes)),
  );
  if (crop == null) return const StickerEditorResult.cancelled();
  return _editInto(navigator, crop.bytes, crop.shape, outputDirectory);
}
