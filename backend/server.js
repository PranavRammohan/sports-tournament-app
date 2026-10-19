const express = require('express');
const path = require('path');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const { initErrorReporting, Sentry } = require('./errorReporting');
const authRoutes = require('./authRoutes');
const sportsRoutes = require('./sportsRoutes');
const leagueRoutes = require('./leagueRoutes');
const matchRoutes = require('./matchRoutes');
const playoffRoutes = require('./playoffRoutes');
const notificationRoutes = require('./notificationRoutes');
const friendlyRoutes = require('./friendlyRoutes');
const blockRoutes = require('./blockRoutes');
const ladderRoutes = require('./ladderRoutes');
const reportRoutes = require('./reportRoutes');
const authMiddleware = require('./authMiddleware');

initErrorReporting();

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
// Everything else behind authMiddleware had zero rate limiting until now —
// fine while this app's whole user base is a handful of trusted people,
// a real gap once it's public (scraping, abuse, a surprise DB bill).
// Generous enough not to interfere with normal usage (e.g. the unread-
// notification-count poll on every bottom-nav tab switch) while still
// capping anything that isn't.
const generalApiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 300,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please slow down and try again shortly.' },
});
app.use('/api', generalApiLimiter);

app.use('/api/auth', authRateLimiter, authRoutes);
app.use('/api/sports', authMiddleware, sportsRoutes);
app.use('/api/leagues', authMiddleware, leagueRoutes);
app.use('/api/matches', authMiddleware, matchRoutes);
app.use('/api/playoffs', authMiddleware, playoffRoutes);
app.use('/api/notifications', authMiddleware, notificationRoutes);
app.use('/api/friendlies', authMiddleware, friendlyRoutes);
app.use('/api/blocks', authMiddleware, blockRoutes);
app.use('/api/ladder', authMiddleware, ladderRoutes);
app.use('/api/reports', authMiddleware, reportRoutes);

// Safety net for anything that escapes a route's own try/catch (a thrown
// error in middleware, or a route that forgot one) — the console.error
// wrap in errorReporting.js is what actually covers the routes' own
// already-handled errors; this is just the remaining gap.
if (process.env.SENTRY_DSN) {
  Sentry.setupExpressErrorHandler(app);
}

// Render (and most PaaS hosts) assigns its own port via $PORT and expects
// the app to bind to it — a hardcoded port can silently fail to receive
// traffic in production. 3000 stays as the local-dev fallback only.
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));