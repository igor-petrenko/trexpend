-- Trexpend v2 to v3. Execute inside the migration transaction.
ALTER TABLE app_settings ADD COLUMN last_created_category_id INTEGER
    REFERENCES categories(id) ON DELETE SET NULL;
ALTER TABLE app_settings ADD COLUMN transfer_category_id INTEGER
    REFERENCES categories(id) ON DELETE SET NULL;

CREATE TABLE transfer_defaults (
    source_account_id INTEGER PRIMARY KEY
        REFERENCES accounts(id) ON DELETE CASCADE,
    destination_account_id INTEGER NOT NULL
        REFERENCES accounts(id) ON DELETE CASCADE,
    CHECK (source_account_id <> destination_account_id)
);
CREATE INDEX transfer_defaults_destination_idx
    ON transfer_defaults(destination_account_id);

UPDATE app_settings
SET transfer_category_id = (
    SELECT CASE WHEN count(*) = 1 THEN min(id) ELSE NULL END
    FROM categories
    WHERE parent_id IS NULL AND name = 'Transfer' AND is_active = 1
);

WITH scored AS (
    SELECT t.account_id, t.to_account_id, t.date, t.id,
           count(*) OVER (
               PARTITION BY t.account_id, t.to_account_id
           ) AS uses
    FROM transactions AS t
    JOIN accounts AS destination ON destination.id = t.to_account_id
    WHERE t.transaction_type = 3 AND destination.status = 1
      AND t.account_id <> t.to_account_id
), ranked AS (
    SELECT account_id, to_account_id,
           row_number() OVER (
               PARTITION BY account_id
               ORDER BY uses DESC, date DESC, id DESC, to_account_id ASC
           ) AS preference_rank
    FROM scored
)
INSERT INTO transfer_defaults(source_account_id, destination_account_id)
SELECT account_id, to_account_id FROM ranked WHERE preference_rank = 1;

PRAGMA user_version = 3;
