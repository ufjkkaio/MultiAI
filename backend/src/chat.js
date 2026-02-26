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

async function callGemini(messages) {
  if (!genAI) throw new Error('Gemini not configured');
  const model = genAI.getGenerativeModel({ model: config.gemini.model });
  const prompt = messages.map((m) => `${m.role}: ${m.content}`).join('\n') + '\nassistant:';
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

module.exports = { getResponses, getResponsesStreaming };
