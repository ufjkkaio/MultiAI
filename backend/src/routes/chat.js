const express = require('express');
const { query } = require('../db');
const { getResponsesStreamingRealtime, parseProviders } = require('../chat');
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
      'SELECT id, name, COALESCE(selected_providers, \'["openai","gemini"]\') AS selected_providers, created_at FROM rooms WHERE user_id = $1 ORDER BY created_at DESC',
      [req.userId]
    );
    const rooms = r.rows.map((row) => ({
      ...row,
      selected_providers: parseProviders(row.selected_providers),
    }));
    res.json({ rooms });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to list rooms' });
  }
});

router.post('/rooms', async (req, res) => {
  try {
    const name = typeof req.body?.name === 'string' ? req.body.name.trim() : '';
    const r = await query(
      'INSERT INTO rooms (user_id, name) VALUES ($1, $2) RETURNING id, name, COALESCE(selected_providers, \'["openai","gemini"]\') AS selected_providers, created_at',
      [req.userId, name || '']
    );
    const row = r.rows[0];
    res.status(201).json({ ...row, selected_providers: parseProviders(row.selected_providers) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to create room' });
  }
});

router.patch('/rooms/:roomId', async (req, res) => {
  try {
    const { roomId } = req.params;
    const name = typeof req.body?.name === 'string' ? req.body.name.trim() : undefined;
    const selectedProviders = req.body?.selected_providers;
    const check = await query(
      'SELECT id FROM rooms WHERE id = $1 AND user_id = $2',
      [roomId, req.userId]
    );
    if (check.rows.length === 0) return res.status(404).json({ error: 'Room not found' });

    const updates = [];
    const values = [];
    let idx = 1;
    if (name !== undefined) {
      updates.push(`name = $${idx++}`);
      values.push(name);
    }
    if (selectedProviders !== undefined) {
      const arr = Array.isArray(selectedProviders)
        ? selectedProviders
        : parseProviders(selectedProviders);
      const valid = arr.filter((p) => p === 'openai' || p === 'gemini');
      updates.push(`selected_providers = $${idx++}`);
      values.push(JSON.stringify(valid.length > 0 ? valid : ['openai', 'gemini']));
    }
    if (updates.length === 0) {
      const r = await query('SELECT id, name, COALESCE(selected_providers, \'["openai","gemini"]\') AS selected_providers, created_at FROM rooms WHERE id = $1', [roomId]);
      const row = r.rows[0];
      return res.json({ ...row, selected_providers: parseProviders(row.selected_providers) });
    }
    values.push(roomId);
    const r = await query(
      `UPDATE rooms SET ${updates.join(', ')} WHERE id = $${idx} RETURNING id, name, COALESCE(selected_providers, '["openai","gemini"]') AS selected_providers, created_at`,
      values
    );
    const row = r.rows[0];
    res.json({ ...row, selected_providers: parseProviders(row.selected_providers) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to update room' });
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
    const { content, providers: bodyProviders } = req.body;
    if (!content || typeof content !== 'string' || !content.trim()) {
      return res.status(400).json({ error: 'content required' });
    }

    const roomCheck = await query(
      'SELECT id, COALESCE(selected_providers, \'["openai","gemini"]\') AS selected_providers FROM rooms WHERE id = $1 AND user_id = $2',
      [roomId, req.userId]
    );
    if (roomCheck.rows.length === 0) return res.status(404).json({ error: 'Room not found' });

    const providers = Array.isArray(bodyProviders) && bodyProviders.length > 0
      ? bodyProviders.filter((p) => p === 'openai' || p === 'gemini')
      : parseProviders(roomCheck.rows[0].selected_providers);

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

    await getResponsesStreamingRealtime(content.trim(), history, {
      providers,
      onChunk: (provider, delta) => {
        sendSSE(res, 'chunk', { provider, delta });
      },
      onDone: async (provider, content, error) => {
        if (error) {
          sendSSE(res, 'error', { provider, error });
          return;
        }
        if (content) {
          const q = await query(
            'INSERT INTO messages (room_id, role, provider, content) VALUES ($1, $2, $3, $4) RETURNING id, role, provider, content, created_at',
            [roomId, 'assistant', provider, content]
          );
          sendSSE(res, 'message', q.rows[0]);
        }
      },
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
