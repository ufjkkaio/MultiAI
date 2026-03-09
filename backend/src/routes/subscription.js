const express = require('express');
const { query } = require('../db');
const { authMiddleware } = require('../auth');
const config = require('../config');

const router = express.Router();
router.use(authMiddleware);

function getCurrentPeriod() {
  const now = new Date();
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
}

router.get('/status', async (req, res) => {
  try {
    const [subRow, usageRow] = await Promise.all([
      query('SELECT is_active FROM subscription_status WHERE user_id = $1', [req.userId]),
      query(
        'SELECT count FROM usage_counts WHERE user_id = $1 AND period = $2',
        [req.userId, getCurrentPeriod()]
      ),
    ]);
    const isActive = subRow.rows[0]?.is_active === true;
    const monthlyUsage = (usageRow.rows[0]?.count ?? 0) | 0;
    const freeRemaining = isActive ? null : Math.max(0, config.freeMessageAllowance - monthlyUsage);
    res.json({
      isActive,
      monthlyUsage,
      monthlyLimit: config.monthlyMessageLimit,
      freeMessageAllowance: config.freeMessageAllowance,
      freeRemaining,
    });
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
