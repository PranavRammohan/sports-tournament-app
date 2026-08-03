// deep_links.dart
// GAP-16 — handles rallyx://league/<id> and rallyx://join/<code> links, both
// the cold-start initial link and the warm stream while the app is already
// running. Custom scheme only (see the AndroidManifest.xml/Info.plist
// comments for why, not a universal/app link) — works from WhatsApp/SMS,
// not from a plain web browser.
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'screens/league_detail_screen.dart';
import 'screens/join_by_code_screen.dart';

class DeepLinkService {
  static final AppLinks _appLinks = AppLinks();

  // A link that arrived before the user was logged in (or before the
  // navigator was ready) — held here and replayed once login completes,
  // rather than silently dropped.
  static Uri? _pendingUri;

  static Future<void> init() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) await _handleUri(initialUri);
    } catch (err) {
      // Malformed/unsupported initial link — not fatal, just skip it.
    }

    _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri);
    });
  }

  static Future<void> _handleUri(Uri uri) async {
    if (uri.scheme != 'rallyx') return;

    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getString('authToken') != null;
    if (!loggedIn) {
      _pendingUri = uri;
      return;
    }
    _navigate(uri);
  }

  // Called after a successful login/signup — replays a link that arrived
  // while the user was logged out.
  static void consumePendingIfAny() {
    final uri = _pendingUri;
    if (uri == null) return;
    _pendingUri = null;
    _navigate(uri);
  }

  static void _navigate(Uri uri) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    // rallyx://league/<id> -> host='league', pathSegments=['<id>']
    // rallyx://join/<code> -> host='join', pathSegments=['<code>']
    if (uri.host == 'league' && uri.pathSegments.isNotEmpty) {
      final leagueId = int.tryParse(uri.pathSegments.first);
      if (leagueId == null) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => LeagueDetailScreen(leagueId: leagueId),
        ),
      );
    } else if (uri.host == 'join' && uri.pathSegments.isNotEmpty) {
      final code = uri.pathSegments.first;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => JoinByCodeScreen(initialCode: code),
        ),
      );
    }
  }
}
