import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_mime.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Hands one document to the system: open it, save it to Files or share it.
typedef DocumentEgressPerformer =
    Future<MediaEgressResult> Function(
      MediaEgressDestination destination,
      MediaAttachment attachment,
    );

/// A document (PDF) attachment in a chat bubble (414): icon, name, size and
/// state. A ready PDF opens in the system viewer on tap; its menu saves it to
/// Files or shares it. Any other `file` attachment shows as unsupported and
/// never leaves the app.
class DocumentAttachmentTile extends StatelessWidget {
  const DocumentAttachmentTile({
    super.key,
    required this.attachment,
    this.onRetryUnavailableMedia,
    this.requireVerifiedContentHash = false,
    this.performEgress,
  });

  final MediaAttachment attachment;
  final VoidCallback? onRetryUnavailableMedia;

  /// Group media must verify its content hash before it is usable.
  final bool requireVerifiedContentHash;

  /// Test seam. Defaults to [ReceivedMediaEgressService].
  final DocumentEgressPerformer? performEgress;

  static Key tileKey(String attachmentId) =>
      ValueKey('document-attachment-$attachmentId');
  static Key menuKey(String attachmentId) =>
      ValueKey('document-attachment-menu-$attachmentId');
  static Key retryKey(String attachmentId) =>
      ValueKey('document-attachment-retry-$attachmentId');
  static Key downloadKey(String attachmentId) =>
      ValueKey('document-attachment-download-$attachmentId');

  bool get _isSupported => isSupportedDocumentMime(attachment.mime);

  bool get _isReady =>
      _isSupported &&
      attachment.localPath != null &&
      attachment.downloadStatus == kMediaDownloadStatusDone &&
      !GroupMediaIntegrityPolicy.isUnavailableMedia(
        attachment,
        requireVerifiedContentHash: requireVerifiedContentHash,
      );

  bool get _isUnavailable =>
      attachment.downloadStatus == kMediaDownloadStatusEvicted ||
      GroupMediaIntegrityPolicy.isUnavailableMedia(
        attachment,
        requireVerifiedContentHash: requireVerifiedContentHash,
      );

  /// Automatic download refused by the user's settings (or not started yet):
  /// offer an explicit Download. `downloading` keeps the progress indicator.
  bool get _canDownloadManually =>
      _isSupported &&
      onRetryUnavailableMedia != null &&
      attachment.downloadStatus == kMediaDownloadStatusPending;

  bool get _isInProgress =>
      _isSupported && !_isReady && !_isUnavailable && !_canDownloadManually;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = _isSupported
        ? (attachment.fileName ?? 'PDF')
        : l10n.media_document_unsupported;
    final subtitle = _isSupported
        ? 'PDF · ${_formatSize(attachment.size)}'
        : (attachment.fileName ?? _formatSize(attachment.size));

    Widget trailing;
    if (_isUnavailable && onRetryUnavailableMedia != null && _isSupported) {
      trailing = IconButton(
        key: retryKey(attachment.id),
        icon: const Icon(Icons.refresh),
        tooltip: l10n.media_retry_unavailable,
        onPressed: onRetryUnavailableMedia,
      );
    } else if (_canDownloadManually) {
      trailing = IconButton(
        key: downloadKey(attachment.id),
        icon: const Icon(Icons.download_rounded),
        tooltip: l10n.media_download,
        onPressed: onRetryUnavailableMedia,
      );
    } else if (_isInProgress) {
      trailing = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (_isReady) {
      trailing = IconButton(
        key: menuKey(attachment.id),
        icon: const Icon(Icons.more_vert),
        tooltip: l10n.media_viewer_action_share,
        onPressed: () => _showMenu(context),
      );
    } else {
      trailing = const SizedBox.shrink();
    }

    return Semantics(
      button: _isReady,
      label: _isReady ? '${l10n.media_document_open}, $name' : name,
      child: Material(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: tileKey(attachment.id),
          borderRadius: BorderRadius.circular(12),
          onTap: _isReady
              ? () => _perform(context, MediaEgressDestination.open)
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                Icon(
                  _isSupported
                      ? Icons.picture_as_pdf_outlined
                      : Icons.insert_drive_file_outlined,
                  color: _isSupported ? colors.error : colors.outline,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final destination = await showModalBottomSheet<MediaEgressDestination>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(l10n.media_save_destination_files),
              onTap: () =>
                  Navigator.of(sheetContext).pop(MediaEgressDestination.files),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: Text(l10n.media_viewer_action_share),
              onTap: () =>
                  Navigator.of(sheetContext).pop(MediaEgressDestination.share),
            ),
          ],
        ),
      ),
    );
    if (destination == null || !context.mounted) return;
    await _perform(context, destination);
  }

  Future<void> _perform(
    BuildContext context,
    MediaEgressDestination destination,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context)!;
    final performer = performEgress ?? _defaultEgress;
    MediaEgressResult result;
    try {
      result = await performer(destination, attachment);
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.media_document_open_failed)),
      );
      return;
    }
    final message = switch (result.outcome) {
      MediaEgressOutcome.presented ||
      MediaEgressOutcome.busy ||
      MediaEgressOutcome.cancelled => null,
      MediaEgressOutcome.saved => l10n.media_egress_result_saved,
      MediaEgressOutcome.noViewer => l10n.media_document_no_viewer,
      MediaEgressOutcome.permissionDenied =>
        l10n.media_egress_result_permission_denied,
      MediaEgressOutcome.partial ||
      MediaEgressOutcome.rejected ||
      MediaEgressOutcome.platformFailure =>
        destination == MediaEgressDestination.open
            ? l10n.media_document_open_failed
            : l10n.media_egress_result_failed,
    };
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  static Future<MediaEgressResult> _defaultEgress(
    MediaEgressDestination destination,
    MediaAttachment attachment,
  ) {
    return ReceivedMediaEgressService().perform(
      requestId: 'doc_${DateTime.now().microsecondsSinceEpoch}',
      destination: destination,
      selection: [
        ReceivedMediaEgressCandidate(
          attachmentId: attachment.id,
          storedPath: attachment.localPath!,
          mime: attachment.mime,
          fileName: attachment.fileName,
        ),
      ],
    );
  }
}

String _formatSize(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}
