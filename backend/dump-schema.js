// dump-schema.js
// Regenerates current_schema.sql from a real database connection — tech debt
// cleanup (batch 9). Run via `npm run dump-schema`. Reads the same
// DATABASE_URL / DB_HOST+DB_PORT+DB_USER+DB_PASSWORD+DB_NAME env vars db.js
// already uses, so pointing this at local vs. hosted Postgres works exactly
// like running the app itself does — see the .env setup in CLAUDE.md.
//
// This shells out to the real `pg_dump` CLI (schema-only, no data) rather
// than hand-assembling DDL, so the output is an actual authoritative dump —
// the whole point is to stop this file from silently drifting out of sync
// with migrations applied directly against the live DB.
require('dotenv').config();
const { execFileSync } = require('child_process');
const path = require('path');

const outFile = path.join(__dirname, 'current_schema.sql');

function buildArgs() {
  const args = ['--schema-only', '--no-owner', '--no-privileges'];
  if (process.env.DATABASE_URL) {
    args.push(process.env.DATABASE_URL);
  } else {
    args.push(
      '-h', process.env.DB_HOST || 'localhost',
      '-p', process.env.DB_PORT || '5432',
      '-U', process.env.DB_USER,
      process.env.DB_NAME
    );
  }
  return args;
}

try {
  const output = execFileSync('pg_dump', buildArgs(), {
    encoding: 'utf8',
    env: {
      ...process.env,
      // pg_dump reads PGPASSWORD directly; DB_PASSWORD is this repo's own
      // env var name (see db.js), so bridge it rather than requiring a
      // second copy of the same secret in .env.
      PGPASSWORD: process.env.DB_PASSWORD || process.env.PGPASSWORD,
    },
  });
  require('fs').writeFileSync(outFile, output);
  console.log(`Wrote ${outFile}`);
} catch (err) {
  console.error('pg_dump failed — is the pg_dump CLI installed and on PATH, and does .env point at a reachable database?');
  console.error(err.message);
  process.exit(1);
}
