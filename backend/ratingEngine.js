// ratingEngine.js
const MIN_RATING = 1.0;
const MAX_RATING = 16.5;
const K_FACTOR = 0.5;

function clamp(value) {
  return Math.min(MAX_RATING, Math.max(MIN_RATING, value));
}

function calculateNewRatings(player1Rating, player2Rating, player1Won, player1Units, player2Units) {
  const expected1 = 1 / (1 + Math.pow(10, (player2Rating - player1Rating) / 6));
  const expected2 = 1 - expected1;

  const actual1 = player1Won ? 1 : 0;
  const actual2 = player1Won ? 0 : 1;

  const baseChange1 = K_FACTOR * (actual1 - expected1);
  const baseChange2 = K_FACTOR * (actual2 - expected2);

  const totalUnits = player1Units + player2Units;
  const unitDiff = Math.abs(player1Units - player2Units);
  const marginRatio = totalUnits > 0 ? unitDiff / totalUnits : 0;
  const marginMultiplier = 1 + Math.min(marginRatio, 1) * 0.5;

  const finalChange1 = baseChange1 * marginMultiplier;
  const finalChange2 = baseChange2 * marginMultiplier;

  const newRating1 = clamp(player1Rating + finalChange1);
  const newRating2 = clamp(player2Rating + finalChange2);

  return {
    newRating1: Math.round(newRating1 * 10) / 10,
    newRating2: Math.round(newRating2 * 10) / 10,
  };
}

module.exports = { calculateNewRatings, MIN_RATING, MAX_RATING };