// Runs schema.sql then seed.sql against the Neon database, then prints a summary.
const fs = require('fs');
const path = require('path');
const { pool } = require('./db');

async function run(file) {
  const sql = fs.readFileSync(path.join(__dirname, file), 'utf8');
  await pool.query(sql);
  console.log(`✓ applied ${file}`);
}

(async () => {
  try {
    await run('schema.sql');
    await run('seed.sql');

    const { rows } = await pool.query(`
      SELECT p.sku, p.name, w.name AS warehouse, i.quantity, p.reorder_level
      FROM inventory i
      JOIN products   p ON p.product_id   = i.product_id
      JOIN warehouses w ON w.warehouse_id = i.warehouse_id
      ORDER BY p.sku, w.name`);

    console.log('\nCurrent stock levels:');
    console.table(rows);

    const low = await pool.query('SELECT sku, name, warehouse, quantity, reorder_level FROM v_low_stock ORDER BY sku');
    console.log('\nLow-stock alerts (quantity <= reorder level):');
    console.table(low.rows);
  } catch (e) {
    console.error('Setup failed:', e.message);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
})();
