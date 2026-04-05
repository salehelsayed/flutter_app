import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

Map<String, dynamic> buildGroupConfigPayload(
  GroupModel group,
  List<GroupMember> members,
) {
  return {
    'name': group.name,
    'groupType': group.type.toValue(),
    'description': group.description,
    'avatarBlobId': group.avatarBlobId,
    'avatarMime': group.avatarMime,
    'metadataUpdatedAt': group.lastMetadataEventAt?.toUtc().toIso8601String(),
    'members': members
        .map(
          (member) => {
            'peerId': member.peerId,
            'username': member.username,
            'role': member.role.toValue(),
            'publicKey': member.publicKey,
            if (member.mlKemPublicKey != null)
              'mlKemPublicKey': member.mlKemPublicKey,
          },
        )
        .toList(),
    'createdBy': group.createdBy,
    'createdAt': group.createdAt.toUtc().toIso8601String(),
  };
}
