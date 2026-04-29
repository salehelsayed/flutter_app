import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/contact_picker_row.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

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
  final BackgroundPreference backgroundPreference;

  const ContactPickerScreen({
    super.key,
    required this.contacts,
    this.isInviting = false,
    required this.onToggle,
    this.selectedPeerIds = const {},
    this.onConfirm,
    required this.onBack,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
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
                      _buildSearchField(context),
                      Expanded(
                        child: widget.contacts.isEmpty
                            ? _buildEmptyState(context)
                            : _buildContactList(),
                      ),
                      if (widget.selectedPeerIds.isNotEmpty &&
                          widget.onConfirm != null)
                        _buildConfirmButton(context),
                    ],
                  ),
                  if (widget.isInviting)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: false,
                        child: AbsorbPointer(
                          child: Container(
                            color: readableColors.overlayScrim.withOpacity(
                              readableColors.isLightSurface ? 0.18 : 0.30,
                            ),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: readableColors.iconPrimary,
                              ),
                            ),
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
            widget.selectedPeerIds.isNotEmpty
                ? 'Add Members (${widget.selectedPeerIds.length})'
                : 'Add Member',
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

  Widget _buildConfirmButton(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final start = readableColors.isLightSurface
        ? const Color(0xFF0F5F9C)
        : const Color(0xFF64B5F6);
    final end = readableColors.isLightSurface
        ? const Color(0xFF0B4D82)
        : const Color(0xFF42A5F5);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: GestureDetector(
        onTap: widget.onConfirm,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [start, end]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Send Invites',
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
}
