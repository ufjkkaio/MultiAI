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

async function callOpenAI(messages) {
  if (!openai) throw new Error('OpenAI not configured');
  const response = await openai.chat.completions.create({
    model: config.openai.model,
    messages: [{ role: 'system', content: 'You are a helpful assistant in a group chat. Reply concisely in the same language as the user.' }, ...messages],
    max_tokens: 1024,
  });
  return response.choices[0]?.message?.content?.trim() || '';
}

/** ストリーミング: チャンクごとに onChunk(provider, delta) を呼ぶ。完了時に fullContent を返す */
async function callOpenAIStream(messages, onChunk) {
  if (!openai) throw new Error('OpenAI not configured');
  const stream = await openai.chat.completions.create({
    model: config.openai.model,
    messages: [{ role: 'system', content: 'You are a helpful assistant in a group chat. Reply concisely in the same language as the user.' }, ...messages],
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

/** ストリーミング: チャンクごとに onChunk(provider, delta) を呼ぶ。完了時に fullContent を返す */
async function callGeminiStream(messages, onChunk) {
  if (!genAI) throw new Error('Gemini not configured');
  const model = genAI.getGenerativeModel({
    model: config.gemini.model,
    generationConfig: {
      thinkingConfig: { thinkingBudget: 0 },
    },
  });
  const prompt = messages.map((m) => `${m.role}: ${m.content}`).join('\n') + '\nassistant:';
  const result = await model.generateContentStream({
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
  });
  let full = '';
  for await (const chunk of result.stream) {
    const text = (typeof chunk.text === 'function' ? chunk.text() : chunk.text) || '';
    if (text) {
      full += text;
      onChunk('gemini', text);
    }
  }
  return full.trim();
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
 */
async function getResponsesStreamingRealtime(userMessage, history, { providers = DEFAULT_PROVIDERS, onChunk, onDone }) {
  const effective = Array.isArray(providers) && providers.length > 0 ? providers : DEFAULT_PROVIDERS;
  const messages = buildMessages(history);
  const nextMessages = [...messages, { role: 'user', content: userMessage }];
  const timeoutMs = parseInt(process.env.AI_TIMEOUT_MS || '30000', 10);

  const runOpenAI = async () => {
    try {
      const full = await withTimeout(
        callOpenAIStream(nextMessages, (delta) => onChunk('openai', delta)),
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
        callGeminiStream(nextMessages, (delta) => onChunk('gemini', delta)),
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

module.exports = { getResponses, getResponsesStreaming, getResponsesStreamingRealtime, parseProviders };
