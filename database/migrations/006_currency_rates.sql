INSERT INTO currencies (
    code, name, symbol, decimal_places, prefix_symbol, suffix_symbol,
    decimal_separator, group_separator, unit_name, subunit_name, currency_type
)
SELECT 'UAH', 'Ukrainian hryvnia', NULL, 2, '', 'UAH',
       '.', ',', 'Hryvnia', 'Kopiyka', 'fiat'
WHERE NOT EXISTS (SELECT 1 FROM currencies WHERE code = 'UAH');

CREATE TABLE currency_rates (
    currency_id INTEGER PRIMARY KEY REFERENCES currencies(id) ON DELETE RESTRICT,
    nbu_rate TEXT CHECK (
        nbu_rate IS NULL OR (
            typeof(nbu_rate) = 'text' AND nbu_rate GLOB '[0-9]*'
            AND nbu_rate NOT GLOB '*[^0-9.]*'
            AND nbu_rate NOT LIKE '%.%.%' AND substr(nbu_rate, -1) <> '.'
            AND replace(replace(nbu_rate, '0', ''), '.', '') <> ''
        )
    ),
    nbu_effective_date TEXT,
    nbu_fetched_at TEXT,
    manual_rate TEXT CHECK (
        manual_rate IS NULL OR (
            typeof(manual_rate) = 'text' AND manual_rate GLOB '[0-9]*'
            AND manual_rate NOT GLOB '*[^0-9.]*'
            AND manual_rate NOT LIKE '%.%.%' AND substr(manual_rate, -1) <> '.'
            AND replace(replace(manual_rate, '0', ''), '.', '') <> ''
        )
    ),
    manual_updated_at TEXT,
    CHECK (
        (nbu_rate IS NULL AND nbu_effective_date IS NULL AND nbu_fetched_at IS NULL)
        OR (nbu_rate IS NOT NULL AND nbu_effective_date IS NOT NULL
            AND nbu_fetched_at IS NOT NULL)
    ),
    CHECK (
        (manual_rate IS NULL AND manual_updated_at IS NULL)
        OR (manual_rate IS NOT NULL AND manual_updated_at IS NOT NULL)
    ),
    CHECK (nbu_rate IS NOT NULL OR manual_rate IS NOT NULL)
);

CREATE TABLE currency_sync_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    auto_update INTEGER NOT NULL DEFAULT 1 CHECK (auto_update IN (0, 1)),
    valuation_mode TEXT NOT NULL DEFAULT 'legacy'
        CHECK (valuation_mode IN ('legacy', 'uah')),
    last_attempt_at TEXT,
    last_success_at TEXT,
    last_success_requested_date TEXT,
    CHECK (
        (last_success_at IS NULL AND last_success_requested_date IS NULL)
        OR (last_success_at IS NOT NULL AND last_success_requested_date IS NOT NULL)
    ),
    CHECK (valuation_mode <> 'legacy' OR last_success_at IS NULL)
);

INSERT INTO currency_sync_state(id) VALUES (1);

PRAGMA user_version = 6;
