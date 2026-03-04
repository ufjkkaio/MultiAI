const express = require('express');
const pdfParse = require('pdf-parse');
const sharp = require('sharp');
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
    const messages = [];
    for (const row of r.rows) {
      try {
        let attachments = [];
        const raw = row.attachments;
        if (Array.isArray(raw) && raw.length > 0) {
          attachments = raw
            .filter((a) => a && (a.base64 != null || a.image_base64 != null))
            .map((a) => {
              const out = {
                base64: String(a.base64 ?? a.image_base64 ?? ''),
                media_type: String(a.media_type ?? a.mediaType ?? a.media_type ?? 'image/jpeg'),
              };
              if (a.filename != null && String(a.filename).trim()) out.filename = String(a.filename).trim();
              return out;
            });
        }
        const createdAt = row.created_at == null
          ? null
          : (row.created_at instanceof Date ? row.created_at.toISOString() : String(row.created_at));
        messages.push({
          id: String(row.id ?? ''),
          role: String(row.role ?? 'user'),
          provider: row.provider != null ? String(row.provider) : null,
          content: String(row.content ?? ''),
          expanded_from_id: row.expanded_from_id != null ? String(row.expanded_from_id) : null,
          created_at: createdAt,
          attachments,
        });
      } catch (err) {
        console.error('Message row map error:', err?.message, 'row id:', row?.id);
      }
    }
    res.json({ messages });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to get messages' });
  }
});

// プロキシ/Node のバッファを超えるよう、chunk 送信後にパディングを足して送信を促す（同時に届く現象の緩和）
const SSE_CHUNK_PADDING = 4096;

function sendSSE(res, event, data) {
  res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  if (typeof res.flush === 'function') res.flush();
  if (event === 'chunk') {
    res.write(': ' + ' '.repeat(Math.max(0, SSE_CHUNK_PADDING - 2)) + '\n\n');
    if (typeof res.flush === 'function') res.flush();
  }
}

const MAX_ATTACHMENT_BASE64_LENGTH = 6 * 1024 * 1024; // ~4.5MB raw 想定（1枚あたり）
const MAX_ATTACHMENTS = 5;
const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic'];
const AI_IMAGE_MAX_SIDE = 384;
const AI_IMAGE_JPEG_QUALITY = 50;
const MAX_FILE_BASE64_LENGTH = 2 * 1024 * 1024; // ファイル1つあたり約1.5MB想定
const MAX_FILES = 3;
const ALLOWED_FILE_TYPES = ['application/pdf', 'text/plain'];

function parseFiles(body) {
  const raw = body.files;
  if (!Array.isArray(raw) || raw.length === 0) return [];
  const list = [];
  for (let i = 0; i < Math.min(raw.length, MAX_FILES); i++) {
    const f = raw[i];
    const mt = (f && f.media_type) ? String(f.media_type).toLowerCase().trim() : null;
    const b64 = (f && f.content_base64) ? String(f.content_base64).trim() : null;
    const name = (f && f.filename && typeof f.filename === 'string') ? String(f.filename).trim() : `file_${i}`;
    if (mt && ALLOWED_FILE_TYPES.includes(mt) && b64 && b64.length > 0 && b64.length <= MAX_FILE_BASE64_LENGTH) {
      list.push({ base64: b64, media_type: mt, filename: name || `file_${i}` });
    }
  }
  return list;
}

async function buildFileTextSuffix(files) {
  if (!Array.isArray(files) || files.length === 0) return '';
  const parts = [];
  for (const f of files) {
    if (f.media_type === 'text/plain') {
      try {
        const text = Buffer.from(f.base64, 'base64').toString('utf8');
        parts.push(`\n\n[File: ${f.filename}]\n${text}`);
      } catch (_) {
        parts.push(`\n\n[File: ${f.filename}]\n(could not decode)`);
      }
    } else if (f.media_type === 'application/pdf') {
      try {
        const buf = Buffer.from(f.base64, 'base64');
        const data = await pdfParse(buf);
        let text = (data && data.text && data.text.trim()) ? data.text.trim() : '';
        const maxChars = 80000;
        if (text.length > maxChars) text = text.slice(0, maxChars) + '\n\n(続きは省略しました)';
        parts.push(text ? `\n\n[PDF: ${f.filename}]\n${text}` : `\n\n[PDF: ${f.filename}]\n(テキストを抽出できませんでした)`);
      } catch (err) {
        console.error('PDF parse error:', err?.message);
        parts.push(`\n\n[PDF: ${f.filename}]\n(読み取りに失敗しました)`);
      }
    }
  }
  return parts.join('');
}

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

/** 画像を AI 送信用にリサイズ（長辺 512px・JPEG）。軽量化で応答を短くする。失敗時は元のまま返す。 */
async function resizeImagesForAI(attachments) {
  if (!Array.isArray(attachments) || attachments.length === 0) return attachments;
  const out = [];
  for (const a of attachments) {
    if (!a || !a.base64 || !ALLOWED_IMAGE_TYPES.includes((a.media_type || '').toLowerCase())) {
      out.push(a);
      continue;
    }
    try {
      const buf = Buffer.from(a.base64, 'base64');
      const resized = await sharp(buf)
        .resize(AI_IMAGE_MAX_SIDE, AI_IMAGE_MAX_SIDE, { fit: 'inside', withoutEnlargement: true })
        .jpeg({ quality: AI_IMAGE_JPEG_QUALITY })
        .toBuffer();
      out.push({ base64: resized.toString('base64'), media_type: 'image/jpeg' });
    } catch (err) {
      console.warn('resizeImagesForAI skip:', err?.message);
      out.push(a);
    }
  }
  return out;
}

router.post('/rooms/:roomId/messages', async (req, res) => {
  try {
    const { roomId } = req.params;
    const { content, providers: bodyProviders } = req.body;
    if (!content || typeof content !== 'string' || !content.trim()) {
      return res.status(400).json({ error: 'content required' });
    }
    const attachmentsList = parseAttachments(req.body);
    const fileList = parseFiles(req.body);
    const mergedAttachments = [
      ...attachmentsList.map((a) => ({ base64: a.base64, media_type: a.media_type })),
      ...fileList.map((f) => ({ base64: f.base64, media_type: f.media_type, filename: f.filename })),
    ];

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

    // 会話履歴: 今回のユーザー送信「前」のメッセージのみ取得（新メッセージはこのあと INSERT し、API には履歴＋新メッセージを渡す）
    const hist = await query(
      'SELECT role, provider, content FROM messages WHERE room_id = $1 ORDER BY created_at ASC LIMIT 40',
      [roomId]
    );
    const history = hist.rows.map((row) => ({
      role: row.role,
      content: String(row.content ?? '').trim() || '(なし)',
    }));

    let profile = '';
    let responseStyle = '';
    const prefs = await query('SELECT profile, response_style FROM user_preferences WHERE user_id = $1', [req.userId]);
    if (prefs.rows.length > 0) {
      profile = prefs.rows[0].profile || '';
      responseStyle = prefs.rows[0].response_style || '';
    }

    const attachmentsJson = mergedAttachments.length > 0 ? JSON.stringify(mergedAttachments) : null;
    const insertResult = await query(
      'INSERT INTO messages (room_id, role, content, attachments) VALUES ($1, $2, $3, $4::jsonb) RETURNING id, role, content, attachments, created_at',
      [roomId, 'user', content.trim(), attachmentsJson]
    );
    const userMessageRow = insertResult.rows[0];
    const attachmentsForClient = userMessageRow.attachments || [];

    if (req.body.prepare_only === true) {
      return res.json({
        user_message: {
          id: userMessageRow.id,
          content: userMessageRow.content,
          attachments: Array.isArray(attachmentsForClient) ? attachmentsForClient : [],
          created_at: userMessageRow.created_at,
        },
      });
    }

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

    const contentForAI = content.trim() + (await buildFileTextSuffix(fileList));
    const hasAttachments = attachmentsList.length > 0 || fileList.length > 0;
    const imagesForAI = await resizeImagesForAI(attachmentsList);
    await getResponsesStreamingRealtime(contentForAI, history, {
      providers,
      profile,
      responseStyle,
      images: imagesForAI,
      timeoutMs: hasAttachments ? 90000 : undefined,
      onChunk: (provider, delta) => {
        if (delta === 'openai' || delta === 'gemini') return; // プロバイダー名だけのチャンクは送らない
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

/** 1プロバイダー専用ストリーム（接続を分けてプロキシのバッファを避け、完了順に届ける） */
router.get('/rooms/:roomId/messages/stream', async (req, res) => {
  try {
    const { roomId } = req.params;
    const messageId = req.query.message_id;
    const provider = (req.query.provider || '').toLowerCase();
    if (!messageId || typeof messageId !== 'string' || !['openai', 'gemini'].includes(provider)) {
      return res.status(400).json({ error: 'message_id and provider (openai or gemini) required' });
    }

    const roomCheck = await query(
      'SELECT id, user_id FROM rooms WHERE id = $1 AND user_id = $2',
      [roomId, req.userId]
    );
    if (roomCheck.rows.length === 0) return res.status(404).json({ error: 'Room not found' });

    const msgRows = await query(
      'SELECT id, room_id, role, content, attachments, created_at FROM messages WHERE id = $1 AND room_id = $2 AND role = $3',
      [messageId, roomId, 'user']
    );
    if (msgRows.rows.length === 0) return res.status(404).json({ error: 'Message not found' });
    const msg = msgRows.rows[0];

    const hist = await query(
      'SELECT role, content FROM messages WHERE room_id = $1 AND created_at < $2 ORDER BY created_at ASC LIMIT 40',
      [roomId, msg.created_at]
    );
    const history = hist.rows.map((r) => ({
      role: r.role,
      content: String(r.content ?? '').trim() || '(なし)',
    }));

    const rawAttachments = msg.attachments || [];
    const imageList = Array.isArray(rawAttachments)
      ? rawAttachments.filter((a) => a && a.media_type && ALLOWED_IMAGE_TYPES.includes(String(a.media_type).toLowerCase()))
          .map((a) => ({ base64: a.base64, media_type: a.media_type }))
      : [];
    const fileList = Array.isArray(rawAttachments)
      ? rawAttachments.filter((a) => a && a.media_type && ALLOWED_FILE_TYPES.includes(String(a.media_type).toLowerCase()))
          .map((a) => ({ base64: a.base64, media_type: a.media_type, filename: a.filename || 'file' }))
      : [];

    const contentForAI = (msg.content || '').trim() + (await buildFileTextSuffix(fileList));
    const imagesForAI = await resizeImagesForAI(imageList);

    let profile = '';
    let responseStyle = '';
    const prefs = await query('SELECT profile, response_style FROM user_preferences WHERE user_id = $1', [req.userId]);
    if (prefs.rows.length > 0) {
      profile = prefs.rows[0].profile || '';
      responseStyle = prefs.rows[0].response_style || '';
    }

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');
    res.flushHeaders();
    res.write(': ' + ' '.repeat(2046) + '\n\n');

    const hasAttachments = imageList.length > 0 || fileList.length > 0;
    await getResponsesStreamingRealtime(contentForAI, history, {
      providers: [provider],
      profile,
      responseStyle,
      images: imagesForAI,
      timeoutMs: hasAttachments ? 90000 : undefined,
      onChunk: (p, delta) => {
        if (delta === 'openai' || delta === 'gemini') return;
        sendSSE(res, 'chunk', { provider: p, delta });
      },
      onDone: async (p, content, error) => {
        if (error) {
          sendSSE(res, 'error', { provider: p, error });
          return;
        }
        if (content) {
          const q = await query(
            'INSERT INTO messages (room_id, role, provider, content, expanded_from_id) VALUES ($1, $2, $3, $4, NULL) RETURNING id, role, provider, content, expanded_from_id, created_at',
            [roomId, 'assistant', p, content]
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
