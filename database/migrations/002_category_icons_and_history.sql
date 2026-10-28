-- Trexpend v1 to v2. Execute inside the migration transaction.
CREATE TABLE category_icons (
    id INTEGER PRIMARY KEY,
    code TEXT NOT NULL UNIQUE CHECK (length(code) > 0),
    name TEXT NOT NULL CHECK (length(name) > 0),
    system_name TEXT NOT NULL CHECK (length(system_name) > 0)
);

INSERT INTO category_icons(id, code, name, system_name) VALUES
    (1, 'general', 'General', 'square.grid.2x2'),
    (2, 'bills', 'Bills', 'doc.text'),
    (3, 'food', 'Food', 'fork.knife'),
    (4, 'groceries', 'Groceries', 'cart'),
    (5, 'leisure', 'Leisure', 'film'),
    (6, 'automobile', 'Automobile', 'car'),
    (7, 'education', 'Education', 'graduationcap'),
    (8, 'home', 'Home', 'house'),
    (9, 'health', 'Healthcare', 'cross.case'),
    (10, 'insurance', 'Insurance', 'shield'),
    (11, 'travel', 'Travel', 'airplane'),
    (12, 'taxes', 'Taxes', 'doc.plaintext'),
    (13, 'gifts', 'Gifts', 'gift'),
    (14, 'income', 'Income', 'banknote'),
    (15, 'transport', 'Public transport', 'tram'),
    (16, 'coffee', 'Coffee', 'cup.and.saucer'),
    (17, 'books', 'Books', 'book');

ALTER TABLE categories ADD COLUMN icon_id INTEGER
    REFERENCES category_icons(id) ON DELETE RESTRICT;
CREATE INDEX categories_icon_idx ON categories(icon_id);

DROP INDEX transactions_all_history_idx;
DROP INDEX transactions_source_history_idx;
DROP INDEX transactions_destination_history_idx;
CREATE INDEX transactions_all_history_idx
    ON transactions(date DESC, id DESC);
CREATE INDEX transactions_source_history_idx
    ON transactions(account_id, date DESC, id DESC);
CREATE INDEX transactions_destination_history_idx
    ON transactions(to_account_id, date DESC, id DESC);

