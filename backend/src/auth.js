const express = require('express');
const { authWithApple, findOrCreateUserByAppleId, signToken } = require('../auth');
const path = require('path');
const { query } = require(path.join(__dirname, '..', 'db.js'));

const router = express.Router();

const DEV_USER_APPLE_ID = 'dev-user';

router.post('/apple', async (req, res) => {
  try {
    const { identityToken } = req.body;
    if (!identityToken) {
      return res.status(400).json({ error: 'identityToken required' });
    }
    const { token, userId } = await authWithApple(identityToken);
    res.json({ token, userId });
  } catch (err) {
    console.error('Auth error:', err);
    res.status(401).json({ error: err.message || 'Authentication failed' });
  }
});

/** 開発用: Apple ログインをスキップしてトークンだけ発行。localhost や開発時のみ使用すること。 */
router.post('/dev', async (req, res) => {
  const allow = process.env.NODE_ENV !== 'production' || process.env.ALLOW_DEV_LOGIN === 'true';
  if (!allow) {
    return res.status(404).json({ error: 'Not available' });
  }
  try {
    const userId = await findOrCreateUserByAppleId(DEV_USER_APPLE_ID);
    await query(
      `INSERT INTO subscription_status (user_id, is_active, updated_at)
       VALUES ($1, true, NOW())
       ON CONFLICT (user_id) DO UPDATE SET is_active = true, updated_at = NOW()`,
      [userId]
    );
    const token = signToken(userId);
    res.json({ token, userId });
  } catch (err) {
    console.error('Dev auth error:', err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
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
