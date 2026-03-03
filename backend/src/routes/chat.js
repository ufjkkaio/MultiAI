const express = require('express');
const { query } = require('../db');
const { getResponsesStreamingRealtime, parseProviders, callGeminiWithModel, buildSystemContent } = require('../chat');
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

router.delete('/rooms/:roomId', async (req, res) => {
  try {
    const { roomId } = req.params;
    const r = await query(
      'DELETE FROM rooms WHERE id = $1 AND user_id = $2 RETURNING id',
      [roomId, req.userId]
    );
    if (r.rowCount === 0) return res.status(404).json({ error: 'Room not found' });
    res.status(204).send();
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to delete room' });
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
      'SELECT id, role, provider, content, expanded_from_id, attachments, created_at FROM messages WHERE room_id = $1 ORDER BY created_at ASC',
      [roomId]
    );
    const messages = r.rows.map((row) => {
      const attachments = Array.isArray(row.attachments) ? row.attachments : [];
      return { ...row, attachments };
    });
    res.json({ messages });
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

const MAX_ATTACHMENT_BASE64_LENGTH = 6 * 1024 * 1024; // ~4.5MB raw 想定（1枚あたり）
const MAX_ATTACHMENTS = 5;
const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic'];

function parseAttachments(body) {
  const { attachments: attachmentsRaw, image_base64: imageBase64Raw, image_media_type: imageMediaTypeRaw } = body;
  if (Array.isArray(attachmentsRaw) && attachmentsRaw.length > 0) {
    const list = [];
    for (let i = 0; i < Math.min(attachmentsRaw.length, MAX_ATTACHMENTS); i++) {
      const a = attachmentsRaw[i];
      const mt = (a && a.image_media_type) ? String(a.image_media_type).toLowerCase().trim() : null;
      const b64 = (a && a.image_base64) ? String(a.image_base64).replace(/^data:image\/\w+;base64,/, '').trim() : null;
      if (mt && ALLOWED_IMAGE_TYPES.includes(mt) && b64 && b64.length > 0 && b64.length <= MAX_ATTACHMENT_BASE64_LENGTH) {
        list.push({ base64: b64, media_type: mt });
      }
    }
    return list;
  }
  if (imageBase64Raw != null && imageMediaTypeRaw != null) {
    const mt = String(imageMediaTypeRaw).toLowerCase().trim();
    if (ALLOWED_IMAGE_TYPES.includes(mt)) {
      const b64 = String(imageBase64Raw).replace(/^data:image\/\w+;base64,/, '').trim();
      if (b64 && b64.length <= MAX_ATTACHMENT_BASE64_LENGTH) {
        return [{ base64: b64, media_type: mt }];
      }
    }
  }
  return [];
}

router.post('/rooms/:roomId/messages', async (req, res) => {
  try {
    const { roomId } = req.params;
    const { content, providers: bodyProviders } = req.body;
    if (!content || typeof content !== 'string' || !content.trim()) {
      return res.status(400).json({ error: 'content required' });
    }
    const attachmentsList = parseAttachments(req.body);

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

    let profile = '';
    let responseStyle = '';
    const prefs = await query('SELECT profile, response_style FROM user_preferences WHERE user_id = $1', [req.userId]);
    if (prefs.rows.length > 0) {
      profile = prefs.rows[0].profile || '';
      responseStyle = prefs.rows[0].response_style || '';
    }

    const attachmentsJson = attachmentsList.length > 0 ? JSON.stringify(attachmentsList) : null;
    const insertResult = await query(
      'INSERT INTO messages (room_id, role, content, attachments) VALUES ($1, $2, $3, $4::jsonb) RETURNING id, role, content, attachments, created_at',
      [roomId, 'user', content.trim(), attachmentsJson]
    );
    const userMessageRow = insertResult.rows[0];
    const attachmentsForClient = userMessageRow.attachments || [];

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');
    res.flushHeaders();

    // プロキシのバッファリング対策: 先頭にパディングを送って即フラッシュさせる
    res.write(': ' + ' '.repeat(2046) + '\n\n');

    sendSSE(res, 'user', {
      id: userMessageRow.id,
      content: userMessageRow.content,
      attachments: Array.isArray(attachmentsForClient) ? attachmentsForClient : [],
      created_at: userMessageRow.created_at,
    });

    await getResponsesStreamingRealtime(content.trim(), history, {
      providers,
      profile,
      responseStyle,
      images: attachmentsList,
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
            'INSERT INTO messages (room_id, role, provider, content, expanded_from_id) VALUES ($1, $2, $3, $4, NULL) RETURNING id, role, provider, content, expanded_from_id, created_at',
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

/** Gemini の「さらに詳しく」: 標準モデルで再回答し、元の下に追加する */
router.post('/rooms/:roomId/messages/expand', async (req, res) => {
  try {
    const { roomId } = req.params;
    const { message_id: messageId } = req.body;
    if (!messageId || typeof messageId !== 'string') {
      return res.status(400).json({ error: 'message_id required' });
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

    const msgRow = await query(
      'SELECT id, role, provider, content FROM messages WHERE id = $1 AND room_id = $2',
      [messageId, roomId]
    );
    if (msgRow.rows.length === 0) return res.status(404).json({ error: 'Message not found' });
    const msg = msgRow.rows[0];
    if (msg.role !== 'assistant' || msg.provider !== 'gemini') {
      return res.status(400).json({ error: 'Only Gemini assistant messages can be expanded' });
    }

    const alreadyExpanded = await query(
      'SELECT id FROM messages WHERE expanded_from_id = $1',
      [messageId]
    );
    if (alreadyExpanded.rows.length > 0) {
      return res.status(400).json({ error: 'Already expanded' });
    }

    const allBefore = await query(
      `SELECT id, role, content, created_at FROM messages WHERE room_id = $1 AND created_at <= (SELECT created_at FROM messages WHERE id = $2) ORDER BY created_at ASC`,
      [roomId, messageId]
    );
    const historyRows = allBefore.rows.filter((r) => r.id !== messageId);
    const history = historyRows.map((r) => ({ role: r.role, content: r.content }));

    let profile = '';
    let responseStyle = '';
    const prefs = await query('SELECT profile, response_style FROM user_preferences WHERE user_id = $1', [req.userId]);
    if (prefs.rows.length > 0) {
      profile = prefs.rows[0].profile || '';
      responseStyle = prefs.rows[0].response_style || '';
    }
    const systemContent = buildSystemContent(profile, responseStyle);

    const expandInstruction = `The user asked for more detail. Your previous brief response was:\n\n${msg.content}\n\nProvide a more detailed and thorough response in the same language.`;
    const expandMessages = [...buildMessagesForExpand(history), { role: 'user', content: expandInstruction }];

    const detailedContent = await callGeminiWithModel(expandMessages, config.gemini.modelStandard, systemContent);

    const inserted = await query(
      `INSERT INTO messages (room_id, role, provider, content, expanded_from_id) VALUES ($1, $2, $3, $4, $5) RETURNING id, role, provider, content, expanded_from_id, created_at`,
      [roomId, 'assistant', 'gemini', detailedContent, messageId]
    );

    res.status(201).json(inserted.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message || 'Expand failed' });
  }
});

function buildMessagesForExpand(history) {
  return history.map((m) => ({
    role: m.role === 'assistant' ? 'assistant' : 'user',
    content: m.content,
  }));
}

module.exports = router;
