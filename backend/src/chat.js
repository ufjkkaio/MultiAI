const OpenAI = require('openai').default;
const { GoogleGenerativeAI } = require('@google/generative-ai');
const config = require('./config');

const openai = config.openai.apiKey
  ? new OpenAI({ apiKey: config.openai.apiKey })
  : null;
const genAI = config.gemini.apiKey
  ? new GoogleGenerativeAI(config.gemini.apiKey)
  : null;

function buildMessages(history) {
  return history.map((m) => ({
    role: m.role === 'assistant' ? 'assistant' : 'user',
    content: m.content,
  }));
}

/** パーソナライズを反映した system 文 */
function buildSystemContent(profile, responseStyle) {
  let base = [
    'You are a helpful assistant in a group chat. Reply in the same language as the user.',
    'Use the full conversation history: the user\'s latest message continues the topic just above. Do not ask "what would you like to know?" or "what do you mean?" when the user already stated their intent (e.g. "I want to know why X is trending" means answer about X).',
    'Answer directly based on the most recent user message and the preceding context. For current events or trends the user mentions, give a concrete answer if you know it, or say you are not sure; avoid deflecting with clarifying questions.',
  ].join(' ');
  if (profile && profile.trim()) base += `\n[User profile: ${profile.trim()}]`;
  if (responseStyle && responseStyle.trim()) base += `\n[Response style: ${responseStyle.trim()}]`;
  return base;
}

async function callOpenAI(messages) {
  if (!openai) throw new Error('OpenAI not configured');
  const response = await openai.chat.completions.create({
    model: config.openai.model,
    messages: [{ role: 'system', content: 'You are a helpful assistant in a group chat. Reply concisely in the same language as the user.' }, ...messages],
    max_tokens: 1024,
  });
  return response.choices[0]?.message?.content?.trim() || '';
}

/** ストリーミング: チャンクごとに onChunk(provider, delta) を呼ぶ。完了時に fullContent を返す。
 *  messages の各要素の content は string または Vision 用の content parts 配列可。
 */
async function callOpenAIStream(messages, onChunk, systemContent) {
  if (!openai) throw new Error('OpenAI not configured');
  const system = systemContent || 'You are a helpful assistant in a group chat. Reply concisely in the same language as the user.';
  const stream = await openai.chat.completions.create({
    model: config.openai.model,
    messages: [{ role: 'system', content: system }, ...messages],
    max_tokens: 1024,
    stream: true,
  });
  let full = '';
  for await (const chunk of stream) {
    const delta = chunk.choices[0]?.delta?.content || '';
    if (delta) {
      full += delta;
      onChunk('openai', delta);
    }
  }
  return full.trim();
}

async function callGemini(messages) {
  if (!genAI) throw new Error('Gemini not configured');
  const model = genAI.getGenerativeModel({
    model: config.gemini.model,
    generationConfig: {
      thinkingConfig: { thinkingBudget: 0 },  // Thinking モードを無効化
    },
  });
  const prompt = messages.map((m) => `${m.role}: ${m.content}`).join('\n') + '\nassistant:';
  const result = await model.generateContent(prompt);
  const text = result.response?.candidates?.[0]?.content?.parts?.[0]?.text;
  return text?.trim() || '';
}

/** ストリーミング: チャンクごとに onChunk(provider, delta) を呼ぶ。完了時に fullContent を返す。
 *  lastMessageImages: { base64, mimeType }[] がある場合、最後の user メッセージに画像を添付（Vision）。
 */
async function callGeminiStream(messages, onChunk, systemContent, lastMessageImages = []) {
  if (!genAI) throw new Error('Gemini not configured');
  const model = genAI.getGenerativeModel({
    model: config.gemini.model,
    generationConfig: {
      thinkingConfig: { thinkingBudget: 0 },
    },
  });
  const basePrompt = messages.map((m) => {
    const content = Array.isArray(m.content) ? m.content.map((p) => (p.type === 'text' ? p.text : '[image]')).join('') : m.content;
    return `${m.role}: ${content}`;
  }).join('\n') + '\nassistant:';
  const prompt = systemContent ? `System: ${systemContent}\n\n${basePrompt}` : basePrompt;
  const parts = [{ text: prompt }];
  const imgList = Array.isArray(lastMessageImages) ? lastMessageImages : [];
  for (const img of imgList) {
    if (img && img.base64 && img.mimeType) {
      parts.push({
        inlineData: {
          mimeType: img.mimeType,
          data: img.base64,
        },
      });
    }
  }
  const result = await model.generateContentStream({
    contents: [{ role: 'user', parts }],
  });
  let full = '';
  for await (const chunk of result.stream) {
    const text = (typeof chunk.text === 'function' ? chunk.text() : chunk.text) || '';
    if (!text) continue;
    // SDK が累積テキストを返す場合があるため、増分だけを送る
    let delta;
    if ((full === '' || text.startsWith(full)) && text.length >= full.length) {
      delta = text.slice(full.length);
      full = text;
    } else {
      delta = text;
      full += text;
    }
    if (delta) onChunk('gemini', delta);
  }
  return full.trim();
}

/** 指定モデルで Gemini を呼ぶ（非ストリーミング）。expand「さらに詳しく」用 */
async function callGeminiWithModel(messages, modelName, systemContent) {
  if (!genAI) throw new Error('Gemini not configured');
  const model = genAI.getGenerativeModel({
    model: modelName || config.gemini.model,
    generationConfig: {
      thinkingConfig: { thinkingBudget: 0 },
    },
  });
  const basePrompt = messages.map((m) => `${m.role}: ${m.content}`).join('\n') + '\nassistant:';
  const prompt = systemContent ? `System: ${systemContent}\n\n${basePrompt}` : basePrompt;
  const result = await model.generateContent(prompt);
  const text = result.response?.candidates?.[0]?.content?.parts?.[0]?.text;
  return text?.trim() || '';
}

function withTimeout(promise, ms, label) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`${label} timeout after ${ms}ms`)), ms)
    ),
  ]);
}

async function getResponses(userMessage, history) {
  const messages = buildMessages(history);
  const nextMessages = [...messages, { role: 'user', content: userMessage }];

  const timeoutMs = parseInt(process.env.AI_TIMEOUT_MS || '30000', 10); // デフォルト 30 秒

  const [openaiResult, geminiResult] = await Promise.allSettled([
    withTimeout(callOpenAI(nextMessages), timeoutMs, 'OpenAI'),
    withTimeout(callGemini(nextMessages), timeoutMs, 'Gemini'),
  ]);

  const openaiText = openaiResult.status === 'fulfilled' ? openaiResult.value : null;
  const geminiText = geminiResult.status === 'fulfilled' ? geminiResult.value : null;

  if (geminiResult.status === 'rejected') {
    console.error('Gemini error:', geminiResult.reason?.message || geminiResult.reason);
  }
  if (openaiResult.status === 'rejected') {
    console.error('OpenAI error:', openaiResult.reason?.message || openaiResult.reason);
  }

  return [
    { provider: 'openai', content: openaiText, error: openaiResult.status === 'rejected' ? openaiResult.reason?.message : null },
    { provider: 'gemini', content: geminiText, error: geminiResult.status === 'rejected' ? geminiResult.reason?.message : null },
  ];
}

/**
 * 回答が完成した順に onResponse を呼ぶ。遅い方を待たない。
 */
async function getResponsesStreaming(userMessage, history, onResponse) {
  const messages = buildMessages(history);
  const nextMessages = [...messages, { role: 'user', content: userMessage }];
  const timeoutMs = parseInt(process.env.AI_TIMEOUT_MS || '30000', 10);

  const emit = (provider, result) => {
    const content = result.status === 'fulfilled' ? result.value : null;
    const error = result.status === 'rejected' ? (result.reason?.message || String(result.reason)) : null;
    if (error) console.error(`${provider} error:`, error);
    onResponse({ provider, content, error });
  };

  const openaiPromise = withTimeout(callOpenAI(nextMessages), timeoutMs, 'OpenAI')
    .then((v) => ({ status: 'fulfilled', value: v }))
    .catch((e) => ({ status: 'rejected', reason: e }))
    .then((r) => emit('openai', r));

  const geminiPromise = withTimeout(callGemini(nextMessages), timeoutMs, 'Gemini')
    .then((v) => ({ status: 'fulfilled', value: v }))
    .catch((e) => ({ status: 'rejected', reason: e }))
    .then((r) => emit('gemini', r));

  await Promise.all([openaiPromise, geminiPromise]);
}

const DEFAULT_PROVIDERS = ['openai', 'gemini'];

function parseProviders(val) {
  if (Array.isArray(val) && val.length > 0) return val;
  if (typeof val === 'string') {
    try {
      const arr = JSON.parse(val);
      if (Array.isArray(arr) && arr.length > 0) return arr;
    } catch (_) {}
  }
  return DEFAULT_PROVIDERS;
}

/**
 * リアルタイムストリーミング: チャンクごとに onChunk(provider, delta) を呼ぶ。
 * 各プロバイダー完了時に onDone(provider, fullContent) を呼ぶ。
 * @param {string[]} [providers] - 呼び出すプロバイダー。省略時は両方。
 * @param {string} [profile] - ユーザープロフィール（パーソナライズ）
 * @param {string} [responseStyle] - 返答スタイル（パーソナライズ）
 * @param {{ base64: string, media_type: string }[]} [images] - 添付画像（最大5枚）
 * @param {number} [timeoutMs] - オーバーライド（省略時は AI_TIMEOUT_MS または 30 秒）
 */
async function getResponsesStreamingRealtime(userMessage, history, { providers = DEFAULT_PROVIDERS, profile, responseStyle, images = [], onChunk, onDone, timeoutMs: timeoutOverride }) {
  const effective = Array.isArray(providers) && providers.length > 0 ? providers : DEFAULT_PROVIDERS;
  const messages = buildMessages(history);
  const imageList = Array.isArray(images) ? images.slice(0, 5) : [];
  const lastUserContent = imageList.length > 0
    ? [
        { type: 'text', text: userMessage },
        ...imageList.map((img) => ({ type: 'image_url', image_url: { url: `data:${img.media_type};base64,${img.base64}` } })),
      ]
    : userMessage;
  const nextMessages = [...messages, { role: 'user', content: lastUserContent }];
  const lastMessageImages = imageList.map((img) => ({ base64: img.base64, mimeType: img.media_type }));
  const timeoutMs = timeoutOverride != null && Number.isFinite(timeoutOverride)
    ? Math.max(10000, timeoutOverride)
    : parseInt(process.env.AI_TIMEOUT_MS || '30000', 10);
  const systemContent = buildSystemContent(profile, responseStyle);

  const runOpenAI = async () => {
    try {
      const full = await withTimeout(
        callOpenAIStream(nextMessages, (delta) => onChunk('openai', delta), systemContent),
        timeoutMs,
        'OpenAI'
      );
      onDone('openai', full);
    } catch (e) {
      console.error('OpenAI error:', e?.message || e);
      onDone('openai', null, e?.message || String(e));
    }
  };

  const runGemini = async () => {
    try {
      const full = await withTimeout(
        callGeminiStream(nextMessages, (delta) => onChunk('gemini', delta), systemContent, lastMessageImages),
        timeoutMs,
        'Gemini'
      );
      onDone('gemini', full);
    } catch (e) {
      console.error('Gemini error:', e?.message || e);
      onDone('gemini', null, e?.message || String(e));
    }
  };

  const tasks = [];
  if (effective.includes('openai')) tasks.push(runOpenAI());
  if (effective.includes('gemini')) tasks.push(runGemini());
  await Promise.all(tasks);
}

module.exports = { getResponses, getResponsesStreaming, getResponsesStreamingRealtime, parseProviders, callGeminiWithModel, buildSystemContent };
