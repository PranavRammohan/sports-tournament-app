// authRoutes.js
const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const pool = require('./db');
const authMiddleware = require('./authMiddleware');

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
    city,
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
         (username, first_name, last_name, email, phone_number, password_hash, city, location, gender, profile_pic_url)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       RETURNING id, username, first_name, last_name, email, phone_number, city, location, gender, profile_pic_url, created_at`,
      [
        username,
        firstName.trim(),
        lastName.trim(),
        normalizedEmail,
        phoneNumber,
        passwordHash,
        city || 'Bangalore',
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
      'SELECT * FROM users WHERE LOWER(email) = LOWER($1) OR phone_number = $1',
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
        city: user.city,
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
  const { firstName, lastName, email, phoneNumber, city, area, gender } = req.body;

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
             phone_number = $5, city = $6, location = $7, gender = $8, profile_pic_url = $9
           WHERE id = $10
           RETURNING id, username, first_name, last_name, email, phone_number, city, location, gender, profile_pic_url`
        : `UPDATE users SET username = $1, first_name = $2, last_name = $3, email = $4,
             phone_number = $5, city = $6, location = $7, gender = $8
           WHERE id = $9
           RETURNING id, username, first_name, last_name, email, phone_number, city, location, gender, profile_pic_url`,
      updatingPhoto
        ? [
            username,
            firstName.trim(),
            lastName.trim(),
            normalizedEmail,
            phoneNumber,
            city || 'Bangalore',
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
            city || 'Bangalore',
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

router.post('/forgot-password', async (req, res) => {
  const { email, phoneNumber, newPassword } = req.body;

  if (!email || !phoneNumber || !newPassword) {
    return res.status(400).json({ error: 'All fields are required.' });
  }
  if (newPassword.length < 6) {
    return res.status(400).json({ error: 'New password must be at least 6 characters.' });
  }

  try {
    // Accepts email (new accounts) or username (legacy accounts that never
    // set an email) in the same field, always paired with the phone number
    // on file — same email-or-legacy-identifier split as /login.
    const identifier = email.trim();
    const result = await pool.query(
      `SELECT id FROM users
       WHERE (LOWER(email) = LOWER($1) OR username ILIKE $1) AND phone_number = $2`,
      [identifier, phoneNumber]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Email and mobile number do not match any account.' });
    }

    const userId = result.rows[0].id;
    const newHash = await bcrypt.hash(newPassword, SALT_ROUNDS);
    await pool.query('UPDATE users SET password_hash = $1 WHERE id = $2', [newHash, userId]);

    res.status(200).json({ message: 'Password reset successfully. You can now log in.' });
  } catch (err) {
    console.error('Forgot password error:', err);
    res.status(500).json({ error: 'Something went wrong resetting your password.' });
  }
});

router.deriveDisplayName = deriveDisplayName;
router.normalizeEmail = normalizeEmail;

module.exports = router;
