const express = require('express');
const cors = require('cors');
const authRoutes = require('./authRoutes');
const sportsRoutes = require('./sportsRoutes');
const leagueRoutes = require('./leagueRoutes');
const authMiddleware = require('./authMiddleware');

const app = express();
app.use(cors());
app.use(express.json());

app.use('/api/auth', authRoutes);
app.use('/api/sports', authMiddleware, sportsRoutes);
app.use('/api/leagues', authMiddleware, leagueRoutes);

app.listen(3000, () => console.log('Server running on port 3000'));