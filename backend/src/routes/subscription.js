const express = require('express');
const path = require('path');
const { query } = require(path.join(__dirname, '..', 'db.js'));
const { authMiddleware } = require('../auth');

const router = express.Router();
router.use(authMiddleware);

router.get('/status', async (req, res) => {
  try {
    const r = await query(
      'SELECT is_active FROM subscription_status WHERE user_id = $1',
      [req.userId]
    );
    res.json({ isActive: r.rows[0]?.is_active ?? false });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to get status' });
  }
});

router.post('/status', async (req, res) => {
  try {
    const { isActive } = req.body;
    await query(
      `INSERT INTO subscription_status (user_id, is_active, updated_at)
       VALUES ($1, $2, NOW())
       ON CONFLICT (user_id) DO UPDATE SET is_active = $2, updated_at = NOW()`,
      [req.userId, !!isActive]
    );
    res.json({ isActive: !!isActive });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to update status' });
  }
});

module.exports = router;
