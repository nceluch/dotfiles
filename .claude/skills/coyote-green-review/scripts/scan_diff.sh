#!/usr/bin/env bash
# Mechanical scan of lines ADDED by a PR. Hits are leads to verify, not findings.
# Usage: scan_diff.sh <pr.diff>
DIFF="$1"
added() { awk '/^\+\+\+ /{f=substr($2,3); next} /^\+/{print f": "substr($0,2)}' "$DIFF"; }

echo "## invoice_*_line usage (should be invoice_lines / InvoiceLine)"
# Matches invoice_cbs_lines, InvoiceFhsLine, invoice_manual_credit_line, etc.
# Excludes InvoiceLine/invoice_lines themselves and the invoice_lines_to_intacct_line join model.
added | grep -E 'invoice_[a-z_]+_lines?\b|Invoice[A-Z][A-Za-z]*Line\b' \
      | grep -vE 'invoice_lines_to_intacct_lines?\b|InvoiceLinesToIntacctLine' || echo "(none)"

echo; echo "## Raw rounding (money should use Utils::Money.round_money / round_non_money_value)"
added | grep -E '\.round\(|\.round\b|\.floor\(|\.ceil\(|toFixed\(|Math\.round' | grep -v 'Utils::Money' || echo "(none)"

echo; echo "## Callbacks added (need '# callback-reviewed <ticket>' style keyword, not rubocop:disable)"
added | grep -E '^\S+: *(before|after|around)_(validation|save|create|update|destroy|commit|rollback|initialize|find|touch)\b|after_(create|update|destroy|save)_commit\b' || echo "(none)"
added | grep -E 'rubocop:disable.*ActiveRecordCallbackRestriction' && echo "^ callback silenced with rubocop:disable"

echo; echo "## Metaprogramming"
added | grep -E '\.(public_send|send|__send__|instance_variable_get|instance_variable_set|define_method)\(|respond_to\?\(' || echo "(none)"

echo; echo "## Commented-out code / debug leftovers"
added | grep -E '^\S+: *#\s*(def |end$|if |return |[a-z_]+\.[a-z_]+\(|puts |binding\.)|binding\.pry|byebug|console\.log|debugger' || echo "(none)"

echo; echo "## structure.sql changes (verify only PR-relevant; watch for extensions)"
grep -nE '^\+.*(CREATE EXTENSION|COMMENT ON EXTENSION)' "$DIFF" || echo "(no extension changes)"
grep -c '^+++ b/db/structure.sql' "$DIFF" | sed 's/^/structure.sql touched: /'
