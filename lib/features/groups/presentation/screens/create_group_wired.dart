import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/create_group_screen.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Wired widget connecting CreateGroupScreen to business logic.
class CreateGroupWired extends StatefulWidget {
  final Bridge bridge;
  final GroupRepository groupRepo;
  final IdentityRepository identityRepo;

  const CreateGroupWired({
    super.key,
    required this.bridge,
    required this.groupRepo,
    required this.identityRepo,
  });

  @override
  State<CreateGroupWired> createState() => _CreateGroupWiredState();
}

class _CreateGroupWiredState extends State<CreateGroupWired> {
  bool _isCreating = false;

  Future<void> _onCreate(
    String name,
    GroupType type,
    String? description,
  ) async {
    if (_isCreating) return;

    setState(() => _isCreating = true);

    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null) {
        throw StateError('No identity found');
      }

      await createGroup(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        name: name,
        type: type,
        creatorPeerId: identity.peerId,
        creatorPublicKey: identity.publicKey,
        creatorMlKemPublicKey: identity.mlKemPublicKey ?? '',
        description: description,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CREATE_GROUP_FL_ERROR',
        details: {'error': e.toString()},
      );
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  void _onBack() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CreateGroupScreen(
      isCreating: _isCreating,
      onCreate: _onCreate,
      onBack: _onBack,
    );
  }
}
