const int groupKeyReplayRetentionGenerationCount = 8;

int minRetainedGroupKeyGeneration(int latestGeneration) {
  final minGeneration =
      latestGeneration - groupKeyReplayRetentionGenerationCount + 1;
  // Initial group keys are generation 0 in current app flows.
  return minGeneration < 0 ? 0 : minGeneration;
}
