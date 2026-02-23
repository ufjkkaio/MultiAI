require('dotenv').config({ path: require('path').resolve(__dirname, '../../secrets/.env') });

module.exports = {
  port: process.env.PORT || 3000,
  nodeEnv: process.env.NODE_ENV || 'development',
  openai: {
    apiKey: process.env.OPENAI_API_KEY,
    model: process.env.OPENAI_MODEL || 'gpt-4o-mini',
  },
  gemini: {
    apiKey: process.env.GEMINI_API_KEY,
    model: process.env.GEMINI_MODEL || 'gemini-3-flash-preview',
  },
  monthlyMessageLimit: parseInt(process.env.MONTHLY_MESSAGE_LIMIT || '2000', 10),
};
