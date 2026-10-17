# MMEX Converter

## Purpose

Create the first independent Trexpend dataset without modifying the original MMEX
export or embedding compatibility code in the iPhone application.

## Goal

A reusable offline command converts compatible exports into a fresh standalone
Trexpend v1 SQLite file, verifies record mappings and Decimal financial parity,
and optionally writes a private reconciliation report. Existing destinations and
the source must survive every failure. The real source conversion must reconcile
before its result is reported ready for subsequent application work.

## Scope

Include canonical schema/seeds, Python standard-library conversion, synthetic
tests, documentation, and a private trial conversion. Exclude iPhone database UI,
rate downloads, merging, automatic file replacement, and speculative MMEX formats.

## Implementation Approach

- Put authoritative v1 SQL in database/migrations/001_initial.sql. The future app
  must bundle/use this file rather than hand-copy its schema.
- Implement tools/convert_mmex.py with sqlite3, decimal, zoneinfo, and safe staged
  filesystem output. Verify the source shape and supported values before mapping.
- Normalize source numeric values deliberately from their SQLite representation;
  never use floating-point sums or approximate SQL financial aggregation.
- Use Toronto for approved historical timestamp assumptions, choosing the earlier
  instant in a repeated local hour; preserve original accounting calendar dates.
- Use private reports for ID maps and per-account/per-month reconciliation. Print
  only generic success/error information and counts on the console.
- Fail on unexpected populated deferred features, deletion markers, incompatible
  statuses, missing references, unrepresentable values, and unknown source shapes.

## Database Changes

This creates a new file; it does not migrate the source in place. Exact DDL and
seed SQL are maintained once in [001_initial.sql](../../../database/migrations/001_initial.sql).
Execution order: create a fresh staged target, execute canonical schema/seeds,
insert mapped currencies/categories/accounts/transactions/settings/rates in one
transaction, validate, close, then publish without replacing an existing path.

Use application_id 0x54525850 and user_version 1. Initial reference IDs are fixed
for this schema version. Monetary scale follows currencies.decimal_places and
is validated in code, not through SQLite REAL casts. No rollback SQL against the
source is needed or allowed; discard a failed staged destination. Preserve a
completed destination independently of the source. Future upgrades need a new plan.

## Tasks

- [x] Finalize canonical schema and document technical choices.
- [x] Implement source validation, field mapping, and exact decimal/date codecs.
- [x] Implement independent target reconciliation and private reporting.
- [x] Implement staged no-overwrite output and safe error handling.
- [x] Add and run synthetic success/failure tests.
- [x] Run and verify a private conversion of the real source.
- [x] Update usage/specification/status documentation and record verification.

## Verification Results

Completed on 2026-10-16 with Python 3.13.1 and SQLite 3.51.0.

- python3 -B -m unittest discover -s tools/tests -v: all 21 synthetic tests passed.
- CLI help and static Python syntax checks passed; no third-party packages added.
- Authored text is ASCII; local documentation links and git diff --check passed.
- A private real-source conversion and report were created under ignored local/.
  Source hashes before/after matched. Independent target reopening and file hashes
  passed, as did exact record/text mappings, FK/integrity checks, native balances,
  every account/calendar-month income and expense total, transfer fees, remapped
  account IDs, and the unused current_balance column.
- Source receiver-field normalization and the earlier DST-hour convention were
  reported privately. Source parity rates were preserved, not refreshed.
- Existing-output and publication-race tests confirm no overwrite and staging cleanup.
- No iPhone source/configuration changed; no iOS build or runtime claim is made.
  App database import, financial UI, illustrations, rate refresh, and snapshot
  restore remain separate implementation stages, outside this plan's acceptance.

No required converter verification remains. Schema upgrade code is deliberately
not implemented until a later schema version requires it.
