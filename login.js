// Simple, basic login for the stock-keeping app.
//
//   Usage:  node login.js <username> <password>
//
// Verification is done entirely in SQL using pgcrypto's crypt():
// the stored bcrypt hash is used as its own salt, so we never handle
// the plaintext password beyond passing it to the query. On success we
// stamp last_login_at and return the user's role, which the app uses to
// decide what actions are permitted (see spec.md, Access Control).

const { pool } = require('./db');

async function login(username, password) {
  const sql = `
    SELECT u.user_id, u.username, u.email, r.role_name, u.is_active
    FROM   users u
    JOIN   roles r ON r.role_id = u.role_id
    WHERE  u.username = $1
      AND  u.is_active = TRUE
      AND  u.password_hash = crypt($2, u.password_hash)`;
  const { rows } = await pool.query(sql, [username, password]);
  if (rows.length === 0) return null;

  await pool.query('UPDATE users SET last_login_at = now() WHERE user_id = $1', [rows[0].user_id]);
  return rows[0];
}

// Role -> permitted actions (enforced by the app layer).
const PERMISSIONS = {
  admin:   ['manage_users', 'manage_products', 'manage_suppliers', 'record_movement', 'view_reports'],
  manager: ['manage_products', 'manage_suppliers', 'record_movement', 'view_reports'],
  staff:   ['record_movement', 'view_reports'],
};

(async () => {
  const [, , username, password] = process.argv;
  if (!username || !password) {
    console.log('Usage: node login.js <username> <password>');
    process.exit(1);
  }
  try {
    const user = await login(username, password);
    if (!user) {
      console.log('❌ Login failed: invalid credentials or inactive account.');
      process.exitCode = 1;
      return;
    }
    console.log(`✓ Welcome, ${user.username} (${user.role_name})`);
    console.log('  Email:      ', user.email);
    console.log('  Permissions:', PERMISSIONS[user.role_name].join(', '));
  } catch (e) {
    console.error('Error:', e.message);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
})();
