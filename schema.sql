-- =====================================================================
--  STOCK-KEEPING DATABASE — SCHEMA
--  Target: PostgreSQL 18 (Neon)
--  Safe to re-run: drops existing objects first.
-- =====================================================================

-- pgcrypto gives us crypt()/gen_salt() for password hashing.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Clean slate (child tables first because of FKs) ---------------------
DROP TRIGGER  IF EXISTS trg_apply_movement ON stock_movements;
DROP FUNCTION IF EXISTS apply_stock_movement() CASCADE;

DROP TABLE IF EXISTS stock_movements CASCADE;
DROP TABLE IF EXISTS inventory       CASCADE;
DROP TABLE IF EXISTS products        CASCADE;
DROP TABLE IF EXISTS categories      CASCADE;
DROP TABLE IF EXISTS suppliers       CASCADE;
DROP TABLE IF EXISTS warehouses      CASCADE;
DROP TABLE IF EXISTS users           CASCADE;
DROP TABLE IF EXISTS roles           CASCADE;

-- =====================================================================
--  ACCESS CONTROL
-- =====================================================================

CREATE TABLE roles (
    role_id     SERIAL PRIMARY KEY,
    role_name   TEXT NOT NULL UNIQUE,          -- admin | manager | staff
    description TEXT
);

CREATE TABLE users (
    user_id       SERIAL PRIMARY KEY,
    username      TEXT NOT NULL UNIQUE,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,               -- bcrypt hash via pgcrypto
    role_id       INTEGER NOT NULL REFERENCES roles(role_id),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
--  MASTER DATA
-- =====================================================================

CREATE TABLE categories (
    category_id   SERIAL PRIMARY KEY,
    name          TEXT NOT NULL UNIQUE,
    description   TEXT
);

CREATE TABLE suppliers (
    supplier_id   SERIAL PRIMARY KEY,
    name          TEXT NOT NULL,
    contact_name  TEXT,
    phone         TEXT,
    email         TEXT,
    address       TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE warehouses (
    warehouse_id  SERIAL PRIMARY KEY,
    name          TEXT NOT NULL,
    location      TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE products (
    product_id    SERIAL PRIMARY KEY,
    sku           TEXT NOT NULL UNIQUE,        -- stock-keeping unit code
    name          TEXT NOT NULL,
    description   TEXT,
    category_id   INTEGER REFERENCES categories(category_id),
    supplier_id   INTEGER REFERENCES suppliers(supplier_id),
    unit          TEXT NOT NULL DEFAULT 'pcs', -- pcs, box, kg, litre ...
    cost_price    NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (cost_price  >= 0),
    sale_price    NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (sale_price  >= 0),
    reorder_level INTEGER NOT NULL DEFAULT 0   CHECK (reorder_level >= 0),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
--  STOCK LEVELS  (one row per product per warehouse)
-- =====================================================================

CREATE TABLE inventory (
    inventory_id  SERIAL PRIMARY KEY,
    product_id    INTEGER NOT NULL REFERENCES products(product_id)   ON DELETE CASCADE,
    warehouse_id  INTEGER NOT NULL REFERENCES warehouses(warehouse_id) ON DELETE CASCADE,
    quantity      INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (product_id, warehouse_id)
);

-- =====================================================================
--  STOCK MOVEMENTS  (immutable audit log of every stock change)
-- =====================================================================

CREATE TABLE stock_movements (
    movement_id   BIGSERIAL PRIMARY KEY,
    product_id    INTEGER NOT NULL REFERENCES products(product_id),
    warehouse_id  INTEGER NOT NULL REFERENCES warehouses(warehouse_id),
    movement_type TEXT    NOT NULL CHECK (movement_type IN ('IN','OUT','ADJUST')),
    quantity      INTEGER NOT NULL CHECK (quantity <> 0),  -- +receive / -issue (signed)
    reference     TEXT,                                    -- PO#, invoice#, note
    created_by    INTEGER REFERENCES users(user_id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_movements_product   ON stock_movements(product_id);
CREATE INDEX idx_movements_warehouse ON stock_movements(warehouse_id);
CREATE INDEX idx_movements_created   ON stock_movements(created_at);

-- ---------------------------------------------------------------------
--  Trigger: every movement automatically updates the inventory table
--  Convention: quantity is signed. IN = positive, OUT = negative,
--  ADJUST = signed correction. Inventory is upserted and can never go
--  below zero (CHECK constraint enforces it).
-- ---------------------------------------------------------------------
--  We UPDATE first, then INSERT only if the (product, warehouse) row does
--  not yet exist. We deliberately do NOT use INSERT ... ON CONFLICT here:
--  PostgreSQL validates CHECK constraints on the *proposed* insert tuple
--  before redirecting a conflict to the UPDATE branch, so an outbound
--  (negative) movement would trip quantity >= 0 before the upsert could
--  turn it into an update. Any resulting negative balance still fails the
--  CHECK constraint, which is the intended guard against overselling.
CREATE FUNCTION apply_stock_movement() RETURNS TRIGGER AS $$
BEGIN
    UPDATE inventory
       SET quantity   = quantity + NEW.quantity,
           updated_at = now()
     WHERE product_id   = NEW.product_id
       AND warehouse_id = NEW.warehouse_id;

    IF NOT FOUND THEN
        INSERT INTO inventory (product_id, warehouse_id, quantity, updated_at)
        VALUES (NEW.product_id, NEW.warehouse_id, NEW.quantity, now());
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_apply_movement
    AFTER INSERT ON stock_movements
    FOR EACH ROW EXECUTE FUNCTION apply_stock_movement();

-- =====================================================================
--  HELPER VIEW: low-stock report
-- =====================================================================
CREATE OR REPLACE VIEW v_low_stock AS
SELECT p.product_id,
       p.sku,
       p.name,
       w.name              AS warehouse,
       i.quantity,
       p.reorder_level
FROM   inventory i
JOIN   products   p ON p.product_id   = i.product_id
JOIN   warehouses w ON w.warehouse_id = i.warehouse_id
WHERE  i.quantity <= p.reorder_level;
