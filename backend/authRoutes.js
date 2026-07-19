// authRoutes.js
const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const pool = require('./db');
const authMiddleware = require('./authMiddleware');

const JWT_SECRET = process.env.JWT_SECRET;
const SALT_ROUNDS = 10;

router.post('/signup', async (req, res) => {
  const { username, phoneNumber, password, location, gender, profilePicUrl } = req.body;

  if (!username || !phoneNumber || !password || !location || !gender) {
    return res.status(400).json({ error: 'All fields are required.' });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters.' });
  }
  if (!/^\d{10}$/.test(phoneNumber)) {
    return res.status(400).json({ error: 'Enter a valid 10-digit mobile number.' });
  }
  if (!['M', 'F'].includes(gender)) {
    return res.status(400).json({ error: 'Gender must be M or F.' });
  }

  try {
    const existing = await pool.query(
      'SELECT id FROM users WHERE username = $1 OR phone_number = $2',
      [username, phoneNumber]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'Username or mobile number already in use.' });
    }

    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

    const result = await pool.query(
      `INSERT INTO users (username, phone_number, password_hash, location, gender, profile_pic_url)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, username, phone_number, location, gender, profile_pic_url, created_at`,
      [username, phoneNumber, passwordHash, location, gender, profilePicUrl || null]
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
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password are required.' });
  }

  try {
    const result = await pool.query('SELECT * FROM users WHERE username = $1', [username]);
    const user = result.rows[0];

    if (!user) {
      return res.status(401).json({ error: 'Invalid username or password.' });
    }

    const passwordMatches = await bcrypt.compare(password, user.password_hash);
    if (!passwordMatches) {
      return res.status(401).json({ error: 'Invalid username or password.' });
    }

    const token = jwt.sign({ userId: user.id }, JWT_SECRET, { expiresIn: '7d' });

    res.status(200).json({
      user: {
        id: user.id,
        username: user.username,
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
  const { username, phoneNumber, location, gender } = req.body;

  if (!username || !phoneNumber || !location || !gender) {
    return res.status(400).json({ error: 'All fields are required.' });
  }
  if (!/^\d{10}$/.test(phoneNumber)) {
    return res.status(400).json({ error: 'Enter a valid 10-digit mobile number.' });
  }
  if (!['M', 'F'].includes(gender)) {
    return res.status(400).json({ error: 'Gender must be M or F.' });
  }

  try {
    const existing = await pool.query(
      'SELECT id FROM users WHERE (username = $1 OR phone_number = $2) AND id != $3',
      [username, phoneNumber, userId]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'That username or mobile number is already taken.' });
    }

    const result = await pool.query(
      `UPDATE users SET username = $1, phone_number = $2, location = $3, gender = $4
       WHERE id = $5
       RETURNING id, username, phone_number, location, gender, profile_pic_url`,
      [username, phoneNumber, location, gender, userId]
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
  const { username, phoneNumber, newPassword } = req.body;

  if (!username || !phoneNumber || !newPassword) {
    return res.status(400).json({ error: 'All fields are required.' });
  }
  if (newPassword.length < 6) {
    return res.status(400).json({ error: 'New password must be at least 6 characters.' });
  }

  try {
    const result = await pool.query(
      'SELECT id FROM users WHERE username = $1 AND phone_number = $2',
      [username, phoneNumber]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Username and mobile number do not match any account.' });
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

module.exports = router;