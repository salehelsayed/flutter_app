import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

Future<void> recordGroupMembershipEventWatermark({
  required GroupRepository groupRepo,
  required String groupId,
  DateTime? eventAt,
}) async {
  if (eventAt == null) {
    return;
  }

  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    return;
  }

  final normalizedEventAt = eventAt.toUtc();
  final current = group.lastMembershipEventAt?.toUtc();
  if (current != null && !normalizedEventAt.isAfter(current)) {
    return;
  }

  await groupRepo.updateGroup(
    group.copyWith(lastMembershipEventAt: normalizedEventAt),
  );
}
