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
  final void Function(MediaAttachment attachment)? onRetryUnavailableMedia;
  final bool requireVerifiedContentHash;

  const MediaGrid({
    super.key,
    required this.media,
    this.onTap,
    this.onRetryUnavailableMedia,
    this.requireVerifiedContentHash = false,
  });

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(mediaGridContainerRadius),
      child: _buildLayout(),
    );
  }

  Widget _buildLayout() {
    final count = media.length;
    if (count == 1) return _buildSingle();
    if (count == 2) return _buildTwo();
    if (count == 3) return _buildThree();
    return _buildFourPlus();
  }

  Widget _buildSingle() {
    return AspectRatio(aspectRatio: 4 / 3, child: _cell(0));
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
                  onRetryUnavailableMedia: onRetryUnavailableMedia != null
                      ? () => onRetryUnavailableMedia!(media[3])
                      : null,
                  requireVerifiedContentHash: requireVerifiedContentHash,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cell(int index) {
    return MediaGridCell(
      attachment: media[index],
      onTap: onTap != null ? () => onTap!(index) : null,
      onRetryUnavailableMedia: onRetryUnavailableMedia != null
          ? () => onRetryUnavailableMedia!(media[index])
          : null,
      requireVerifiedContentHash: requireVerifiedContentHash,
    );
  }
}
