import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/build_direct_media_library_batch_forward.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/share/application/direct_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Pure, bounded UI for the direct-only Shared Media Batch Forward flow.
///
/// Authority, contact loading, delivery, wake-lock ownership, and route
/// completion stay in the wired owner. This widget only renders immutable
/// state and invokes typed callbacks.
class DirectMediaBatchForwardPickerScreen extends StatelessWidget {
  const DirectMediaBatchForwardPickerScreen({
    super.key,
    required this.items,
    required this.captionControllers,
    required this.contacts,
    required this.selectedContactPeerIds,
    required this.isLoading,
    required this.isSending,
    required this.targetsFrozen,
    required this.matrix,
    required this.progress,
    required this.showSourceUnavailable,
    required this.onToggleContact,
    required this.onClose,
    this.onSend,
    this.onRetryFailed,
  }) : assert(items.length == captionControllers.length);

  final List<DirectMediaLibraryBatchForwardItemDraft> items;
  final List<TextEditingController> captionControllers;
  final List<ContactModel> contacts;
  final Set<String> selectedContactPeerIds;
  final bool isLoading;
  final bool isSending;
  final bool targetsFrozen;
  final DirectMediaBatchForwardMatrix? matrix;
  final DirectMediaBatchForwardProgress? progress;
  final bool showSourceUnavailable;
  final ValueChanged<ContactModel> onToggleContact;
  final VoidCallback onClose;
  final VoidCallback? onSend;
  final VoidCallback? onRetryFailed;

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    return Semantics(
      key: const ValueKey('direct-batch-forward-picker'),
      container: true,
      child: Scaffold(
        backgroundColor: colors.surfaceBase,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              _buildSourceCount(context),
              _buildSourceList(context),
              // Progress, denial, and settled counts share one compact live
              // region. The prior matrix remains owned by the wired state
              // during retry, but rendering it underneath live progress can
              // push the action off a 320x568 RTL viewport at accessible text
              // scale. Its summary returns unchanged as soon as the attempt
              // settles.
              if (progress != null)
                _buildProgress(context, progress!)
              else if (showSourceUnavailable)
                _buildSourceUnavailable(context)
              else if (matrix != null)
                _buildMatrixSummary(context, matrix!),
              _buildContactsHeader(context),
              Expanded(child: _buildContactList(context)),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('direct-batch-forward-close'),
            onPressed: isSending ? null : onClose,
            tooltip: l10n.direct_batch_forward_close,
            color: colors.iconPrimary,
            disabledColor: colors.iconMuted,
            icon: const Icon(Icons.close),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              l10n.direct_batch_forward_title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildSourceCount(BuildContext context) {
    final colors = context.backgroundReadableColors;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
        child: Text(
          AppLocalizations.of(
            context,
          )!.direct_batch_forward_item_count(items.length),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildSourceList(BuildContext context) {
    // Keep the result/progress controls reachable on the compact supported
    // viewport. Arabic at 1.3x text scale legitimately needs an extra status
    // line; reclaim a small amount from the preview rail instead of allowing
    // the outer, non-scrollable action column to overflow.
    final hasStatusRegion =
        matrix != null || progress != null || showSourceUnavailable;
    return SizedBox(
      height: hasStatusRegion ? 160 : 176,
      child: ListView.builder(
        key: const ValueKey('direct-batch-forward-source-list'),
        scrollDirection: Axis.horizontal,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
        cacheExtent: 40,
        itemCount: items.length,
        itemBuilder: (context, index) => _buildSourceCard(context, index),
      ),
    );
  }

  Widget _buildSourceCard(BuildContext context, int index) {
    final colors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final item = items[index];
    final sourceLabel = l10n.direct_batch_forward_source_label(
      index + 1,
      items.length,
    );
    final captionLabel = l10n.direct_batch_forward_caption_label(
      index + 1,
      items.length,
    );
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth - 48).clamp(220.0, 320.0);

    return Semantics(
      key: ValueKey('direct-batch-forward-source-$index'),
      container: true,
      label: sourceLabel,
      child: Container(
        width: cardWidth,
        margin: const EdgeInsetsDirectional.only(end: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sourceLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 72,
                      child: Image.file(
                        File(item.resolvedPath),
                        key: ValueKey('direct-batch-forward-thumbnail-$index'),
                        fit: BoxFit.cover,
                        cacheWidth: 144,
                        filterQuality: FilterQuality.low,
                        excludeFromSemantics: true,
                        errorBuilder: (context, error, stackTrace) =>
                            ColoredBox(
                              color: colors.surfaceSubtle,
                              child: Icon(Icons.image, color: colors.iconMuted),
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: ValueKey('direct-batch-forward-caption-$index'),
                      controller: captionControllers[index],
                      enabled: !isSending,
                      maxLines: 3,
                      minLines: 2,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(color: colors.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: captionLabel,
                        labelStyle: TextStyle(
                          color: colors.textMuted,
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: colors.inputFill,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: colors.inputBorder),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: colors.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: colors.accent),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(
    BuildContext context,
    DirectMediaBatchForwardProgress value,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final phase = switch (value.phase) {
      DirectMediaBatchForwardProgressPhase.uploading =>
        l10n.direct_batch_forward_phase_uploading,
      DirectMediaBatchForwardProgressPhase.sending =>
        l10n.direct_batch_forward_phase_sending,
    };
    final label = l10n.direct_batch_forward_progress(
      phase,
      value.completedCellCount,
      value.totalCellCount,
    );
    return _liveRegion(
      context,
      key: const ValueKey('direct-batch-forward-progress'),
      label: label,
      icon: Icons.sync,
    );
  }

  Widget _buildSourceUnavailable(BuildContext context) => _liveRegion(
    context,
    key: const ValueKey('direct-batch-forward-source-unavailable'),
    label: AppLocalizations.of(
      context,
    )!.direct_batch_forward_source_unavailable,
    icon: Icons.info_outline,
  );

  Widget _buildMatrixSummary(
    BuildContext context,
    DirectMediaBatchForwardMatrix value,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final summary = l10n.direct_batch_forward_summary(
      value.sentCount,
      value.queuedCount,
      value.failedCount,
    );
    final colors = context.backgroundReadableColors;
    return Semantics(
      key: const ValueKey('direct-batch-forward-summary'),
      container: true,
      liveRegion: true,
      label: summary,
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _statusLabel(
                    key: const ValueKey('direct-batch-forward-status-sent'),
                    label: l10n.direct_batch_forward_status_sent,
                    count: value.sentCount,
                    color: colors.accent,
                  ),
                  _statusLabel(
                    key: const ValueKey('direct-batch-forward-status-queued'),
                    label: l10n.direct_batch_forward_status_queued,
                    count: value.queuedCount,
                    color: colors.textSecondary,
                  ),
                  _statusLabel(
                    key: const ValueKey('direct-batch-forward-status-failed'),
                    label: l10n.direct_batch_forward_status_failed,
                    count: value.failedCount,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusLabel({
    required Key key,
    required String label,
    required int count,
    required Color color,
  }) => Text(
    '$label $count',
    key: key,
    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
  );

  Widget _liveRegion(
    BuildContext context, {
    required Key key,
    required String label,
    required IconData icon,
  }) {
    final colors = context.backgroundReadableColors;
    return Semantics(
      key: key,
      container: true,
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: colors.iconSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactsHeader(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.direct_batch_forward_contacts_title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            l10n.share_target_count(selectedContactPeerIds.length),
            key: const ValueKey('direct-batch-forward-selection-count'),
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildContactList(BuildContext context) {
    final colors = context.backgroundReadableColors;
    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: colors.iconMuted));
    }
    if (contacts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            AppLocalizations.of(context)!.direct_batch_forward_no_contacts,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textMuted, fontSize: 14),
          ),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('direct-batch-forward-contacts-list'),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 4),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      cacheExtent: 80,
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final contact = contacts[index];
        final selected = selectedContactPeerIds.contains(contact.peerId);
        final enabled = !isSending && !targetsFrozen;
        return Semantics(
          key: ValueKey('direct-batch-forward-contact-${contact.peerId}'),
          container: true,
          button: true,
          selected: selected,
          enabled: enabled,
          label: contact.username,
          child: ExcludeSemantics(
            child: ListTile(
              enabled: enabled,
              contentPadding: EdgeInsets.zero,
              leading: RingAvatar(peerId: contact.peerId, size: 40),
              title: Text(
                contact.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textPrimary, fontSize: 15),
              ),
              trailing: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? colors.accent : colors.iconMuted,
              ),
              onTap: enabled ? () => onToggleContact(contact) : null,
            ),
          ),
        );
      },
    );
  }

  Widget _buildActions(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final hasMatrix = matrix != null;
    final showRetry = hasMatrix && matrix!.failedCount > 0;
    final callback = showRetry ? onRetryFailed : (hasMatrix ? null : onSend);
    final label = showRetry
        ? l10n.direct_batch_forward_retry_failed
        : l10n.direct_batch_forward_send;
    final key = showRetry
        ? const ValueKey('direct-batch-forward-retry-failed')
        : const ValueKey('direct-batch-forward-send');

    if (hasMatrix && !showRetry) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: colors.surfaceBase,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: FilledButton(
        key: key,
        onPressed: isSending ? null : callback,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          backgroundColor: colors.accent,
          foregroundColor: colors.accentIcon,
          disabledBackgroundColor: colors.disabledSurface,
          disabledForegroundColor: colors.disabledForeground,
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
