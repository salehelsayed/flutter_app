import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';

/// A front-card-only view. Removing it also disposes any voice player. Its
/// generation prevents a previous card's asynchronous media from reappearing.
class OrbitDepthMedia extends StatefulWidget {
  const OrbitDepthMedia({
    super.key,
    required this.postId,
    required this.load,
    required this.download,
    required this.onOpen,
  });
  final String postId;
  final Future<List<PostMediaAttachmentModel>> Function(String) load;
  final Future<PostMediaAttachmentModel> Function(PostMediaAttachmentModel)
  download;
  final VoidCallback onOpen;
  @override
  State<OrbitDepthMedia> createState() => _OrbitDepthMediaState();
}

class _OrbitDepthMediaState extends State<OrbitDepthMedia> {
  List<PostMediaAttachmentModel> _media = const [];
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant OrbitDepthMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) {
      _media = const [];
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final postId = widget.postId;
    setState(() {
      _loading = true;
      _failed = false;
    });
    bool current() =>
        mounted && generation == _generation && widget.postId == postId;
    try {
      var media = await widget
          .load(postId)
          .timeout(const Duration(seconds: 30));
      if (!current()) return;
      setState(() => _media = media);
      // Do not start media work for any card except the one still displayed.
      for (final attachment in media) {
        if (!current()) return;
        final local = attachment.localPath;
        if (local != null &&
            local.isNotEmpty &&
            File(MediaFileManager.resolveStoredPathSync(local)).existsSync()) {
          continue;
        }
        // The existing downloader joins an in-flight request and owns retry
        // state. Skipping it here would leave this card with a stale snapshot.
        try {
          await widget
              .download(attachment)
              .timeout(const Duration(seconds: 30));
        } catch (_) {
          if (!current()) return;
          _failed = true;
        }
      }
      if (!current()) return;
      media = await widget.load(postId).timeout(const Duration(seconds: 30));
      if (!current()) return;
      setState(() {
        _media = media;
        _loading = false;
        _failed |=
            media.isEmpty ||
            media.any((item) {
              final local = item.localPath;
              return local == null ||
                  local.isEmpty ||
                  !File(
                    MediaFileManager.resolveStoredPathSync(local),
                  ).existsSync();
            });
      });
    } catch (_) {
      if (current()) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = _media.where((item) => item.kind != 'voice').toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_loading && _media.isEmpty)
          const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_failed)
          TextButton(
            key: const ValueKey('orbit-depth-media-retry'),
            onPressed: () => unawaited(_load()),
            child: Text(AppLocalizations.of(context)!.btn_retry),
          ),
        for (final item in _media.where((item) => item.kind == 'voice'))
          AudioPlayerWidget(
            key: ValueKey('orbit-depth-voice-${item.mediaId}'),
            attachment: item.toSharedMediaAttachment(),
            onRetryUnavailableMedia: () => unawaited(_load()),
          ),
        if (visual.isNotEmpty)
          MediaGrid(
            media: visual
                .map((item) => item.toSharedMediaAttachment())
                .toList(),
            onTap: (_) => widget.onOpen(),
            onRetryUnavailableMedia: (_) => unawaited(_load()),
          ),
      ],
    );
  }
}
