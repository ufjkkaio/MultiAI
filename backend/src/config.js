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
    model: process.env.GEMINI_MODEL || 'gemini-2.5-flash',
    modelStandard: process.env.GEMINI_MODEL_STANDARD || 'gemini-2.5-flash',  // 「さらに詳しく」用
  },
  monthlyMessageLimit: parseInt(process.env.MONTHLY_MESSAGE_LIMIT || '3000', 10),
};
