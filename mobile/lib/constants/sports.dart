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
