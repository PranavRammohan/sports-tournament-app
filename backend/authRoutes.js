// authRoutes.js
const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const pool = require('./db');
const authMiddleware = require('./authMiddleware');
const { sendPasswordResetEmail } = require('./email');

const JWT_SECRET = process.env.JWT_SECRET;
const SALT_ROUNDS = 10;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// `username` stays as the app-wide display name column — leaderboards,
// schedules, match cards, partner selection, and brackets all read it
// (~250 call sites across mobile+backend) — but it's now auto-derived from
// first/last name at signup/edit instead of being a user-chosen unique
// handle. Exported off the router (like sportsRoutes.js's
// reconstructRatingHistory) so Jest can reach it directly.
function deriveDisplayName(firstName, lastName) {
  return [firstName, lastName]
    .map((part) => (part || '').trim())
    .filter(Boolean)
    .join(' ')
    .replace(/\s+/g, ' ');
}

function normalizeEmail(email) {
  return (email || '').trim().toLowerCase();
}

router.post('/signup', async (req, res) => {
  const {
    firstName,
    lastName,
    email,
    phoneNumber,
    password,
    confirmPassword,
    area,
    gender,
    profilePicUrl,
  } = req.body;

  if (
    !firstName ||
    !lastName ||
    !email ||
    !phoneNumber ||
    !password ||
    !confirmPassword ||
    !area ||
    !gender
  ) {
    return res.status(400).json({ error: 'All fields are required.' });
  }
  const normalizedEmail = normalizeEmail(email);
  if (!EMAIL_RE.test(normalizedEmail)) {
    return res.status(400).json({ error: 'Enter a valid email address.' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters.' });
  }
  if (password !== confirmPassword) {
    return res.status(400).json({ error: 'Passwords do not match.' });
  }
  if (!/^\d{10}$/.test(phoneNumber)) {
    return res.status(400).json({ error: 'Enter a valid 10-digit mobile number.' });
  }
  if (!['M', 'F'].includes(gender)) {
    return res.status(400).json({ error: 'Gender must be M or F.' });
  }
  // username (the app-wide display name, derived below) is written into a
  // varchar(30) column — without this check, a longer combined name fails
  // signup with a raw, unexplained 500 at the INSERT instead of a clear
  // message here.
  if (deriveDisplayName(firstName, lastName).length > 30) {
    return res.status(400).json({ error: 'First and last name combined must be 30 characters or fewer.' });
  }

  try {
    const existing = await pool.query(
      'SELECT id FROM users WHERE LOWER(email) = $1 OR phone_number = $2',
      [normalizedEmail, phoneNumber]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'Email or mobile number already in use.' });
    }

    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
    const username = deriveDisplayName(firstName, lastName);

    const result = await pool.query(
      `INSERT INTO users
         (username, first_name, last_name, email, phone_number, password_hash, location, gender, profile_pic_url)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING id, username, first_name, last_name, email, phone_number, location, gender, profile_pic_url, created_at`,
      [
        username,
        firstName.trim(),
        lastName.trim(),
        normalizedEmail,
        phoneNumber,
        passwordHash,
        area,
        gender,
        profilePicUrl || null,
      ]
    );

    const newUser = result.rows[0];
    const token = jwt.sign({ userId: newUser.id }, JWT_SECRET, { expiresIn: '7d' });

    res.status(201).json({ user: newUser, token });
  } catch (err) {
    console.error('Signup error:', err);
    res.status(500).json({ error: 'Something went wrong during signup.' });
  }
});

router.post('/login', async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'Email/mobile number and password are required.' });
  }

  try {
    // Accepts either an email or a phone number in the same field: existing
    // pre-migration accounts have no email on file, so they sign in with
    // their phone number while new accounts use email.
    const identifier = email.trim();
    const result = await pool.query(
      'SELECT * FROM users WHERE (LOWER(email) = LOWER($1) OR phone_number = $1) AND deleted_at IS NULL',
      [identifier]
    );
    const user = result.rows[0];

    if (!user) {
      return res.status(401).json({ error: 'Invalid email/mobile number or password.' });
    }

    const passwordMatches = await bcrypt.compare(password, user.password_hash);
    if (!passwordMatches) {
      return res.status(401).json({ error: 'Invalid email/mobile number or password.' });
    }

    const token = jwt.sign({ userId: user.id }, JWT_SECRET, { expiresIn: '7d' });

    res.status(200).json({
      user: {
        id: user.id,
        username: user.username,
        firstName: user.first_name,
        lastName: user.last_name,
        email: user.email,
        phoneNumber: user.phone_number,
        location: user.location,
        gender: user.gender,
        profilePicUrl: user.profile_pic_url,
      },
      token,
    });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Something went wrong during login.' });
  }
});

router.patch('/profile', authMiddleware, async (req, res) => {
  const userId = req.userId;
  const { firstName, lastName, email, phoneNumber, area, gender } = req.body;

  if (!firstName || !lastName || !email || !phoneNumber || !area || !gender) {
    return res.status(400).json({ error: 'All fields are required.' });
  }
  const normalizedEmail = normalizeEmail(email);
  if (!EMAIL_RE.test(normalizedEmail)) {
    return res.status(400).json({ error: 'Enter a valid email address.' });
  }
  if (!/^\d{10}$/.test(phoneNumber)) {
    return res.status(400).json({ error: 'Enter a valid 10-digit mobile number.' });
  }
  if (!['M', 'F'].includes(gender)) {
    return res.status(400).json({ error: 'Gender must be M or F.' });
  }
  if (deriveDisplayName(firstName, lastName).length > 30) {
    return res.status(400).json({ error: 'First and last name combined must be 30 characters or fewer.' });
  }

  try {
    const existing = await pool.query(
      'SELECT id FROM users WHERE (LOWER(email) = $1 OR phone_number = $2) AND id != $3',
      [normalizedEmail, phoneNumber, userId]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'That email or mobile number is already taken.' });
    }

    const username = deriveDisplayName(firstName, lastName);

    // profilePicUrl is optional and tri-state:
    // - key absent from the request body -> leave the existing photo untouched
    // - key present with a value -> replace the photo with that value
    // - key present but explicitly null -> clear the photo
    const updatingPhoto = Object.prototype.hasOwnProperty.call(req.body, 'profilePicUrl');
    const { profilePicUrl } = req.body;

    const result = await pool.query(
      updatingPhoto
        ? `UPDATE users SET username = $1, first_name = $2, last_name = $3, email = $4,
             phone_number = $5, location = $6, gender = $7, profile_pic_url = $8
           WHERE id = $9
           RETURNING id, username, first_name, last_name, email, phone_number, location, gender, profile_pic_url`
        : `UPDATE users SET username = $1, first_name = $2, last_name = $3, email = $4,
             phone_number = $5, location = $6, gender = $7
           WHERE id = $8
           RETURNING id, username, first_name, last_name, email, phone_number, location, gender, profile_pic_url`,
      updatingPhoto
        ? [
            username,
            firstName.trim(),
            lastName.trim(),
            normalizedEmail,
            phoneNumber,
            area,
            gender,
            profilePicUrl || null,
            userId,
          ]
        : [
            username,
            firstName.trim(),
            lastName.trim(),
            normalizedEmail,
            phoneNumber,
            area,
            gender,
            userId,
          ]
    );

    res.status(200).json({ user: result.rows[0] });
  } catch (err) {
    console.error('Edit profile error:', err);
    res.status(500).json({ error: 'Something went wrong updating your profile.' });
  }
});

router.patch('/change-password', authMiddleware, async (req, res) => {
  const userId = req.userId;
  const { currentPassword, newPassword } = req.body;

  if (!currentPassword || !newPassword) {
    return res.status(400).json({ error: 'Both current and new password are required.' });
  }
  if (newPassword.length < 6) {
    return res.status(400).json({ error: 'New password must be at least 6 characters.' });
  }

  try {
    const result = await pool.query('SELECT password_hash FROM users WHERE id = $1', [userId]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found.' });
    }

    const matches = await bcrypt.compare(currentPassword, result.rows[0].password_hash);
    if (!matches) {
      return res.status(401).json({ error: 'Current password is incorrect.' });
    }

    const newHash = await bcrypt.hash(newPassword, SALT_ROUNDS);
    await pool.query('UPDATE users SET password_hash = $1 WHERE id = $2', [newHash, userId]);

    res.status(200).json({ message: 'Password updated successfully.' });
  } catch (err) {
    console.error('Change password error:', err);
    res.status(500).json({ error: 'Something went wrong changing your password.' });
  }
});

// ---------- FORGOT PASSWORD — STEP 1: REQUEST A CODE ----------
// Replaces the old "email/username + phone number" self-service reset (see
// migration_password_reset_tokens.sql for why: neither value is actually
// secret in this app — usernames are shown app-wide and phone numbers are
// deliberately shown to scheduled opponents by privacy.js — so that flow let
// any past opponent take over an account). This step only ever confirms an
// email was *sent*, never whether the account exists, so the response can't
// be used to enumerate registered emails.
const RESET_CODE_TTL_MINUTES = 15;
const RESET_CODE_MAX_ATTEMPTS = 5;

function generateResetCode() {
  // 6-digit numeric code, zero-padded (crypto.randomInt is already used
  // elsewhere in this file for the account-deletion lock hash's entropy
  // source, so this stays consistent with that).
  return crypto.randomInt(0, 1000000).toString().padStart(6, '0');
}

router.post('/forgot-password', async (req, res) => {
  const { email } = req.body;

  if (!email) {
    return res.status(400).json({ error: 'Enter your email address.' });
  }

  const normalizedEmail = normalizeEmail(email);
  const genericResponse = {
    message: "If that email is registered, we've sent a reset code to it.",
  };

  try {
    const result = await pool.query(
      'SELECT id FROM users WHERE LOWER(email) = LOWER($1) AND deleted_at IS NULL',
      [normalizedEmail]
    );

    // Same response whether or not the account exists — see comment above.
    if (result.rows.length === 0) {
      return res.status(200).json(genericResponse);
    }

    const userId = result.rows[0].id;
    const code = generateResetCode();
    const codeHash = await bcrypt.hash(code, SALT_ROUNDS);
    const expiresAt = new Date(Date.now() + RESET_CODE_TTL_MINUTES * 60 * 1000);

    await pool.query(
      `INSERT INTO password_reset_tokens (user_id, code_hash, expires_at)
       VALUES ($1, $2, $3)`,
      [userId, codeHash, expiresAt]
    );

    await sendPasswordResetEmail(normalizedEmail, code);

    res.status(200).json(genericResponse);
  } catch (err) {
    console.error('Forgot password error:', err);
    // Still generic — a 500 here would itself leak whether the lookup
    // reached the "account exists" branch versus failing earlier.
    res.status(200).json(genericResponse);
  }
});

// ---------- FORGOT PASSWORD — STEP 2: REDEEM THE CODE ----------
router.post('/reset-password', async (req, res) => {
  const { email, code, newPassword } = req.body;

  if (!email || !code || !newPassword) {
    return res.status(400).json({ error: 'All fields are required.' });
  }
  if (newPassword.length < 6) {
    return res.status(400).json({ error: 'New password must be at least 6 characters.' });
  }

  try {
    const normalizedEmail = normalizeEmail(email);
    const userResult = await pool.query(
      'SELECT id FROM users WHERE LOWER(email) = LOWER($1) AND deleted_at IS NULL',
      [normalizedEmail]
    );
    if (userResult.rows.length === 0) {
      return res.status(400).json({ error: 'Invalid or expired code.' });
    }
    const userId = userResult.rows[0].id;

    // Most recent still-usable token for this user — expired/used/exhausted
    // ones are excluded outright rather than fetched and checked in JS, so
    // a stale row from an earlier request never blocks a fresh one.
    const tokenResult = await pool.query(
      `SELECT * FROM password_reset_tokens
       WHERE user_id = $1 AND used_at IS NULL AND expires_at > NOW() AND attempts < $2
       ORDER BY created_at DESC LIMIT 1`,
      [userId, RESET_CODE_MAX_ATTEMPTS]
    );
    if (tokenResult.rows.length === 0) {
      return res.status(400).json({ error: 'Invalid or expired code. Request a new one.' });
    }
    const token = tokenResult.rows[0];

    const codeMatches = await bcrypt.compare(code, token.code_hash);
    if (!codeMatches) {
      await pool.query(
        'UPDATE password_reset_tokens SET attempts = attempts + 1 WHERE id = $1',
        [token.id]
      );
      return res.status(400).json({ error: 'Invalid or expired code.' });
    }

    const newHash = await bcrypt.hash(newPassword, SALT_ROUNDS);
    await pool.query('UPDATE users SET password_hash = $1 WHERE id = $2', [newHash, userId]);
    await pool.query('UPDATE password_reset_tokens SET used_at = NOW() WHERE id = $1', [token.id]);

    res.status(200).json({ message: 'Password reset successfully. You can now log in.' });
  } catch (err) {
    console.error('Reset password error:', err);
    res.status(500).json({ error: 'Something went wrong resetting your password.' });
  }
});

// ---------- DELETE ACCOUNT (GAP-10) ----------
// A hard DELETE FROM users isn't viable — see migration_account_deletion.sql
// for why — so this anonymizes the row instead: opponents' match history,
// standings, and ratings stay intact, the account just reads "Deleted user"
// from then on and can never log in again.
router.delete('/account', authMiddleware, async (req, res) => {
  const userId = req.userId;
  const { password } = req.body;

  if (!password) {
    return res.status(400).json({ error: 'Enter your password to confirm.' });
  }

  try {
    const userResult = await pool.query('SELECT password_hash FROM users WHERE id = $1', [userId]);
    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'User not found.' });
    }

    // Deleting an account is exactly the kind of action that shouldn't ride
    // on a stale JWT alone — re-verify the password like change-password does.
    const matches = await bcrypt.compare(password, userResult.rows[0].password_hash);
    if (!matches) {
      return res.status(401).json({ error: 'Incorrect password.' });
    }

    // A live tournament can't be left with a tombstone host — they must
    // complete or delete those first.
    const activeLeagues = await pool.query(
      `SELECT name FROM leagues WHERE created_by = $1 AND status = 'active'`,
      [userId]
    );
    if (activeLeagues.rows.length > 0) {
      const names = activeLeagues.rows.map((l) => l.name).join(', ');
      return res.status(409).json({
        error: `Complete or delete these tournaments you host before deleting your account: ${names}.`,
      });
    }

    await pool.withTransaction(async (client) => {
      // A fresh random hash nobody holds — belt-and-suspenders alongside
      // deleted_at, in case any code path still checks a password directly.
      const lockHash = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), SALT_ROUNDS);
      await client.query(
        `UPDATE users
         SET username = 'Deleted user', first_name = NULL, last_name = NULL, email = NULL,
             profile_pic_url = NULL, location = NULL, phone_number = $1,
             password_hash = $2, deleted_at = now()
         WHERE id = $3`,
        [`DELETED${userId}`, lockHash, userId]
      );
      await client.query('DELETE FROM notifications WHERE user_id = $1', [userId]);
    });

    res.status(200).json({ message: 'Account deleted.' });
  } catch (err) {
    console.error('Delete account error:', err);
    res.status(500).json({ error: 'Something went wrong deleting your account.' });
  }
});

router.deriveDisplayName = deriveDisplayName;
router.normalizeEmail = normalizeEmail;

module.exports = router;
