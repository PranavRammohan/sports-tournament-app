// sports.dart
// Shared per-sport skill-level -> starting rating table, used at signup
// (select_sports_screen.dart) and when adding a sport later
// (add_sport_screen.dart).
const Map<String, Map<String, num>> sportLevels = {
  'Badminton': {
    'beginner': 6000,
    'intermediate': 6500,
    'higher intermediate': 7000,
    'advanced': 7500,
    'pro': 8500,
  },
  'Tennis': {
    'beginner': 2.5,
    'lower intermediate': 4.5,
    'intermediate': 6.5,
    'intermediate advanced': 8.5,
    'advanced': 10.5,
    'pro': 13,
  },
  'Table Tennis': {
    'beginner': 1000,
    'early intermediate': 1400,
    'intermediate': 1600,
    'higher intermediate': 1800,
    'advanced': 2200,
    'pro': 2500,
  },
  'Pickleball': {
    'beginner': 2.5,
    'intermediate': 3.5,
    'mid-intermediate': 4,
    'advanced': 5,
    'pro': 7,
  },
};

String capitalizeLevel(String level) {
  return level
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

// sportLevels above is keyed by the Title Case display name ("Table
// Tennis"), but a rating value in hand is always tagged with the backend's
// snake_case sport key ("table_tennis") — same reverse transform used
// elsewhere in the mobile app (e.g. add_guest_dialog.dart's _sportLabel).
String _titleCaseSport(String sport) => sport
    .split('_')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

// GAP-11 — turns a raw rating number into a human skill-level label, so
// "6500.0" also reads as "Intermediate" somewhere on screen. sportLevels'
// thresholds are already in ascending order, so the band is just the
// highest threshold at or below the given rating. `rating` is `dynamic`
// since it may arrive as a String (see utils.dart's formatRating).
String? ratingBandFor(String sport, dynamic rating) {
  final value = rating is num ? rating : num.tryParse(rating.toString());
  if (value == null) return null;
  final levels = sportLevels[_titleCaseSport(sport)];
  if (levels == null) return null;
  String? band;
  for (final entry in levels.entries) {
    if (value >= entry.value) {
      band = entry.key;
    }
  }
  return band == null ? null : capitalizeLevel(band);
}
