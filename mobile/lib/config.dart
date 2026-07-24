// config.dart
// Single source of truth for the backend's base URL.
//
// Defaults to the hosted Render backend (production) — this is what runs
// whenever you use a plain `flutter run` or `flutter build apk`, so you never
// accidentally build/test against local data by mistake.
//
// To test against your LOCAL backend instead, pass the override explicitly:
//   flutter run -d chrome --dart-define=API_URL=http://192.168.0.105:3000/api
// (swap in whatever your PC's current local IP is, from `ipconfig`)
//
// This makes which backend you're hitting an explicit, visible choice in the
// command you run, rather than something silently set in this file that's
// easy to forget about.
const String baseApiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://sports-tournament-app-87r1.onrender.com/api',
);
