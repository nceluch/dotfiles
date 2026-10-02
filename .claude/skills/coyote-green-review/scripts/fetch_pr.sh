#!/usr/bin/env bash
# Gather everything needed to review a Coyote PR into one directory.
# Usage: fetch_pr.sh <pr-number> <out-dir> [owner/repo]
set -euo pipefail
PR="$1"; OUT="$2"; REPO="${3:-RoadRunnerEngineering/coyote}"
OWNER="${REPO%/*}"; NAME="${REPO#*/}"
mkdir -p "$OUT"

gh pr view "$PR" -R "$REPO" --json number,title,body,state,author,headRefName,headRefOid,baseRefName,additions,deletions,files,reviewDecision,mergeable,createdAt,updatedAt > "$OUT/meta.json"

# Commits with dates, so review comments can be compared against what landed after them
gh pr view "$PR" -R "$REPO" --json commits \
  --jq '.commits[] | "\(.oid[0:8]) \(.committedDate) \(.messageHeadline)"' > "$OUT/commits.txt"

# CI: only list checks that did not succeed
gh pr view "$PR" -R "$REPO" --json statusCheckRollup \
  --jq '[.statusCheckRollup[] | {n: (.name // .context), c: (.conclusion // .state)}] | "total=\(length)\n" + ([.[] | select(.c != "SUCCESS") | "\(.c)\t\(.n)"] | join("\n"))' > "$OUT/ci.txt"

# Review summaries (approve / request changes bodies)
gh api "repos/$REPO/pulls/$PR/reviews?per_page=100" \
  --jq '.[] | "\(.submitted_at) \(.user.login) [\(.state)] \(.body)"' > "$OUT/reviews.txt"

# Inline review threads with resolved/outdated status and every reply
gh api graphql -F owner="$OWNER" -F name="$NAME" -F pr="$PR" -f query='
query($owner:String!,$name:String!,$pr:Int!){repository(owner:$owner,name:$name){pullRequest(number:$pr){
  reviewThreads(first:100){nodes{isResolved isOutdated path line originalLine
    comments(first:50){nodes{author{login} createdAt body originalCommit{oid}}}}}}}}' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] |
    "=== \(.path):\(.line // .originalLine) resolved=\(.isResolved) outdated=\(.isOutdated)\n" +
    ([.comments.nodes[] | "-- \(.author.login) @\(.createdAt) [\(.originalCommit.oid[0:8])]: \(.body)"] | join("\n")) + "\n"' > "$OUT/threads.txt"

# Human conversation comments
gh api "repos/$REPO/issues/$PR/comments?per_page=100" \
  --jq '.[] | select(.user.type != "Bot") | "\(.created_at) \(.user.login): \(.body)"' > "$OUT/conversation.txt"

# Bot verdicts that matter for review (PR conventions, SonarCloud quality gate); skip coverage tables
gh api "repos/$REPO/issues/$PR/comments?per_page=100" \
  --jq '.[] | select(.user.type == "Bot") | select(.body | test("code-coverage-overview") | not)
        | "\(.updated_at) \(.user.login): \(.body[0:600])"' > "$OUT/bots.txt"

gh pr diff "$PR" -R "$REPO" > "$OUT/pr.diff"

# Ticket keys from title + branch (e.g. GT-1860)
jq -r '.title + " " + .headRefName' "$OUT/meta.json" | grep -oiE '\b[a-z]{2,4}-[0-9]{1,5}\b' | tr a-z A-Z | sort -u > "$OUT/tickets.txt" || true

echo "Wrote PR #$PR context to $OUT:"
ls -1 "$OUT"
echo "Tickets: $(tr '\n' ' ' < "$OUT/tickets.txt")"
