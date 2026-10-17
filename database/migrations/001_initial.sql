-- Canonical Trexpend v1 schema. Execute only against a new empty database.
PRAGMA foreign_keys = ON;
PRAGMA application_id = 0x54525850;
PRAGMA user_version = 1;

CREATE TABLE currencies (
    id INTEGER PRIMARY KEY,
    code TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK (length(code) > 0),
    name TEXT NOT NULL,
    symbol TEXT,
    decimal_places INTEGER NOT NULL CHECK (typeof(decimal_places) = 'integer' AND decimal_places BETWEEN 0 AND 18),
    prefix_symbol TEXT,
    suffix_symbol TEXT,
    decimal_separator TEXT,
    group_separator TEXT,
    unit_name TEXT,
    subunit_name TEXT,
    currency_type TEXT NOT NULL CHECK (currency_type IN ('fiat', 'crypto'))
);

CREATE TABLE account_images (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'built_in' CHECK (source = 'built_in'),
    asset_name TEXT NOT NULL UNIQUE
);

CREATE TRIGGER protect_builtin_account_images
BEFORE DELETE ON account_images
BEGIN
    SELECT RAISE(ABORT, 'Built-in account images cannot be deleted.');
END;

CREATE TABLE account_types (
    id INTEGER PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    default_image_id INTEGER NOT NULL REFERENCES account_images(id) ON DELETE RESTRICT
);

CREATE TABLE account_statuses (
    id INTEGER PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL
);

CREATE TABLE transaction_types (
    id INTEGER PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    CHECK ((id = 1 AND code = 'expense') OR
           (id = 2 AND code = 'income') OR
           (id = 3 AND code = 'transfer'))
);

CREATE TABLE categories (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id INTEGER REFERENCES categories(id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    favorite INTEGER NOT NULL DEFAULT 0 CHECK (favorite IN (0, 1))
);

CREATE TABLE accounts (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    currency_id INTEGER NOT NULL REFERENCES currencies(id) ON DELETE RESTRICT,
    initial_balance TEXT NOT NULL CHECK (typeof(initial_balance) = 'text'),
    current_balance TEXT DEFAULT NULL CHECK (current_balance IS NULL),
    open_date TEXT,
    exp_date TEXT,
    close_date TEXT,
    status INTEGER NOT NULL REFERENCES account_statuses(id) ON DELETE RESTRICT,
    account_type INTEGER NOT NULL REFERENCES account_types(id) ON DELETE RESTRICT,
    account_number TEXT,
    bank TEXT,
    credit_limit TEXT CHECK (credit_limit IS NULL OR typeof(credit_limit) = 'text'),
    favorite INTEGER NOT NULL DEFAULT 0 CHECK (favorite IN (0, 1)),
    image_id INTEGER REFERENCES account_images(id) ON DELETE RESTRICT,
    color TEXT CHECK (color IS NULL OR (length(color) = 7 AND substr(color, 1, 1) = '#' AND substr(color, 2) NOT GLOB '*[^0-9A-Fa-f]*')),
    notes TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE transactions (
    id INTEGER PRIMARY KEY,
    transaction_type INTEGER NOT NULL REFERENCES transaction_types(id) ON DELETE RESTRICT,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    amount TEXT NOT NULL CHECK (typeof(amount) = 'text' AND amount GLOB '[0-9]*' AND amount NOT GLOB '*[^0-9.]*' AND amount NOT LIKE '%.%.%' AND substr(amount, -1) <> '.'),
    to_account_id INTEGER REFERENCES accounts(id) ON DELETE RESTRICT,
    to_amount TEXT CHECK (to_amount IS NULL OR (typeof(to_amount) = 'text' AND to_amount GLOB '[0-9]*' AND to_amount NOT GLOB '*[^0-9.]*' AND to_amount NOT LIKE '%.%.%' AND substr(to_amount, -1) <> '.')),
    date TEXT NOT NULL CHECK (length(date) = 19 AND date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]'),
    date_with_offset TEXT,
    category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
    notes TEXT,
    fee TEXT NOT NULL CHECK (typeof(fee) = 'text' AND fee GLOB '[0-9]*' AND fee NOT GLOB '*[^0-9.]*' AND fee NOT LIKE '%.%.%' AND substr(fee, -1) <> '.'),
    fee_account_id INTEGER REFERENCES accounts(id) ON DELETE RESTRICT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    CHECK (
        (transaction_type = 3 AND to_account_id IS NOT NULL AND to_account_id <> account_id AND to_amount IS NOT NULL AND fee_account_id IS NOT NULL AND fee_account_id IN (account_id, to_account_id)) OR
        (transaction_type IN (1, 2) AND to_account_id IS NULL AND to_amount IS NULL AND fee_account_id IS NULL AND replace(replace(fee, '0', ''), '.', '') = '')
    )
);

CREATE TABLE exchange_rates (
    id INTEGER PRIMARY KEY,
    from_currency_id INTEGER NOT NULL REFERENCES currencies(id) ON DELETE RESTRICT,
    to_currency_id INTEGER NOT NULL REFERENCES currencies(id) ON DELETE RESTRICT,
    rate TEXT NOT NULL CHECK (typeof(rate) = 'text' AND rate GLOB '[0-9]*' AND rate NOT GLOB '*[^0-9.]*' AND rate NOT LIKE '%.%.%' AND substr(rate, -1) <> '.' AND replace(replace(rate, '0', ''), '.', '') <> ''),
    updated_at TEXT NOT NULL,
    UNIQUE (from_currency_id, to_currency_id),
    CHECK (from_currency_id <> to_currency_id)
);

CREATE TABLE app_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    display_currency_id INTEGER NOT NULL REFERENCES currencies(id) ON DELETE RESTRICT,
    default_account_id INTEGER REFERENCES accounts(id) ON DELETE RESTRICT,
    user_name TEXT
);

CREATE INDEX categories_parent_idx ON categories(parent_id);
CREATE INDEX accounts_currency_idx ON accounts(currency_id);
CREATE INDEX transactions_all_history_idx ON transactions(substr(date, 1, 10) DESC, date ASC, id ASC);
CREATE INDEX transactions_source_history_idx ON transactions(account_id, substr(date, 1, 10) DESC, date ASC, id ASC);
CREATE INDEX transactions_destination_history_idx ON transactions(to_account_id, substr(date, 1, 10) DESC, date ASC, id ASC);
CREATE INDEX transactions_category_idx ON transactions(category_id);
CREATE INDEX transactions_fee_account_idx ON transactions(fee_account_id);

INSERT INTO account_images(id, name, asset_name) VALUES
    (1, 'Checking account', 'account_checking'),
    (2, 'Credit card', 'account_credit_card'),
    (3, 'Cash', 'account_cash'),
    (4, 'Deposit', 'account_deposit');

INSERT INTO account_types(id, code, name, default_image_id) VALUES
    (1, 'checking', 'Checking', 1),
    (2, 'credit_card', 'Credit card', 2),
    (3, 'cash', 'Cash', 3),
    (4, 'deposit', 'Deposit', 4);

INSERT INTO account_statuses(id, code, name) VALUES
    (1, 'open', 'Open'),
    (2, 'closed', 'Closed');

INSERT INTO transaction_types(id, code, name) VALUES
    (1, 'expense', 'Expense'),
    (2, 'income', 'Income'),
    (3, 'transfer', 'Transfer');
