-- =====================================================================
--  STOCK-KEEPING DATABASE — SEED / EXAMPLE DATA
--  Re-runnable: clears table data and restarts identity counters.
-- =====================================================================

TRUNCATE stock_movements, inventory, products, categories, suppliers,
         warehouses, users, roles RESTART IDENTITY CASCADE;

-- ---- Roles ----------------------------------------------------------
INSERT INTO roles (role_name, description) VALUES
  ('admin',   'Full access: manage users, products and stock'),
  ('manager', 'Manage products, suppliers and record stock movements'),
  ('staff',   'View stock and record incoming/outgoing movements');

-- ---- Users (passwords are bcrypt-hashed via pgcrypto) ---------------
--  Demo credentials (username / password):
--    admin   / admin123
--    manager / manager123
--    staff   / staff123
INSERT INTO users (username, email, password_hash, role_id) VALUES
  ('admin',   'admin@first.clinic',   crypt('admin123',   gen_salt('bf')),
      (SELECT role_id FROM roles WHERE role_name='admin')),
  ('manager', 'manager@first.clinic', crypt('manager123', gen_salt('bf')),
      (SELECT role_id FROM roles WHERE role_name='manager')),
  ('staff',   'staff@first.clinic',   crypt('staff123',   gen_salt('bf')),
      (SELECT role_id FROM roles WHERE role_name='staff'));

-- ---- Categories -----------------------------------------------------
INSERT INTO categories (name, description) VALUES
  ('Beverages',   'Drinks and liquids'),
  ('Snacks',      'Packaged snack foods'),
  ('Stationery',  'Office and writing supplies'),
  ('Cleaning',    'Cleaning and hygiene products');

-- ---- Suppliers ------------------------------------------------------
INSERT INTO suppliers (name, contact_name, phone, email, address) VALUES
  ('Global Drinks Co.',  'Somchai P.', '+66-2-111-1111', 'sales@globaldrinks.co',  'Bangkok, TH'),
  ('SnackWorld Ltd.',    'Aree K.',    '+66-2-222-2222', 'orders@snackworld.co',   'Nonthaburi, TH'),
  ('OfficePlus',         'Niran S.',   '+66-2-333-3333', 'contact@officeplus.co',  'Bangkok, TH');

-- ---- Warehouses -----------------------------------------------------
INSERT INTO warehouses (name, location) VALUES
  ('Main Warehouse',  'Bangkok HQ'),
  ('Branch Store',    'Chiang Mai');

-- ---- Products -------------------------------------------------------
INSERT INTO products
  (sku, name, description, category_id, supplier_id, unit, cost_price, sale_price, reorder_level)
VALUES
  ('BEV-001', 'Mineral Water 500ml',  'Bottled drinking water',
      (SELECT category_id FROM categories WHERE name='Beverages'),
      (SELECT supplier_id FROM suppliers  WHERE name='Global Drinks Co.'),
      'bottle', 5.00, 10.00, 100),
  ('BEV-002', 'Orange Juice 1L',      'Fresh orange juice',
      (SELECT category_id FROM categories WHERE name='Beverages'),
      (SELECT supplier_id FROM suppliers  WHERE name='Global Drinks Co.'),
      'bottle', 25.00, 45.00, 40),
  ('SNK-001', 'Potato Chips 50g',     'Salted potato chips',
      (SELECT category_id FROM categories WHERE name='Snacks'),
      (SELECT supplier_id FROM suppliers  WHERE name='SnackWorld Ltd.'),
      'pack', 12.00, 20.00, 60),
  ('SNK-002', 'Chocolate Bar 40g',    'Milk chocolate bar',
      (SELECT category_id FROM categories WHERE name='Snacks'),
      (SELECT supplier_id FROM suppliers  WHERE name='SnackWorld Ltd.'),
      'bar', 8.00, 15.00, 80),
  ('STA-001', 'Ballpoint Pen Blue',   'Blue ink ballpoint pen',
      (SELECT category_id FROM categories WHERE name='Stationery'),
      (SELECT supplier_id FROM suppliers  WHERE name='OfficePlus'),
      'pcs', 3.00, 7.00, 150),
  ('STA-002', 'A4 Paper Ream',        '500 sheets, 80gsm',
      (SELECT category_id FROM categories WHERE name='Stationery'),
      (SELECT supplier_id FROM suppliers  WHERE name='OfficePlus'),
      'ream', 90.00, 130.00, 30);

-- ---- Stock movements (trigger auto-updates the inventory table) -----
--  Positive quantity = stock IN, negative = stock OUT.
--  NOTE: inbound movements are inserted first (in their own statement) so
--  that every (product, warehouse) inventory row exists before any
--  outbound movement is applied. Within a single multi-row INSERT,
--  PostgreSQL does not guarantee AFTER-ROW triggers observe each other's
--  effects in listed order, so mixing IN and OUT in one statement can
--  transiently drive a brand-new inventory row negative.

-- Step 1: all inbound (receiving) movements.
INSERT INTO stock_movements (product_id, warehouse_id, movement_type, quantity, reference, created_by)
VALUES
  ((SELECT product_id FROM products WHERE sku='BEV-001'), 1, 'IN',  500, 'PO-1001', 1),
  ((SELECT product_id FROM products WHERE sku='BEV-002'), 1, 'IN',  200, 'PO-1001', 1),
  ((SELECT product_id FROM products WHERE sku='SNK-001'), 1, 'IN',  300, 'PO-1002', 1),
  ((SELECT product_id FROM products WHERE sku='SNK-002'), 1, 'IN',  400, 'PO-1002', 1),
  ((SELECT product_id FROM products WHERE sku='STA-001'), 1, 'IN', 1000, 'PO-1003', 1),
  ((SELECT product_id FROM products WHERE sku='STA-002'), 1, 'IN',  100, 'PO-1003', 1),
  ((SELECT product_id FROM products WHERE sku='BEV-001'), 2, 'IN',  120, 'PO-1004', 2),
  ((SELECT product_id FROM products WHERE sku='SNK-001'), 2, 'IN',   50, 'PO-1004', 2);

-- Step 2: outbound (sales/issues) and adjustments.
INSERT INTO stock_movements (product_id, warehouse_id, movement_type, quantity, reference, created_by)
VALUES
  ((SELECT product_id FROM products WHERE sku='BEV-001'), 1, 'OUT',   -430, 'INV-5001', 3),
  ((SELECT product_id FROM products WHERE sku='SNK-002'), 1, 'OUT',   -350, 'INV-5002', 3),
  ((SELECT product_id FROM products WHERE sku='STA-002'), 1, 'OUT',    -80, 'INV-5003', 3),
  ((SELECT product_id FROM products WHERE sku='STA-001'), 1, 'ADJUST',  -5, 'Count adj', 2);
