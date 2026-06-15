import 'package:intl/intl.dart' as intl;

/// Formats a message timestamp into a WhatsApp-style day-separator label.
///
/// Tiers, all computed on the LOCAL calendar day relative to [now]:
/// - same calendar day as [now]            -> [todayLabel]
/// - the calendar day before [now]         -> [yesterdayLabel]
/// - older, same calendar year as [now]    -> e.g. `Wed 13. May`
/// - older, an earlier year than [now]     -> e.g. `Wed 13. May 2025`
///
/// [todayLabel] and [yesterdayLabel] are injected so callers pass localized
/// strings (e.g. `AppLocalizations.of(context)!.date_today`). [now] is injected
/// so the tiering is deterministic and unit-testable.
///
/// The weekday and month NAMES are localized via [locale]; the field ORDER is
/// fixed (`EEE d. MMM`) by product decision so every locale renders the same
/// WhatsApp-style arrangement. Note that the punctuation is locale-defined: a
/// locale whose abbreviated weekday self-terminates with a period (e.g. German
/// "Mi.") renders as "Mi. 13. Mai" — the order is uniform, the dots are not.
String formatDaySeparatorLabel(
  DateTime timestamp, {
  required DateTime now,
  required String todayLabel,
  required String yesterdayLabel,
  String? locale,
}) {
  final local = timestamp.toLocal();
  final nowLocal = now.toLocal();

  // Calendar-day anchors at local midnight. Built with the DateTime(y, m, d)
  // constructor (never by adding a Duration) so month/year rollover is handled
  // and there is no daylight-saving drift.
  final messageDay = DateTime(local.year, local.month, local.day);
  final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  final yesterday = DateTime(today.year, today.month, today.day - 1);

  if (messageDay == today) return todayLabel;
  if (messageDay == yesterday) return yesterdayLabel;

  // Older than yesterday: weekday + day + month, plus the year only when the
  // message is from an earlier calendar year.
  final pattern = messageDay.year == today.year ? 'EEE d. MMM' : 'EEE d. MMM y';
  try {
    return intl.DateFormat(pattern, locale).format(local);
  } catch (_) {
    // Some test/runtime environments do not have the requested locale data
    // initialized; fall back to the default locale with the same pattern.
    return intl.DateFormat(pattern).format(local);
  }
}
