#!/usr/bin/env bash
# Dispatches a Claude agent to read PRD.md and create new GitHub issues
# when the backlog runs low. Called from dispatch-tasks.sh.
set -euo pipefail

ORCHESTRATOR_REPO="${ORCHESTRATOR_REPO:?}"
DISPATCH_TOKEN="${DISPATCH_TOKEN:?}"

owner=$(echo "$ORCHESTRATOR_REPO" | cut -d'/' -f1)

read -r -d '' PROMPT << PROMPT || true
You are a product owner for StrataReport AI, a SaaS tool that generates quarterly performance reports for short-term rental property managers.

STEP 1 - Read the PRD:
  gh api repos/${ORCHESTRATOR_REPO}/contents/PRD.md --jq '.content' | base64 -d

STEP 2 - Read existing issues:
  gh issue list --repo ${ORCHESTRATOR_REPO} --state all --limit 100 --json number,title,labels --jq '.[] | "#\(.number) [\(.labels | map(.name) | join(", "))] \(.title)"'

STEP 3 - Create 3-5 new issues for features not yet issued, in priority order from section 16.1 of the PRD (Week 1-2 first). Use:
  gh issue create --repo ${ORCHESTRATOR_REPO} --title "[title]" --body "[body]" --label "ready" --label "[repo-label]"

Where [repo-label] is one of:
  repo:fn-strata-reports     (backend/API)
  repo:web-strata-reports    (frontend)
  repo:dbproj-strata-reports (DB migrations/schema)

Body format:
  ## What to build
  [2-3 sentences]

  ## Acceptance criteria
  - [ ] [specific testable criterion]

  ## Technical notes
  [files to create/modify, API routes, schema changes]

Rules:
- Follow build sequencing from section 16.1 strictly - do not skip ahead
- Create exactly 3-5 issues
- Make acceptance criteria detailed enough to implement without clarifying questions
- End with: Done. Created N issues.
PROMPT

echo "Dispatching backlog generation agent..."

python3 -c "
import json, sys
prompt = sys.stdin.read()
print(json.dumps({'ref': 'main', 'inputs': {'prompt': prompt}}))
" <<< "$PROMPT" | \
GH_TOKEN="$DISPATCH_TOKEN" gh api \
  "repos/${owner}/orchestrator-strata-reports/actions/workflows/generate-backlog.yml/dispatches" \
  --method POST --input -

echo "Backlog generation dispatched."
