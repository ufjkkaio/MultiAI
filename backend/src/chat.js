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

async function getResponses(userMessage, history) {
  const messages = buildMessages(history);
  const nextMessages = [...messages, { role: 'user', content: userMessage }];

  const [openaiResult, geminiResult] = await Promise.allSettled([
    callOpenAI(nextMessages),
    callGemini(nextMessages),
  ]);

  const openaiText = openaiResult.status === 'fulfilled' ? openaiResult.value : null;
  const geminiText = geminiResult.status === 'fulfilled' ? geminiResult.value : null;

  return [
    { provider: 'openai', content: openaiText, error: openaiResult.status === 'rejected' ? openaiResult.reason?.message : null },
    { provider: 'gemini', content: geminiText, error: geminiResult.status === 'rejected' ? geminiResult.reason?.message : null },
  ];
}

module.exports = { getResponses };
