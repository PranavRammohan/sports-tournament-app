// authMiddleware.js
// Protects routes that require a logged-in user.
// Usage: app.use('/api/sports', authMiddleware, sportsRoutes);

const jwt = require('jsonwebtoken');

function authMiddleware(req, res, next) {
  const authHeader = req.headers['authorization']; // expected format: "Bearer <token>"
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'No token provided.' });
  }

  jwt.verify(token, process.env.JWT_SECRET, (err, decoded) => {
    if (err) {
      // 401, not 403 — this means "not authenticated" (bad/expired token),
      // distinct from the 403s used elsewhere for "authenticated but not
      // allowed to do this." The mobile client's ApiClient relies on that
      // distinction to redirect to login only on genuine auth failures.
      return res.status(401).json({ error: 'Invalid or expired token.' });
    }
    req.userId = decoded.userId;
    next();
  });
}

module.exports = authMiddleware;