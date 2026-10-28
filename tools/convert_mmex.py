#!/usr/bin/env python3
"""Convert a supported standalone MMEX export into a new Trexpend v1 database."""

import argparse
from collections import defaultdict
from contextlib import closing
from datetime import datetime, timezone
from decimal import Decimal, DecimalException, Inexact, InvalidOperation, ROUND_HALF_UP, localcontext
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
from zoneinfo import ZoneInfo


SCHEMA_PATH = Path(__file__).resolve().parents[1] / "database/migrations/001_initial.sql"
APPLICATION_ID = 0x54525850
SCHEMA_VERSION = 2
SOURCE_VERSION = 20
TORONTO = ZoneInfo("America/Toronto")
TYPE_IDS = {"Withdrawal": 1, "Deposit": 2, "Transfer": 3}
ACCOUNT_TYPES = {"Checking": 1, "Credit Card": 2, "Cash": 3, "Term": 4}
ACCOUNT_STATUSES = {"Open": 1, "Closed": 2}
CORE_COLUMNS = {
    "ACCOUNTLIST_V1": "ACCOUNTID ACCOUNTNAME ACCOUNTTYPE ACCOUNTNUM STATUS NOTES HELDAT WEBSITE CONTACTINFO ACCESSINFO INITIALBAL INITIALDATE FAVORITEACCT CURRENCYID STATEMENTLOCKED STATEMENTDATE MINIMUMBALANCE CREDITLIMIT INTERESTRATE PAYMENTDUEDATE MINIMUMPAYMENT".split(),
    "CHECKINGACCOUNT_V1": "TRANSID ACCOUNTID TOACCOUNTID PAYEEID TRANSCODE TRANSAMOUNT STATUS TRANSACTIONNUMBER NOTES CATEGID TRANSDATE LASTUPDATEDTIME DELETEDTIME FOLLOWUPID TOTRANSAMOUNT COLOR".split(),
    "CATEGORY_V1": "CATEGID CATEGNAME ACTIVE PARENTID".split(),
    "CURRENCYFORMATS_V1": "CURRENCYID CURRENCYNAME PFX_SYMBOL SFX_SYMBOL DECIMAL_POINT GROUP_SEPARATOR UNIT_NAME CENT_NAME SCALE BASECONVRATE CURRENCY_SYMBOL CURRENCY_TYPE".split(),
    "INFOTABLE_V1": "INFOID INFONAME INFOVALUE".split(),
}
OMITTED_TABLES = {"PAYEE_V1", "TAG_V1", "TAGLINK_V1", "CURRENCYHISTORY_V1"}
DEFERRED_TABLES = {
    "ASSETS_V1", "ATTACHMENT_V1", "BILLSDEPOSITS_V1", "BUDGETSPLITTRANSACTIONS_V1",
    "BUDGETTABLE_V1", "BUDGETYEAR_V1", "CUSTOMFIELDDATA_V1", "CUSTOMFIELD_V1",
    "REPORT_V1", "SHAREINFO_V1", "SPLITTRANSACTIONS_V1", "STOCKHISTORY_V1",
    "STOCK_V1", "TRANSLINK_V1",
}


class ConversionError(Exception):
    """A safe, non-record-bearing explanation of a failed conversion."""


def require(condition, message):
    if not condition:
        raise ConversionError(message)


def text(value, field, nullable=False):
    if nullable and value is None:
        return None
    require(isinstance(value, str), f"Invalid text in {field}.")
    return value


def integer(value, field, positive=False):
    require(isinstance(value, int) and not isinstance(value, bool), f"Invalid integer in {field}.")
    require(not positive or value > 0, f"Invalid positive ID in {field}.")
    return value


def exact_decimal(value, field):
    # SQLite REAL has already lost its original spelling. Normalize its shortest
    # round-trip representation; never perform binary floating-point arithmetic.
    require(isinstance(value, (str, int, float)) and not isinstance(value, bool), f"Invalid number in {field}.")
    try:
        result = Decimal(str(value))
        require(result.is_finite(), f"Nonfinite number in {field}.")
        parts = result.as_tuple()
        digits, exponent = list(parts.digits), parts.exponent
        while len(digits) > 1 and digits[-1] == 0:
            digits.pop()
            exponent += 1
        if result == 0:
            digits, exponent = [0], 0
        require(len(digits) <= 38 and -128 <= exponent <= 127,
                f"Number exceeds the supported Decimal range in {field}.")
        return result
    except InvalidOperation as error:
        raise ConversionError(f"Invalid decimal in {field}.") from error


def money(value, places, field, signed=False):
    result = exact_decimal(value, field)
    require(signed or result >= 0, f"Negative amount in {field}.")
    with localcontext() as context:
        context.prec = 100
        rounded = result.quantize(Decimal(1).scaleb(-places), rounding=ROUND_HALF_UP)
    require(result == rounded, f"Source amount needs rounding in {field}; review before conversion.")
    return format(abs(rounded) if rounded == 0 else rounded, f".{places}f")


def scale_places(value):
    scale = integer(value, "SCALE", positive=True)
    places = 0
    while scale > 1 and scale % 10 == 0:
        scale //= 10
        places += 1
    require(scale == 1 and places <= 18, "Unsupported currency SCALE.")
    return places


def parse_datetime(value, field):
    try:
        result = datetime.fromisoformat(text(value, field))
        return result
    except ValueError as error:
        raise ConversionError(f"Invalid calendar value in {field}.") from error


def toronto_instant(local, overlap_counter=None):
    require(local.tzinfo is None, "Expected local calendar components.")
    candidates = {}
    for fold in (0, 1):
        candidate = local.replace(tzinfo=TORONTO, fold=fold)
        instant = candidate.astimezone(timezone.utc)
        if instant.astimezone(TORONTO).replace(tzinfo=None) == local:
            candidates[instant] = candidate
    require(bool(candidates), "A source local time falls in a daylight-saving gap.")
    if len(candidates) > 1 and overlap_counter is not None:
        overlap_counter["earlier_dst_occurrences"] += 1
    return candidates[min(candidates)]


def utc_text(value):
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def occurrence_fields(source_date, last_update, counters):
    day = parse_datetime(source_date, "TRANSDATE")
    require(day.tzinfo is None and day.hour == day.minute == day.second == day.microsecond == 0,
            "Unsupported occurrence time in TRANSDATE; do not discard non-midnight values.")
    require(day.date() <= datetime.now(TORONTO).date(), "Source contains a future occurrence date.")
    update = parse_datetime(last_update, "LASTUPDATEDTIME")
    local = datetime.combine(day.date(), update.time().replace(tzinfo=None, microsecond=0))
    occurrence = toronto_instant(local, counters)
    if update.tzinfo is None:
        update = toronto_instant(update, counters)
    return local.isoformat(timespec="seconds"), occurrence.isoformat(timespec="seconds"), utc_text(update)


def read_rows(connection, table):
    # Identifiers come exclusively from constants or validated sqlite_master rows.
    quoted = '"' + table.replace('"', '""') + '"'
    return [dict(row) for row in connection.execute("SELECT * FROM " + quoted)]


def checked_source(connection):
    require(connection.execute("PRAGMA user_version").fetchone()[0] == SOURCE_VERSION,
            "Unsupported MMEX schema version; expected user_version 20.")
    require([row[0] for row in connection.execute("PRAGMA integrity_check")] == ["ok"],
            "Source integrity check failed.")
    names = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    for table, columns in CORE_COLUMNS.items():
        require(table in names, "A required MMEX source table is missing.")
        actual = {row[1] for row in connection.execute(f'PRAGMA table_info("{table}")')}
        require(actual == set(columns), f"Unsupported source columns in {table}.")
    omitted = {}
    for table in sorted(names - set(CORE_COLUMNS)):
        require(not table.startswith("sqlite_"), "Unexpected internal source table.")
        rows = read_rows(connection, table)
        if table in OMITTED_TABLES:
            omitted[table] = len(rows)
        else:
            require(table in DEFERRED_TABLES and not rows,
                    "Unexpected populated or unsupported source table; review the mapping.")
    data = {table: read_rows(connection, table) for table in CORE_COLUMNS}
    return data, omitted


def keyed(rows, key):
    result = {}
    for row in rows:
        identity = integer(row[key], key, positive=True)
        require(identity not in result, "Duplicate source ID.")
        result[identity] = row
    return result


def account_id_map(ids):
    # Keep compact IDs, fill their gaps with the remaining legacy outliers.
    ordered = sorted(ids)
    mapping = {old: old for old in ordered if old <= len(ordered)}
    free = iter(index for index in range(1, len(ordered) + 1) if index not in mapping.values())
    for old in ordered:
        if old not in mapping:
            mapping[old] = next(free)
    return mapping


def check_category_tree(categories):
    for identity in categories:
        seen = set()
        current = identity
        while current not in (None, -1):
            require(current in categories, "Missing category parent.")
            require(current not in seen, "Source category hierarchy has a cycle.")
            seen.add(current)
            current = categories[current]["PARENTID"]


def insert_rows(connection, table, rows):
    if not rows:
        return
    columns = list(rows[0])
    query = f'INSERT INTO "{table}" (' + ", ".join('"' + col + '"' for col in columns) + ") VALUES ("
    query += ", ".join("?" for _ in columns) + ")"
    connection.executemany(query, [tuple(row[col] for col in columns) for row in rows])


def mapped_data(source, written_at):
    currencies = keyed(source["CURRENCYFORMATS_V1"], "CURRENCYID")
    accounts = keyed(source["ACCOUNTLIST_V1"], "ACCOUNTID")
    categories = keyed(source["CATEGORY_V1"], "CATEGID")
    transactions = keyed(source["CHECKINGACCOUNT_V1"], "TRANSID")
    require(bool(currencies) and bool(accounts) and bool(categories), "Source has no usable ledger reference data.")
    check_category_tree(categories)
    mapping = account_id_map(accounts)
    tx_mapping = {old: index for index, old in enumerate(sorted(transactions), 1)}
    counters = defaultdict(int)
    target = {name: [] for name in ("currencies", "categories", "accounts", "transactions", "exchange_rates", "app_settings")}
    precisions = {}
    codes = set()
    for identity, row in sorted(currencies.items()):
        code = text(row["CURRENCY_SYMBOL"], "CURRENCY_SYMBOL")
        require(bool(code.strip()) and code.upper() not in codes, "Missing or duplicate currency code.")
        codes.add(code.upper())
        places = scale_places(row["SCALE"])
        precisions[identity] = places
        kind = row["CURRENCY_TYPE"]
        require(kind in ("Fiat", "Crypto"), "Unknown source currency type.")
        prefix = text(row["PFX_SYMBOL"], "PFX_SYMBOL", nullable=True)
        suffix = text(row["SFX_SYMBOL"], "SFX_SYMBOL", nullable=True)
        target["currencies"].append(dict(
            id=identity, code=code, name=text(row["CURRENCYNAME"], "CURRENCYNAME"),
            symbol=prefix or suffix or None, decimal_places=places,
            prefix_symbol=prefix, suffix_symbol=suffix,
            decimal_separator=text(row["DECIMAL_POINT"], "DECIMAL_POINT", nullable=True),
            group_separator=text(row["GROUP_SEPARATOR"], "GROUP_SEPARATOR", nullable=True),
            unit_name=text(row["UNIT_NAME"], "UNIT_NAME", nullable=True),
            subunit_name=text(row["CENT_NAME"], "CENT_NAME", nullable=True), currency_type=kind.lower()))
    for identity, row in sorted(categories.items()):
        require(row["ACTIVE"] in (0, 1), "Invalid category active flag.")
        target["categories"].append(dict(id=identity, name=text(row["CATEGNAME"], "CATEGNAME"),
            parent_id=None if row["PARENTID"] in (None, -1) else row["PARENTID"],
            is_active=row["ACTIVE"], favorite=0))
    for identity, row in sorted(accounts.items()):
        currency = row["CURRENCYID"]
        require(currency in currencies, "Missing account currency.")
        require(row["ACCOUNTTYPE"] in ACCOUNT_TYPES, "Unknown source account type.")
        require(row["STATUS"] in ACCOUNT_STATUSES, "Unknown source account status.")
        require(row["FAVORITEACCT"] in ("TRUE", "FALSE"), "Invalid account favorite flag.")
        opened = parse_datetime(row["INITIALDATE"], "INITIALDATE")
        require(opened.tzinfo is None, "Unexpected offset on account INITIALDATE.")
        stamp = utc_text(toronto_instant(datetime.combine(opened.date(), datetime.min.time()), counters))
        target["accounts"].append(dict(id=mapping[identity], name=text(row["ACCOUNTNAME"], "ACCOUNTNAME"),
            currency_id=currency, initial_balance=money(row["INITIALBAL"], precisions[currency], "INITIALBAL", signed=True),
            current_balance=None, open_date=opened.date().isoformat(), exp_date=None, close_date=None,
            status=ACCOUNT_STATUSES[row["STATUS"]], account_type=ACCOUNT_TYPES[row["ACCOUNTTYPE"]],
            account_number=text(row["ACCOUNTNUM"], "ACCOUNTNUM", nullable=True), bank=None,
            credit_limit=money(0, precisions[currency], "CREDITLIMIT"), favorite=int(row["FAVORITEACCT"] == "TRUE"),
            image_id=None, color=None, notes=text(row["NOTES"], "NOTES", nullable=True), created_at=stamp, updated_at=stamp))
    for identity, row in sorted(transactions.items()):
        kind = row["TRANSCODE"]
        require(kind in TYPE_IDS, "Unknown source transaction type.")
        require(row["STATUS"] == "R", "Unsupported source transaction status; review before conversion.")
        require(row["DELETEDTIME"] in (None, ""), "Source contains deleted transactions; review before conversion.")
        require(row["FOLLOWUPID"] in (None, -1) and row["COLOR"] in (None, -1),
                "Source contains unsupported transaction review/color metadata.")
        require(row["ACCOUNTID"] in accounts and row["CATEGID"] in categories, "Missing transaction reference.")
        account = accounts[row["ACCOUNTID"]]
        places = precisions[account["CURRENCYID"]]
        amount = money(row["TRANSAMOUNT"], places, "TRANSAMOUNT")
        destination = None
        received = None
        if kind == "Transfer":
            require(row["TOACCOUNTID"] in accounts and row["TOACCOUNTID"] != row["ACCOUNTID"], "Invalid transfer destination.")
            destination = mapping[row["TOACCOUNTID"]]
            target_places = precisions[accounts[row["TOACCOUNTID"]]["CURRENCYID"]]
            received = money(row["TOTRANSAMOUNT"], target_places, "TOTRANSAMOUNT")
        else:
            require(row["TOACCOUNTID"] in (None, -1, 0), "Non-transfer has a recipient account.")
            extra = exact_decimal(row["TOTRANSAMOUNT"], "TOTRANSAMOUNT")
            require(extra == 0 or extra == Decimal(amount), "Non-transfer has an unexplained receiver amount.")
            counters["normalized_nontransfer_receiver_fields"] += int(extra != 0)
        local, offset, updated = occurrence_fields(row["TRANSDATE"], row["LASTUPDATEDTIME"], counters)
        target["transactions"].append(dict(id=tx_mapping[identity], transaction_type=TYPE_IDS[kind],
            account_id=mapping[row["ACCOUNTID"]], amount=amount, to_account_id=destination, to_amount=received,
            date=local, date_with_offset=offset, category_id=row["CATEGID"], notes=text(row["NOTES"], "NOTES", nullable=True),
            fee=money(0, places, "fee"), fee_account_id=mapping[row["ACCOUNTID"]] if kind == "Transfer" else None,
            created_at=updated, updated_at=updated))
    info = {}
    for row in source["INFOTABLE_V1"]:
        require(row["INFONAME"] not in info, "Duplicate source setting key.")
        info[row["INFONAME"]] = row["INFOVALUE"]
    try:
        base = int(info["BASECURRENCYID"])
        default = info.get("android:default_account_id")
        default = None if default in (None, "", "-1", "0") else int(default)
    except (KeyError, TypeError, ValueError) as error:
        raise ConversionError("Invalid source base currency or default account setting.") from error
    require(base in currencies, "Missing source base currency reference.")
    require(exact_decimal(currencies[base]["BASECONVRATE"], "base BASECONVRATE") == 1,
            "Source base currency coefficient must be one.")
    require(default is None or default in accounts, "Missing default account reference.")
    if default is not None and accounts[default]["STATUS"] != "Open":
        default = None
        counters["closed_default_accounts_cleared"] += 1
    target["app_settings"].append(dict(id=1, display_currency_id=base,
        default_account_id=mapping[default] if default is not None else None,
        user_name=text(info.get("USERNAME"), "USERNAME", nullable=True)))
    used = {row["CURRENCYID"] for row in accounts.values()}
    for currency in sorted(used - {base}):
        rate = exact_decimal(currencies[currency]["BASECONVRATE"], "BASECONVRATE")
        require(rate > 0, "Invalid used-currency coefficient.")
        target["exchange_rates"].append(dict(id=len(target["exchange_rates"]) + 1,
            from_currency_id=currency, to_currency_id=base, rate=format(rate, "f"), updated_at=written_at))
        if rate == 1:
            counters["legacy_nonbase_parity_rates"] += 1
    return target, mapping, tx_mapping, dict(counters)


def source_financials(source, account_map):
    """Aggregate the source directly, independently of the target-row mapper."""
    balances = {account_map[row["ACCOUNTID"]]: exact_decimal(row["INITIALBAL"], "INITIALBAL")
                for row in source["ACCOUNTLIST_V1"]}
    months = defaultdict(lambda: {"income": Decimal(0), "expense": Decimal(0)})
    for row in source["CHECKINGACCOUNT_V1"]:
        account = account_map[row["ACCOUNTID"]]
        amount = exact_decimal(row["TRANSAMOUNT"], "TRANSAMOUNT")
        month = row["TRANSDATE"][:7]
        if row["TRANSCODE"] == "Deposit":
            balances[account] += amount
            months[(account, month)]["income"] += amount
        else:
            balances[account] -= amount
            if row["TRANSCODE"] == "Transfer":
                balances[account_map[row["TOACCOUNTID"]]] += exact_decimal(row["TOTRANSAMOUNT"], "TOTRANSAMOUNT")
            else:
                months[(account, month)]["expense"] += amount
    return balances, dict(months)


def target_financials(connection):
    balances = {row["id"]: Decimal(row["initial_balance"]) for row in connection.execute("SELECT * FROM accounts")}
    months = defaultdict(lambda: {"income": Decimal(0), "expense": Decimal(0)})
    for row in connection.execute("SELECT * FROM transactions"):
        account = row["account_id"]
        value = Decimal(row["amount"])
        month = row["date"][:7]
        if row["transaction_type"] == 1:
            balances[account] -= value
            months[(account, month)]["expense"] += value
        elif row["transaction_type"] == 2:
            balances[account] += value
            months[(account, month)]["income"] += value
        else:
            balances[account] -= value
            balances[row["to_account_id"]] += Decimal(row["to_amount"])
        fee = Decimal(row["fee"])
        if fee:
            balances[row["fee_account_id"]] -= fee
            months[(row["fee_account_id"], month)]["expense"] += fee
    return balances, dict(months)


def validate_target(connection, source, expected, account_map):
    require(connection.execute("PRAGMA application_id").fetchone()[0] == APPLICATION_ID,
            "Target file identity validation failed.")
    require(connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION,
            "Target schema version validation failed.")
    require([row[0] for row in connection.execute("PRAGMA integrity_check")] == ["ok"],
            "Target integrity validation failed.")
    require(not connection.execute("PRAGMA foreign_key_check").fetchall(), "Target foreign-key validation failed.")
    for table, wanted in expected.items():
        got = {row["id"]: dict(row) for row in connection.execute(f'SELECT * FROM "{table}"')}
        require(got == {row["id"]: row for row in wanted}, f"Target record/text mapping failed for {table}.")
    with localcontext() as context:
        context.prec = 100
        context.traps[Inexact] = True
        original = source_financials(source, account_map)
        converted = target_financials(connection)
    require(original == converted, "Native balances or calendar-month totals do not reconcile.")
    for value in converted[0].values():
        exact_decimal(value.to_eng_string(), "reconciled balance")
    for totals in converted[1].values():
        for value in totals.values():
            exact_decimal(value.to_eng_string(), "reconciled monthly total")
    return {
        "balances": {str(key): format(value, "f") for key, value in sorted(converted[0].items())},
        "monthly_totals": [dict(account_id=key[0], month=key[1],
            income=format(value["income"], "f"), expense=format(value["expense"], "f"))
            for key, value in sorted(converted[1].items())],
    }


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def check_standalone(path):
    require(not any(Path(str(path) + suffix).exists() for suffix in ("-wal", "-shm", "-journal")),
            "Source has journal companions; use a closed, standalone MMEX export.")


def staged_path(destination):
    handle, name = tempfile.mkstemp(prefix=".trexpend-", suffix=".tmp", dir=destination.parent)
    os.close(handle)
    return Path(name)



def upgrade_target(connection, expected):
    migration = SCHEMA_PATH.with_name("002_category_icons_and_history.sql")
    mapping_path = SCHEMA_PATH.parents[1] / "seeds/002_category_icon_defaults.json"
    connection.executescript("BEGIN;\n" + migration.read_text(encoding="ascii"))
    categories = {row["id"]: row for row in expected["categories"]}
    paths = {}
    for identity, row in categories.items():
        path, current, seen = [], identity, set()
        while current is not None:
            require(current not in seen and current in categories, "Invalid category path.")
            seen.add(current)
            node = categories[current]
            path.insert(0, node["name"])
            current = node["parent_id"]
        paths.setdefault(tuple(path), []).append(identity)
        row["icon_id"] = None
    catalog = [dict(row) for row in connection.execute("SELECT * FROM category_icons ORDER BY id")]
    icons = {row["code"]: row["id"] for row in catalog}
    for mapping in json.loads(mapping_path.read_text(encoding="ascii")):
        matches = paths.get(tuple(mapping["path"]), [])
        if len(matches) == 1:
            identity = matches[0]
            icon = icons[mapping["code"]]
            connection.execute("UPDATE categories SET icon_id=? WHERE id=? AND icon_id IS NULL", (icon, identity))
            categories[identity]["icon_id"] = icon
    expected["category_icons"] = catalog
    connection.execute("PRAGMA user_version = 2")
    connection.commit()


def convert(source_path, output_path, report_path=None):
    source_path = Path(source_path).resolve(strict=True)
    output_path = Path(output_path).absolute()
    report_path = Path(report_path).absolute() if report_path is not None else None
    require(source_path.is_file(), "Source must be a regular file.")
    destinations = [output_path] + ([report_path] if report_path is not None else [])
    require(len({str(path.resolve()) for path in destinations + [source_path, SCHEMA_PATH]}) == len(destinations) + 2,
            "Source, output, report, and schema paths must be different.")
    for destination in destinations:
        require(destination.parent.is_dir(), "A destination parent directory does not exist.")
        require(not os.path.lexists(destination), "A destination already exists; choose a new path.")
    check_standalone(source_path)
    source_hash = digest(source_path)
    with closing(sqlite3.connect(source_path.as_uri() + "?mode=ro", uri=True, timeout=5)) as source_db:
        source_db.row_factory = sqlite3.Row
        source_db.execute("PRAGMA query_only = ON")
        source_db.execute("BEGIN")
        source, omitted = checked_source(source_db)
    written_at = utc_text(datetime.now(timezone.utc))
    expected, accounts, transactions, counters = mapped_data(source, written_at)
    staged = staged_path(output_path)
    staged_report = None
    published = []
    try:
        with closing(sqlite3.connect(staged)) as target:
            target.row_factory = sqlite3.Row
            target.executescript(SCHEMA_PATH.read_text(encoding="ascii"))
            target.execute("BEGIN")
            for table, rows in expected.items():
                insert_rows(target, table, rows)
            target.commit()
            upgrade_target(target, expected)
            reconciliation = validate_target(target, source, expected, accounts)
        # Reopen independently, with no live SQLite connection or journal needed.
        with closing(sqlite3.connect(staged.as_uri() + "?mode=ro", uri=True)) as reopened:
            reopened.row_factory = sqlite3.Row
            validate_target(reopened, source, expected, accounts)
        require(digest(source_path) == source_hash, "Source changed during conversion; output was not published.")
        check_standalone(source_path)
        report = dict(schema_version=SCHEMA_VERSION, application_id=APPLICATION_ID,
            source_user_version=SOURCE_VERSION, source_sha256=source_hash, output_sha256=digest(staged),
            schema_sha256=digest(SCHEMA_PATH),
            counts={key: len(rows) for key, rows in expected.items()}, omitted_tables=omitted,
            account_id_map=accounts, transaction_id_map=transactions, notices=counters,
            reconciliation=reconciliation, checks="passed", written_at=written_at)
        if report_path is not None:
            staged_report = staged_path(report_path)
            staged_report.write_text(json.dumps(report, indent=2, ensure_ascii=True) + "\n", encoding="ascii")
        for temporary, destination in [(staged_report, report_path), (staged, output_path)]:
            if temporary is not None:
                with temporary.open("rb") as stream:
                    os.fsync(stream.fileno())
                # Hard-link publication is atomic and fails if the path exists.
                os.link(temporary, destination)
                published.append((temporary, destination))
        return report
    except BaseException:
        for temporary, destination in reversed(published):
            if destination.exists() and os.path.samestat(temporary.stat(), destination.stat()):
                destination.unlink()
        raise
    finally:
        for temporary in (staged, staged_report):
            if temporary is not None:
                temporary.unlink(missing_ok=True)
                for suffix in ("-journal", "-wal", "-shm"):
                    Path(str(temporary) + suffix).unlink(missing_ok=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="Standalone MMEX v20 SQLite export (read-only).")
    parser.add_argument("--output", required=True, type=Path, help="New Trexpend SQLite file; existing paths are never overwritten.")
    parser.add_argument("--report", type=Path, help="Optional new private JSON reconciliation report; keep outside version control.")
    args = parser.parse_args(argv)
    try:
        report = convert(args.source, args.output, args.report)
    except ConversionError as error:
        print(f"Conversion failed: {error}", file=sys.stderr)
        return 1
    except (sqlite3.Error, OSError, DecimalException, OverflowError):
        print("Conversion failed: a database, numeric, or file operation failed. No source records are printed.", file=sys.stderr)
        return 1
    print(f"Conversion passed: {report['counts']['accounts']} accounts, {report['counts']['transactions']} transactions. Source unchanged.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
