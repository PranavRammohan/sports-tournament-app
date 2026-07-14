// ratingEngine.js
// Four different rating engines, one per sport, matching each sport's real-world system.

// ---- Tennis (UTR-style) & Badminton (UBR-style) & Pickleball (DUPR-style) ----
// All three use the same underlying idea: compare actual performance share
// (games/points won) to expected performance share based on rating gap.
// Overperforming expectation raises rating even in a loss; underperforming
// lowers it even in a win.
const CONTINUOUS_CONFIGS = {
  tennis: { min: 1.0, max: 16.5, scaleConstant: 3, kFraction: 0.042, decimals: 1 },
  badminton: { min: 1000, max: 8000, scaleConstant: 800, kFraction: 0.042, decimals: 0 },
  pickleball: { min: 2.0, max: 8.0, scaleConstant: 1.5, kFraction: 0.042, decimals: 1 },
};

function calculateContinuousRatings(sport, player1Rating, player2Rating, player1Units, player2Units) {
  const config = CONTINUOUS_CONFIGS[sport];
  const range = config.max - config.min;
  const K = config.kFraction * range;

  const ratingDiff = player1Rating - player2Rating;
  const expectedShare1 = 1 / (1 + Math.pow(10, -ratingDiff / config.scaleConstant));
  const expectedShare2 = 1 - expectedShare1;

  const totalUnits = player1Units + player2Units;
  const actualShare1 = totalUnits > 0 ? player1Units / totalUnits : 0.5;
  const actualShare2 = 1 - actualShare1;

  const delta1 = actualShare1 - expectedShare1;
  const delta2 = actualShare2 - expectedShare2;

  const change1 = K * delta1;
  const change2 = K * delta2;

  const clamp = (v) => Math.min(config.max, Math.max(config.min, v));
  const round = (v) => (config.decimals === 0 ? Math.round(v) : Math.round(v * 10) / 10);

  return {
    newRating1: round(clamp(player1Rating + change1)),
    newRating2: round(clamp(player2Rating + change2)),
  };
}

// ---- Table Tennis (USATT-style) ----
// Discrete lookup chart: only rating gap + win/loss matter, score margin is ignored.
// Upsets (lower-rated player wins) exchange far more points than expected results.
const USATT_CHART = [
  { max: 12, higherWins: 8, lowerWins: 8 },
  { max: 37, higherWins: 7, lowerWins: 10 },
  { max: 62, higherWins: 6, lowerWins: 13 },
  { max: 87, higherWins: 5, lowerWins: 16 },
  { max: 112, higherWins: 4, lowerWins: 20 },
  { max: 137, higherWins: 3, lowerWins: 25 },
  { max: 162, higherWins: 2, lowerWins: 30 },
  { max: 187, higherWins: 2, lowerWins: 35 },
  { max: 212, higherWins: 1, lowerWins: 40 },
  { max: 237, higherWins: 1, lowerWins: 45 },
  { max: Infinity, higherWins: 0, lowerWins: 50 },
];

function calculateTableTennisRatings(player1Rating, player2Rating, player1Won) {
  const diff = Math.abs(player1Rating - player2Rating);
  const bracket = USATT_CHART.find((b) => diff <= b.max);

  const higherIsPlayer1 = player1Rating >= player2Rating;
  const higherWon = higherIsPlayer1 ? player1Won : !player1Won;

  const pointsExchanged = higherWon ? bracket.higherWins : bracket.lowerWins;

  let change1;
  if (player1Won) {
    change1 = pointsExchanged;
  } else {
    change1 = -pointsExchanged;
  }
  const change2 = -change1;

  // Safety floor: ratings below 100 can only lose a max of 3 points
  const applyFloorRule = (rating, change) => {
    if (rating < 100 && change < 0) {
      return Math.max(change, -3);
    }
    return change;
  };

  const finalChange1 = applyFloorRule(player1Rating, change1);
  const finalChange2 = applyFloorRule(player2Rating, change2);

  return {
    newRating1: Math.max(0, Math.round(player1Rating + finalChange1)),
    newRating2: Math.max(0, Math.round(player2Rating + finalChange2)),
  };
}

// ---- Unified entry point ----
// units = games won (tennis) or points won (badminton/pickleball). Not used for table tennis.
function calculateNewRatings(sport, player1Rating, player2Rating, player1Won, player1Units, player2Units) {
  if (sport === 'table_tennis') {
    return calculateTableTennisRatings(player1Rating, player2Rating, player1Won);
  }
  return calculateContinuousRatings(sport, player1Rating, player2Rating, player1Units, player2Units);
}

module.exports = { calculateNewRatings };