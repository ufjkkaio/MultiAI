const express = require('express');
const { query } = require('../db');
const { authMiddleware } = require('../auth');

const router = express.Router();
router.use(authMiddleware);

/** 自分のパーソナライズ設定を取得 */
router.get('/preferences', async (req, res) => {
  try {
    const r = await query(
      'SELECT profile, response_style FROM user_preferences WHERE user_id = $1',
      [req.userId]
    );
    if (r.rows.length === 0) {
      return res.json({ profile: '', response_style: '' });
    }
    res.json(r.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to get preferences' });
  }
});

/** パーソナライズ設定を更新 */
router.patch('/preferences', async (req, res) => {
  try {
    const profile = typeof req.body?.profile === 'string' ? req.body.profile.trim() : '';
    const responseStyle = typeof req.body?.response_style === 'string' ? req.body.response_style.trim() : '';
    await query(
      `INSERT INTO user_preferences (user_id, profile, response_style, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (user_id) DO UPDATE SET profile = $2, response_style = $3, updated_at = NOW()`,
      [req.userId, profile, responseStyle]
    );
    res.json({ profile, response_style: responseStyle });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to update preferences' });
  }
});

module.exports = router;
