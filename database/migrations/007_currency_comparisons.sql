CREATE TABLE currency_comparison_currencies (
    currency_id INTEGER PRIMARY KEY REFERENCES currencies(id) ON DELETE RESTRICT,
    sort_order INTEGER NOT NULL UNIQUE
        CHECK (typeof(sort_order) = 'integer' AND sort_order >= 0)
);

INSERT INTO currency_comparison_currencies(currency_id, sort_order)
SELECT id, ROW_NUMBER() OVER (
    ORDER BY CASE UPPER(code)
        WHEN 'UAH' THEN 0 WHEN 'CAD' THEN 1 WHEN 'USD' THEN 2 WHEN 'EUR' THEN 3
    END
) - 1
FROM currencies
WHERE UPPER(code) IN ('UAH', 'CAD', 'USD', 'EUR');

PRAGMA user_version = 7;
