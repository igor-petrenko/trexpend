# Development and Offline Conversion

## Current Status

The iPhone project is apps/ios/Trexpend/Trexpend.xcodeproj. Its UI is still the
branded placeholder; application persistence/import is not implemented. The
desktop MMEX converter and canonical Trexpend v1 schema are implemented separately.

## Converter Requirements

- Python 3.11 or newer, standard library only, with SQLite and America/Toronto
  timezone data available. No pip packages are required on the tested macOS host.
- A standalone SQLite MMEX export with user_version 20 and the supported source
  columns described in the [mapping](specs/mmex-conversion.md).
- Existing output directories; choose unused destination names. A source with
  -wal, -shm, or -journal companions is refused. Export/close MMEX first.

## Run the Converter

From the repository root:

```sh
python3 -B tools/convert_mmex.py \
  --source local/init_export_db.mmb \
  --output local/new-ledger.sqlite \
  --report local/new-ledger.report.json
```

The report is optional. It contains private ID maps, balances, and account/month
totals: keep it in ignored local/ or outside version control. Console output is
limited to generic results and counts. All source and target text, including
non-English imported user data, is preserved rather than translated.

The command does not overwrite existing files. For another conversion choose new
output/report names. It produces an independent dataset and never merges existing
Trexpend edits. Rate downloads do not run. The destination is published only after
validation and independent reopening. Keep the original export for recovery.

Unsupported populated features/statuses or amounts requiring currency rounding
cause a clear failure, not silent data loss. Compatibility is deliberately bounded;
different future MMEX structures may require converter changes.

## Verification

```sh
python3 -B -m unittest discover -s tools/tests -v
```

Synthetic tests cover mapping, financial totals, text preservation, zero/unequal
transfer amounts, eight-digit currency precision, Toronto offsets/DST, FK checks,
invalid source data, no-overwrite behavior, and staging/publication failures.

The private trial output is local/trexpend.sqlite, with report
local/trexpend.report.json. Neither belongs in Git or the iPhone target. A successful
conversion and standalone reopen do not imply iPhone import/runtime verification.

## Schema Ownership

Use [001_initial.sql](../database/migrations/001_initial.sql) as the single schema
definition. See [v1 contract](specs/database-schema.md) for constraints and limits.
The future iPhone storage implementation must add the canonical SQL as a resource
and validate/migrate supported Trexpend snapshots; it must not embed MMEX SQL.
