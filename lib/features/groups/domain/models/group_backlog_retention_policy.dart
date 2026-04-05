const int groupBacklogRetentionWindowDays = 7;

const Duration groupBacklogRetentionWindow = Duration(
  days: groupBacklogRetentionWindowDays,
);

DateTime groupBacklogRetentionCutoff(DateTime now) =>
    now.toUtc().subtract(groupBacklogRetentionWindow);
