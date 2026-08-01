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

/// Thrown by [pickProfileImageAsDataUri] when the picked photo is too large
/// to send even after compression — callers should catch this and show a
/// friendly message instead of letting the upload hit the server's body-size
/// limit (see server.js's express.json({limit}) and the PayloadTooLargeError
/// that used to surface instead).
class ProfileImageTooLargeException implements Exception {}

/// Picks a photo from the gallery, downsizes it for an avatar (never
/// rendered above ~88px anywhere in the app), and returns both the raw bytes
/// (for an immediate MemoryImage preview) and the base64 data-URI the
/// backend expects. Returns null if the user cancels the picker.
///
/// `imageQuality`/`maxWidth`/`maxHeight` on ImagePicker are advisory and are
/// silently ignored on some platforms (notably web and a few Android
/// devices), so this still checks the encoded size afterward and throws
/// [ProfileImageTooLargeException] rather than trust compression alone.
Future<({Uint8List bytes, String dataUri})?> pickProfileImageAsDataUri() async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 256,
    maxHeight: 256,
    imageQuality: 60,
  );
  if (picked == null) return null;

  final bytes = await picked.readAsBytes();
  final dataUri = 'data:image/jpeg;base64,${base64Encode(bytes)}';
  if (dataUri.length > 2 * 1024 * 1024) {
    throw ProfileImageTooLargeException();
  }
  return (bytes: bytes, dataUri: dataUri);
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
