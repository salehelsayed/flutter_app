import '../models/group_thread_summary.dart';

abstract class GroupThreadSummaryRepository {
  Future<GroupThreadSummary> getGroupThreadSummary(String groupId);

  Future<Map<String, GroupThreadSummary>> getGroupThreadSummaries(
    Iterable<String> groupIds,
  );
}
