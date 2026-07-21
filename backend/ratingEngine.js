// ratingEngine.js
// Rating engines for each sport. Tennis/Badminton/Pickleball use a continuous
// expected-vs-actual performance formula; Table Tennis uses a discrete
// USATT-style lookup chart based on rating differential.

const K_FRACTION = 0.042;

// scaleConstant controls how much a given rating GAP affects the expected
// outcome probability. Recalibrated to match each sport's real practical
// rating range used in this app (not the full theoretical range of the
// underlying real-world system).
const SCALE_CONSTANTS = {
  tennis: 3,        // real range ~2.5–16.5, unchanged
  badminton: 286,   // real range ~6000–8500 (recalibrated from 800, tuned for 1000–8000)
  pickleball: 1.125, // real range ~2.5–7.0 (recalibrated from 1.5, tuned for 2.0–8.0)
};

const MAX_RANGE = {
  tennis: 16.5 - 1.0,
  badminton: 8500 - 6000,
  pickleball: 7.0 - 2.5,
};

function calculateContinuousRating(sport, team1Rating, team2Rating, team1Won, team1Units, team2Units) {
  const scaleConstant = SCALE_CONSTANTS[sport];
  const ratingDiff = team1Rating - team2Rating;
  const expectedShare = 1 / (1 + Math.pow(10, -ratingDiff / scaleConstant));

  const totalUnits = team1Units + team2Units;
  const actualShare = totalUnits > 0 ? team1Units / totalUnits : (team1Won ? 1 : 0);

  const kMax = K_FRACTION * MAX_RANGE[sport];
  const change = kMax * (actualShare - expectedShare);

  return {
    newRating1: team1Rating + change,
    newRating2: team2Rating - change,
  };
}

// Discrete USATT-style chart: only win/loss + rating differential matters,
// score margin is ignored. Larger upsets earn more points, expected results
// earn very little. Differential brackets are wide relative to the app's
// actual level gaps, so big skill-gap matchups naturally hit the max bonus —
// which is realistic, so no change needed here.
function calculateTableTennisRating(team1Rating, team2Rating, team1Won) {
  const diff = Math.abs(team1Rating - team2Rating);
  const favoriteIsTeam1 = team1Rating >= team2Rating;
  const upsetHappened = favoriteIsTeam1 ? !team1Won : team1Won;

  let pointsForUpset;
  if (diff <= 12) pointsForUpset = 8;
  else if (diff <= 37) pointsForUpset = 10;
  else if (diff <= 62) pointsForUpset = 13;
  else if (diff <= 87) pointsForUpset = 16;
  else if (diff <= 112) pointsForUpset = 20;
  else if (diff <= 137) pointsForUpset = 25;
  else if (diff <= 162) pointsForUpset = 31;
  else if (diff <= 187) pointsForUpset = 38;
  else if (diff <= 212) pointsForUpset = 46;
  else if (diff <= 237) pointsForUpset = 50;
  else pointsForUpset = 50;

  const pointsForExpected = Math.max(1, Math.round(pointsForUpset * 0.08));

  const change = upsetHappened ? pointsForUpset : pointsForExpected;

  if (team1Won) {
    return {
      newRating1: team1Rating + change,
      newRating2: team2Rating - change,
    };
  } else {
    return {
      newRating1: team1Rating - change,
      newRating2: team2Rating + change,
    };
  }
}

function calculateNewRatings(sport, team1Rating, team2Rating, team1Won, team1Units, team2Units) {
  if (sport === 'table_tennis') {
    return calculateTableTennisRating(team1Rating, team2Rating, team1Won);
  }
  return calculateContinuousRating(sport, team1Rating, team2Rating, team1Won, team1Units, team2Units);
}

module.exports = { calculateNewRatings };