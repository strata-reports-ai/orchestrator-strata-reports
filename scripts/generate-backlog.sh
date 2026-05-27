#!/usr/bin/env bash
# Dispatches a Claude agent to read PRD.md and create new GitHub issues
# when the backlog runs low. Called from dispatch-tasks.sh.
set -euo pipefail

ORCHESTRATOR_REPO="${ORCHESTRATOR_REPO:?}"
DISPATCH_TOKEN="${DISPATCH_TOKEN:?}"

owner=$(echo "$ORCHESTRATOR_REPO" | cut -d'/' -f1)

PRD=$(cat "$(dirname "$0")/../PRD.md")

EXISTING_ISSUES=$(GH_TOKEN="$DISPATCH_TOKEN" gh issue list \
  --repo "$ORCHESTRATOR_REPO" \
  --state all \
  --limit 100 \
  --json number,title,labels \
  --jq '.[] | "#\(.number) [\(.labels | map(.name) | join(", "))] \(.title)"' \
  2>/dev/null || echo "(none)")

read -r -d '' PROMPT << PROMPT || true
You are a product owner for StrataReport AI, a SaaS tool that generates quarterly performance reports for short-term rental property managers.

Your job: read the PRD below and create 3-5 new GitHub issues for features that have NOT yet been issued. Choose items in priority order from the build sequencing in §16.1 (Week 1–2 first, then Week 3, etc.).

## PRD
${PRD}

## Already-created issues (DO NOT duplicate these)
${EXISTING_ISSUES}

## How to create each issue

Use this exact gh command for each issue:
  gh issue create \
    --repo ${ORCHESTRATOR_REPO} \
    --title "[title]" \
    --body "[body]" \
    --label "ready" \
    --label "repo:fn-strata-reports"   # or repo:web-strata-reports for frontend issues, repo:dbproj-strata-reports for DB/migration issues

The body MUST follow this format:
  ## What to build
  [2-3 sentences describing what to implement]

  ## Acceptance criteria
  - [ ] [specific testable criterion]
  - [ ] [specific testable criterion]
  ...

  ## Technical notes
  [Specific files to create/modify, DB schema changes, API routes, test file names]

Make acceptance criteria detailed enough that a developer can implement the feature without asking clarifying questions.

## Important rules
- Follow build sequencing from §16.1 — do not skip ahead
- Create exactly 3-5 issues, no more
- Each issue must be a distinct, implementable unit of work
- Backend/API issues: --label "repo:fn-strata-reports"
- Frontend issues: --label "repo:web-strata-reports"
- DB migration/schema issues: --label "repo:dbproj-strata-reports"
- After creating issues, print "Done. Created N issues." so we know you finished
PROMPT

echo "Dispatching backlog generation agent..."

jq -n --arg prompt "$PROMPT" \
  '{"ref":"main","inputs":{"prompt":$prompt}}' | \
GH_TOKEN="$DISPATCH_TOKEN" gh api \
  "repos/${owner}/orchestrator-strata-reports/actions/workflows/generate-backlog.yml/dispatches" \
  --method POST --input -

echo "Backlog generation dispatched."
