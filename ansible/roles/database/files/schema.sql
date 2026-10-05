CREATE SCHEMA IF NOT EXISTS app;

CREATE TABLE IF NOT EXISTS app.customers (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email       text NOT NULL UNIQUE,
    full_name   text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS app.products (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku         text NOT NULL UNIQUE,
    name        text NOT NULL,
    price       numeric(12,2) NOT NULL CHECK (price >= 0),
    stock       integer NOT NULL DEFAULT 0 CHECK (stock >= 0),
    active      boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS app.orders (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id bigint NOT NULL REFERENCES app.customers(id),
    status      text NOT NULL CHECK (
        status IN ('new', 'paid', 'shipped', 'cancelled')
    ),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS app.order_items (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    bigint NOT NULL REFERENCES app.orders(id) ON DELETE CASCADE,
    product_id  bigint NOT NULL REFERENCES app.products(id),
    quantity    integer NOT NULL CHECK (quantity > 0),
    unit_price  numeric(12,2) NOT NULL CHECK (unit_price >= 0)
);

CREATE TABLE IF NOT EXISTS app.payments (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    bigint NOT NULL REFERENCES app.orders(id),
    amount      numeric(14,2) NOT NULL CHECK (amount >= 0),
    status      text NOT NULL CHECK (
        status IN ('pending', 'completed', 'failed', 'refunded')
    ),
    created_at  timestamptz NOT NULL DEFAULT now()
);

INSERT INTO app.customers (email, full_name, created_at, updated_at)
SELECT
    'customer' || g || '@example.com',
    'Customer ' || g,
    now() - ((g % 365) || ' days')::interval,
    now() - ((g % 30) || ' days')::interval
FROM generate_series(1, 10000) AS g
ON CONFLICT (email) DO NOTHING;

INSERT INTO app.products (sku, name, price, stock, active)
SELECT
    'SKU-' || lpad(g::text, 6, '0'),
    'Product ' || g,
    round((5 + ((g * 37) % 5000) / 10.0)::numeric, 2),
    (g * 17) % 500,
    (g % 20) <> 0
FROM generate_series(1, 1000) AS g
ON CONFLICT (sku) DO NOTHING;

INSERT INTO app.orders (customer_id, status, created_at, updated_at)
SELECT
    ((g - 1) % 10000) + 1,
    CASE g % 4
        WHEN 0 THEN 'new'
        WHEN 1 THEN 'paid'
        WHEN 2 THEN 'shipped'
        ELSE 'cancelled'
    END,
    now() - ((g % 180) || ' days')::interval,
    now() - ((g % 30) || ' days')::interval
FROM generate_series(1, 50000) AS g
WHERE NOT EXISTS (SELECT 1 FROM app.orders);

INSERT INTO app.order_items (order_id, product_id, quantity, unit_price)
SELECT
    o.id,
    p.id,
    ((o.id + x.n) % 5)::integer + 1,
    p.price
FROM app.orders o
CROSS JOIN generate_series(1, 3) AS x(n)
JOIN app.products p
  ON p.id = ((o.id + x.n - 1) % 1000) + 1
WHERE NOT EXISTS (SELECT 1 FROM app.order_items);

INSERT INTO app.payments (order_id, amount, status, created_at)
SELECT
    o.id,
    round(sum(oi.quantity * oi.unit_price), 2),
    CASE o.id % 4
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'completed'
        WHEN 2 THEN 'completed'
        ELSE 'failed'
    END,
    o.created_at + interval '5 minutes'
FROM app.orders o
JOIN app.order_items oi ON oi.order_id = o.id
WHERE NOT EXISTS (SELECT 1 FROM app.payments)
GROUP BY o.id, o.created_at;

CREATE INDEX IF NOT EXISTS idx_order_items_order_id
    ON app.order_items(order_id);

CREATE INDEX IF NOT EXISTS idx_orders_customer_created_at
    ON app.orders(customer_id, created_at DESC);
