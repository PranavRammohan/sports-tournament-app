// errorReporting.js
// Crash/error reporting — previously zero visibility into what breaks for
// real users beyond whatever scrolls past in Render's log viewer. SENTRY_DSN
// is optional (unset locally/in dev), same fail-soft posture as email.js's
// RESEND_API_KEY: nothing here throws or changes behavior for anyone who
// hasn't set it up.
//
// Sentry's own Express error handler only ever sees errors that escape a
// route handler via `throw`/`next(err)` — but every route in this backend
// already catches its own errors and responds with a handled 500 (see
// CLAUDE.md's RouteError/try-catch convention), so almost nothing would
// actually reach it. Retrofitting ~110 call sites across every route file
// to explicitly report would be a much bigger change than "add crash
// reporting" — instead, this wraps `console.error` once, globally: every
// route already calls `console.error('X error:', err)` right before its
// 500 response, so forwarding whichever argument is an Error gets the same
// coverage at a single chokepoint instead of a sprawling diff.
const Sentry = require('@sentry/node');

function initErrorReporting() {
  if (!process.env.SENTRY_DSN) return;

  Sentry.init({ dsn: process.env.SENTRY_DSN, tracesSampleRate: 0.1 });

  const originalConsoleError = console.error.bind(console);
  console.error = (...args) => {
    originalConsoleError(...args);
    const err = args.find((a) => a instanceof Error);
    if (err) Sentry.captureException(err);
  };
}

module.exports = { initErrorReporting, Sentry };
