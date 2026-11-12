-- Shared sibling order for category management and transaction selection.
ALTER TABLE categories ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0
    CHECK (typeof(sort_order) = 'integer' AND sort_order >= 0);

WITH ranked AS (
    SELECT id,
           row_number() OVER (
               PARTITION BY parent_id ORDER BY name, id
           ) - 1 AS position
    FROM categories
)
UPDATE categories
SET sort_order = (SELECT position FROM ranked WHERE ranked.id = categories.id);

CREATE INDEX categories_parent_order_idx
    ON categories(parent_id, sort_order, name, id);

PRAGMA user_version = 5;
