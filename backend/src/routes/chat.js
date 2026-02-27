const express = require('express');
const { query } = require('../db');
const { getResponsesStreaming } = require('../chat');
const config = require('../config');
const { authMiddleware } = require('../auth');

const router = express.Router();
router.use(authMiddleware);

function getCurrentPeriod() {
  const now = new Date();
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
}

async function checkSubscription(userId) {
  const r = await query(
    'SELECT is_active FROM subscription_status WHERE user_id = $1',
    [userId]
  );
  return r.rows[0]?.is_active === true;
}

async function checkAndIncrementUsage(userId) {
  const period = getCurrentPeriod();
  const r = await query(
    'INSERT INTO usage_counts (user_id, period, count) VALUES ($1, $2, 1) ON CONFLICT (user_id, period) DO UPDATE SET count = usage_counts.count + 1 RETURNING count',
    [userId, period]
  );
  return r.rows[0].count;
}

router.get('/rooms', async (req, res) => {
  try {
    const r = await query(
      'SELECT id, created_at FROM rooms WHERE user_id = $1 ORDER BY created_at DESC',
      [req.userId]
    );
    res.json({ rooms: r.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to list rooms' });
  }
});

router.post('/rooms', async (req, res) => {
  try {
    const r = await query(
      'INSERT INTO rooms (user_id) VALUES ($1) RETURNING id, created_at',
      [req.userId]
    );
    res.status(201).json(r.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to create room' });
  }
});

router.get('/rooms/:roomId/messages', async (req, res) => {
  try {
    const { roomId } = req.params;
    const check = await query(
      'SELECT id FROM rooms WHERE id = $1 AND user_id = $2',
      [roomId, req.userId]
    );
    if (check.rows.length === 0) return res.status(404).json({ error: 'Room not found' });

    const r = await query(
      'SELECT id, role, provider, content, created_at FROM messages WHERE room_id = $1 ORDER BY created_at ASC',
      [roomId]
    );
    res.json({ messages: r.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to get messages' });
  }
});

function sendSSE(res, event, data) {
  res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  // プロキシのバッファリング対策: flush があれば呼ぶ（compression 等で利用可）
  if (typeof res.flush === 'function') res.flush();
}

router.post('/rooms/:roomId/messages', async (req, res) => {
  try {
    const { roomId } = req.params;
    const { content } = req.body;
    if (!content || typeof content !== 'string' || !content.trim()) {
      return res.status(400).json({ error: 'content required' });
    }

    const roomCheck = await query(
      'SELECT id FROM rooms WHERE id = $1 AND user_id = $2',
      [roomId, req.userId]
    );
    if (roomCheck.rows.length === 0) return res.status(404).json({ error: 'Room not found' });

    const subscribed = await checkSubscription(req.userId);
    if (!subscribed) {
      return res.status(403).json({ error: 'Subscription required', code: 'SUBSCRIPTION_REQUIRED' });
    }

    const count = await checkAndIncrementUsage(req.userId);
    if (count > config.monthlyMessageLimit) {
      return res.status(429).json({
        error: 'Monthly limit reached',
        code: 'MONTHLY_LIMIT_REACHED',
      });
    }

    const hist = await query(
      'SELECT role, provider, content FROM messages WHERE room_id = $1 ORDER BY created_at ASC LIMIT 40',
      [roomId]
    );
    const history = hist.rows.map((row) => ({
      role: row.role,
      content: row.content,
    }));

    await query(
      'INSERT INTO messages (room_id, role, content) VALUES ($1, $2, $3)',
      [roomId, 'user', content.trim()]
    );

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');
    res.flushHeaders();

    // プロキシのバッファリング対策: 先頭にパディングを送って即フラッシュさせる
    res.write(': ' + ' '.repeat(2046) + '\n\n');

    sendSSE(res, 'user', { content: content.trim() });

    await getResponsesStreaming(content.trim(), history, async (r) => {
      if (r.content) {
        const q = await query(
          'INSERT INTO messages (room_id, role, provider, content) VALUES ($1, $2, $3, $4) RETURNING id, role, provider, content, created_at',
          [roomId, 'assistant', r.provider, r.content]
        );
        sendSSE(res, 'message', q.rows[0]);
      } else if (r.error) {
        sendSSE(res, 'error', { provider: r.provider, error: r.error });
      }
    });

    sendSSE(res, 'done', {});
    res.end();
  } catch (err) {
    console.error(err);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Failed to send message' });
    } else {
      sendSSE(res, 'error', { error: err.message });
      res.end();
    }
  }
});

module.exports = router;
