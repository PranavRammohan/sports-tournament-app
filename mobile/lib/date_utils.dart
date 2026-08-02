// date_utils.dart
// Small shared date-formatting helpers for timestamps (as opposed to
// utils.dart's formatDateOnly, which formats league season/registration
// dates). Previously player_profile_screen.dart hand-rolled its own
// near-identical copy of the month-table formatting logic; this both pulls
// that out for reuse by match_history_screen.dart and pending_matches_screen.dart,
// and delegates the actual day/month/year formatting to utils.dart's
// existing formatDateOnly rather than a third copy of the month table, so
// match dates and season dates render in the same "14 Jul 2026" style
// app-wide.
import 'utils.dart' show formatDateOnly;

/// Formats a match/history timestamp using the same style as
/// [formatDateOnly]. Returns '' if `raw` is null or unparseable, so callers
/// can drop it from a ` · `-joined subtitle without leaving a stray
/// separator.
String formatMatchDate(dynamic raw) {
  if (raw == null) return '';
  return formatDateOnly(raw.toString());
}

/// Formats a timestamp relative to now — "just now" / "5m ago" / "3h ago" /
/// "2d ago" — falling back to [formatMatchDate] once it's more than a week
/// old, since "23d ago" is less useful than the actual date at that point.
String formatRelativeTime(dynamic raw) {
  if (raw == null) return '';
  final dt = DateTime.tryParse(raw.toString())?.toLocal();
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.isNegative || diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatMatchDate(raw);
}
