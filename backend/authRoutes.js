// authRoutes.js
const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const pool = require('./db');

const JWT_SECRET = process.env.JWT_SECRET;
const SALT_ROUNDS = 10;

router.post('/signup', async (req, res) => {
  const { username, phoneNumber, password, location, gender } = req.body;

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
      `INSERT INTO users (username, phone_number, password_hash, location, gender)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, username, phone_number, location, gender, created_at`,
      [username, phoneNumber, passwordHash, location, gender]
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
      },
      token,
    });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Something went wrong during login.' });
  }
});

module.exports = router;