const express = require('express');
const cors = require('cors');
const authRoutes = require('./authRoutes');
const sportsRoutes = require('./sportsRoutes');
const leagueRoutes = require('./leagueRoutes');
const matchRoutes = require('./matchRoutes');
const playoffRoutes = require('./playoffRoutes');
const authMiddleware = require('./authMiddleware');

const app = express();
app.use(cors());
// Profile photos ride in the JSON body as base64 data-URIs (see authRoutes.js),
// which inflates ~33% over the raw image bytes — express.json()'s 100kb default
// was rejecting most photo uploads before any route ran (PayloadTooLargeError).
app.use(express.json({ limit: '5mb' }));

app.use('/api/auth', authRoutes);
app.use('/api/sports', authMiddleware, sportsRoutes);
app.use('/api/leagues', authMiddleware, leagueRoutes);
app.use('/api/matches', authMiddleware, matchRoutes);
app.use('/api/playoffs', authMiddleware, playoffRoutes);

app.listen(3000, () => console.log('Server running on port 3000'));