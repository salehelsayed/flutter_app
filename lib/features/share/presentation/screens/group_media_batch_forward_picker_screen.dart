import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_media_batch_forward.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/share/application/group_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Pure target/caption/result surface shared by discussion and announcement
/// libraries. All source and destination authority stays in the wired owner.
class GroupMediaBatchForwardPickerScreen extends StatelessWidget {
  const GroupMediaBatchForwardPickerScreen({
    super.key,
    required this.items,
    required this.captionControllers,
    required this.contacts,
    required this.groups,
    required this.selectedContactPeerIds,
    required this.selectedGroupIds,
    required this.isLoading,
    required this.isSending,
    required this.targetsFrozen,
    required this.matrix,
    required this.progress,
    required this.sourceDenial,
    required this.onToggleContact,
    required this.onToggleGroup,
    required this.onClose,
    this.onSend,
    this.onRetryFailed,
  }) : assert(items.length == captionControllers.length);

  final List<GroupMediaBatchForwardItemDraft> items;
  final List<TextEditingController> captionControllers;
  final List<ContactModel> contacts;
  final List<GroupModel> groups;
  final Set<String> selectedContactPeerIds;
  final Set<String> selectedGroupIds;
  final bool isLoading;
  final bool isSending;
  final bool targetsFrozen;
  final GroupMediaBatchForwardMatrix? matrix;
  final GroupMediaBatchForwardProgress? progress;
  final GroupMediaBatchForwardDenial? sourceDenial;
  final ValueChanged<ContactModel> onToggleContact;
  final ValueChanged<GroupModel> onToggleGroup;
  final VoidCallback onClose;
  final VoidCallback? onSend;
  final VoidCallback? onRetryFailed;

  int get _selectionCount =>
      selectedContactPeerIds.length + selectedGroupIds.length;

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    return Semantics(
      key: const ValueKey('group-batch-forward-picker'),
      container: true,
      child: Scaffold(
        backgroundColor: colors.surfaceBase,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              _buildSourceStrip(context),
              if (progress != null)
                _buildProgress(context, progress!)
              else if (sourceDenial != null)
                _buildLiveRegion(
                  context,
                  key: ValueKey(
                    sourceDenial ==
                            GroupMediaBatchForwardDenial.sizeLimitExceeded
                        ? 'group-batch-forward-size-limit'
                        : 'group-batch-forward-source-unavailable',
                  ),
                  label:
                      sourceDenial ==
                          GroupMediaBatchForwardDenial.sizeLimitExceeded
                      ? AppLocalizations.of(
                          context,
                        )!.media_attachments_too_large_note
                      : AppLocalizations.of(
                          context,
                        )!.direct_batch_forward_source_unavailable,
                  icon: Icons.info_outline,
                )
              else if (matrix != null)
                _buildSummary(context, matrix!),
              _buildTargetHeader(context),
              Expanded(child: _buildTargetList(context)),
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
            key: const ValueKey('group-batch-forward-close'),
            onPressed: isSending ? null : onClose,
            tooltip: l10n.direct_batch_forward_close,
            color: colors.iconPrimary,
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

  Widget _buildSourceStrip(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.backgroundReadableColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
          child: Text(
            l10n.direct_batch_forward_item_count(items.length),
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ),
        SizedBox(
          height: 176,
          child: ListView.builder(
            key: const ValueKey('group-batch-forward-source-list'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
            itemCount: items.length,
            itemBuilder: (context, index) => _buildSourceCard(context, index),
          ),
        ),
      ],
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
    final width = (MediaQuery.sizeOf(context).width - 48).clamp(220.0, 320.0);
    return Semantics(
      key: ValueKey('group-batch-forward-source-$index'),
      container: true,
      label: sourceLabel,
      child: Container(
        width: width,
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
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 72,
                      height: double.infinity,
                      child: Image.file(
                        File(item.resolvedPath),
                        key: ValueKey('group-batch-forward-thumbnail-$index'),
                        fit: BoxFit.cover,
                        cacheWidth: 144,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: colors.surfaceSubtle,
                          child: Icon(Icons.image, color: colors.iconMuted),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: ValueKey('group-batch-forward-caption-$index'),
                      controller: captionControllers[index],
                      enabled: !isSending && !targetsFrozen,
                      minLines: 2,
                      maxLines: 3,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(color: colors.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: l10n.direct_batch_forward_caption_label(
                          index + 1,
                          items.length,
                        ),
                        filled: true,
                        fillColor: colors.inputFill,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
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
    GroupMediaBatchForwardProgress value,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final phase = switch (value.phase) {
      GroupMediaBatchForwardProgressPhase.uploading =>
        l10n.direct_batch_forward_phase_uploading,
      GroupMediaBatchForwardProgressPhase.sending =>
        l10n.direct_batch_forward_phase_sending,
    };
    return _buildLiveRegion(
      context,
      key: const ValueKey('group-batch-forward-progress'),
      label: l10n.direct_batch_forward_progress(
        phase,
        value.completedCellCount,
        value.totalCellCount,
      ),
      icon: Icons.sync,
    );
  }

  Widget _buildSummary(
    BuildContext context,
    GroupMediaBatchForwardMatrix value,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return _buildLiveRegion(
      context,
      key: const ValueKey('group-batch-forward-summary'),
      label: l10n.direct_batch_forward_summary(
        value.sentCount,
        value.queuedCount,
        value.failedCount,
      ),
      icon: value.failedCount == 0 ? Icons.check_circle_outline : Icons.info,
    );
  }

  Widget _buildLiveRegion(
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
          padding: const EdgeInsets.all(10),
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

  Widget _buildTargetHeader(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.share_title_empty,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            l10n.share_target_count(_selectionCount),
            key: const ValueKey('group-batch-forward-selection-count'),
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetList(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.backgroundReadableColors;
    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: colors.iconMuted));
    }
    if (contacts.isEmpty && groups.isEmpty) {
      return Center(
        child: Text(
          l10n.share_no_targets,
          style: TextStyle(color: colors.textMuted),
        ),
      );
    }
    return ListView(
      key: const ValueKey('group-batch-forward-target-list'),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 4),
      children: [
        if (contacts.isNotEmpty) ...[
          _sectionLabel(context, l10n.share_contacts_section),
          for (final contact in contacts) _contactTile(context, contact),
        ],
        if (groups.isNotEmpty) ...[
          _sectionLabel(context, l10n.share_groups_section),
          for (final group in groups) _groupTile(context, group),
        ],
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String label) => Padding(
    padding: const EdgeInsetsDirectional.only(top: 8, bottom: 4),
    child: Text(
      label,
      style: TextStyle(
        color: context.backgroundReadableColors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _contactTile(BuildContext context, ContactModel contact) {
    final selected = selectedContactPeerIds.contains(contact.peerId);
    return _targetTile(
      context,
      key: ValueKey('group-batch-forward-contact-${contact.peerId}'),
      label: contact.username,
      selected: selected,
      leading: RingAvatar(peerId: contact.peerId, size: 40),
      onTap: () => onToggleContact(contact),
    );
  }

  Widget _groupTile(BuildContext context, GroupModel group) {
    final selected = selectedGroupIds.contains(group.id);
    return _targetTile(
      context,
      key: ValueKey('group-batch-forward-group-${group.id}'),
      label: group.name,
      selected: selected,
      leading: const CircleAvatar(child: Icon(Icons.group_outlined)),
      onTap: () => onToggleGroup(group),
    );
  }

  Widget _targetTile(
    BuildContext context, {
    required Key key,
    required String label,
    required bool selected,
    required Widget leading,
    required VoidCallback onTap,
  }) {
    final colors = context.backgroundReadableColors;
    final enabled = !isSending && !targetsFrozen;
    return Semantics(
      key: key,
      container: true,
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: ListTile(
          enabled: enabled,
          contentPadding: EdgeInsets.zero,
          leading: leading,
          title: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary),
          ),
          trailing: Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected ? colors.accent : colors.iconMuted,
          ),
          onTap: enabled ? onTap : null,
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final showRetry = (matrix?.failedCount ?? 0) > 0;
    if (matrix != null && !showRetry) return const SizedBox.shrink();
    final callback = showRetry ? onRetryFailed : onSend;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: colors.surfaceBase,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: FilledButton(
        key: showRetry
            ? const ValueKey('group-batch-forward-retry-failed')
            : const ValueKey('group-batch-forward-send'),
        onPressed: isSending ? null : callback,
        child: Text(
          showRetry
              ? l10n.direct_batch_forward_retry_failed
              : l10n.direct_batch_forward_send,
        ),
      ),
    );
  }
}
