const express = require('express');
const crypto = require('crypto');
const { authWithApple, findOrCreateUserByAppleId, signToken } = require('../auth');
const { query } = require('../db');

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

/**
 * ゲスト用: ログイン画面を出さずに利用するための簡易セッション発行。
 * Apple 個人情報の入力は行わない（端末ごとの匿名セッション）。
 */
router.post('/guest', async (req, res) => {
  try {
    const guestAppleUserId = `guest-${crypto.randomUUID()}`;
    const userId = await findOrCreateUserByAppleId(guestAppleUserId);
    const token = signToken(userId);
    res.json({ token, userId });
  } catch (err) {
    console.error('Guest auth error:', err);
    res.status(500).json({ error: err.message || 'Failed to create guest session' });
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
