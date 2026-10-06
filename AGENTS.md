# Trexpend Agent Instructions

## Repository Language

- English is mandatory for every file committed to this repository.
- All authored text must be English, including source code, comments, documentation, plans, specifications, UI strings, error messages, logs, file names, and commit messages.
- Use ASCII for authored text files and file names. Do not introduce text or language-specific characters from other languages.
- Images and other binary assets must not contain non-English visible text or authored metadata.
- Preserve imported user data exactly, including its original text. Keep personal databases, exports, and other private data outside version control in `local/`. Never rewrite user data to satisfy repository language rules.

## Scope and Working Style

- Follow the latest user instructions and relevant project documentation.
- A request to discuss, investigate, or write a specification does not authorize implementing the application feature.
- Make the smallest change that addresses the task. Avoid unrelated refactoring, renaming, formatting, and speculative abstractions.
- Use existing project patterns. Do not add dependencies, frameworks, or architectural layers without an explicit user request.
- Prefer native Apple APIs and the system SQLite library for the current application.
- Keep documentation consistent with implemented behavior. Distinguish proposed, implemented, and verified work.

## Repository Layout

- `apps/ios/`: the iPhone application and its Xcode project.
- `docs/product-overview.md`: product purpose and current scope.
- `docs/architecture.md`: application architecture and architectural decisions.
- `docs/database.md`: database structure, conventions, and migration behavior.
- `docs/development.md`: environment setup, build, run, and verification instructions.
- `docs/specs/`: feature specifications and behavior decisions.
- `docs/plans/`: active implementation plans.
- `docs/plans/completed/`: completed plans retained for history.
- `assets/`: reference files independent of application resources. Do not reference this folder from the application target.
- `design/`: design files intended for version control.
- `local/`: private data and temporary working files. This entire folder is ignored by Git; do not add a predefined subdirectory structure unless needed.
- `design/logo-exploration/`: temporary experiments excluded from Git.
- Record decisions in the architecture document or the relevant specification. Do not create a separate decisions directory.
- Do not create empty application source hierarchies ahead of implementation. Add folders when they contain actual project files.

## Implementation Plans

- Before implementing a non-trivial feature, or a change to database structure or financial behavior, create or update a plan in `docs/plans/`.
- Small, straightforward edits do not require a new plan unless the user asks for one.
- Use descriptive kebab-case Markdown file names, such as `transaction-editor.md`.
- Read relevant specifications and inspect existing behavior before writing the plan. Identify unresolved requirements instead of inventing decisions.
- Keep each plan proportional to the change and include these sections:
  1. **Purpose**: why the feature or change is needed.
  2. **Goal**: the intended outcome and observable acceptance criteria.
  3. **Scope**: what this change includes and any relevant exclusions.
  4. **Implementation Approach**: how behavior will change, affected components and files, and any risks or unresolved questions.
  5. **Database Changes**: exact migration SQL when applicable, execution order, data preservation, and recovery considerations. Write `None` when no schema or data migration is needed. Do not invent rollback SQL when a change cannot be safely reversed.
  6. **Tasks**: an actionable checklist covering implementation, documentation, and necessary verification.
  7. **Verification Results**: completed checks, remaining checks, and any limitations.
- Every task and subtask must use a Markdown checkbox: `- [ ]` for pending work and `- [x]` for completed work.
- Update checkboxes as work is completed. Check a parent task only after all its subtasks are complete. Do not check tasks for work that is only drafted, partially implemented, or still awaiting required verification.
- Revise the plan when the agreed scope changes. Keep it consistent with the final implementation.
- Move a plan to `docs/plans/completed/` only after its acceptance criteria and required tasks are satisfied. Update references after moving it. Preserve the completed checklist and verification results.
- A plan does not authorize expanding the user's requested scope.

## iOS Project Conventions

- Target iPhone and iOS 27. Do not add older OS support or other platforms unless requested.
- Create the initial application project through Xcode under `apps/ios/`. Do not create an empty or fake `.xcodeproj` placeholder.
- Keep the physical file layout consistent with the Xcode project. Ensure new source files and resources belong to the correct target.
- Commit project settings, application resources, and shared schemes. Do not commit user-specific Xcode settings, signing secrets, build output, or caches.
- Use Swift and SwiftUI. Prefer standard controls, navigation, sheets, and accessibility behavior.
- Keep views focused on presentation and interaction. Keep SQL and financial calculations outside views.
- Use the narrowest appropriate state ownership. Separate editor drafts from persisted records so cancellation does not save changes.
- Refresh affected lists and summaries after successful database writes. Observation alone does not monitor an arbitrary SQLite file.
- Keep expensive database and file operations from blocking the UI, and serialize access to the working database.
- Verify API availability against the actual deployment target and installed SDK. Do not silently lower the target to work around an older local Xcode installation.

## Financial Data and SQLite

- Work with a local SQLite database. Keep the original imported file intact and use a working copy.
- Preserve existing records and relationships, including fields and tags not currently exposed in the UI.
- Use exact decimal calculations or an explicitly defined integer minor-unit representation for money. Do not use binary floating-point arithmetic as the basis of financial calculations.
- Define rounding and conversion rules explicitly. Handle the existing database's numeric storage deliberately; do not change amount representation without a planned migration.
- Calculate balances from opening balances and the relevant transaction history. Calculate monthly income and expenses by transaction date and calendar-month boundaries.
- Exclude transfers between owned accounts from income and expense summaries.
- Treat a transfer as one operation affecting both accounts. Preserve both actual amounts for transfers between currencies; later exchange-rate changes must not rewrite those amounts.
- Preserve calendar dates during import. Avoid unintended date shifts caused by timezone conversion.
- Use bound SQL parameters for values. Finalize statements, close resources correctly, and report database errors without exposing private records.
- Use SQLite transactions for related changes. Confirm a save only after a successful commit; keep the editor draft available after failure.
- Validate replacement imports before switching the working database. A failed import must leave the current database usable. Imports replace data rather than merge it.
- Export a consistent standalone database snapshot using SQLite backup facilities. Do not copy only the main file of an active database without accounting for journal state.
- Version future schema changes and document their SQL and data preservation requirements. Initial import compatibility does not require indefinite compatibility with the original application.

## Verification and Reporting

- Run an appropriate build after changes to application code or Xcode configuration.
- Add or update focused tests for financial calculations, transfer behavior, database migrations, and import/export when those behaviors change.
- Use synthetic test fixtures. Never commit real financial records or identifying data.
- Run relevant existing tests. Do not remove tests to make a change pass or add tests that merely duplicate implementation details.
- Use Simulator or device verification when a change depends on runtime UI or platform behavior. A successful build alone does not confirm runtime behavior.
- For documentation-only changes, check formatting, paths, and English-only content; application tests are not necessary.
- Report what changed, what was verified, and any checks that could not be completed. Do not claim successful verification when the required SDK, device, or tools were unavailable.

## Privacy and Git Configuration

- Treat this repository as public. Never commit personal databases, backups, credentials, keys, or private intermediate files.
- Keep private working files in `local/` and respect `.gitignore`. Do not force-add ignored private data.
- Preserve the computer's work-account setup. Configure personal commit identity and repository authentication locally for this repository; do not change global Git or shared SSH settings without an explicit request.
- Never expose secrets or personal financial data in logs, screenshots, committed documentation, or command output.
