// reportRoutes.js
// Report-to-moderator — see migration_player_reports.sql's header for why
// this is "store it + email support" instead of a full admin review-queue.
// Mounted at /api/reports, authMiddleware applies at the app.use() level
// like every other route file in this backend.
const express = require('express');
const router = express.Router();
const pool = require('./db');
const { sendEmail } = require('./email');

const VALID_REASONS = ['harassment', 'inappropriate_behavior', 'no_show', 'other'];
const REASON_LABELS = {
  harassment: 'Harassment',
  inappropriate_behavior: 'Inappropriate behavior',
  no_show: "Didn't show up / no-show",
  other: 'Other',
};
const MAX_DETAILS_LENGTH = 1000;

// ---------- REPORT A PLAYER ----------
router.post('/', async (req, res) => {
  const reporterId = req.userId;
  const { reportedUserId, reason, details } = req.body;
  const reportedId = reportedUserId != null ? parseInt(reportedUserId, 10) : null;

  if (!reportedId || !reason) {
    return res.status(400).json({ error: 'A player and a reason are required.' });
  }
  if (reportedId === reporterId) {
    return res.status(400).json({ error: "You can't report yourself." });
  }
  if (!VALID_REASONS.includes(reason)) {
    return res.status(400).json({ error: 'Invalid reason.' });
  }
  if (details != null && (typeof details !== 'string' || details.length > MAX_DETAILS_LENGTH)) {
    return res.status(400).json({ error: `Details must be ${MAX_DETAILS_LENGTH} characters or fewer.` });
  }

  try {
    const usersResult = await pool.query(
      'SELECT id, username FROM users WHERE id = ANY($1::int[]) AND deleted_at IS NULL',
      [[reporterId, reportedId]]
    );
    const reporter = usersResult.rows.find((u) => u.id === reporterId);
    const reported = usersResult.rows.find((u) => u.id === reportedId);
    if (!reported) {
      return res.status(404).json({ error: 'Player not found.' });
    }

    await pool.query(
      `INSERT INTO player_reports (reporter_id, reported_id, reason, details)
       VALUES ($1, $2, $3, $4)`,
      [reporterId, reportedId, reason, details || null]
    );

    // Best-effort — a failed/unconfigured email never blocks the report
    // itself from being recorded, same fail-soft posture as email.js's
    // other callers.
    await sendEmail({
      to: 'support@playmyset.app',
      subject: `Player report: ${REASON_LABELS[reason]}`,
      text: `${reporter?.username ?? `User #${reporterId}`} reported ${reported.username} (user #${reportedId}).\n\nReason: ${REASON_LABELS[reason]}\n\nDetails: ${details || '(none provided)'}`,
      html: `<p><strong>${reporter?.username ?? `User #${reporterId}`}</strong> reported <strong>${reported.username}</strong> (user #${reportedId}).</p><p><strong>Reason:</strong> ${REASON_LABELS[reason]}</p><p><strong>Details:</strong> ${details ? details.replace(/</g, '&lt;') : '(none provided)'}</p>`,
    });

    res.status(201).json({ message: 'Report submitted.' });
  } catch (err) {
    console.error('Submit report error:', err);
    res.status(500).json({ error: 'Something went wrong submitting the report.' });
  }
});

module.exports = router;
