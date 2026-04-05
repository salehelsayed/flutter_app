import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
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
  String get _draftFieldLabel =>
      widget.sharedFilePaths.isNotEmpty ? 'Caption' : 'Message';

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
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  if (widget.sharedFilePaths.isNotEmpty ||
                      (!_showsCaptionField && widget.sharedText != null))
                    _buildPreviewStrip(),
                  if (_showsCaptionField) _buildCaptionField(),
                  _buildSearchField(),
                  Expanded(child: _buildTargetList()),
                  if (_selectionCount > 0) _buildSendButton(),
                ],
              ),
              if (widget.isSending)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: false,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.18),
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final title = _selectionCount > 0
        ? 'Share with ($_selectionCount)'
        : 'Share with...';

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            color: Colors.white,
            onPressed: widget.isSending ? null : widget.onCancel,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewStrip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.08)),
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
                        cacheWidth: 144,
                        cacheHeight: 144,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: const Color.fromRGBO(255, 255, 255, 0.1),
                          child: const Icon(Icons.image, color: Colors.white38),
                        ),
                      )
                    : Container(
                        key: const ValueKey('share-preview-placeholder'),
                        color: const Color.fromRGBO(255, 255, 255, 0.1),
                        child: const Icon(Icons.image, color: Colors.white38),
                      ),
              ),
            ),
            if (widget.sharedFilePaths.length > 1)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '+${widget.sharedFilePaths.length - 1}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
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
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCaptionField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _draftFieldLabel,
            key: const ValueKey('share-caption-label'),
            style: const TextStyle(
              color: Colors.white70,
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
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: _draftFieldLabel,
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
              filled: true,
              fillColor: const Color.fromRGBO(255, 255, 255, 0.06),
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

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        key: const ValueKey('share-search-field'),
        controller: _searchController,
        enabled: !widget.isSending,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.picker_search_all,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
          filled: true,
          fillColor: const Color.fromRGBO(255, 255, 255, 0.06),
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

  Widget _buildTargetList() {
    final contacts = _filteredContacts;
    final groups = _filteredGroups;

    if (contacts.isEmpty && groups.isEmpty && widget.isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
        ),
      );
    }

    if (contacts.isEmpty && groups.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty
              ? 'No contacts or groups yet'
              : 'No matches found',
          style: const TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
    }

    final entries = <_TargetListEntry>[
      if (contacts.isNotEmpty) ...[
        const _SectionHeaderEntry('Contacts'),
        ...contacts.map(_ContactEntry.new),
      ],
      if (groups.isNotEmpty) ...[
        const _SectionHeaderEntry('Groups'),
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
          return _buildSectionHeader(entry.title);
        }
        if (entry is _ContactEntry) {
          return _buildContactRow(entry.contact);
        }
        if (entry is _GroupEntry) {
          return _buildGroupRow(entry.group);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildContactRow(ContactModel contact) {
    final isSelected = widget.selectedContactPeerIds.contains(contact.peerId);
    return ListTile(
      key: ValueKey('share-contact-${contact.peerId}'),
      contentPadding: EdgeInsets.zero,
      enabled: !widget.isSending,
      leading: RingAvatar(peerId: contact.peerId, size: 40),
      title: Text(
        contact.username,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      trailing: _buildSelectionIcon(isSelected),
      onTap: widget.isSending ? null : () => widget.onToggleContact(contact),
    );
  }

  Widget _buildGroupRow(GroupModel group) {
    final isSelected = widget.selectedGroupIds.contains(group.id);
    return ListTile(
      key: ValueKey('share-group-${group.id}'),
      contentPadding: EdgeInsets.zero,
      enabled: !widget.isSending,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: const Color.fromRGBO(78, 205, 196, 0.15),
        child: const Icon(Icons.group, color: Color(0xFF4ECDC4), size: 20),
      ),
      title: Text(
        group.name,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      subtitle: Text(
        group.type == GroupType.announcement ? 'Announcement' : 'Chat',
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: _buildSelectionIcon(isSelected),
      onTap: widget.isSending ? null : () => widget.onToggleGroup(group),
    );
  }

  Widget _buildSelectionIcon(bool isSelected) {
    return Icon(
      isSelected ? Icons.check_circle : Icons.add_circle_outline,
      color: isSelected ? const Color(0xFF64B5F6) : Colors.white38,
    );
  }

  Widget _buildSendButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: GestureDetector(
        onTap: widget.isSending ? null : widget.onSend,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF64B5F6), Color(0xFF42A5F5)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.isSending ? 'Sending...' : 'Send',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
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
