import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'media_display_helpers.dart';
import 'media_grid_cell.dart';

/// Grid layout for image/video attachments.
///
/// Layout rules:
/// - 1 item: full width, 4:3 aspect ratio
/// - 2 items: side by side, 1:1 each
/// - 3 items: 1 top full (2:1) + 2 bottom (1:1 each)
/// - 4 items: 2x2 grid, 1:1 each
/// - 5+ items: 2x2 grid, "+N" overlay on 4th cell
class MediaGrid extends StatelessWidget {
  final List<MediaAttachment> media;
  final void Function(int index)? onTap;

  /// 235: per-attachment long-press carrying the exact tile index within
  /// [media] — the same index space as [onTap].
  final void Function(int index)? onLongPressItem;
  final void Function(MediaAttachment attachment)? onRetryUnavailableMedia;
  final bool requireVerifiedContentHash;

  /// 128 (round 5): owned-media dir id (1:1 contact peerId / groupId) for the
  /// render-boundary fallback to the durable `media/<id>/<blob>` copy.
  final String? ownedMediaPeerId;
  final Map<String, String> renderedSemanticsLabels;

  /// Opt-in for thoughts: a single photo or video keeps its own shape, whole,
  /// and stays at most this tall. The thought card fills the space around it
  /// with a blurred copy, so nothing is cropped. Null keeps the 4:3 frame chat
  /// uses.
  final double? singleMaxHeight;

  const MediaGrid({
    super.key,
    required this.media,
    this.onTap,
    this.onLongPressItem,
    this.onRetryUnavailableMedia,
    this.requireVerifiedContentHash = false,
    this.ownedMediaPeerId,
    this.renderedSemanticsLabels = const <String, String>{},
    this.singleMaxHeight,
  });

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();

    final grid = ClipRRect(
      borderRadius: BorderRadius.circular(mediaGridContainerRadius),
      child: _buildLayout(),
    );
    return singleMaxHeight != null && media.length == 1
        ? Center(heightFactor: 1, child: grid)
        : grid;
  }

  Widget _buildLayout() {
    final count = media.length;
    if (count == 1) return _buildSingle();
    if (count == 2) return _buildTwo();
    if (count == 3) return _buildThree();
    return _buildFourPlus();
  }

  Widget _buildSingle() {
    final maxHeight = singleMaxHeight;
    if (maxHeight == null) {
      return AspectRatio(aspectRatio: 4 / 3, child: _cell(0));
    }
    final width = media.single.width ?? 0;
    final height = media.single.height ?? 0;
    final ratio = width > 0 && height > 0 ? width / height : 4 / 3;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: AspectRatio(
        aspectRatio: ratio,
        child: _cell(0, fit: BoxFit.contain, cacheWidth: _fullScreenWidth),
      ),
    );
  }

  Widget _buildTwo() {
    return Row(
      children: [
        Expanded(child: AspectRatio(aspectRatio: 1, child: _cell(0))),
        const SizedBox(width: mediaGridGap),
        Expanded(child: AspectRatio(aspectRatio: 1, child: _cell(1))),
      ],
    );
  }

  Widget _buildThree() {
    return Column(
      children: [
        AspectRatio(aspectRatio: 2 / 1, child: _cell(0)),
        const SizedBox(height: mediaGridGap),
        Row(
          children: [
            Expanded(child: AspectRatio(aspectRatio: 1, child: _cell(1))),
            const SizedBox(width: mediaGridGap),
            Expanded(child: AspectRatio(aspectRatio: 1, child: _cell(2))),
          ],
        ),
      ],
    );
  }

  Widget _buildFourPlus() {
    final overflow = media.length - 4;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: AspectRatio(aspectRatio: 1, child: _cell(0))),
            const SizedBox(width: mediaGridGap),
            Expanded(child: AspectRatio(aspectRatio: 1, child: _cell(1))),
          ],
        ),
        const SizedBox(height: mediaGridGap),
        Row(
          children: [
            Expanded(child: AspectRatio(aspectRatio: 1, child: _cell(2))),
            const SizedBox(width: mediaGridGap),
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: MediaGridCell(
                  attachment: media[3],
                  showOverlayCount: overflow > 0,
                  overlayCount: overflow,
                  onTap: onTap != null ? () => onTap!(3) : null,
                  onLongPress: onLongPressItem != null
                      ? () => onLongPressItem!(3)
                      : null,
                  onRetryUnavailableMedia: onRetryUnavailableMedia != null
                      ? () => onRetryUnavailableMedia!(media[3])
                      : null,
                  requireVerifiedContentHash: requireVerifiedContentHash,
                  ownedMediaPeerId: ownedMediaPeerId,
                  renderedSemanticsLabel: renderedSemanticsLabels[media[3].id],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Decode width for a thought's single full-screen photo: sharp on large
  /// phones without decoding a camera original at full size.
  static const _fullScreenWidth = 1440;

  Widget _cell(int index, {BoxFit fit = BoxFit.cover, int cacheWidth = 400}) {
    return MediaGridCell(
      fit: fit,
      cacheWidth: cacheWidth,
      attachment: media[index],
      onTap: onTap != null ? () => onTap!(index) : null,
      onLongPress: onLongPressItem != null
          ? () => onLongPressItem!(index)
          : null,
      onRetryUnavailableMedia: onRetryUnavailableMedia != null
          ? () => onRetryUnavailableMedia!(media[index])
          : null,
      requireVerifiedContentHash: requireVerifiedContentHash,
      ownedMediaPeerId: ownedMediaPeerId,
      renderedSemanticsLabel: renderedSemanticsLabels[media[index].id],
    );
  }
}
