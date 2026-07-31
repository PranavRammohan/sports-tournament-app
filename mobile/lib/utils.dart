// utils.dart
// Shared helper functions used across multiple screens.
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone dialer pre-filled with [phone]. Silently does nothing if
/// the device has no way to handle a tel: link (e.g. some desktop/web
/// builds) — callers show a phone number either way, this is a convenience
/// on top of it, not the only way to see the number.
Future<void> launchPhoneCall(String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  }
}

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
