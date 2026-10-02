# Past green team review comments (Coyote)

Real comments from recent green team reviews, grouped by the check they illustrate. Use them to calibrate what's worth flagging, how severe it is, and how to word it. Don't copy them; match the tone.

## Table of contents
- invoice_*_line usage
- Ticket / intent mismatch
- Tests
- Readability
- Comments & docs
- Callbacks
- Money & rounding
- Blast radius
- Other teams' code
- PR hygiene
- Review summaries (approve / request changes)

## invoice_*_line usage
- (#14004, blocking) "We shouldn't use `invoice_cbs_lines` or `invoice_fhs_lines` here, we should query with something like `InvoiceLine.where(invoiceable: service)`"
- (#14004, NAB follow-on) "Hopefully we don't need these `respond_to` checks after we use `invoice_lines`"
- (#14004, teammate) "The ticket's refinement note says to read `invoice_lines`, not `invoice_cbs_lines`/`invoice_fhs_lines`. Can this switch to `invoice_lines` filtered on `service_type` + `service_id`?"
- (#13744, Playwright) "Minor, but probably better to query on `invoice_lines` here b/c `invoice_cbs_lines` will hopefully go away in the future"
- (#13699, Playwright) "it'd probably be better to rely on `invoice_lines` rather than `invoice_x_lines` in these tests. `invoice_x_lines` are hopefully going away eventually"

In app code this has been a request-changes item. In e2e/Playwright tests it's been softer ("minor").

## Ticket / intent mismatch
- (#14004) "One functionality question - do we need to integrate this functionality into the job in this ticket? I kind of expect that we do, but can't say for sure"
- (#14004, teammate) "The ticket says to read the pushed invoice lines. I don't see a filter on invoice state here. Could a draft invoice's lines get in?"
- (#13979) "I'm probably misremembering, but I thought we were not going to have this alternative creation of `helcim_card_transactions`?"
- (#13704) "I could easily be misremembering, but I thought we were leaning against actually recovering checkouts?"
- (#13810) "Hmm I don't think we should need `default_columns`... I think we want the parent `columns` to be the default, right? Are the current `columns` the full list and we actually want to pare those back to just this list of 25 as part of this ticket?"
- (#13704) "in `hash_check_satisfied?` we `return false` if `recovered_checkout` exists. So won't we always return this error and never continue down to `recover_cancelled_checkout()`?" (logic that can't reach the intended path)

## Tests
- (#13873) "NAB: Could we also check that the data is stored in the DB? I think this test would pass if we just returned the params rn"
- (#13861) "Looks like this test parses out the data set ID from the URL then checks the same URL to ensure the data set ID is in it - I think we can get rid of this test" (tautological test)
- (#13861) "Might be beneficial to confirm it did change the count `expect { described_class.new([101, 202]).url }.to(change(DataSet, :count))`"
- (#13849, teammate) "This test case name does not match the expectations"
- (#13849, teammate) "Can you make this test populate it from the account rather than checking vs a hardcoded value?"
- (#13936, teammate) "Can you add a test case for original invoice line existing, but its a credit so it still returns nil?" (missing edge case)
- (#13786) "NAB: I see we do this above too, but why not just create the real `ExportResult`?" (over-mocking)
- (#13744) "Do we actually want to fallback to `draftInvoiceIds` and run this test with those invoices? Seems like we know we've failed this test already if we don't have any `finalizeInvoiceIds`" (test that can't fail)

## Readability
- (#14004) "NAB: Is there any way to get away from `.public_send`? Whenever possible I think it's best to avoid metaprogramming in production code."
- (#14004) "NAB: If we're going to name to primary method `.call` we can make the class inherit `ApplicationService`"
- (#13786) "NAB: if this is just a wrapper around `resolve_base_invoice_lines`, can we just call `resolve_base_invoice_lines` where this function is called and remove this function?"
- (#13704) "Could we use a boolean instead of returning the same checkout twice?"
- (#13986) "NAB: Could we name the module something more descriptive like `SeedCorrectableCbs`?"
- (#13936, teammate) "We are sending this down through multiple components, each of which is not using the info, just passing it down. Does it make sense to put the hook call in this component directly?"
- (#13936, teammate) "Rather than `splice`ing it in by ID, can we follow the pattern of spreading an empty array in line where it should live in the final array? Its cleaner to parse the order on a quick glance"
- (#13899, teammate) "Since we have to do this in multiple spots across the codebase, I think a helper on the `invoice_line` model to handle this check & math might be nice."
- (#13979) "NAB: I think our only use of `last_cancelled_autopay_transaction_id` is here, could we just move this `rescue` to that method? Also will that ever throw an error? It looks like it will just return a value or `nil`?"

## Comments & docs
- (#14004) "NAB: I personally lean against keeping these verbose comments in here, especially when they start describing what is _not_ happening"
- (#13789) "NAB: Not sure if we should reference things that were removed, especially pre-implementation. I personally find just a current representation of the state most helpful"
- (#13789) "NAB: Not sure if we need these more general details here. If we do want them, maybe they should go in `docs/README.md`?"
- (#13849, teammate) "NAB: Do we want to keep this commented out?"

## Callbacks
- (#13923) "I think we want to change this to be `# callback-reviewed <link to ticket>` instead of the rubocop disable to align with how we handle callbacks rn"
- (#13922) Walked through `previous_changes` being wiped when an HSF `after_commit` re-saves the parent CBS, so the CBS `after_commit` sees empty `previous_changes`. Then: "this is probably a good reason to move this logic into a concern. Adding this callback pattern in multiple places will probably confuse someone down the road"
- (#13922) "If the `hauler_service_fee` callback mentioned on CBS is the concrete example that caused this issue, do we need this pattern on FHS since they don't have `hauler_service_fee`s associated with them?"
- (#13912, teammate) "Should this only trigger on update? Otherwise, every creation of BM will trigger this."

## Money & rounding
- (#13899, teammate) "Should the result of the subtraction be rounded? We are doing floating point math here"

## Blast radius
- (#13979) "One thing Claude pointed out - could this get called if an ACH transaction fails? Should we guard this on the transaction type being card?"
- (#13996, teammate) "If the push still raises the already pushed error, won't this rescue still schedule the retry worker?"
- (#13923, teammate) "rate-based templates fall through `CORRECTION_SERVICE_CLASSES`. I checked the prod DB and 800 of them carry a subscription type, so `correction_account_id` returns nil and we log `for account #` with no id."
- (#13912, teammate) "could there ever be same account owns both a CBS and FHS here? just thinking maybe we would have dupes without adding `.uniq`?"

## Other teams' code
- (#13936) "The description's explanation of this does sound good to me, but it looks like this was added by purple team pretty recently so we should probably check with them on this to be sure"
- (#13936 summary) "Just calling out that it'd probably be worth looping purple team in on this. A quick note in #finance-tech would be ideal"

## PR hygiene
- (#13810) "NAB: I think the description is a bit outdated"
- (#13835) "Not totally sure, but I think we should remove these extensions 👀" (unrelated structure.sql changes)
- (#13118) "This seems fine, but do we want to commit it here?" (structure.sql)

## Review summaries (approve / request changes)
- "Requesting changes to get away from using `invoice_x_lines`"
- "Just one question about savings `helcim_card_transactions` before I approve - nice work!"
- "Some comments, just curious on your thoughts before approving, nice work though!"
- "Some minor comments, but nothing blocking! Nice work!"
- "Left some comments/potential improvements, but I do think these tests are good smoke tests! Nice work!"
- "One question, but it's not a big deal either way. LGTM!"
- "LGTM!" / "💯" (clean PRs get short approvals)
