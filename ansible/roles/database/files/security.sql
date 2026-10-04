REVOKE CREATE ON SCHEMA public FROM PUBLIC;

CREATE TABLE IF NOT EXISTS app.audit_log (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name  text NOT NULL,
    operation   text NOT NULL,
    row_id      bigint,
    changed_by  text NOT NULL DEFAULT current_user,
    old_data    jsonb,
    new_data    jsonb,
    changed_at  timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION app.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS customers_set_updated_at ON app.customers;

CREATE TRIGGER customers_set_updated_at
BEFORE UPDATE ON app.customers
FOR EACH ROW
EXECUTE FUNCTION app.set_updated_at();

DROP TRIGGER IF EXISTS products_set_updated_at ON app.products;

CREATE TRIGGER products_set_updated_at
BEFORE UPDATE ON app.products
FOR EACH ROW
EXECUTE FUNCTION app.set_updated_at();

DROP TRIGGER IF EXISTS orders_set_updated_at ON app.orders;

CREATE TRIGGER orders_set_updated_at
BEFORE UPDATE ON app.orders
FOR EACH ROW
EXECUTE FUNCTION app.set_updated_at();

CREATE OR REPLACE FUNCTION app.audit_row_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, pg_catalog
AS $$
DECLARE
    affected_id bigint;
BEGIN
    IF TG_OP = 'DELETE' THEN
        affected_id := OLD.id;
    ELSE
        affected_id := NEW.id;
    END IF;

    INSERT INTO app.audit_log (
        table_name,
        operation,
        row_id,
        changed_by,
        old_data,
        new_data
    )
    VALUES (
        TG_TABLE_NAME,
        TG_OP,
        affected_id,
        session_user,
        CASE
            WHEN TG_OP IN ('UPDATE', 'DELETE')
            THEN to_jsonb(OLD)
        END,
        CASE
            WHEN TG_OP IN ('INSERT', 'UPDATE')
            THEN to_jsonb(NEW)
        END
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_audit ON app.orders;

CREATE TRIGGER orders_audit
AFTER INSERT OR UPDATE OR DELETE ON app.orders
FOR EACH ROW
EXECUTE FUNCTION app.audit_row_change();

DROP TRIGGER IF EXISTS payments_audit ON app.payments;

CREATE TRIGGER payments_audit
AFTER INSERT OR UPDATE OR DELETE ON app.payments
FOR EACH ROW
EXECUTE FUNCTION app.audit_row_change();

CREATE OR REPLACE FUNCTION app.order_total(p_order_id bigint)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        SUM(quantity * unit_price),
        0
    )
    FROM app.order_items
    WHERE order_id = p_order_id;
$$;

CREATE OR REPLACE VIEW app.order_summary AS
SELECT
    o.id AS order_id,
    o.customer_id,
    c.email,
    o.status,
    o.created_at,
    COUNT(oi.id) AS line_count,
    COALESCE(SUM(oi.quantity), 0) AS item_count,
    COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS total_amount
FROM app.orders o
JOIN app.customers c
  ON c.id = o.customer_id
LEFT JOIN app.order_items oi
  ON oi.order_id = o.id
GROUP BY
    o.id,
    o.customer_id,
    c.email,
    o.status,
    o.created_at;

CREATE OR REPLACE VIEW app.customer_stats AS
SELECT
    c.id AS customer_id,
    c.email,
    COUNT(o.id) AS orders_count,
    COALESCE(SUM(app.order_total(o.id)), 0) AS lifetime_value
FROM app.customers c
LEFT JOIN app.orders o
  ON o.customer_id = c.id
GROUP BY c.id, c.email;
