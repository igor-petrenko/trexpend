"""Synthetic contract tests for the offline converter and canonical schema."""

from contextlib import closing
from datetime import datetime
from decimal import Decimal
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch


MODULE_PATH = Path(__file__).resolve().parents[1] / "convert_mmex.py"
SPEC = importlib.util.spec_from_file_location("convert_mmex", MODULE_PATH)
converter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(converter)
LARGE_ID = 1700000000000000


def insert(connection, table, values):
    columns = list(values)
    connection.execute(f'INSERT INTO "{table}" (' + ",".join(columns) + ") VALUES (" +
                       ",".join("?" for _ in columns) + ")", list(values.values()))


def make_source(path):
    with closing(sqlite3.connect(path)) as connection:
        numeric = {"INITIALBAL", "CREDITLIMIT", "TRANSAMOUNT", "TOTRANSAMOUNT", "BASECONVRATE"}
        integers = {"ACCOUNTID", "TRANSID", "CATEGID", "CURRENCYID", "INFOID", "TOACCOUNTID", "PAYEEID",
                    "PARENTID", "ACTIVE", "SCALE", "FOLLOWUPID", "COLOR", "STATEMENTLOCKED"}
        keys = {"ACCOUNTLIST_V1": "ACCOUNTID", "CHECKINGACCOUNT_V1": "TRANSID", "CATEGORY_V1": "CATEGID",
                "CURRENCYFORMATS_V1": "CURRENCYID", "INFOTABLE_V1": "INFOID"}
        for table, columns in converter.CORE_COLUMNS.items():
            definitions = []
            for column in columns:
                kind = "INTEGER" if column in integers else "NUMERIC" if column in numeric else "TEXT"
                definitions.append(column + " " + kind + (" PRIMARY KEY" if column == keys[table] else ""))
            connection.execute(f'CREATE TABLE "{table}" (' + ",".join(definitions) + ")")
        connection.execute("PRAGMA user_version = 20")
        for identity, code, scale, rate, kind in [(1, "CAD", 100, "1", "Fiat"), (2, "USD", 100, "1.35", "Fiat"),
                (3, "UAH", 100, "0.03333333333333333", "Fiat"), (4, "BTC", 100000000, "80000", "Crypto")]:
            insert(connection, "CURRENCYFORMATS_V1", dict(CURRENCYID=identity, CURRENCY_SYMBOL=code,
                CURRENCYNAME=code + " example", SCALE=scale, BASECONVRATE=rate, CURRENCY_TYPE=kind,
                PFX_SYMBOL="$" if code in ("USD", "CAD") else "", SFX_SYMBOL="\u20b4" if code == "UAH" else "",
                DECIMAL_POINT=".", GROUP_SEPARATOR=",", UNIT_NAME="unit", CENT_NAME="cent"))
        insert(connection, "CATEGORY_V1", dict(CATEGID=1, CATEGNAME="Example", ACTIVE=1, PARENTID=-1))
        insert(connection, "CATEGORY_V1", dict(CATEGID=2, CATEGNAME="Example", ACTIVE=1, PARENTID=1))
        for identity, currency, balance, kind in [(1, 1, "-25.00", "Checking"),
                (2, 3, "100.00", "Credit Card"), (LARGE_ID, 1, "0.00", "Cash")]:
            insert(connection, "ACCOUNTLIST_V1", dict(ACCOUNTID=identity, ACCOUNTNAME="Same name", CURRENCYID=currency,
                INITIALBAL=balance, INITIALDATE="2024-01-01", ACCOUNTTYPE=kind, STATUS="Open", FAVORITEACCT="TRUE",
                ACCOUNTNUM="0004", NOTES="Example notes \u00e9", CREDITLIMIT="999.00"))
        for identity, key, value in [(1, "BASECURRENCYID", "1"), (2, "android:default_account_id", str(LARGE_ID)),
                (3, "USERNAME", "Example owner"), (4, "DATAVERSION", "3")]:
            insert(connection, "INFOTABLE_V1", dict(INFOID=identity, INFONAME=key, INFOVALUE=value))
        examples = [
            (1, 2, "Deposit", "100000.00", -1, "0", "2024-02-01", "2024-02-01T09:10:11"),
            (2, 2, "Withdrawal", "1200.50", -1, "1200.50", "2024-02-02", "2024-02-05T10:11:12.689-0500"),
            (1800000000000000, 2, "Transfer", "5000", LARGE_ID, "150", "2024-02-03", "2024-02-03T18:00:00"),
            (1800000000000001, 1, "Transfer", "10", LARGE_ID, "10", "2024-02-04", "2024-02-04T12:00:00"),
        ]
        for identity, account, kind, amount, recipient, received, day, update in examples:
            insert(connection, "CHECKINGACCOUNT_V1", dict(TRANSID=identity, ACCOUNTID=account, TRANSCODE=kind,
                TRANSAMOUNT=amount, TOACCOUNTID=recipient, TOTRANSAMOUNT=received, CATEGID=2, TRANSDATE=day,
                LASTUPDATEDTIME=update, STATUS="R", FOLLOWUPID=-1, COLOR=-1, NOTES="Retained text \u00e9"))
        connection.commit()


class ConverterTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.folder = Path(self.directory.name)
        self.source = self.folder / "source.mmb"
        self.output = self.folder / "result.sqlite"
        self.report = self.folder / "report.json"
        make_source(self.source)
        self.source_hash = converter.digest(self.source)

    def change_source(self, query, parameters=()):
        with closing(sqlite3.connect(self.source)) as connection:
            connection.execute(query, parameters)
            connection.commit()

    def run_conversion(self):
        return converter.convert(self.source, self.output, self.report)

    def rejected(self, fragment):
        source_hash = converter.digest(self.source)
        with self.assertRaisesRegex(converter.ConversionError, fragment):
            self.run_conversion()
        self.assertEqual(converter.digest(self.source), source_hash)
        self.assertFalse(self.output.exists())
        self.assertFalse(self.report.exists())
        self.assertFalse(list(self.folder.glob(".trexpend-*")))

    def test_conversion_reconciles_and_preserves_text_dates_and_settings(self):
        report = self.run_conversion()
        self.assertEqual(converter.digest(self.source), self.source_hash)
        self.assertEqual(report["counts"]["transactions"], 4)
        self.assertEqual(report["account_id_map"][LARGE_ID], 3)
        self.assertEqual(report["reconciliation"]["balances"], {"1": "-35.00", "2": "93899.50", "3": "160.00"})
        self.assertEqual(json.loads(self.report.read_text())["checks"], "passed")
        with closing(sqlite3.connect(self.output)) as connection:
            connection.row_factory = sqlite3.Row
            settings = connection.execute("SELECT * FROM app_settings").fetchone()
            self.assertEqual((settings["default_account_id"], settings["display_currency_id"], settings["user_name"]),
                             (3, 1, "Example owner"))
            expense = connection.execute("SELECT * FROM transactions WHERE id = 2").fetchone()
            self.assertEqual(expense["date"], "2024-02-02T10:11:12")
            self.assertEqual(expense["date_with_offset"], "2024-02-02T10:11:12-05:00")
            self.assertEqual(expense["updated_at"], "2024-02-05T15:11:12.689000Z")
            self.assertEqual(expense["created_at"], expense["updated_at"])
            self.assertIsNone(expense["to_amount"])
            self.assertEqual(expense["notes"], "Retained text \u00e9")
            self.assertEqual(connection.execute("SELECT credit_limit FROM accounts WHERE id=2").fetchone()[0], "0.00")
            self.assertEqual(connection.execute("SELECT account_number FROM accounts WHERE id=2").fetchone()[0], "0004")
            self.assertEqual(connection.execute("SELECT count(*) FROM accounts WHERE current_balance IS NOT NULL").fetchone()[0], 0)
            self.assertEqual(connection.execute("SELECT count(*) FROM exchange_rates").fetchone()[0], 1)
            self.assertEqual(connection.execute("SELECT count(*) FROM currencies").fetchone()[0], 4)
            for row in connection.execute("SELECT * FROM transactions WHERE transaction_type=3"):
                self.assertEqual(row["fee_account_id"], row["account_id"])
                self.assertEqual(row["fee"], "0.00")

    def test_repeat_runs_create_independent_files_with_stable_id_maps(self):
        first = self.run_conversion()
        second = converter.convert(self.source, self.folder / "second.sqlite")
        self.assertEqual(first["transaction_id_map"], second["transaction_id_map"])
        self.assertEqual(first["reconciliation"], second["reconciliation"])

    def test_output_and_report_are_never_overwritten(self):
        for destination in (self.output, self.report):
            with self.subTest(path=destination.name):
                destination.write_bytes(b"existing")
                with self.assertRaisesRegex(converter.ConversionError, "already exists"):
                    self.run_conversion()
                self.assertEqual(destination.read_bytes(), b"existing")
                destination.unlink()
        self.assertEqual(converter.digest(self.source), self.source_hash)

    def test_source_cannot_be_output_or_report(self):
        for output, report in [(self.source, None), (self.output, self.source)]:
            with self.subTest(output=output.name):
                with self.assertRaisesRegex(converter.ConversionError, "must be different"):
                    converter.convert(self.source, output, report)
        self.assertEqual(converter.digest(self.source), self.source_hash)

    def test_source_journal_companion_is_refused(self):
        Path(str(self.source) + "-wal").write_bytes(b"pending")
        self.rejected("journal companions")

    def test_unknown_schema_version_is_refused(self):
        self.change_source("PRAGMA user_version=21")
        self.rejected("schema version")

    def test_unknown_columns_are_refused(self):
        self.change_source("ALTER TABLE CHECKINGACCOUNT_V1 ADD COLUMN EXTRA TEXT")
        self.rejected("source columns")

    def test_populated_deferred_features_are_refused(self):
        self.change_source("CREATE TABLE ATTACHMENT_V1(id INTEGER)")
        self.change_source("INSERT INTO ATTACHMENT_V1 VALUES(1)")
        self.rejected("populated or unsupported")

    def test_explicitly_omitted_tag_data_is_allowed(self):
        self.change_source("CREATE TABLE TAG_V1(id INTEGER)")
        self.change_source("INSERT INTO TAG_V1 VALUES(1)")
        report = self.run_conversion()
        self.assertEqual(report["omitted_tables"]["TAG_V1"], 1)

    def test_missing_references_are_refused(self):
        self.change_source("UPDATE CHECKINGACCOUNT_V1 SET ACCOUNTID=99 WHERE TRANSID=1")
        self.rejected("Missing transaction reference")

    def test_category_cycles_are_refused(self):
        self.change_source("UPDATE CATEGORY_V1 SET PARENTID=2 WHERE CATEGID=1")
        self.rejected("cycle")

    def test_invalid_source_values_are_refused_without_output(self):
        cases = [
            ("UPDATE CHECKINGACCOUNT_V1 SET STATUS='V' WHERE TRANSID=1", "status"),
            ("UPDATE CHECKINGACCOUNT_V1 SET DELETEDTIME='2024-01-01' WHERE TRANSID=1", "deleted"),
            ("UPDATE CHECKINGACCOUNT_V1 SET TRANSAMOUNT=-1 WHERE TRANSID=1", "Negative"),
            ("UPDATE CHECKINGACCOUNT_V1 SET TRANSAMOUNT=0.001 WHERE TRANSID=1", "rounding"),
            ("UPDATE CHECKINGACCOUNT_V1 SET TRANSDATE='not a date' WHERE TRANSID=1", "calendar"),
            ("UPDATE CHECKINGACCOUNT_V1 SET TRANSDATE='2024-01-01T12:00:00' WHERE TRANSID=1", "non-midnight"),
            ("UPDATE CURRENCYFORMATS_V1 SET SCALE=3 WHERE CURRENCYID=1", "SCALE"),
            ("UPDATE CURRENCYFORMATS_V1 SET BASECONVRATE=0 WHERE CURRENCYID=3", "coefficient"),
            ("UPDATE CURRENCYFORMATS_V1 SET BASECONVRATE=2 WHERE CURRENCYID=1", "base currency coefficient"),
        ]
        for query, fragment in cases:
            with self.subTest(query=query):
                self.source.unlink()
                make_source(self.source)
                self.change_source(query)
                self.rejected(fragment)

    def test_zero_and_unequal_same_currency_transfers_are_preserved(self):
        self.change_source("UPDATE CHECKINGACCOUNT_V1 SET TRANSAMOUNT=0 WHERE TRANSID=1")
        self.change_source("UPDATE CHECKINGACCOUNT_V1 SET TOTRANSAMOUNT=9 WHERE TRANSID=?", (1800000000000001,))
        self.run_conversion()
        with closing(sqlite3.connect(self.output)) as connection:
            self.assertEqual(connection.execute("SELECT amount FROM transactions WHERE id=1").fetchone()[0], "0.00")
            self.assertEqual(connection.execute("SELECT to_amount FROM transactions WHERE id=4").fetchone()[0], "9.00")

    def test_eight_digit_currency_amounts_are_not_rounded_to_cents(self):
        self.change_source("UPDATE ACCOUNTLIST_V1 SET CURRENCYID=4 WHERE ACCOUNTID=1")
        self.change_source("UPDATE CHECKINGACCOUNT_V1 SET TRANSAMOUNT=0.00001234 WHERE TRANSID=?", (1800000000000001,))
        self.run_conversion()
        with closing(sqlite3.connect(self.output)) as connection:
            self.assertEqual(connection.execute("SELECT amount FROM transactions WHERE id=4").fetchone()[0], "0.00001234")
            self.assertEqual(connection.execute("SELECT fee FROM transactions WHERE id=4").fetchone()[0], "0.00000000")

    def test_toronto_offset_uses_occurrence_date_not_update_date(self):
        values = converter.occurrence_fields("2024-01-01", "2024-07-01T18:00:00.123-0400", defaultdict_int())
        self.assertEqual(values, ("2024-01-01T18:00:00", "2024-01-01T18:00:00-05:00", "2024-07-01T22:00:00.123000Z"))

    def test_dst_overlap_uses_earlier_instant_and_gap_is_refused(self):
        stamp = converter.toronto_instant(datetime(2024, 11, 3, 1, 30))
        self.assertEqual(stamp.isoformat(), "2024-11-03T01:30:00-04:00")
        with self.assertRaisesRegex(converter.ConversionError, "gap"):
            converter.toronto_instant(datetime(2024, 3, 10, 2, 30))

    def test_decimal_range_rejects_values_that_normalization_could_round(self):
        for value in ["1" + "0" * 100 + "1", "1e-129", "NaN", "Infinity"]:
            with self.subTest(value=value):
                with self.assertRaises(converter.ConversionError):
                    converter.exact_decimal(value, "synthetic number")
        self.assertEqual(converter.exact_decimal("0.00000001", "synthetic number"), Decimal("0.00000001"))

    def test_target_reconciliation_detects_a_changed_transfer_side(self):
        self.run_conversion()
        with closing(sqlite3.connect(self.source)) as source:
            source.row_factory = sqlite3.Row
            source_data, _ = converter.checked_source(source)
        with closing(sqlite3.connect(self.output)) as target:
            target.row_factory = sqlite3.Row
            expected = {name: [dict(row) for row in target.execute(f'SELECT * FROM "{name}"')]
                        for name in ["currencies", "accounts", "categories", "transactions", "exchange_rates", "app_settings"]}
            target.execute("UPDATE transactions SET to_amount='149.00' WHERE id=3")
            for row in expected["transactions"]:
                if row["id"] == 3:
                    row["to_amount"] = "149.00"
            with self.assertRaisesRegex(converter.ConversionError, "do not reconcile"):
                converter.validate_target(target, source_data, expected, {1: 1, 2: 2, LARGE_ID: 3})

    def test_failed_validation_cleans_staging_and_publishes_nothing(self):
        with patch.object(converter, "validate_target", side_effect=converter.ConversionError("Injected validation failure.")):
            self.rejected("Injected")

    def test_publication_race_preserves_competing_output_and_removes_own_report(self):
        original_link = converter.os.link

        def compete(source, destination):
            if destination == self.output:
                self.output.write_bytes(b"competing file")
            return original_link(source, destination)

        with patch.object(converter.os, "link", side_effect=compete):
            with self.assertRaises(FileExistsError):
                self.run_conversion()
        self.assertEqual(self.output.read_bytes(), b"competing file")
        self.assertFalse(self.report.exists())
        self.assertFalse(list(self.folder.glob(".trexpend-*")))

    def test_canonical_schema_integrity_and_fee_accounting(self):
        self.run_conversion()
        with closing(sqlite3.connect(self.output)) as connection:
            connection.row_factory = sqlite3.Row
            connection.execute("PRAGMA foreign_keys=ON")
            connection.execute("UPDATE transactions SET fee='2.50', fee_account_id=3 WHERE id=3")
            balances, months = converter.target_financials(connection)
            self.assertEqual(balances[3], Decimal("157.50"))
            self.assertEqual(months[(3, "2024-02")]["expense"], Decimal("2.50"))
            for query in ["DELETE FROM accounts WHERE id=2", "DELETE FROM categories WHERE id=2",
                    "DELETE FROM account_images WHERE id=1", "UPDATE transactions SET fee_account_id=1 WHERE id=3",
                    "UPDATE transactions SET amount='-1' WHERE id=1",
                    "UPDATE accounts SET current_balance='1.00' WHERE id=1"]:
                with self.subTest(query=query):
                    with self.assertRaises(sqlite3.IntegrityError):
                        connection.execute(query)


def defaultdict_int():
    from collections import defaultdict
    return defaultdict(int)


if __name__ == "__main__":
    unittest.main()
