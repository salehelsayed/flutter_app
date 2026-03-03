import 'package:flutter/material.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/contact_picker_row.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_name_panel.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';

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

  const CreateGroupPickerScreen({
    super.key,
    required this.contacts,
    required this.selectedPeerIds,
    required this.onToggle,
    required this.onStartGroup,
    required this.onBack,
    this.isCreating = false,
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
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  _buildSearchField(),
                  Expanded(
                    child: widget.contacts.isEmpty
                        ? _buildEmptyState()
                        : _buildContactList(),
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
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: Colors.white,
            onPressed: widget.onBack,
          ),
          const SizedBox(width: 4),
          const Text(
            'New Group',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search contacts...',
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: Colors.white.withOpacity(0.35),
            size: 20,
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_search_outlined,
            size: 64,
            color: Colors.white.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No contacts available',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.4),
            ),
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
