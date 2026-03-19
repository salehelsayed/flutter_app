import 'package:flutter/material.dart';

import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/contact_picker_row.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';

/// Pure UI screen for picking contacts to invite to a group.
///
/// StatefulWidget only because it manages a local search filter. All data
/// and callbacks come from props.
class ContactPickerScreen extends StatefulWidget {
  final List<ContactModel> contacts;
  final bool isInviting;
  final ValueChanged<ContactModel> onToggle;
  final Set<String> selectedPeerIds;
  final VoidCallback? onConfirm;
  final VoidCallback onBack;

  const ContactPickerScreen({
    super.key,
    required this.contacts,
    this.isInviting = false,
    required this.onToggle,
    this.selectedPeerIds = const {},
    this.onConfirm,
    required this.onBack,
  });

  @override
  State<ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<ContactPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
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
    super.dispose();
  }

  List<ContactModel> get _filteredContacts {
    if (_searchQuery.isEmpty) return widget.contacts;
    final query = _searchQuery.toLowerCase();
    return widget.contacts
        .where((c) => c.username.toLowerCase().contains(query))
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
                  _buildSearchField(),
                  Expanded(
                    child: widget.contacts.isEmpty
                        ? _buildEmptyState()
                        : _buildContactList(),
                  ),
                  if (widget.selectedPeerIds.isNotEmpty &&
                      widget.onConfirm != null)
                    _buildConfirmButton(),
                ],
              ),
              if (widget.isInviting)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: false,
                    child: AbsorbPointer(
                      child: Container(
                        color: Colors.black.withOpacity(0.3),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        ),
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
          Text(
            widget.selectedPeerIds.isNotEmpty
                ? 'Add Members (${widget.selectedPeerIds.length})'
                : 'Add Member',
            style: const TextStyle(
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
          hintText: AppLocalizations.of(context)!.picker_search_contacts,
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

  Widget _buildConfirmButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: GestureDetector(
        onTap: widget.onConfirm,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF64B5F6), Color(0xFF42A5F5)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Send Invites',
            textAlign: TextAlign.center,
            style: TextStyle(
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
