const appleSignin = require('apple-signin-auth');
const jwt = require('jsonwebtoken');
const { query } = require('./db');

const JWT_SECRET = process.env.JWT_SECRET || 'multiai-dev-secret-change-in-production';

async function verifyAppleToken(identityToken) {
  const appleUser = await appleSignin.verifyIdToken(identityToken, {
    audience: process.env.APPLE_BUNDLE_ID || 'com.multiai.app',
    ignoreExpiration: false,
  });
  return appleUser.sub;
}

function signToken(userId) {
  return jwt.sign({ userId }, JWT_SECRET, { expiresIn: '30d' });
}

function verifyToken(token) {
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    return decoded.userId;
  } catch (_) {
    return null;
  }
}

async function findOrCreateUserByAppleId(appleUserId) {
  const existing = await query(
    'SELECT id FROM users WHERE apple_user_id = $1',
    [appleUserId]
  );
  if (existing.rows.length > 0) return existing.rows[0].id;
  const insert = await query(
    'INSERT INTO users (apple_user_id) VALUES ($1) RETURNING id',
    [appleUserId]
  );
  return insert.rows[0].id;
}

async function authWithApple(identityToken) {
  const appleUserId = await verifyAppleToken(identityToken);
  const userId = await findOrCreateUserByAppleId(appleUserId);
  const token = signToken(userId);
  return { token, userId };
}

function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  const token = authHeader.slice(7);
  const userId = verifyToken(token);
  if (!userId) return res.status(401).json({ error: 'Invalid or expired token' });
  req.userId = userId;
  next();
}

module.exports = {
  authWithApple,
  authMiddleware,
  verifyToken,
  findOrCreateUserByAppleId,
  signToken,
};
