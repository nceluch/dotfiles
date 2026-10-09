# Green Team (GT) — Claude instructions

These are the RoadRunner green team's instructions. GT owns finance in Coyote (`RoadRunnerEngineering/coyote`): invoicing, payments (Helcim card, ACH, autopay), invoice lines, adjustments (shared with Purple team), exports, and automated corrections. Tickets are `GT-####` in Jira (`roadrunnerwm.atlassian.net`).

The instructions below apply when working in the Coyote repo. Coyote's own `CLAUDE.md` holds the repo-wide conventions (callback keywords, `build` vs `create`, Sidekiq queues, minimal comments, migrations). This file only adds GT-specific rules on top of it. If the two conflict, follow the repo file and tell me about the conflict.

---

## AI working agreements (hard rules)

- **No commits, pushes, or PRs.** Never run `git commit`, `git push`, or `gh pr create`, and never add yourself as a co-author. I commit and open PRs myself. Staging changes or suggesting a commit message is fine.
- **No GitHub writes.** No PR comments, reviews, approvals, replies, or resolving threads. Write review feedback in the terminal and I decide what to post.
- **No Jira writes.** Reading tickets, descriptions, and comments is encouraged. Don't comment on, edit, or transition tickets.
- **No production database queries.** If a question needs prod data (for example, "how many records actually hit this branch?"), give me the query and I'll run it.

---

## Before writing code: read the ticket

- Fetch the GT ticket from Jira and read the whole description and all comments. Refinement notes often sit at the **bottom** (for example, "use invoice_lines NOT invoice_x_lines"). Treat "do NOT" lines as scope decisions.
- Treat the ticket's acceptance criteria as the source of truth. If the ticket and the RFC/Confluence disagree, follow the ticket and mention the difference in the PR description.
- Don't go beyond the ticket's scope. If a refactor or fix is clearly worth doing, suggest it as a follow-up ticket instead of doing it now.
- If the ticket is ambiguous about a design decision, ask me. Don't pick one quietly.

---

## Domain glossary

<!-- TODO(team): verify and extend -->

| Term | Meaning |
|---|---|
| **CBS** | `CostBasedService`. A cost-based service on a location. |
| **CBBS** | `CostBasedBillService`. Its invoice lines point at the parent CBS. |
| **FHS** | `FleetHaulService` (fleet haul). "Tonnage pilot" FHS behaves differently. |
| **RBS** | `RateBasedService`. Often out of scope for automated corrections; check the ticket. |
| **HSF** | `HaulerServiceFee`. Its callback re-saves the parent CBS. |
| **CbBenchmark** | Benchmark amounts and fee percent for a CBS. |
| **`invoice_lines` / `InvoiceLine`** | The unified invoice line table. It links to its source through the polymorphic `invoiceable`. |
| **`invoice_*_lines`** | Legacy per-type line tables (`invoice_cbs_lines`, `invoice_fhs_lines`, `invoice_charge_lines`, and so on). Being phased out; see the rules below. |
| **MUB** | Universal blocker date range (`mub_start` / `mub_end`). It blocks pushing invoices outside the range to Intacct and filters the invoice queues. It isn't a model validation. |
| **Automated corrections** | GT-1749 RFC. Detects service, benchmark, or subscription edits that affect already-invoiced months, then corrects them. Design docs are in `docs/automated-corrections/`. |
| **Corrections window** | The months the corrections job evaluates, relative to the MUB. <!-- TODO: confirm (currently MUB -5 to -2?) --> |
| **Push** | Sending a finalized invoice to Intacct. Pushed invoices are the ones that were "actually invoiced". Drafts aren't. |
| **Avalara / AvaTax** | Tax calculation. Committing or voiding a transaction changes the tax totals on lines and invoices. |
| **Helcim** | Card payment processor. Coyote keeps a synced copy of its data in `HelcimCardTransaction`. |
| **SSC** | Service / Savings Correction, an adjustment type. |
| **NAB** | "Not a blocker." A review comment prefix. |

---

## Code conventions (GT-specific)

### Invoice lines
- **Never add new reads or writes of the per-type `invoice_*_line` models** (`InvoiceCbsLine`, `InvoiceFhsLine`, `InvoiceChargeLine`, `InvoiceCreditLine`, and so on) in app code. Use `invoice_lines`, usually `InvoiceLine.where(invoiceable: service)`. Be careful with `service_id`: CBS and FHS lines leave it nil, and CBBS lines set it to the parent CBS.
- In specs, factories, and Playwright SQL, prefer `invoice_lines` too.
- If the code ends up needing `respond_to?` or `public_send` to handle the per-type split, that usually means it should be using `invoice_lines` instead.

### Invoice status
- Prefer `accounts_receivable_lifecycle_status_id` on invoices over `intacct_push_status` when checking an invoice's state.

### Money
- Round money with `Utils::Money.round_money` (2 decimal places, half-up, BigDecimal). Round rates and percentages with `Utils::Money.round_non_money_value`.
- Never use a raw `.round(2)`, and never persist or push to Intacct the result of unrounded float math. The `Finance/RequireRoundMoney` cop only covers `app/classes/invoice_lines/line_data/*`, so apply this everywhere else yourself.
- Think about the messy cases: credit memos, voids, re-invoiced months, duplicate rows, nil vs 0. "No value recorded" must not quietly become `$0`.

### Callbacks
- Tag new ActiveRecord callbacks with `# callback-reviewed <link to GT ticket>`, not a `rubocop:disable`.
- `previous_changes` gets wiped if a nested callback re-saves the record before `after_commit` runs (for example, HSF re-saves the CBS, and an FHS placemark re-touches the FHS). Account for that, and test it.
- If the same callback pattern goes on more than one model, extract a concern instead of copying it.
- Be deliberate about `on: :create` vs `on: :update`, and state the choice in the PR.

### Workers and jobs
- Assume Sidekiq will retry. Retries must not duplicate side effects like Slack posts, charges, Intacct pushes, or AvaTax commits.
- Don't put a `.blank?` guard after `find`, since `find` raises. Don't rescue code that can't raise.
- Check whether other payment types reach a new path (does an ACH failure hit card-only logic?), and check other service types too (CBS / CBBS / FHS / RBS, legacy Xero-era records).
- When the work only applies to a single type, guard explicitly on that type.
- When a job writes as Sidekiq, use `PaperTrail.request.whodunnit ||=` so it doesn't overwrite the editing user.

### Ruby style the team prefers
- Write plain, direct Ruby. Avoid metaprogramming in production code (`public_send` with computed names, `define_method`, `respond_to?` branching).
- If a class's main method is `.call`, make it inherit `ApplicationService` so callers can use `Klass.call(...)`.
- Prefer `private_class_method def foo` over making a method private after the fact.
- Don't write wrappers that only forward to another method. Return a boolean when the caller only needs yes or no.
- Use descriptive names, like `SeedCorrectableCbs`, not `Gt1802Seed`.
- Push filtering into the query (scopes) rather than filtering in Ruby after loading.

### Comments and docs
- Keep comments short and only explain a non-obvious *why*. Don't put ticket numbers in comments, since tickets go stale. Don't describe what the code *doesn't* do, and don't mention removed code.
- Don't leave commented-out code behind.
- Docs and diagrams should describe the current state, not its history.

### Rake tasks and seeds
- One task per file. On-demand tasks (`lib/tasks/run_on_demand/`) get descriptive names without ticket numbers. One-off tasks go in `lib/tasks/run_once/`.
- Seed data should be created in a repeatable way, not looked up from whatever data got copied down from prod.
- Don't include destructive delete paths "just in case", because other foreign keys may point at the table later.
- Leave gaps in `display_order` values (10, 20, 30) so new items can be inserted later.

### Migrations
- When you add an index with `algorithm: :concurrently`, don't combine it with `if_not_exists`. An index build that fails leaves an invalid index that `if_not_exists` then silently skips. Drop any invalid index first, so the migration fails loudly and can be retried.
- `db/structure.sql` should contain only this PR's changes. Drop unrelated Postgres extension changes.

### Frontend (`app/webpack/apps/`)
- Don't prop-drill data through components that don't use it. Call the hook where the data is needed (except in legacy class components).
- Build conditional array entries with inline spreads (`...(cond ? [x] : [])`), not by `splice`ing in by ID.
- Links to Lyra pages use `LYRA_BASE_URL`, not Coyote's base URL.
- No data fetching in `useEffect`; use the react-query hooks.
- `useMemo` / `useCallback` only for a slow calculation or a child that needs a stable reference. Otherwise move constants to module level.

---

## Tests

Every main behavior in the ticket needs a spec that **would fail if the code were wrong**:
- Request and controller specs check DB state (`change(Model, :count)`, reload and compare), not just the response body.
- No tautological tests that build the expected value from the output.
- Test names match what the test actually asserts.
- Take expected values from the setup, not hardcoded literals.
- Use real records when they're cheap to create, rather than mocking them.
- Cover the edge cases the ticket names (nil or none, multiple rows, credits vs charges, the "do NOT raise" paths).
- Toggle Flipper with `Flipper.enable` / `Flipper.disable`; never stub it.

---

## Other teams' code

GT and Purple team (PT) share ownership of adjustments. PT alone owns adjustment types and adjustment templates. Teal (EP), OT, and TA own other areas. If a change modifies recent or meaningful behavior another team built, call it out so I can check with them (for PT, that's `#finance-tech`). Use `git blame` and the PR's ticket prefix to tell who owns it.

---

## Reviewing GT PRs

Use the `coyote-green-review` skill if you have it. Otherwise, review in this order:
1. **Correctness first:** run realistic messy finance data through the changed logic before touching any checklist.
2. **Ticket match:** map each requirement and "do NOT" to `file:line`.
3. **Team checks:** no new `invoice_*_line` usage, money rounding, callbacks, test quality, blast radius, other teams' code, PR hygiene.
4. **Existing threads:** decide whether each one has been addressed.

Output goes to the terminal only, with **Blocking**, **NABs**, and **Questions** sections. Write ready-to-paste comments in a casual, collaborative voice, prefix non-blocking ones with `NAB:`, and phrase uncertain points as questions. A blocking finding needs a concrete failure scenario.
