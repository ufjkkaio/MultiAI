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
    model: process.env.GEMINI_MODEL || 'gemini-2.5-flash-lite',   // 普段は Lite（コスト削減）
    modelStandard: process.env.GEMINI_MODEL_STANDARD || 'gemini-2.5-flash',  // 「さらに詳しく」押下時は標準で回答し直す
  },
  monthlyMessageLimit: parseInt(process.env.MONTHLY_MESSAGE_LIMIT || '30', 10),
  /** 会話履歴としてAPIに渡す最大件数。5往復＝15件。大きいと文脈は豊かになるが入力トークン増でコスト増。 */
  chatHistoryLimit: Math.max(10, Math.min(100, parseInt(process.env.CHAT_HISTORY_LIMIT || '15', 10))),
};
