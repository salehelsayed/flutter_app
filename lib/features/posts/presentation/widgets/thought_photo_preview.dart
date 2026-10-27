import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_app/features/posts/application/post_media_draft.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'thought_photo_preparation.dart';

Future<PreparedThoughtPhotos?> showThoughtPhotoPreview(
  BuildContext context,
  List<PostMediaDraft> drafts, {
  required bool replacesCurrentThought,
}) => Navigator.of(context).push<PreparedThoughtPhotos>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _ThoughtPhotoPreview(
      drafts: drafts,
      replacesCurrentThought: replacesCurrentThought,
    ),
  ),
);

class _ThoughtPhotoPreview extends StatefulWidget {
  final List<PostMediaDraft> drafts;
  final bool replacesCurrentThought;

  const _ThoughtPhotoPreview({
    required this.drafts,
    required this.replacesCurrentThought,
  });

  @override
  State<_ThoughtPhotoPreview> createState() => _ThoughtPhotoPreviewState();
}

class _ThoughtPhotoPreviewState extends State<_ThoughtPhotoPreview> {
  final _pages = PageController();
  late final _framing = List<ThoughtPhotoFraming>.filled(
    widget.drafts.length,
    ThoughtPhotoFraming.fit,
  );
  int _index = 0;
  bool _applying = false;
  bool _failed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _apply(double aspectRatio) async {
    if (_applying) return;
    setState(() {
      _applying = true;
      _failed = false;
    });
    try {
      final result = await prepareThoughtPhotos(
        widget.drafts,
        _framing,
        aspectRatio: aspectRatio,
      );
      if (!mounted) {
        await result.discard();
        return;
      }
      Navigator.of(context).pop(result);
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  ImageProvider _photo(int index) => ResizeImage(
    FileImage(File(widget.drafts[index].localFilePath)),
    width: 2048,
    height: 2048,
    policy: ResizeImagePolicy.fit,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_applying,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final aspectRatio =
                math.min(constraints.maxWidth, constraints.maxHeight) /
                math.max(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: ClipRect(
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Color(0x66000000),
                          BlendMode.darken,
                        ),
                        child: Image.file(
                          File(widget.drafts[_index].localFilePath),
                          fit: BoxFit.cover,
                          cacheWidth: 120,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
                PageView.builder(
                  controller: _pages,
                  itemCount: widget.drafts.length,
                  onPageChanged: (index) => setState(() => _index = index),
                  itemBuilder: (context, index) => Center(
                    child: AspectRatio(
                      aspectRatio: aspectRatio,
                      child: Image(
                        image: _photo(index),
                        key: ValueKey('thought-photo-page-$index'),
                        fit: _framing[index] == ThoughtPhotoFraming.fit
                            ? BoxFit.contain
                            : BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: ColoredBox(
                    color: Colors.black45,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 16,
                          end: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.thought_compose_preview_photos,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                            TextButton(
                              key: const ValueKey('thought-photo-cancel'),
                              onPressed: _applying
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: Text(l10n.btn_cancel),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ColoredBox(
                    color: Colors.black87,
                    child: SafeArea(
                      top: false,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * .65,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.drafts.length > 1)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      key: const ValueKey(
                                        'thought-photo-previous',
                                      ),
                                      tooltip: MaterialLocalizations.of(
                                        context,
                                      ).previousPageTooltip,
                                      onPressed: _applying || _index == 0
                                          ? null
                                          : () => _pages.previousPage(
                                              duration: const Duration(
                                                milliseconds: 200,
                                              ),
                                              curve: Curves.easeOut,
                                            ),
                                      icon: const Icon(
                                        Icons.chevron_left,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      '${_index + 1} / ${widget.drafts.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    IconButton(
                                      key: const ValueKey('thought-photo-next'),
                                      tooltip: MaterialLocalizations.of(
                                        context,
                                      ).nextPageTooltip,
                                      onPressed:
                                          _applying ||
                                              _index == widget.drafts.length - 1
                                          ? null
                                          : () => _pages.nextPage(
                                              duration: const Duration(
                                                milliseconds: 200,
                                              ),
                                              curve: Curves.easeOut,
                                            ),
                                      icon: const Icon(
                                        Icons.chevron_right,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              Center(
                                child: Wrap(
                                  spacing: 12,
                                  children: [
                                    ChoiceChip(
                                      key: const ValueKey('thought-photo-fit'),
                                      label: Text(l10n.thought_photo_fit),
                                      selected:
                                          _framing[_index] ==
                                          ThoughtPhotoFraming.fit,
                                      onSelected: _applying
                                          ? null
                                          : (_) => setState(
                                              () => _framing[_index] =
                                                  ThoughtPhotoFraming.fit,
                                            ),
                                    ),
                                    ChoiceChip(
                                      key: const ValueKey('thought-photo-crop'),
                                      label: Text(l10n.thought_photo_crop),
                                      selected:
                                          _framing[_index] ==
                                          ThoughtPhotoFraming.fillScreen,
                                      onSelected: _applying
                                          ? null
                                          : (_) => setState(
                                              () => _framing[_index] =
                                                  ThoughtPhotoFraming
                                                      .fillScreen,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l10n.thought_compose_lifetime,
                                key: const ValueKey('thought-photo-lifetime'),
                                style: const TextStyle(color: Colors.white70),
                              ),
                              if (widget.replacesCurrentThought)
                                Text(
                                  l10n.thought_compose_replaces,
                                  key: const ValueKey('thought-photo-replaces'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (_failed)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    l10n.thought_compose_media_failed,
                                    key: const ValueKey('thought-photo-error'),
                                    style: const TextStyle(
                                      color: Color(0xFFFFB4A9),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              FilledButton(
                                key: const ValueKey('thought-photo-use'),
                                onPressed: _applying
                                    ? null
                                    : () => _apply(aspectRatio),
                                child: _applying
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(l10n.thought_photo_use),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
