import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Pure UI screen for picking one or more share targets.
///
/// StatefulWidget only because it manages local search filtering. All data and
/// interaction callbacks come from props.
class ShareTargetPickerScreen extends StatefulWidget {
  final String? sharedText;
  final List<String> sharedFilePaths;
  final TextEditingController? captionController;
  final List<ContactModel> contacts;
  final List<GroupModel> groups;
  final bool isLoading;
  final bool isSending;
  final Set<String> selectedContactPeerIds;
  final Set<String> selectedGroupIds;
  final ValueChanged<ContactModel> onToggleContact;
  final ValueChanged<GroupModel> onToggleGroup;
  final VoidCallback? onSend;
  final VoidCallback? onCancel;
  final BackgroundPreference backgroundPreference;

  const ShareTargetPickerScreen({
    super.key,
    this.sharedText,
    this.sharedFilePaths = const [],
    this.captionController,
    required this.contacts,
    required this.groups,
    this.isLoading = false,
    this.isSending = false,
    this.selectedContactPeerIds = const {},
    this.selectedGroupIds = const {},
    required this.onToggleContact,
    required this.onToggleGroup,
    this.onSend,
    this.onCancel,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  State<ShareTargetPickerScreen> createState() =>
      _ShareTargetPickerScreenState();
}

class _ShareTargetPickerScreenState extends State<ShareTargetPickerScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showPreviewImage = false;

  bool get _showsCaptionField => widget.captionController != null;
  String _draftFieldLabel(BuildContext context) =>
      widget.sharedFilePaths.isNotEmpty
      ? AppLocalizations.of(context)!.share_caption
      : AppLocalizations.of(context)!.group_message_hint;

  int get _selectionCount =>
      widget.selectedContactPeerIds.length + widget.selectedGroupIds.length;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    if (widget.sharedFilePaths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() => _showPreviewImage = true);
      });
    }
  }

  void _onSearchChanged() {
    setState(() => _searchQuery = _searchController.text);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  List<ContactModel> get _filteredContacts {
    if (_searchQuery.isEmpty) {
      return widget.contacts;
    }
    final query = _searchQuery.toLowerCase();
    return widget.contacts
        .where((contact) => contact.username.toLowerCase().contains(query))
        .toList();
  }

  List<GroupModel> get _filteredGroups {
    if (_searchQuery.isEmpty) {
      return widget.groups;
    }
    final query = _searchQuery.toLowerCase();
    return widget.groups
        .where((group) => group.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      preference: widget.backgroundPreference,
      child: Builder(
        builder: (context) {
          final readableColors = context.backgroundReadableColors;
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      _buildHeader(context),
                      if (widget.sharedFilePaths.isNotEmpty ||
                          (!_showsCaptionField && widget.sharedText != null))
                        _buildPreviewStrip(context),
                      if (_showsCaptionField) _buildCaptionField(context),
                      _buildSearchField(context),
                      Expanded(child: _buildTargetList(context)),
                      if (_selectionCount > 0) _buildSendButton(context),
                    ],
                  ),
                  if (widget.isSending)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: false,
                        child: Container(
                          color: readableColors.overlayScrim.withValues(
                            alpha: readableColors.isLightSurface ? 0.18 : 0.22,
                          ),
                          alignment: Alignment.center,
                          child: CircularProgressIndicator(
                            color: readableColors.iconPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final title = _selectionCount > 0
        ? l10n.share_title_count(_selectionCount)
        : l10n.share_title_empty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            color: readableColors.iconPrimary,
            onPressed: widget.isSending ? null : widget.onCancel,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ).copyWith(color: readableColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewStrip(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final previewPath = widget.sharedFilePaths.isEmpty
        ? null
        : widget.sharedFilePaths.first;
    final isGifPreview =
        previewPath != null && previewPath.toLowerCase().endsWith('.gif');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: readableColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: readableColors.divider),
      ),
      child: Row(
        children: [
          if (widget.sharedFilePaths.isNotEmpty) ...[
            SizedBox(
              width: 48,
              height: 48,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _showPreviewImage
                    ? Image.file(
                        File(widget.sharedFilePaths.first),
                        key: const ValueKey('share-preview-image'),
                        fit: BoxFit.cover,
                        cacheWidth: isGifPreview ? null : 144,
                        cacheHeight: isGifPreview ? null : 144,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: readableColors.surfaceSubtle,
                          child: Icon(
                            Icons.image,
                            color: readableColors.iconMuted,
                          ),
                        ),
                      )
                    : Container(
                        key: const ValueKey('share-preview-placeholder'),
                        color: readableColors.surfaceSubtle,
                        child: Icon(
                          Icons.image,
                          color: readableColors.iconMuted,
                        ),
                      ),
              ),
            ),
            if (widget.sharedFilePaths.length > 1)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '+${widget.sharedFilePaths.length - 1}',
                  style: TextStyle(
                    color: readableColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            const SizedBox(width: 12),
          ],
          if (!_showsCaptionField && widget.sharedText != null)
            Expanded(
              child: Text(
                widget.sharedText!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: detectTextDirection(widget.sharedText!),
                style: TextStyle(
                  color: readableColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCaptionField(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final label = _draftFieldLabel(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            key: const ValueKey('share-caption-label'),
            style: TextStyle(
              color: readableColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('share-caption-field'),
            controller: widget.captionController,
            enabled: !widget.isSending,
            minLines: 1,
            maxLines: 4,
            style: TextStyle(color: readableColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: label,
              hintStyle: TextStyle(
                color: readableColors.placeholderText,
                fontSize: 14,
              ),
              filled: true,
              fillColor: readableColors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        key: const ValueKey('share-search-field'),
        controller: _searchController,
        enabled: !widget.isSending,
        style: TextStyle(color: readableColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.picker_search_all,
          hintStyle: TextStyle(
            color: readableColors.placeholderText,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: readableColors.iconMuted,
            size: 20,
          ),
          filled: true,
          fillColor: readableColors.inputFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildTargetList(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final contacts = _filteredContacts;
    final groups = _filteredGroups;

    if (contacts.isEmpty && groups.isEmpty && widget.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(readableColors.iconMuted),
        ),
      );
    }

    if (contacts.isEmpty && groups.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? l10n.share_no_targets : l10n.share_no_matches,
          style: TextStyle(color: readableColors.textMuted, fontSize: 14),
        ),
      );
    }

    final entries = <_TargetListEntry>[
      if (contacts.isNotEmpty) ...[
        _SectionHeaderEntry(l10n.share_contacts_section),
        ...contacts.map(_ContactEntry.new),
      ],
      if (groups.isNotEmpty) ...[
        _SectionHeaderEntry(l10n.share_groups_section),
        ...groups.map(_GroupEntry.new),
      ],
    ];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is _SectionHeaderEntry) {
          return _buildSectionHeader(context, entry.title);
        }
        if (entry is _ContactEntry) {
          return _buildContactRow(context, entry.contact);
        }
        if (entry is _GroupEntry) {
          return _buildGroupRow(context, entry.group);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final readableColors = context.backgroundReadableColors;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          color: readableColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildContactRow(BuildContext context, ContactModel contact) {
    final readableColors = context.backgroundReadableColors;
    final isSelected = widget.selectedContactPeerIds.contains(contact.peerId);
    return ListTile(
      key: ValueKey('share-contact-${contact.peerId}'),
      contentPadding: EdgeInsets.zero,
      enabled: !widget.isSending,
      leading: RingAvatar(peerId: contact.peerId, size: 40),
      title: Text(
        contact.username,
        style: TextStyle(color: readableColors.textPrimary, fontSize: 15),
      ),
      trailing: _buildSelectionIcon(context, isSelected),
      onTap: widget.isSending ? null : () => widget.onToggleContact(contact),
    );
  }

  Widget _buildGroupRow(BuildContext context, GroupModel group) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final groupAccent = readableColors.isLightSurface
        ? const Color(0xFF16756F)
        : const Color(0xFF4ECDC4);
    final isSelected = widget.selectedGroupIds.contains(group.id);
    return ListTile(
      key: ValueKey('share-group-${group.id}'),
      contentPadding: EdgeInsets.zero,
      enabled: !widget.isSending,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: groupAccent.withValues(alpha: 0.15),
        child: Icon(Icons.group, color: groupAccent, size: 20),
      ),
      title: Text(
        group.name,
        style: TextStyle(color: readableColors.textPrimary, fontSize: 15),
      ),
      subtitle: Text(
        group.type == GroupType.announcement
            ? l10n.share_group_type_announcement
            : l10n.share_group_type_chat,
        style: TextStyle(color: readableColors.textMuted, fontSize: 12),
      ),
      trailing: _buildSelectionIcon(context, isSelected),
      onTap: widget.isSending ? null : () => widget.onToggleGroup(group),
    );
  }

  Widget _buildSelectionIcon(BuildContext context, bool isSelected) {
    final readableColors = context.backgroundReadableColors;
    final selectedColor = _blueAccent(readableColors);
    return Icon(
      isSelected ? Icons.check_circle : Icons.add_circle_outline,
      color: isSelected ? selectedColor : readableColors.iconMuted,
    );
  }

  Widget _buildSendButton(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final start = _blueAccent(readableColors);
    final end = readableColors.isLightSurface
        ? const Color(0xFF0B4D82)
        : const Color(0xFF42A5F5);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: GestureDetector(
        onTap: widget.isSending ? null : widget.onSend,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [start, end]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.isSending ? l10n.share_sending : l10n.share_send,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: readableColors.isLightSurface
                  ? Colors.white
                  : Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Color _blueAccent(BackgroundReadableColors readableColors) {
    return readableColors.isLightSurface
        ? const Color(0xFF0F5F9C)
        : const Color(0xFF64B5F6);
  }
}

sealed class _TargetListEntry {
  const _TargetListEntry();
}

final class _SectionHeaderEntry extends _TargetListEntry {
  final String title;

  const _SectionHeaderEntry(this.title);
}

final class _ContactEntry extends _TargetListEntry {
  final ContactModel contact;

  const _ContactEntry(this.contact);
}

final class _GroupEntry extends _TargetListEntry {
  final GroupModel group;

  const _GroupEntry(this.group);
}
