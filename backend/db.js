const { Pool, types } = require('pg');
require('dotenv').config();

// node-postgres parses BIGINT (OID 20) as a JS string by default, to avoid
// silently losing precision for values beyond Number.MAX_SAFE_INTEGER.
// SUM(...)/COUNT(...) over an integer column returns bigint in Postgres, so
// every aggregated wins/losses/points/matches_played value in this app
// (league standings, head-to-head records, etc.) comes back as a string
// unless this is overridden — which crashes any mobile code expecting a
// number (e.g. a widget typed to take an int). Nothing in this app deals in
// counts anywhere near 2^53, so parsing bigint as a plain JS number is safe.
types.setTypeParser(20, (value) => parseInt(value, 10));

// Prefer a single connection string (DATABASE_URL) when present — this is
// how Render/Neon/most hosts provide database credentials. Falls back to
// the individual DB_HOST/DB_USER/etc. variables for local development,
// so nothing changes for your local setup.
const pool = process.env.DATABASE_URL
  ? new Pool({
      connectionString: process.env.DATABASE_URL,
      // Neon (and most managed Postgres hosts) require SSL. rejectUnauthorized:
      // false is the standard setting for these hosts' self-signed-style certs —
      // it still encrypts the connection, just doesn't validate against a
      // public CA chain the way a browser would for a website.
      ssl: { rejectUnauthorized: false },
    })
  : new Pool({
      host: process.env.DB_HOST || 'localhost',
      port: process.env.DB_PORT || 5432,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME,
    });

// Runs `fn` inside a single BEGIN/COMMIT transaction on one dedicated
// connection, rolling back on any thrown error. `fn` receives that
// connection (a pg PoolClient — same `.query()` shape as `pool` itself) and
// MUST use it for every query in the sequence; a query issued against `pool`
// directly instead would run on a different connection and fall outside the
// transaction. Used by routes that apply/reverse rating changes together
// with other writes (points, schedule rows) that all need to succeed or fail
// as one unit — see matchRoutes.js/playoffRoutes.js/leagueRoutes.js.
async function withTransaction(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// Thrown by route handlers from inside a withTransaction callback to signal
// a specific HTTP status + user-facing message, since an early `return
// res.status(...).json(...)` inside the callback would leave the outer
// function to send a second response after the transaction resolves.
// Route catch blocks check for this and translate it back into the response
// that would otherwise have been returned directly.
class RouteError extends Error {
  constructor(statusCode, message) {
    super(message);
    this.statusCode = statusCode;
  }
}

pool.withTransaction = withTransaction;
pool.RouteError = RouteError;

module.exports = pool;