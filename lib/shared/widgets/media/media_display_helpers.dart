const double mediaGridGap = 3.0;
const double mediaGridContainerRadius = 10.0;
const double mediaGridItemRadius = 4.0;

String formatDurationMs(int? ms) {
  if (ms == null || ms <= 0) return '0:00';
  final seconds = (ms ~/ 1000) % 60;
  final minutes = ms ~/ 60000;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
