-- Shared bank identities and portable custom account images.
CREATE TABLE banks (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    asset_name TEXT
);
INSERT INTO banks (id,name,asset_name) VALUES
    (1,'PrivatBank','bank_privatbank'),
    (2,'CIBC','bank_cibc'),
    (3,'monobank','bank_monobank');
INSERT INTO banks (name)
SELECT DISTINCT bank FROM accounts
WHERE bank IS NOT NULL AND bank <> '' AND bank NOT IN (SELECT name FROM banks)
ORDER BY bank;

CREATE TABLE account_custom_images (
    id INTEGER PRIMARY KEY,
    png_data BLOB NOT NULL CHECK (typeof(png_data) = 'blob' AND length(png_data) BETWEEN 1 AND 1048576)
);
ALTER TABLE accounts ADD COLUMN bank_id INTEGER REFERENCES banks(id) ON DELETE RESTRICT;
ALTER TABLE accounts ADD COLUMN custom_image_id INTEGER REFERENCES account_custom_images(id) ON DELETE RESTRICT;
UPDATE accounts SET bank_id = (SELECT id FROM banks WHERE name = accounts.bank);
CREATE INDEX idx_accounts_bank ON accounts(bank_id);
CREATE INDEX idx_accounts_custom_image ON accounts(custom_image_id);
PRAGMA user_version = 4;
