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
  monthlyMessageLimit: parseInt(process.env.MONTHLY_MESSAGE_LIMIT || '1200', 10),
  /** 課金前の無料で使えるメッセージ数（月あたり・ユーザーあたり・テキストのみ）。この数を超えるとサブスク必須。写真・ファイル添付は課金後のみ。 */
  // FREE_MESSAGE_ALLOWANCE を外部で上書きされても、無料枠は最大3に固定する（審査/挙動の不一致を防ぐ）
  freeMessageAllowance: Math.min(
    3,
    Math.max(0, parseInt(process.env.FREE_MESSAGE_ALLOWANCE || '3', 10))
  ),
  /** 会話履歴としてAPIに渡す最大件数。10往復＝30件（ユーザー1+AI2×10）。大きいと文脈は豊かになるが入力トークン増でコスト増。 */
  chatHistoryLimit: Math.max(10, Math.min(100, parseInt(process.env.CHAT_HISTORY_LIMIT || '30', 10))),
};
