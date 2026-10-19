// push_notifications.dart
// Thin wrapper around firebase_messaging — registers this device's FCM
// token with the backend (see notificationRoutes.js's /device-token) and
// routes cold-start/background notification taps to the right screen. Not
// responsible for whether Firebase itself is configured: main.dart only
// calls PushNotificationService.init() after Firebase.initializeApp() has
// already succeeded, so every method here can assume Firebase is present —
// a missing google-services.json means init() is simply never called, the
// same fail-soft posture as the backend side (push.js) when FCM isn't
// configured there.
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'main.dart';
import 'screens/league_detail_screen.dart';
import 'screens/pending_matches_screen.dart';

class PushNotificationService {
  static bool _listenersSet = false;

  /// Call once at startup, after Firebase.initializeApp() has succeeded.
  /// Wires up tap-through routing and the foreground unread-count refresh,
  /// and — if the user is already logged in — (re)registers this device's
  /// token, since it can rotate between app launches.
  static Future<void> init() async {
    if (_listenersSet) return;
    _listenersSet = true;

    // App already open when the push arrives — no system banner to tap,
    // just keep the bell badge current. A local banner needs
    // flutter_local_notifications, deferred as a later enhancement.
    FirebaseMessaging.onMessage.listen((_) {
      mainShellKey.currentState?.refreshUnreadCount();
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) _handleTap(initialMessage);

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('authToken') != null) {
      await registerDeviceToken();
    }
  }

  /// Call once after a successful login/signup. init() above also calls
  /// this at startup if already logged in, so a token that rotated since
  /// the last launch still gets re-registered.
  static Future<void> registerDeviceToken() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await ApiClient.post('/notifications/device-token', body: {'token': token});
    } catch (err) {
      // Best-effort — no Firebase config, no network, permission denied,
      // etc. must never block login/signup itself.
    }
  }

  // Mirrors notifications_screen.dart's _onTapNotification routing: a
  // league_id goes to that tournament, the friendly/ladder types with no
  // league to link back to go to the Pending tab instead. Uses
  // navigatorKey's NavigatorState directly (push/pushNamed work without a
  // BuildContext of their own) since this fires from a message listener,
  // not a widget.
  static void _handleTap(RemoteMessage message) {
    final navState = navigatorKey.currentState;
    if (navState == null) return;

    final data = message.data;
    final leagueId = data['leagueId'];
    if (leagueId != null) {
      navState.push(
        MaterialPageRoute(
          builder: (_) => LeagueDetailScreen(leagueId: int.parse(leagueId)),
        ),
      );
      return;
    }

    const pendingTypes = {
      'friendly_challenge',
      'friendly_response',
      'ladder_challenge',
      'ladder_response',
      'ladder_report',
      'ladder_confirmed',
    };
    if (pendingTypes.contains(data['type'])) {
      navState.push(
        MaterialPageRoute(builder: (_) => const PendingMatchesScreen()),
      );
    }
  }
}
