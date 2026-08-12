// cities.dart
// Cities a user/tournament can be based in. Bangalore was the only city
// this app supported until now (see areas.dart's header comment); this
// list is the first step of multi-city support — picking a city here
// determines which area list `areasByCity` (areas.dart) offers next.
//
// Adding a new city later is two edits, both additive: one more entry
// here, and one more entry in areas.dart's `areasByCity` map.
const List<String> indianCities = [
  'Bangalore',
  'Mumbai',
  'Delhi NCR',
  'Hyderabad',
  'Chennai',
  'Kolkata',
  'Pune',
  'Ahmedabad',
  'Jaipur',
];
