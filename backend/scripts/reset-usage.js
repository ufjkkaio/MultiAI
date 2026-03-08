/**
 * 今月の利用数（usage_counts）を 0 にリセットする。
 * 使い方: cd backend && npm run reset-usage
 * ローカルでは secrets/.env の DATABASE_URL を使用。Railway では railway run npm run reset-usage
 */
require('dotenv').config({ path: require('path').resolve(__dirname, '../secrets/.env') });
const { query } = require('../src/db');

const period = `${new Date().getUTCFullYear()}-${String(new Date().getUTCMonth() + 1).padStart(2, '0')}`;

async function main() {
  if (!process.env.DATABASE_URL) {
    console.error('DATABASE_URL が設定されていません。secrets/.env または環境変数を確認してください。');
    process.exit(1);
  }
  const r = await query(
    'UPDATE usage_counts SET count = 0 WHERE period = $1 RETURNING user_id',
    [period]
  );
  console.log(`今月（${period}）の利用数をリセットしました。${r.rowCount} 件更新。`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
