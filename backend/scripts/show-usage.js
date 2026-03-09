/**
 * 今月の利用数（usage_counts）を表示する。
 * 使い方: cd backend && npm run show-usage
 */
require('dotenv').config({ path: require('path').resolve(__dirname, '../secrets/.env') });
const { Pool } = require('pg');

const period = `${new Date().getUTCFullYear()}-${String(new Date().getUTCMonth() + 1).padStart(2, '0')}`;

async function main() {
  if (!process.env.DATABASE_URL) {
    console.error('DATABASE_URL が設定されていません。secrets/.env または環境変数を確認してください。');
    process.exit(1);
  }
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  try {
    const r = await pool.query(
      'SELECT user_id, count FROM usage_counts WHERE period = $1 ORDER BY count DESC',
      [period]
    );
    console.log(`今月（${period}）の利用数:`);
    if (r.rows.length === 0) {
      console.log('  0 件（まだ送信なし）');
      return;
    }
    let total = 0;
    for (const row of r.rows) {
      console.log(`  ${row.user_id}: ${row.count} 通`);
      total += Number(row.count);
    }
    console.log(`  合計: ${total} 通（${r.rows.length} ユーザー）`);
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
