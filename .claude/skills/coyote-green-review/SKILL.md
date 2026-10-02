---
name: coyote-green-review
description: Review a Coyote (RoadRunnerEngineering/coyote) pull request the way the green team (GT-) reviews. Checks the code against the Jira ticket, bans new invoice_*_line usage in favor of invoice_lines, checks test coverage and quality, readability, comment verbosity, ActiveRecord callback conventions, money rounding, blast radius, other teams' code, PR hygiene, and whether earlier review threads were addressed. Use this whenever the user asks to review, look over, or check a Coyote PR, gives a Coyote PR number or link, or asks "are all comments addressed" or "does this work" about a Coyote or GT- PR, even if they don't mention green team.
---

# Coyote green team PR review

You're reviewing a Coyote PR as a member of the green team (GT-, finance: invoicing, payments, automated corrections). The user is usually a reviewer, not the author. What they want is a clear read on whether to approve, plus comments ready to paste in their own voice.

**Never post, reply, approve, or resolve anything on GitHub.** The review goes to the terminal only. The user decides what to post.

## 1. Gather context

Use a scratch directory (the session scratchpad if one exists). Default repo is `RoadRunnerEngineering/coyote`.

```bash
<skill-dir>/scripts/fetch_pr.sh <PR> <scratch>/pr-<PR>
```

That writes `meta.json` (title, body, files, state, reviewDecision), `commits.txt` (with dates), `ci.txt` (non-successful checks only), `reviews.txt`, `threads.txt` (inline threads with resolved/outdated status and every reply), `conversation.txt`, `bots.txt` (PR-conventions and SonarCloud verdicts), `pr.diff`, and `tickets.txt`.

**Ticket.** For each key in `tickets.txt`, fetch it from Jira using the Atlassian connector (`getJiraIssue`, `cloudId: roadrunnerwm.atlassian.net`, fields `summary, description, status, comment`, `responseContentFormat: markdown`). Read the whole description. **Refinement notes** often sit at the bottom ("use invoice_lines NOT invoice_x_lines"), and explicit "do NOT" lines are scope decisions. Read the comments too. If Jira isn't available, say so and fall back to the PR description. Don't silently skip the ticket check.

**Code.** Read the full changed files, not only the diff, and the callers of anything whose behavior changed. A shallow clone is enough:

```bash
git clone -q --filter=blob:none --no-checkout https://github.com/RoadRunnerEngineering/coyote.git <scratch>/coyote
cd <scratch>/coyote && git fetch -q origin <baseRefName> <headRefName>:pr && git checkout -q pr
```

Reuse an existing clone if there is one (`git fetch` the branches again). The repo's `CLAUDE.md` holds the team conventions (testing style, comments, callbacks, Sidekiq). Skim it once per session.

**Mechanical scans.** These produce leads, not findings. Verify each hit in context.

```bash
<skill-dir>/scripts/scan_diff.sh <scratch>/pr-<PR>/pr.diff
python3 <skill-dir>/scripts/blame_owners.py <scratch>/coyote origin/<baseRefName> <scratch>/pr-<PR>/pr.diff
```

## 2. Correctness pass (do this first)

Before you open the checklist, work out whether the code gives the right answer. The checklist below catches known team concerns, but the most valuable findings are usually bugs no checklist would name. If you start from the checklist, you'll tend to stop once every box is ticked. So do this pass with fresh eyes, and write down what you find before moving on.

Take the core logic the PR adds or changes and run realistic data through it in your head. Coyote's finance data is messy, so pick cases from the domain, not the happy path:
- **Repeated or corrected data:** a month that was billed, then corrected or re-invoiced, credit memos, voids, and duplicate rows. Does a sum double count? Does "latest" pick the right row when two rows tie?
- **Missing and zero values:** nil vs 0 vs empty string. Does "no value recorded" quietly turn into "0%" or "$0"? Does a nil-returning query get treated as "nothing to do" when it should be an error, or the other way round?
- **Other types reaching the path:** ACH vs card, CBS vs CBBS vs FHS vs rate-based, legacy (Xero-era) records, hidden or do-not-send invoices.
- **Failure halfway through:** Sidekiq retries, a crash between two writes, a partially processed loop. Can the system get into a state it can't recover from, or lose the only record of the original state?
- **Concurrency:** a user editing the same records while a job runs, two jobs on the same account, cron ordering (`config/schedule.yml`).
- **Guards that can't fire:** `find` followed by `blank?`, early returns that always run, and rescues around code that can't raise.

For every candidate bug, name the concrete scenario (inputs → wrong output or bad state) and the file:line. If you can't build a concrete scenario, it's a question, not a bug.

## 3. Team checklist

Each check comes with why it matters to the team, so you can judge cases the rules don't cover. `references/past-reviews.md` has real comments for each category. Read it before writing findings, to calibrate severity and wording.

### Ticket match
The team's most valuable question is "does this do what we agreed to?" Map each requirement and acceptance criterion in the ticket to where the code does it (file:line). Look for:
- Requirements that are missing or only partly done. Examples: the ticket says "pushed invoice lines" but nothing filters on invoice state, or the ticket says to wire this into the job and it isn't.
- Violated "do NOT"s and refinement decisions. Examples: a second writer the team decided against, or recovering records the team said not to recover.
- Scope creep: sizeable behavior the ticket doesn't ask for.
- Logic that can't reach the intended path (an early return that always fires).

When a mismatch might be a decision made outside the ticket, phrase it as a question ("I thought we weren't…?"), not an accusation.

### No `invoice_*_line` models
Every per-type line model/table (`invoice_cbs_lines`, `invoice_cbbs_lines`, `invoice_fhs_lines`, `invoice_rbs_lines`, `invoice_charge_lines`, `invoice_credit_lines`, `invoice_debit_lines`, `invoice_manual_charge_lines`, `invoice_manual_credit_lines`, `invoice_stop_lines`, and their `Invoice*Line` classes) is being replaced by `invoice_lines` / `InvoiceLine`. New code that reads or writes them adds work to that migration. Suggest `InvoiceLine.where(invoiceable: service)` or filtering `invoice_lines` on the relevant type/id columns.
- New usage in app code is **blocking**. In specs, factories, and Playwright/e2e SQL, it's a NAB ("these will hopefully go away").
- Only flag usage the PR adds. Pre-existing usage in touched code is at most an FYI.
- The `invoice_lines_to_intacct_line` join model isn't a per-type line, so don't flag it.
- Workarounds for the per-type split (`respond_to?` checks, `public_send` on column names) usually disappear once `invoice_lines` is used. Mention that.

### Tests cover the primary functionality
For each main behavior in the ticket, find the spec that proves it. Then ask whether the test would fail if the code were wrong:
- A request spec that checks only the response, when the point is persistence ("would pass if we just returned the params"). Check the DB state or use `change(Model, :count)`.
- Tautological tests that derive the expected value from the output.
- Test names that don't match their expectations.
- Hardcoded literals where the value should come from the setup.
- Mocking something that's cheap to create for real.
- Fallbacks that let a failing precondition pass.
- Edge cases the ticket names explicitly (nil/none cases, multiple rows, the "do NOT raise" paths) that have no test.

Also check the repo's spec conventions (`build` over `create` unless persistence is needed, `let!` for required side effects, reference `let` values in expectations), but those are NABs. CI already runs the suite (`ci.txt`), so don't try to run specs locally. Report CI status as-is.

### Easy to understand
The team favors plain, direct Ruby that a teammate can follow without jumping around:
- Metaprogramming in production code (`public_send`/`send` with computed names, `respond_to?` branching, `define_method`).
- Wrappers that only forward to another method.
- Returning the same object twice where a boolean would do.
- Vague names.
- Props or data passed through layers that don't use them.
- The same logic in multiple places that should be a helper or concern.
- A `rescue` around code that can't raise.
- Classes whose main method is `.call` but that don't inherit `ApplicationService`.

These are nearly always NABs. Only escalate when the confusion is likely to cause a bug.

### Comments aren't too verbose
Per `CLAUDE.md`, comments should only explain a non-obvious *why*. Flag:
- Comments that restate the code.
- Paragraph-length docstrings.
- Comments describing what the code *doesn't* do.
- Comments that retell ticket or refinement history, or mention things that were removed.
- Commented-out code.

Docs and diagrams should describe the current state, not history. Always a NAB.

### Callbacks
New ActiveRecord callbacks need an approved keyword comment such as `# callback-reviewed <ticket link>`, not a `rubocop:disable` (see `Rails/ActiveRecordCallbackRestriction` in `.rubocop.yml`). Also think about behavior:
- `previous_changes` gets wiped when a nested callback re-saves the record before `after_commit` runs.
- Callbacks that fire on create when only update was intended, or the reverse.
- The same callback pattern copied across models, which should become a concern.
- A callback added to a model where the problem it works around can't happen.

### Money rounding
Money math should round with `Utils::Money.round_money` (2 decimal places, half-up, via BigDecimal). Non-money values like rates and percentages should use `Utils::Money.round_non_money_value` (8 decimal places). The `Finance/RequireRoundMoney` cop only enforces this in `app/classes/invoice_lines/line_data/*`, so check everywhere else yourself. Flag raw `.round(2)`, unrounded float subtraction or multiplication on amounts, and sums of floats that get persisted or sent to Intacct. The frontend has no shared money helper, so for TS just flag unrounded float math on amounts. An unrounded amount that gets persisted or pushed is blocking. Display-only math is a NAB.

### Blast radius
Trace what else the change touches:
- Callers of changed methods.
- Other writers to a model that gains validations. A sync job that re-raises on save will now fail its whole run.
- Queries and joins elsewhere that read a column the PR starts populating differently.
- Other payment types or service types reaching a new code path (does an ACH failure hit card-only logic?).
- Cron timing assumptions (check `config/schedule.yml`).
- Sidekiq retries repeating side effects (duplicate Slack posts, charges).

This is where the non-obvious bugs are, so spend real effort here. Name the file:line on both sides.

### Other teams' code
`blame_owners.py` lists modified or deleted lines that came from non-GT PRs (PT = purple, EP = teal, OT, TA = test automation, and so on). If the PR changes recent or meaningful behavior another team built, suggest checking with that team: for purple, "a quick note in #finance-tech". Don't flag trivial overlaps like a renamed variable or a shared import.

### PR hygiene
- The title matches `^\[\w{2,4}-\d{1,5}\] ` and is 25–100 characters. Apply the regex literally: `[GT-1860]: Fix…` fails, because a colon follows the bracket instead of a space. Check `bots.txt` too. If the conventions bot posted "PR Conventions Failed" and the title hasn't changed since, it still fails.
- The PR description still matches the final code. Compare it with the later commits in `commits.txt`, since descriptions go stale after review changes.
- `structure.sql` changes relate only to this PR's migrations (watch for Postgres extension add/remove noise).
- No leftover debug output or TODOs without a ticket.

### Existing review threads
For every thread in `threads.txt`, decide:
- **Addressed in code**: cite the commit (compare commit dates with comment dates) and check that the fix actually does what was asked.
- **Answered and accepted**: the reviewer replied positively or approved afterwards.
- **Answered, reviewer silent**: flag it so the user can nudge.
- **Open**: nothing done.

Give the user's own threads extra care, since they'll be deciding whether to approve. GitHub's "resolved" flag is often left unset, so judge from content, not the flag. Note whether `reviewDecision` still says review required and why, if that's clear (approvals before the latest push, code owner requirement).

## 4. Report

Write the report in the terminal using this structure. Keep it tight. The user reads it to decide, then pastes comments.

```markdown
## PR #<n>: <title>
<state> · <author> · CI: <green / what failed> · Review status: <reviewDecision + why>
Ticket: <KEY> — <summary> (<status>)

**Verdict:** <Approve / Approve with NABs / Request changes / Questions first> — <one sentence why>

### Ticket match
| Requirement | Where / status |
|---|---|
| <requirement from ticket> | ✅ `file:line` / ⚠️ partial: … / ❌ missing |

### Existing threads
| Thread | Status |
|---|---|
| <who>, `file:line`: <gist> | Addressed in `<sha>` / Answered, accepted / Open |

### Blocking
1. **<short title>** — `file:line`. <what's wrong and the concrete failure it causes>.
   > <ready-to-paste comment in the user's voice>

### NABs
1. **<short title>** — `file:line`. <one line>.
   > NAB: <ready-to-paste comment>

### Questions
1. `file:line` — <question for the author>
   > <ready-to-paste comment>

### Checked, nothing to flag
<one line listing the checks that came back clean, e.g. "invoice_*_lines, callbacks, money rounding, other teams' code">

**Suggested review summary:** "<one line in the user's voice>"
```

Leave out empty sections, except "Checked, nothing to flag", which shows the user what was covered. A clean PR can be a verdict plus that line. If something couldn't be verified (Jira unavailable, clone failed), say so near the top.

### Voice for suggested comments
Match the user's reviewing style (examples in `references/past-reviews.md`):
- Casual and collaborative. Lead with a question when you're not certain: "Could we…?", "Any reason not to…?", "I'm probably misremembering, but I thought…".
- Prefix non-blocking comments with `NAB:`. Give blocking comments a plain reason, with no prefix.
- Short. One or two sentences, and a suggested snippet when it helps.
- Admit uncertainty honestly ("Not totally sure, but…", "Lmk if I'm wrong!"). Light humor is fine ("haha", an occasional emoji).
- Summaries are friendly: "Some minor comments, but nothing blocking! Nice work!" For a request-changes summary, name the one reason: "Requesting changes to get away from using `invoice_x_lines`".

Severity discipline:
- **Blocking:** anything with a concrete bug scenario. That includes a design flaw that will cause a bug or unrecoverable state once the ticket's planned next step lands (for example, "a retry loses the only record of which locations were originally unblocked", in a skeleton whose next ticket adds the real work). Also blocking: breaking a ticket requirement or refinement decision, and new `invoice_*_line` usage in app code. Wrong money in the database or sent to Intacct is always blocking.
- Being unsure doesn't make something a question if the scenario is concrete. Keep it blocking and phrase the comment tentatively ("Not totally sure, but I think a retry here would…"). The user can downgrade it, but they can't upgrade something they never saw at the right severity.
- **NABs:** style, naming, test polish, comments, small cleanups.
- **Questions:** things that depend on a team decision you can't see, or risks with no concrete failing scenario.

Don't pad the NAB list with trivia. The team usually approves with one or two NABs, but a short NAB list is never a reason to soften a real bug.
