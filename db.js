// Shared database connection helper for the stock-keeping app.
const { Pool } = require('pg');

const connectionString =
  process.env.DATABASE_URL ||
  'postgresql://neondb_owner:npg_GoPqbjO2Z6kQ@ep-red-king-aol35wfp-pooler.c-2.ap-southeast-1.aws.neon.tech/neondb?sslmode=require';

const pool = new Pool({
  connectionString,
  ssl: { rejectUnauthorized: false },
});

module.exports = { pool };
