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

/** アカウント削除（ユーザー配下データを含め完全削除） */
router.delete('/account', async (req, res) => {
  try {
    // ゲスト（匿名）ユーザーは無料枠のリセット対策として削除できないようにする
    const userRow = await query(
      'SELECT id, apple_user_id FROM users WHERE id = $1',
      [req.userId]
    );

    if (userRow.rows.length === 0) return res.status(404).json({ error: 'User not found' });

    const appleUserId = String(userRow.rows[0].apple_user_id ?? '');
    if (appleUserId.startsWith('guest-')) {
      return res.status(403).json({ error: 'Guest accounts cannot be deleted' });
    }

    const r = await query('DELETE FROM users WHERE id = $1 RETURNING id', [req.userId]);
    res.status(204).send();
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to delete account' });
  }
});

module.exports = router;
