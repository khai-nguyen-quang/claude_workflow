#!/usr/bin/env bash
# Gate commands for the implementation phase (template/epic_workflow.md §6).
#
# Anchored to .gitlab-ci.yml's validate stage — tidy, unit, ASan, TSan, itest,
# py-lint — so a green gate means a green pipeline.
#
# A repo with no ./dev.sh reports the gate as SKIPPED, never as passed.

run_gate() {          # <worktree> <gate>  -> 0 pass, 1 fail, 3 skipped
  local wt="$1" gate="$2"
  [[ -d "$wt" ]] || { echo "worktree missing: $wt"; return 1; }
  [[ -x "$wt/dev.sh" ]] || { echo "no ./dev.sh in $wt — gate '$gate' SKIPPED, not passed"; return 3; }

  local -a cmd
  case "$gate" in
    build)     cmd=(./dev.sh build) ;;
    test)      cmd=(./dev.sh test) ;;
    lint)      cmd=(./dev.sh lint --cpp) ;;
    pylint)    cmd=(./dev.sh lint --python) ;;
    asan)      cmd=(./dev.sh test --asan) ;;
    tsan)      cmd=(./dev.sh test --tsan) ;;
    *)         echo "unknown gate: $gate"; return 1 ;;
  esac

  local out
  out="$(cd "$wt" && "${cmd[@]}" 2>&1)" || { printf '%s\n' "$out" | tail -60; return 1; }

  # A shared build cache can make cached results look like a run, so a test gate
  # must see a summary, not just exit 0.
  case "$gate" in
    test|asan|tsan)
      if ! grep -qiE '[0-9]+ *(test|assertion|case)s? *(ran|passed|ok)|PASSED|OK \(' <<<"$out"; then
        echo "no test summary in output — cannot confirm tests actually ran:"
        printf '%s\n' "$out" | tail -30
        return 1
      fi ;;
  esac
  return 0
}
