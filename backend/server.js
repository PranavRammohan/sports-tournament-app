const express = require('express');
const path = require('path');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const authRoutes = require('./authRoutes');
const sportsRoutes = require('./sportsRoutes');
const leagueRoutes = require('./leagueRoutes');
const matchRoutes = require('./matchRoutes');
const playoffRoutes = require('./playoffRoutes');
const notificationRoutes = require('./notificationRoutes');
const friendlyRoutes = require('./friendlyRoutes');
const authMiddleware = require('./authMiddleware');

const app = express();
app.use(cors());

// Static, public policy pages — served at the same hosted URL as the API
// (e.g. /privacy.html, /delete-account.html) so Play Console's "Privacy
// policy" and "Data deletion" listing fields have a real, always-reachable
// URL with no separate hosting to stand up. Plain express.static, not an
// /api/* route, since these are public HTML, not JSON.
app.use(express.static(path.join(__dirname, 'public')));

// Profile photos ride in the JSON body as base64 data-URIs (see authRoutes.js),
// which inflates ~33% over the raw image bytes — express.json()'s 100kb default
// was rejecting most photo uploads before any route ran (PayloadTooLargeError).
app.use(express.json({ limit: '5mb' }));

// Every account-takeover-adjacent path (login, password reset) lives under
// /api/auth, so it's the one place brute-forcing is actually cheap for an
// attacker — a 6-digit reset code or a guessed password is only safe behind
// a request cap, not on its own. Everything else sits behind authMiddleware
// (a JWT an attacker doesn't have), so it doesn't need this same limiter.
const authRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many attempts. Please try again later.' },
});
app.use('/api/auth', authRateLimiter, authRoutes);
app.use('/api/sports', authMiddleware, sportsRoutes);
app.use('/api/leagues', authMiddleware, leagueRoutes);
app.use('/api/matches', authMiddleware, matchRoutes);
app.use('/api/playoffs', authMiddleware, playoffRoutes);
app.use('/api/notifications', authMiddleware, notificationRoutes);
app.use('/api/friendlies', authMiddleware, friendlyRoutes);

app.listen(3000, () => console.log('Server running on port 3000'));