import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/contact_picker_row.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_name_panel.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Pure UI screen for the new group creation flow.
///
/// Displays a contact list for selection. When contacts are selected, a
/// bottom [GroupNamePanel] slides up with overlapping avatars, optional
/// group name input, and a "Start group chat" button.
///
/// StatefulWidget only because it manages a local search filter and
/// the group name TextEditingController.
class CreateGroupPickerScreen extends StatefulWidget {
  final List<ContactModel> contacts;
  final Set<String> selectedPeerIds;
  final ValueChanged<ContactModel> onToggle;
  final ValueChanged<String?> onStartGroup;
  final VoidCallback onBack;
  final bool isCreating;
  final bool isLoadingContacts;
  final String? loadErrorMessage;
  final VoidCallback? onRetryLoadContacts;
  final BackgroundPreference backgroundPreference;

  const CreateGroupPickerScreen({
    super.key,
    required this.contacts,
    required this.selectedPeerIds,
    required this.onToggle,
    required this.onStartGroup,
    required this.onBack,
    this.isCreating = false,
    this.isLoadingContacts = false,
    this.loadErrorMessage,
    this.onRetryLoadContacts,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  State<CreateGroupPickerScreen> createState() =>
      _CreateGroupPickerScreenState();
}

class _CreateGroupPickerScreenState extends State<CreateGroupPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  List<ContactModel> get _filteredContacts {
    if (_searchQuery.isEmpty) return widget.contacts;
    final query = _searchQuery.toLowerCase();
    return widget.contacts
        .where((c) => c.username.toLowerCase().contains(query))
        .toList();
  }

  List<ContactModel> get _selectedContacts {
    return widget.contacts
        .where((c) => widget.selectedPeerIds.contains(c.peerId))
        .toList();
  }

  bool get _hasSelection => widget.selectedPeerIds.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      preference: widget.backgroundPreference,
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      _buildHeader(context),
                      _buildSearchField(context),
                      Expanded(
                        child: widget.contacts.isNotEmpty
                            ? _buildContactList()
                            : widget.isLoadingContacts
                            ? _buildLoadingState(context)
                            : widget.loadErrorMessage != null
                            ? _buildLoadErrorState(context)
                            : _buildEmptyState(context),
                      ),
                    ],
                  ),
                  if (_hasSelection)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: GroupNamePanel(
                        selectedContacts: _selectedContacts,
                        nameController: _nameController,
                        onStartGroup: () {
                          final name = _nameController.text.trim();
                          widget.onStartGroup(name.isEmpty ? null : name);
                        },
                        isCreating: widget.isCreating,
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: readableColors.iconPrimary,
            onPressed: widget.onBack,
          ),
          const SizedBox(width: 4),
          Text(
            'New Group',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: readableColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: readableColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.picker_search_contacts,
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
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Center(
      child: SizedBox(
        key: const ValueKey('create-group-contact-loading'),
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: readableColors.iconMuted,
        ),
      ),
    );
  }

  Widget _buildLoadErrorState(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: readableColors.iconMuted,
            ),
            const SizedBox(height: 16),
            Text(
              widget.loadErrorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: readableColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: readableColors.disabledForeground,
              ),
            ),
            if (widget.onRetryLoadContacts != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: widget.onRetryLoadContacts,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_search_outlined,
            size: 64,
            color: readableColors.iconMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'No contacts available',
            style: TextStyle(fontSize: 16, color: readableColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildContactList() {
    final contacts = _filteredContacts;
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(bottom: _hasSelection ? 240 : 0),
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final contact = contacts[index];
        return ContactPickerRow(
          contact: contact,
          isSelected: widget.selectedPeerIds.contains(contact.peerId),
          onTap: () => widget.onToggle(contact),
        );
      },
    );
  }
}
