/**
 * schema.sql を実行する。Railway 上で railway run npm run db:init で実行する。
 */
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const schemaPath = path.join(__dirname, '../schema.sql');
const sql = fs.readFileSync(schemaPath, 'utf8');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production'
    ? { rejectUnauthorized: false }
    : false,
});

async function main() {
  try {
    await pool.query(sql);
    console.log('Schema executed successfully.');
  } catch (err) {
    console.error('Schema execution failed:', err.message);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

main();
