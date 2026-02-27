/**
 * rooms テーブルに name カラムを追加するマイグレーション。
 * railway run node scripts/run-migration-add-room-name.js
 */
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production'
    ? { rejectUnauthorized: false }
    : false,
});

async function main() {
  try {
    await pool.query(`
      ALTER TABLE rooms
      ADD COLUMN IF NOT EXISTS name TEXT DEFAULT ''
    `);
    console.log('Migration add-room-name completed.');
  } catch (err) {
    console.error('Migration failed:', err.message);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

main();
