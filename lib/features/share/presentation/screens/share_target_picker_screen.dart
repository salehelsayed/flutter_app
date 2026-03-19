import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';

/// Pure UI screen for picking a share target (contact or group).
///
/// Shows a preview of the shared content, a search field, and lists of
/// contacts and groups to share with. All data and callbacks from props.
class ShareTargetPickerScreen extends StatefulWidget {
  final String? sharedText;
  final List<String> sharedFilePaths;
  final List<ContactModel> contacts;
  final List<GroupModel> groups;
  final bool isLoading;
  final ValueChanged<ContactModel> onContactSelected;
  final ValueChanged<GroupModel> onGroupSelected;
  final VoidCallback onCancel;

  const ShareTargetPickerScreen({
    super.key,
    this.sharedText,
    this.sharedFilePaths = const [],
    required this.contacts,
    required this.groups,
    this.isLoading = false,
    required this.onContactSelected,
    required this.onGroupSelected,
    required this.onCancel,
  });

  @override
  State<ShareTargetPickerScreen> createState() =>
      _ShareTargetPickerScreenState();
}

class _ShareTargetPickerScreenState extends State<ShareTargetPickerScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
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
    if (_searchQuery.isEmpty) return widget.contacts;
    final query = _searchQuery.toLowerCase();
    return widget.contacts
        .where((c) => c.username.toLowerCase().contains(query))
        .toList();
  }

  List<GroupModel> get _filteredGroups {
    if (_searchQuery.isEmpty) return widget.groups;
    final query = _searchQuery.toLowerCase();
    return widget.groups
        .where((g) => g.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              if (widget.sharedText != null ||
                  widget.sharedFilePaths.isNotEmpty)
                _buildPreviewStrip(),
              _buildSearchField(),
              Expanded(child: _buildTargetList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: widget.onCancel,
          ),
          const SizedBox(width: 8),
          const Text(
            'Share with...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
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
                child: Image.file(
                  File(widget.sharedFilePaths.first),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: const Color.fromRGBO(255, 255, 255, 0.1),
                    child: const Icon(Icons.image, color: Colors.white38),
                  ),
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
          if (widget.sharedText != null)
            Expanded(
              child: Text(
                widget.sharedText!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
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
        controller: _searchController,
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

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (contacts.isNotEmpty) ...[
          _buildSectionHeader('Contacts'),
          ...contacts.map(_buildContactRow),
        ],
        if (groups.isNotEmpty) ...[
          _buildSectionHeader('Groups'),
          ...groups.map(_buildGroupRow),
        ],
      ],
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
    return ListTile(
      key: ValueKey('share-contact-${contact.peerId}'),
      contentPadding: EdgeInsets.zero,
      leading: RingAvatar(peerId: contact.peerId, size: 40),
      title: Text(
        contact.username,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      onTap: () => widget.onContactSelected(contact),
    );
  }

  Widget _buildGroupRow(GroupModel group) {
    return ListTile(
      key: ValueKey('share-group-${group.id}'),
      contentPadding: EdgeInsets.zero,
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
      onTap: () => widget.onGroupSelected(group),
    );
  }
}
