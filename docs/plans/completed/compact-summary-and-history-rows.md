# Compact Summary and History Rows

## Purpose

Reduce summary height and keep transaction amounts legible beside truncated text.

## Goal

Home and account history share a compact card: balance first, month and currency,
then income/expenses and a third difference column only when income is nonzero.
Transaction amounts stay in the trailing column; optional details extend only the
middle column below its two primary lines. Account names on Home keep wrapping.

## Scope

Presentation changes only. Move the account favorite indicator to the trailing
navigation toolbar. Favorite mutation remains future work. Remove counterpart
amount captions from history rows; preserve the underlying stored/read amounts.

## Implementation Approach

Reuse a shared summary view with explicit values. Calculate the account difference
outside views with existing Decimal arithmetic. Use equal flexible summary columns
and smaller scalable figures; stack metrics at accessibility sizes. Transaction
rows use a two-line primary identity as their alignment anchor, with optional
category/notes/fee lines underneath; the icon and amount remain aligned with the
primary identity. Truncate central text to one line. Native amounts omit currency;
fees retain their explicit currency/account attribution. Prioritize complete amounts
and allow reduced type size for unusually long figures without a stacked fallback.

## Database Changes

None.

## Tasks

- [x] Implement shared compact summary and account difference projection.
- [x] Move favorite indicator to the toolbar without an inactive button.
- [x] Implement anchored three-column transaction rows and remove counterpart captions.
- [x] Update affected specifications and run focused calculation tests/build.
- [x] Inspect normal/long text layouts on the existing running Simulator without rebooting it.

## Verification Results

The iOS 27 app build succeeded. On the existing running Simulator, inspected
Home with three metrics, an account with zero income/two metrics, and an account
with income/three metrics. Filled/outline toolbar stars rendered in both states.
Transfer and long-category income rows kept native amounts at the trailing edge;
notes/category details stayed beneath the primary identity in the middle column.
Home account names retained multiline layout. The Simulator was not rebooted or
erased. The app was rebuilt/relaunched to install the updated code.

All 8 focused account-history test functions passed, including the native
account difference assertion. The build reported no warnings or errors.
`git diff --check` and authored-file ASCII checks passed. Maximum Dynamic Type and extreme-width monetary
strings have not been visually exercised in this refinement; the layout scales
figures and switches summary metrics to a vertical arrangement at accessibility
sizes. Real financial data was not modified for UI verification.

## Follow-up: Centered Metrics (2026-10-28)

Income, expense, and conditional difference cells retain equal flexible widths.
Their headings and values now align to the center of each cell to remove the
visual left bias, including the two-column state. This is presentation only;
no financial calculations or database behavior changed. The iOS Simulator build
passed and `git diff --check` passed. The three-column Home card was visually
confirmed on the existing Simulator. The attempted automation tap did not open
account history, so its two-column state was not independently recaptured in this
follow-up; both screens use the same updated metric component.

## Follow-up: Approximate Balance Placement (2026-10-28)

Display the converted balance directly beneath the native amount, right-aligned,
with an approximation symbol and secondary caption styling. Keep the currency code
on this equivalent and retain the spoken Approximately accessibility label. Bank
metadata and missing-rate explanations remain separate. The iOS Simulator build
passed; the foreign-currency account layout was visually verified without rebooting
the Simulator. No calculations or persisted data changed.
