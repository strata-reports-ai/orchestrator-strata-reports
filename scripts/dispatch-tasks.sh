#!/usr/bin/env bash
set -euo pipefail

ORCHESTRATOR_REPO="${ORCHESTRATOR_REPO:?}"
GH_TOKEN="${GH_TOKEN:?}"
DISPATCH_TOKEN="${DISPATCH_TOKEN:?}"
TRIGGER_EVENT="${TRIGGER_EVENT:-workflow_dispatch}"

STALE_THRESHOLD_SECONDS=21600  # 6 hours

owner=$(echo "$ORCHESTRATOR_REPO" | cut -d'/' -f1)

# ── Helper: check if an open PR already references an issue ──────────────────
pr_exists_for_issue() {
  local target_repo="$1" issue_number="$2"
  local count
  count=$(GH_TOKEN="$DISPATCH_TOKEN" gh pr list \
    --repo "${owner}/${target_repo}" \
    --state open \
    --json body \
    --jq "[.[] | select(.body | contains(\"orchestrator-strata-reports#${issue_number}\"))] | length" \
    2>/dev/null || echo "0")
  [ "${count:-0}" -gt 0 ]
}

# ── Helper: check if a branch exists in a target repo ───────────────────────
branch_exists() {
  local target_repo="$1" branch="$2"
  GH_TOKEN="$DISPATCH_TOKEN" gh api \
    "repos/${owner}/${target_repo}/branches/${branch}" \
    --silent 2>/dev/null
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 0a — Close any open issues already labeled 'done'
# ══════════════════════════════════════════════════════════════════════════════
gh issue list --repo "$ORCHESTRATOR_REPO" --label done --state open \
  --json number --jq '.[].number' 2>/dev/null | \
while read -r n; do
  gh issue close "$n" --repo "$ORCHESTRATOR_REPO" \
    --comment "Auto-closing: already marked done." 2>/dev/null || true
  echo "Auto-closed done issue #$n"
done

# ══════════════════════════════════════════════════════════════════════════════
# STEP 0 — Clear expired cap-wait labels and re-trigger stalled stages
# ══════════════════════════════════════════════════════════════════════════════
cap_wait_issues=$(gh issue list \
  --repo "$ORCHESTRATOR_REPO" \
  --label cap-wait \
  --state open \
  --json number,labels \
  --limit 10 \
  2>/dev/null || echo "[]")

echo "$cap_wait_issues" | jq -c '.[]' | while read -r issue; do
  number=$(echo "$issue" | jq -r '.number')

  reset_iso=$(gh issue view "$number" --repo "$ORCHESTRATOR_REPO" --json comments \
    --jq '[.comments[] | select(.body | contains("RESET_ISO:"))] | last | .body' \
    2>/dev/null | grep -oP 'RESET_ISO: \K\S+' || true)

  if [ -n "$reset_iso" ]; then
    reset_epoch=$(date -d "$reset_iso" +%s 2>/dev/null || echo "0")
    current_epoch=$(date +%s)
    if [ "$current_epoch" -lt "$reset_epoch" ]; then
      remaining=$(( (reset_epoch - current_epoch) / 60 ))
      echo "Issue #$number: cap-wait active for ${remaining}m more — skipping"
      continue
    fi
  fi

  echo "Issue #$number: cap-wait expired — clearing label"
  gh issue edit "$number" --repo "$ORCHESTRATOR_REPO" --remove-label "cap-wait"

  has_in_test=$(echo "$issue" | jq -r '[.labels[].name] | any(. == "in-test")')
  if [ "$has_in_test" = "true" ]; then
    target_repo=$(echo "$issue" | jq -r '[.labels[].name | select(startswith("repo:"))] | first // empty' | sed 's/repo://')
    if [ -n "$target_repo" ]; then
      pr_number=$(GH_TOKEN="$DISPATCH_TOKEN" gh pr list \
        --repo "${owner}/${target_repo}" \
        --state merged \
        --json number,body \
        --jq "[.[] | select(.body | contains(\"orchestrator-strata-reports#${number}\"))] | .[0].number // empty" \
        2>/dev/null || true)
      if [ -n "$pr_number" ] && [ "$pr_number" != "null" ]; then
        GH_TOKEN="$DISPATCH_TOKEN" gh workflow run test-agent.yml \
          --repo "${owner}/fn-strata-reports" --ref main \
          -f pr_numbers="$pr_number" \
          -f target_repo="$target_repo" \
          -f orchestrator_issues="$number"
        echo "Re-triggered test agent for issue #$number (PR #$pr_number)"
      fi
    fi
  fi

  has_code_review=$(echo "$issue" | jq -r '[.labels[].name] | any(. == "code-review")')
  if [ "$has_code_review" = "true" ]; then
    target_repo=$(echo "$issue" | jq -r '[.labels[].name | select(startswith("repo:"))] | first // empty' | sed 's/repo://')
    if [ -n "$target_repo" ]; then
      pr_data=$(GH_TOKEN="$DISPATCH_TOKEN" gh pr list \
        --repo "${owner}/${target_repo}" --state open \
        --json number,headRefName,body \
        --jq "[.[] | select(.body | contains(\"orchestrator-strata-reports#${number}\"))] | .[0] // empty" \
        2>/dev/null || echo "")
      if [ -n "$pr_data" ] && [ "$pr_data" != "null" ] && [ "$pr_data" != "" ]; then
        pr_number=$(echo "$pr_data" | jq -r '.number')
        head_branch=$(echo "$pr_data" | jq -r '.headRefName')
        GH_TOKEN="$DISPATCH_TOKEN" gh workflow run code-review.yml \
          --repo "${owner}/${target_repo}" --ref main \
          -f pr_number="$pr_number" \
          -f head_branch="$head_branch"
        echo "Re-triggered code review for issue #$number (PR #$pr_number)"
      else
        gh issue edit "$number" --repo "$ORCHESTRATOR_REPO" \
          --remove-label "code-review" --add-label "in-progress"
      fi
    fi
  fi
done

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — Recover stale in-progress issues
# ══════════════════════════════════════════════════════════════════════════════
echo "Checking for stale in-progress issues..."
if true; then

stale_issues=$(gh issue list \
  --repo "$ORCHESTRATOR_REPO" \
  --label in-progress \
  --state open \
  --json number,title,body,labels,updatedAt \
  --limit 20)

stale_dispatched=0
while IFS= read -r issue; do
  number=$(echo "$issue" | jq -r '.number')
  title=$(echo "$issue" | jq -r '.title')
  body=$(echo "$issue" | jq -r '.body // ""')
  updated_at=$(echo "$issue" | jq -r '.updatedAt')
  target_repo=$(echo "$issue" | jq -r '.labels[].name' | grep '^repo:' | head -1 | sed 's/repo://' || true)

  if [ -z "$target_repo" ]; then
    echo "Stale issue #$number has no repo: label - skipping"
    continue
  fi

  has_cap_wait=$(echo "$issue" | jq -r '[.labels[].name] | any(. == "cap-wait")')
  if [ "$has_cap_wait" = "true" ]; then
    echo "Issue #$number has active cap-wait — skipping"
    continue
  fi

  has_done=$(echo "$issue" | jq -r '[.labels[].name] | any(. == "done")')
  if [ "$has_done" = "true" ]; then
    gh issue edit "$number" --repo "$ORCHESTRATOR_REPO" --remove-label in-progress
    continue
  fi

  # Check active runs first — only act on "Merge blocked" when no agent is working
  active_runs=$(GH_TOKEN="$DISPATCH_TOKEN" gh run list \
    --repo "${owner}/${target_repo}" \
    --workflow=claude-code.yml \
    --status in_progress \
    --json status --jq 'length' 2>/dev/null || echo "0")
  open_pr=""
  open_pr_number=""
  last_comment=""
  if [ "${active_runs:-0}" -eq 0 ]; then
    open_pr=$(GH_TOKEN="$DISPATCH_TOKEN" gh pr list \
      --repo "${owner}/${target_repo}" --state open \
      --json number,body \
      --jq "[.[] | select(.body | contains(\"orchestrator-strata-reports#${number}\"))] | .[0]" \
      2>/dev/null || echo "")
    if [ -n "$open_pr" ] && [ "$open_pr" != "null" ]; then
      open_pr_number=$(echo "$open_pr" | jq -r '.number // empty' 2>/dev/null || true)
      last_comment=$(GH_TOKEN="$DISPATCH_TOKEN" gh pr view "$open_pr_number" \
        --repo "${owner}/${target_repo}" --json comments \
        --jq '.comments[-1].body[:60]' 2>/dev/null || echo "")
      if echo "$last_comment" | grep -q "Merge blocked"; then
        # Review passed but merge conflict — move to code-review for Guard 2b to rebase
        gh issue edit "$number" --repo "$ORCHESTRATOR_REPO" \
          --remove-label in-progress --add-label code-review 2>/dev/null || true
        echo "Issue #$number: PR #$open_pr_number has merge conflict -- moved to code-review for rebase"
        continue
      fi
    fi
  fi

  age=$(( $(date +%s) - $(date -d "$updated_at" +%s) ))
  if [ "${active_runs:-0}" -eq 0 ]; then
    effective_threshold=900  # 15 min: no agent running, recover quickly
  else
    effective_threshold="$STALE_THRESHOLD_SECONDS"
  fi
  if [ "$age" -lt "$effective_threshold" ]; then
    echo "Issue #$number in-progress for $((age/60))m (threshold: $((effective_threshold/60))m) - skipping"
    continue
  fi

  echo "Issue #$number ('$title') stale for $((age/60))m - checking recovery..."

  if [ -n "$open_pr" ] && [ "$open_pr" != "null" ]; then
    echo "Issue #$number: open PR #$open_pr_number needs revision -- dispatching agent"
  fi
  retry_count=$(echo "$issue" | jq -r '[.labels[].name | select(startswith("retry-"))] | length')
  next_retry=$((retry_count + 1))

  if [ "$retry_count" -ge 3 ]; then
    gh issue edit "$number" --repo "$ORCHESTRATOR_REPO" --remove-label in-progress --add-label agent-failed
    gh issue comment "$number" --repo "$ORCHESTRATOR_REPO" \
      --body "Agent failed **$retry_count** times. Marking **agent-failed** — will retry at lower priority."
    continue
  fi

  branch="feature/issue-${number}"

  if branch_exists "$target_repo" "$branch"; then
    gh issue edit "$number" --repo "$ORCHESTRATOR_REPO" --add-label "retry-$next_retry"

    if [ "$target_repo" = "fn-strata-reports" ]; then
      build_cmd="dotnet build StrataReports.Functions.csproj"
    elif [ "$target_repo" = "dbproj-strata-reports" ]; then
      build_cmd="dotnet build StrataReports.Database.csproj"
    else
      build_cmd="npm install && npm run build"
    fi

    read -r -d '' prompt << PROMPT || true
RESUME incomplete task from StrataReport AI backlog.

Issue #${number} in ${ORCHESTRATOR_REPO}: ${title}

${body}

CONTEXT: A previous agent started this task but did not finish. Branch ${branch} exists with partial work.

Resume instructions:
1. Check out branch ${branch} -- do NOT create a new branch.
2. Run: git log origin/main..HEAD --oneline   to see what was committed.
3. Run: ${build_cmd}   to check current build state.
4. Check for an existing open PR: gh pr list --repo ${owner}/${target_repo} --state open --json number,body --jq "[.[] | select(.body | contains(\"${ORCHESTRATOR_REPO}#${number}\"))] | .[0]"
5. If an open PR exists with review comments: address all findings and push to branch ${branch} (do NOT open a new PR). After pushing, re-trigger review: GH_TOKEN="\$GH_DISPATCH_TOKEN" gh workflow run code-review.yml --repo ${owner}/${target_repo} --field pr_number=[PR_NUMBER] --field head_branch=${branch}
6. If an open PR exists but needs rebase: git merge origin/main, resolve conflicts, push.
7. If no open PR: complete remaining acceptance criteria, then open a PR targeting main.
   PR title: ${title}. PR body must include: Implements ${ORCHESTRATOR_REPO}#${number}
PROMPT

    jq -n --arg prompt "$prompt" --arg branch "$branch" \
      '{"ref":"main","inputs":{"prompt":$prompt,"branch":$branch}}' | \
    GH_TOKEN="$DISPATCH_TOKEN" gh api \
      "repos/${owner}/${target_repo}/actions/workflows/claude-code.yml/dispatches" \
      --method POST --input -

    echo "Dispatched resume for issue #$number to $target_repo"
    stale_dispatched=$((stale_dispatched + 1))
    [ "$stale_dispatched" -ge 1 ] && break
  else
    gh issue edit "$number" --repo "$ORCHESTRATOR_REPO" \
      --remove-label in-progress --add-label ready --add-label "retry-$next_retry"
    gh issue comment "$number" --repo "$ORCHESTRATOR_REPO" \
      --body "Previous agent failed before creating a branch (retry $next_retry/3). Resetting to **ready**."
  fi
done < <(echo "$stale_issues" | jq -c '.[]')
fi

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — Replenish backlog if running low
# ══════════════════════════════════════════════════════════════════════════════
BACKLOG_THRESHOLD=3

open_count=$(gh issue list \
  --repo "$ORCHESTRATOR_REPO" \
  --state open \
  --json number,labels \
  --jq '[.[] | select(.labels | map(.name) | any(. == "ready"))] | length' \
  2>/dev/null || echo "99")

echo "Ready issues: $open_count (threshold: $BACKLOG_THRESHOLD)"

if [ "${open_count:-99}" -lt "$BACKLOG_THRESHOLD" ]; then
  backlog_running=$(GH_TOKEN="$DISPATCH_TOKEN" gh run list \
    --repo "$ORCHESTRATOR_REPO" \
    --workflow=generate-backlog.yml \
    --status in_progress \
    --json status --jq 'length' 2>/dev/null || echo "0")
  if [ "${backlog_running:-0}" -gt 0 ]; then
    echo "Backlog generation already in progress — skipping"
  else
    echo "Backlog below threshold ($BACKLOG_THRESHOLD) — triggering backlog generation"
    bash "$(dirname "$0")/generate-backlog.sh" || echo "Backlog generation dispatch failed (non-fatal)"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2b — Re-trigger code reviews that are stuck (no active review agent)
# Covers the review-retry case: the dev agent fixed revisions but the
# "Trigger code review" step in claude-code.yml skips PRs with review-retry-*.
# ══════════════════════════════════════════════════════════════════════════════
code_review_issues=$(gh issue list \
  --repo "$ORCHESTRATOR_REPO" \
  --label code-review --state open \
  --json number,labels \
  --limit 20 \
  2>/dev/null || echo "[]")

echo "$code_review_issues" | jq -c '.[]' | while read -r cr_issue; do
  cr_number=$(echo "$cr_issue" | jq -r '.number')
  cr_repo=$(echo "$cr_issue" | jq -r '[.labels[].name | select(startswith("repo:"))] | first // empty' | sed 's/repo://')
  [ -z "$cr_repo" ] && continue

  active_review=$(GH_TOKEN="$DISPATCH_TOKEN" gh run list \
    --repo "${owner}/${cr_repo}" \
    --workflow=code-review.yml \
    --status in_progress \
    --json status --jq 'length' 2>/dev/null || echo "0")
  [ "${active_review:-0}" -gt 0 ] && continue

  pr_data=$(GH_TOKEN="$DISPATCH_TOKEN" gh pr list \
    --repo "${owner}/${cr_repo}" --state open \
    --json number,headRefName,body \
    --jq "[.[] | select(.body | contains(\"orchestrator-strata-reports#${cr_number}\"))] | .[0] // empty" \
    2>/dev/null || echo "")
  [ -z "$pr_data" ] || [ "$pr_data" = "null" ] && continue

  pr_number=$(echo "$pr_data" | jq -r '.number')
  head_branch=$(echo "$pr_data" | jq -r '.headRefName')
  GH_TOKEN="$DISPATCH_TOKEN" gh workflow run code-review.yml \
    --repo "${owner}/${cr_repo}" --ref main \
    -f pr_number="$pr_number" \
    -f head_branch="$head_branch"
  echo "Re-triggered code review for issue #$cr_number (${cr_repo} PR #$pr_number)"
done

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — Dispatch next ready task
# Dev slot (in-progress only) — code-review runs in parallel on its own agent.
# Test slot (in-test) is independent: a test running does NOT block dispatch.
# ══════════════════════════════════════════════════════════════════════════════
echo "Checking pipeline state..."

# Per-repo dev slots: collect which repos already have an in-progress issue
occupied_repos=$(gh issue list \
  --repo "$ORCHESTRATOR_REPO" \
  --state open \
  --json labels \
  --jq '[.[] | select(.labels | map(.name) | any(. == "in-progress"))
        | .labels[] | select(.name | startswith("repo:")) | .name | ltrimstr("repo:")] | unique' \
  2>/dev/null || echo "[]")
dev_active_count=$(echo "$occupied_repos" | jq length 2>/dev/null || echo "0")
echo "Occupied repos: $(echo "$occupied_repos" | jq -r 'join(", ")' 2>/dev/null || echo "none")"

in_test_issues=$(gh issue list \
  --repo "$ORCHESTRATOR_REPO" \
  --label in-test \
  --state open \
  --json number,labels,updatedAt \
  --limit 20 \
  2>/dev/null || echo "[]")

in_test_count=$(echo "$in_test_issues" | jq length)

linked_bugs=""

# ── Auto-close story issues where all linked bugs are resolved ────────────────
if [ "$in_test_count" -gt 0 ]; then
  echo "$in_test_issues" | jq -c '.[]' | while read -r in_test_entry; do
    in_test_number=$(echo "$in_test_entry" | jq -r '.number')
    is_bug=$(echo "$in_test_entry" | jq -r '[.labels[].name] | any(. == "bug")')
    [ "$is_bug" = "true" ] && continue  # bugs are closed by the test agent directly

    all_bugs=$(gh issue list \
      --repo "$ORCHESTRATOR_REPO" --label bug --state all --limit 50 \
      --json body \
      --jq "[.[] | select(.body | contains(\"orchestrator-strata-reports#${in_test_number}\"))] | length" \
      2>/dev/null || echo "0")
    [ "${all_bugs:-0}" -eq 0 ] && continue  # never been tested yet — let test agent run first

    open_bugs=$(gh issue list \
      --repo "$ORCHESTRATOR_REPO" --label bug --state open --limit 50 \
      --json body \
      --jq "[.[] | select(.body | contains(\"orchestrator-strata-reports#${in_test_number}\"))] | length" \
      2>/dev/null || echo "1")

    if [ "${open_bugs:-1}" -eq 0 ]; then
      gh issue edit "$in_test_number" --repo "$ORCHESTRATOR_REPO" \
        --remove-label in-test --add-label done 2>/dev/null || true
      echo "Story #$in_test_number: all $all_bugs bug(s) resolved — marking done"
    else
      echo "Story #$in_test_number: $open_bugs/$all_bugs bug(s) still open"
    fi
  done
fi

# ── Dispatch one test per cycle (bugs first, then untested stories) ───────────
if [ "$in_test_count" -gt 0 ]; then
  while IFS= read -r in_test_entry; do
    in_test_number=$(echo "$in_test_entry" | jq -r '.number')

    linked=$(gh issue list \
      --repo "$ORCHESTRATOR_REPO" \
      --label ready --label bug --state open \
      --json number,title,body,labels \
      --limit 10 \
      --jq "[.[] | select(.body | contains(\"orchestrator-strata-reports#${in_test_number}\"))]" \
      2>/dev/null || echo "[]")

    cnt=$(echo "$linked" | jq length)
    if [ "$cnt" -gt 0 ]; then
      linked_bugs="$linked"
      break
    fi

    # Skip if this issue has already been tested (bugs were filed) — auto-close loop handles it
    is_bug=$(echo "$in_test_entry" | jq -r '[.labels[].name] | any(. == "bug")')
    if [ "$is_bug" = "false" ]; then
      all_bugs=$(gh issue list \
        --repo "$ORCHESTRATOR_REPO" --label bug --state all --limit 50 \
        --json body \
        --jq "[.[] | select(.body | contains(\"orchestrator-strata-reports#${in_test_number}\"))] | length" \
        2>/dev/null || echo "0")
      if [ "${all_bugs:-0}" -gt 0 ]; then
        echo "Story #$in_test_number: previously tested ($all_bugs bug(s) filed) — skipping re-test"
        continue
      fi
    fi

    # Only count bugs that are not yet in-test — in-test bugs are already being handled
    open_linked_bug_cnt=$(gh issue list \
      --repo "$ORCHESTRATOR_REPO" \
      --label bug --state open \
      --json number,body,labels \
      --limit 20 \
      --jq "[.[] | select(
        (.body | contains(\"orchestrator-strata-reports#${in_test_number}\")) and
        (.labels | map(.name) | any(. == \"in-test\") | not)
      )] | length" \
      2>/dev/null || echo "0")
    if [ "${open_linked_bug_cnt:-0}" -gt 0 ]; then
      continue
    fi

    updated_at=$(echo "$in_test_entry" | jq -r '.updatedAt')
    age=$(( $(date +%s) - $(date -d "$updated_at" +%s) ))
    target_repo_raw=$(echo "$in_test_entry" | jq -r '[.labels[].name | select(startswith("repo:"))] | first // empty' | sed 's/repo://')
    if [ -n "$target_repo_raw" ]; then
      test_active=$(GH_TOKEN="$DISPATCH_TOKEN" gh run list \
        --repo "${owner}/fn-strata-reports" \
        --workflow=test-agent.yml \
        --status in_progress \
        --json status --jq 'length' 2>/dev/null || echo "0")
    else
      test_active=0
    fi
    # Fire immediately if no test is running; only require stale check if one is already active
    if [ "${test_active:-0}" -eq 0 ] || [ "$age" -gt "$STALE_THRESHOLD_SECONDS" ]; then
      if [ -n "$target_repo_raw" ]; then
        pr=$(GH_TOKEN="$DISPATCH_TOKEN" gh pr list \
          --repo "${owner}/${target_repo_raw}" --state merged \
          --json number,body \
          --jq "[.[] | select(.body | contains(\"orchestrator-strata-reports#${in_test_number}\"))] | .[0].number // empty" \
          2>/dev/null || true)
        if [ -n "$pr" ] && [ "$pr" != "null" ]; then
          GH_TOKEN="$DISPATCH_TOKEN" gh workflow run test-agent.yml \
            --repo "${owner}/fn-strata-reports" --ref main \
            -f pr_numbers="$pr" \
            -f target_repo="$target_repo_raw" \
            -f orchestrator_issues="$in_test_number"
          echo "Dispatched test for issue #$in_test_number (PR #$pr in $target_repo_raw)"
          break  # one test per orchestrator cycle
        fi
      fi
    fi
  done < <(echo "$in_test_issues" | jq -c '.[]')
fi

# Per-repo slots: each repo (fn, dbproj, web) can run one dev agent concurrently.
# Build the full candidate pool (linked bugs take priority, then ready + failed),
# and let the dispatch loop skip any issue whose repo is already occupied.
if [ -n "$linked_bugs" ]; then
  issues="$linked_bugs"
else
  ready_issues=$(gh issue list \
    --repo "$ORCHESTRATOR_REPO" \
    --label ready --state open \
    --json number,title,body,labels \
    --limit 10)

  failed_issues=$(gh issue list \
    --repo "$ORCHESTRATOR_REPO" \
    --label agent-failed --state open \
    --json number,title,body,labels \
    --limit 10)

  issues=$(jq -s '
    (.[0] + .[1]) | unique_by(.number) |
    sort_by(
      if (.labels | map(.name) | any(. == "priority:high")) then 0
      elif (.labels | map(.name) | any(. == "agent-failed")) then 1
      else 2
      end
    )
  ' <(echo "$ready_issues") <(echo "$failed_issues"))
fi

count=$(echo "$issues" | jq length)
echo "Found $count ready task(s)"

if [ "$count" -eq 0 ]; then
  echo "Nothing to dispatch."
  exit 0
fi

dispatched=0

echo "$issues" | jq -c '.[]' | while read -r issue; do
  if [ "$dispatched" -ge 3 ]; then
    break
  fi

  number=$(echo "$issue" | jq -r '.number')
  title=$(echo "$issue" | jq -r '.title')
  body=$(echo "$issue" | jq -r '.body // ""')
  is_bug=$(echo "$issue" | jq -r '[.labels[].name] | any(. == "bug")')
  is_priority=$(echo "$issue" | jq -r '[.labels[].name] | any(. == "priority:high")')
  is_failed=$(echo "$issue" | jq -r '[.labels[].name] | any(. == "agent-failed")')

  target_repo=$(echo "$issue" | jq -r '.labels[].name' | grep '^repo:' | head -1 | sed 's/repo://' || true)

  if [ -z "$target_repo" ]; then
    echo "Issue #$number has no repo: label - skipping"
    continue
  fi

  # Skip if this repo already has an in-progress issue (per-repo dev slot)
  if echo "$occupied_repos" | jq -e --arg r "$target_repo" 'index($r) != null' >/dev/null 2>&1; then
    echo "Issue #$number: $target_repo slot occupied — skipping"
    continue
  fi

  if [ "$target_repo" = "fn-strata-reports" ]; then
    build_cmd="dotnet build StrataReports.Functions.csproj --configuration Release"
  elif [ "$target_repo" = "dbproj-strata-reports" ]; then
    build_cmd="dotnet build StrataReports.Database.csproj --configuration Release"
  else
    build_cmd="npm install && npm run build"
  fi

  if [ "$is_bug" = "true" ]; then
    task_type="Bug fix"
    task_note="This is a confirmed bug found by the QA testing agent. Fix the specific issue — do not add unrelated changes."
  else
    task_type="Feature task"
    task_note=""
  fi

  priority_tag=""
  [ "$is_priority" = "true" ] && priority_tag=" [PRIORITY]"
  echo "Dispatching issue #$number ('$title')${priority_tag} to $target_repo..."

  read -r -d '' prompt << PROMPT || true
${task_type} from StrataReport AI backlog.

Issue #${number} in ${ORCHESTRATOR_REPO}: ${title}

${body}

${task_note}

Instructions:
1. Read CLAUDE.md for coding standards before making any changes.
2. For DB schema or model questions, read the models in Models/ directory.
3. Create branch feature/issue-${number} off main.
4. Implement the task following all project conventions.
5. Run: ${build_cmd}
6. Open a pull request targeting main.
7. PR title: ${title}. PR body must include: Implements ${ORCHESTRATOR_REPO}#${number}
PROMPT

  if [ "$is_failed" = "true" ]; then
    gh issue edit "$number" --repo "$ORCHESTRATOR_REPO" \
      --remove-label agent-failed --add-label in-progress
    for n in 1 2 3; do
      gh issue edit "$number" --repo "$ORCHESTRATOR_REPO" --remove-label "retry-$n" 2>/dev/null || true
    done
  else
    gh issue edit "$number" --repo "$ORCHESTRATOR_REPO" \
      --remove-label ready --add-label in-progress
  fi

  jq -n --arg prompt "$prompt" \
    '{"ref":"main","inputs":{"prompt":$prompt,"branch":"main"}}' | \
  GH_TOKEN="$DISPATCH_TOKEN" gh api \
    "repos/${owner}/${target_repo}/actions/workflows/claude-code.yml/dispatches" \
    --method POST --input -

  echo "Dispatched issue #$number to $target_repo"
  dispatched=$((dispatched + 1))
done

