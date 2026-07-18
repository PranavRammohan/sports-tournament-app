// utils.dart
// Shared helper functions used across multiple screens.

/// Formats an ISO date string like "2026-07-14T18:30:00.000Z" into "14 Jul 2026",
/// dropping the time portion entirely.
String formatDateOnly(String isoDate) {
  try {
    final date = DateTime.parse(isoDate);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  } catch (err) {
    return isoDate; // fall back to raw string if parsing fails
  }
}
