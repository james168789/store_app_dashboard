# Stock-Keeping Database — Project Specification

## 1. Overview

A simple inventory (stock-keeping) system backed by PostgreSQL (hosted on
Neon). It tracks **products**, where they are stored (**warehouses**), who
supplies them (**suppliers**), how they are grouped (**categories**), current
**stock levels** per location, and a full **audit log of every stock movement**.
Basic username/password **access control** with three roles is included.

- **Database:** PostgreSQL 18 on Neon (`neondb`)
- **Driver / runtime:** Node.js + `pg`
- **Password hashing:** bcrypt via the `pgcrypto` extension (`crypt()` / `gen_salt('bf')`)

## 2. Files

| File          | Purpose                                                           |
|---------------|------------------------------------------------------------------|
| `schema.sql`  | Creates all tables, the inventory-updating trigger, and a view. Re-runnable. |
| `seed.sql`    | Loads example roles, users, categories, suppliers, warehouses, products, and stock movements. Re-runnable (truncates first). |
| `db.js`       | Shared Neon connection pool.                                      |
| `setup.js`    | Applies `schema.sql` + `seed.sql`, then prints stock levels and low-stock alerts. |
| `login.js`    | Command-line login demo showing role-based permissions.          |

**Setup:**
```bash
npm install          # installs pg
node setup.js        # build schema + seed + show report
node login.js admin admin123
```

The connection string is read from `DATABASE_URL` if set, otherwise it falls
back to the Neon URL in `db.js`.

## 3. Data Model

```
categories ─┐
suppliers ──┼──< products >──┬──< inventory >── warehouses
            │                └──< stock_movements >── warehouses
roles ──< users >── (records) ── stock_movements
```

### 3.1 Master data

- **categories** — product groupings (`name` unique).
- **suppliers** — vendor contact details.
- **warehouses** — physical stock locations.
- **products** — catalogue items. Each has a unique **`sku`**, a `unit`
  (pcs/box/kg…), `cost_price`, `sale_price`, and a **`reorder_level`** used for
  low-stock alerts. Optional links to a category and a supplier.

### 3.2 Stock tracking

- **inventory** — current quantity of one product at one warehouse.
  `UNIQUE (product_id, warehouse_id)`. `CHECK (quantity >= 0)` prevents
  overselling. This table is **maintained automatically** by a trigger.
- **stock_movements** — append-only audit log. Every row is a single stock
  change with a **signed `quantity`**:
  - `IN`  → positive (receiving / purchase)
  - `OUT` → negative (sale / issue)
  - `ADJUST` → signed correction (stock counts, damage, etc.)
  Includes an optional `reference` (PO#, invoice#) and `created_by` (user).

### 3.3 Automatic inventory maintenance (trigger)

`AFTER INSERT` on `stock_movements` runs `apply_stock_movement()`, which adds
the movement's signed quantity to the matching `inventory` row (creating the row
on first receipt). The application never writes `inventory` directly — it only
inserts movements, and the ledger stays consistent.

> **Design note:** the trigger uses an explicit `UPDATE` then conditional
> `INSERT`, **not** `INSERT … ON CONFLICT DO UPDATE`. PostgreSQL validates
> `CHECK` constraints on the proposed insert tuple *before* redirecting a
> conflict to the UPDATE branch, so an outbound (negative) movement under the
> upsert pattern would fail `quantity >= 0` before it could become an update.
> An oversell (quantity below zero) still correctly fails the `CHECK`.

> **Seeding note:** within a *single* multi-row `INSERT`, AFTER-ROW triggers are
> not guaranteed to observe each other's effects in listed order, so `seed.sql`
> loads all inbound movements in one statement before any outbound movements.
> In normal operation each movement is inserted on its own, so ordering is a
> non-issue.

### 3.4 Reporting view

- **v_low_stock** — products whose on-hand quantity is at or below their
  `reorder_level`, per warehouse.

## 4. Access Control

Simple and basic username/password authentication with role-based permissions.

### 4.1 Roles

| Role      | Permissions                                                            |
|-----------|-----------------------------------------------------------------------|
| `admin`   | manage users, products, suppliers; record movements; view reports     |
| `manager` | manage products, suppliers; record movements; view reports            |
| `staff`   | record movements; view reports                                        |

### 4.2 Users & authentication

- **users** — `username` and `email` are unique. `password_hash` stores a
  bcrypt hash. `is_active` disables an account without deleting it.
  `last_login_at` is stamped on successful login.
- **Password storage:** `crypt('plaintext', gen_salt('bf'))` — bcrypt with a
  per-user random salt. Plaintext is never stored.
- **Verification:** `password_hash = crypt(<entered>, password_hash)` in SQL;
  the stored hash acts as its own salt. The app never compares hashes itself.
- **Authorization:** the role returned at login maps to the permission list in
  `login.js` (`PERMISSIONS`), which the app checks before each action.

### 4.3 Demo credentials

| Username  | Password     | Role    |
|-----------|--------------|---------|
| `admin`   | `admin123`   | admin   |
| `manager` | `manager123` | manager |
| `staff`   | `staff123`   | staff   |

> These are workshop demo passwords. Change them before any real use, and store
> the connection string / credentials in environment variables, not in source.

## 5. Example Data

- 4 categories, 3 suppliers, 2 warehouses, 6 products.
- 12 stock movements (8 inbound, 3 outbound, 1 adjustment) producing 8 inventory
  rows; 4 of them fall at/below reorder level and surface in `v_low_stock`.

## 6. Common Queries

```sql
-- Current stock of one product across all warehouses
SELECT w.name, i.quantity
FROM inventory i JOIN warehouses w USING (warehouse_id)
WHERE i.product_id = (SELECT product_id FROM products WHERE sku = 'BEV-001');

-- Record receiving 50 more units (trigger updates inventory automatically)
INSERT INTO stock_movements (product_id, warehouse_id, movement_type, quantity, reference, created_by)
VALUES ((SELECT product_id FROM products WHERE sku='BEV-001'), 1, 'IN', 50, 'PO-2001', 1);

-- Everything that needs reordering
SELECT * FROM v_low_stock ORDER BY sku;

-- Movement history for a product
SELECT created_at, movement_type, quantity, reference
FROM stock_movements
WHERE product_id = (SELECT product_id FROM products WHERE sku='BEV-001')
ORDER BY created_at;
```

## 7. Possible Extensions

- Purchase orders and sales orders as first-class tables.
- Batch/lot numbers and expiry dates (useful for a clinic setting).
- Stock transfers between warehouses as paired movements.
- Per-role enforcement inside the database via PostgreSQL row-level security.
- A web UI / REST API on top of the existing schema.
```
