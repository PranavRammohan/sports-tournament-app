const { Pool } = require('pg');
require('dotenv').config();

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

module.exports = pool;