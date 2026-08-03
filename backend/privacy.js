// privacy.js
// A plain (non-router) module for redacting contact info out of fixture rows
// before they leave the server — GAP-09 from the codebase audit. Same kind of
// deliberate exception to "route files duplicate small helpers instead of
// sharing a module" as notifications.js/scheduling.js/authorization.js: a
// genuinely new cross-cutting concern (every schedule endpoint needs the same
// redaction), not two files re-implementing the same narrow check.
//
// Phone numbers exist so a player can arrange their own match with their own
// opponent — not so any league member can page through the whole roster's
// phone book. `GET /:id/schedule` and `GET /:id/groups/:groupId/schedule`
// both return every fixture in scope, so without this a member of a
// 60-player league sees all 60 phone numbers, not just their own opponents'.
function redactFixturePhones(rows, userId) {
  return rows.map((row) => {
    const involvesMe =
      row.player1_id === userId ||
      row.player1_partner_id === userId ||
      row.player2_id === userId ||
      row.player2_partner_id === userId;
    if (involvesMe) return row;
    const redacted = { ...row };
    delete redacted.player1_phone;
    delete redacted.player1_partner_phone;
    delete redacted.player2_phone;
    delete redacted.player2_partner_phone;
    return redacted;
  });
}

// Same idea as redactFixturePhones, but for endpoints (like GET
// /matches/pending) where every row already involves the requester by
// construction — the row-level redaction above would be a no-op there, yet
// the requester's own phone and their partner's phone are still returned
// needlessly (a player already knows their own number, and reaches their own
// partner some other way). Only the opponent side's numbers are ever
// actually useful on that screen.
function redactOwnSidePhones(rows, userId) {
  return rows.map((row) => {
    const redacted = { ...row };
    const onSide1 = row.player1_id === userId || row.player1_partner_id === userId;
    const onSide2 = row.player2_id === userId || row.player2_partner_id === userId;
    if (onSide1) {
      delete redacted.player1_phone;
      delete redacted.player1_partner_phone;
    }
    if (onSide2) {
      delete redacted.player2_phone;
      delete redacted.player2_partner_phone;
    }
    return redacted;
  });
}

module.exports = { redactFixturePhones, redactOwnSidePhones };
