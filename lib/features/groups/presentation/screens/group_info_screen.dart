import 'package:flutter/material.dart';

import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_member_row.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';

/// Pure UI screen for group info.
///
/// Shows group name, type, description, member list, and action buttons.
class GroupInfoScreen extends StatelessWidget {
  final GroupModel group;
  final List<GroupMember> members;
  final bool isAdmin;
  final String? ownPeerId;
  final VoidCallback onBack;
  final VoidCallback onLeave;
  final ValueChanged<GroupMember>? onRemoveMember;
  final VoidCallback? onAddMember;

  const GroupInfoScreen({
    super.key,
    required this.group,
    required this.members,
    required this.isAdmin,
    this.ownPeerId,
    required this.onBack,
    required this.onLeave,
    this.onRemoveMember,
    this.onAddMember,
  });

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(context),
              // Body
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    const SizedBox(height: 24),
                    // Group info section
                    _buildGroupInfo(),
                    const SizedBox(height: 24),
                    // Members section
                    _buildMembersSection(),
                    const SizedBox(height: 32),
                    // Leave button
                    _buildLeaveButton(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: Colors.white,
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          const Text(
            'Group Info',
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

  Widget _buildGroupInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + type badge
          Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GroupTypeBadge(type: group.type),
            ],
          ),
          if (group.description != null && group.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              group.description!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${members.length} member${members.length == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Members',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.5),
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (isAdmin && onAddMember != null) _buildAddMemberButton(),
        ...members.map(
          (member) => GroupMemberRow(
            member: member,
            isAdmin: isAdmin,
            isSelf: ownPeerId != null && member.peerId == ownPeerId,
            onRemove: isAdmin && onRemoveMember != null
                ? () => onRemoveMember!(member)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildAddMemberButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: onAddMember,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF64B5F6).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF64B5F6).withOpacity(0.15),
              width: 0.5,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_add_outlined,
                size: 20,
                color: Color(0xFF64B5F6),
              ),
              SizedBox(width: 8),
              Text(
                'Add Member',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64B5F6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaveButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onLeave,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.red.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          child: const Text(
            'Leave Group',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
        ),
      ),
    );
  }
}
