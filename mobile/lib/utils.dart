// utils.dart
// Shared helper functions used across multiple screens.
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
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

/// Thrown by [pickImageAsDataUri] when the picked photo is too large to send
/// even after compression — callers should catch this and show a friendly
/// message instead of letting the upload hit the server's body-size limit
/// (see server.js's express.json({limit}) and the PayloadTooLargeError that
/// used to surface instead). Kept under its original name — it predates
/// match photos (GAP-17) and every existing call site already catches it by
/// this name.
class ProfileImageTooLargeException implements Exception {}

/// Picks a photo from the gallery and returns both the raw bytes (for an
/// immediate MemoryImage preview) and the base64 data-URI the backend
/// expects. Returns null if the user cancels the picker.
///
/// `imageQuality`/`maxWidth`/`maxHeight` on ImagePicker are advisory and are
/// silently ignored on some platforms (notably web and a few Android
/// devices), so this still checks the encoded size afterward and throws
/// [ProfileImageTooLargeException] rather than trust compression alone.
/// `maxSizeBytes` scales with the use case — an avatar (never rendered above
/// ~88px anywhere) can stay tiny; a match scorecard photo needs more room.
Future<({Uint8List bytes, String dataUri})?> pickImageAsDataUri({
  int maxWidth = 256,
  int maxHeight = 256,
  int imageQuality = 60,
  int maxSizeBytes = 2 * 1024 * 1024,
}) async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: maxWidth.toDouble(),
    maxHeight: maxHeight.toDouble(),
    imageQuality: imageQuality,
  );
  if (picked == null) return null;

  final bytes = await picked.readAsBytes();
  final dataUri = 'data:image/jpeg;base64,${base64Encode(bytes)}';
  if (dataUri.length > maxSizeBytes) {
    throw ProfileImageTooLargeException();
  }
  return (bytes: bytes, dataUri: dataUri);
}

/// Avatar-sized picker — thin wrapper over [pickImageAsDataUri] with the
/// defaults every existing avatar call site already relied on.
Future<({Uint8List bytes, String dataUri})?> pickProfileImageAsDataUri() {
  return pickImageAsDataUri();
}

/// GAP-11 — every rating render site used to just interpolate the raw JSON
/// value, so a numeric(6,2) column showed up as "6500.0" or "3.50". Badminton
/// and table tennis ratings are always whole numbers in practice; tennis and
/// pickleball carry one decimal of real precision.
///
/// `rating` is `dynamic` because Postgres numeric columns arrive over JSON
/// as strings (only bigint gets coerced server-side — see db.js) — accepting
/// either a String or a num means callers don't each have to parse first.
String formatRating(String sport, dynamic rating) {
  final value = rating is num ? rating : num.tryParse(rating.toString());
  if (value == null) return '${rating ?? ''}';
  if (sport == 'badminton' || sport == 'table_tennis') {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
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
