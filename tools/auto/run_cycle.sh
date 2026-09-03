#!/usr/bin/env bash
# run_cycle.sh — drive workflow stages for any number of tickets at once.
#
# Every run is STAGE FLAGS + REFS. Nothing is implied: with no stage flag the
# script prints its usage and exits.
#
#   --research    brainstorming only, on a `research::` ticket
#   --design      planning (brainstorm + design) -> plan-review        [loop]
#   --code        coding -> review -> fix_review                       [loop]
#   --verify      test -> lint -> integration tests                    [loop]
#   --doc         write the research/design up as a document in the repo
#   --review      review a merge request, report its verdict           [loop]
#   --fix_review  act on a merge request's review
#
# Stage flags combine and always run in that order, so the whole issue cycle is
# `--design --code --verify`. Every stage takes any number of refs: each gets
# its own worktree and its own window, and they all run at the same time
# (--serial for one at a time).
#
# Each stage opens its own terminal and runs Claude Code INTERACTIVELY inside
# it — the normal TUI, exactly as if you had typed `claude` yourself — with the
# phase prompt already submitted. You watch it work, you answer its permission
# prompts, you can steer it. When a phase is finished you exit the session
# (Ctrl-D or /exit); the driver then runs that phase's gate and either moves on
# or drops you back into the SAME session with the real failure output.
#
# The stage's window closes when its gate passes. The next stage starts a fresh
# `claude` process — stages never share a session, so each begins clean.
#
# `--headless` restores the old unattended behaviour (`claude -p`, streamed as
# JSON), for runs nobody is going to sit in front of.
#
# The DRIVER, not the model, runs every gate: the build's exit code, the test
# summary, the lint run, the review verdict. A model's claim that something is
# clean is not evidence.
#
# NOTE: --design automates the design-approval gate that template/workflow.md
# reserves for a human. Nobody reviews the brainstorm spec or the design before
# coding starts. Run `--code` on its own after approving a design by hand when
# that review matters.
#
# Usage:
#   run_cycle.sh <stage-flags> '<ref>'... [options]
#
# Examples:
#   run_cycle.sh --design 'projectX#123' 'projectX#456'
#   run_cycle.sh --code   'projectX#123' 'projectX#456'
#   run_cycle.sh --verify 'projectX#123'
#   run_cycle.sh --design --code --verify 'projectX#309'   # the whole cycle
#   run_cycle.sh --research --doc 'projectX#412'           # a research ticket
#   run_cycle.sh --review --fix_review 'projectX#MR!123' 'projectX#MR!456'
#
# SINGLE-QUOTE MR refs. In an interactive shell `!177` is a history expansion
# and bash rejects the line with "event not found" before this script ever runs.
# Double quotes do not help; single quotes do.

set -euo pipefail

# The stage sessions are real top-level sessions, not sub-agents of whatever
# launched this script. Inheriting a parent Claude's markers turns transcript
# saving off, and a session with no transcript cannot be --resume'd -- which is
# exactly what every repair attempt does.
unset CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ID CLAUDE_CODE_ENTRYPOINT \
      CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
CLAUDE_WORKFLOW="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# Exported so the phases and the workflow shell tools resolve the same workspace.
WORKSPACE_ROOT="$(cd "${CLAUDE_WORKFLOW}/.." && pwd)"
export WORKSPACE_ROOT

ALL_STAGES=(research design code verify doc)

# Planning needs Skill (superpowers:brainstorming) and the agent tool; coding,
# review and fix_review need the agent tool too.
CLAUDE_TOOLS="Bash,Edit,Write,Read,Glob,Grep,Task,Agent,Skill,TodoWrite"

_show_help() {
  cat << 'EOF'
Usage: run_cycle.sh <stage-flags> '<ref>'... [options]

Stage flags say WHAT to run, refs say WHAT ON. Nothing is implied: with no
stage flag this help is all you get.

  --research     /wf research — brainstorming on its own, for a ticket whose
                 description starts with `research::`. Produces the same
                 <slug>_brainstorm.md as --design's first step and stops there:
                 no design document, no code. Pair it with --doc.
  --design       /wf planning  -> /wf plan-review     loop until no design conflicts
  --code         /wf coding    -> /wf review          loop until PRODUCTION READY
                               -> /wf fix_review        (between review rounds)
  --verify       /wf test -> /wf lint -> integration   loop until all gates pass
  --doc          /wf doc — write up whatever --research or --design produced as
                 a document under the worktree's docs/, committed on the branch
                 so it ships with the MR.
  --review       /wf review on a merge request. A verdict of NEEDS WORK is a
                 result, not a failure — the report is the deliverable.
  --fix_review   /wf fix_review on a merge request. On its own it acts on the
                 review that already exists; combined with --review it becomes
                 review -> fix -> re-review, looping until PRODUCTION READY or
                 --max-iter rounds.

--research/--design/--code/--verify/--doc take GitLab issue refs (projectX#309)
and COMBINE, always running in that order whatever order they were typed:

  run_cycle.sh --design --code --verify 'projectX#309'   # a feature ticket
  run_cycle.sh --research --doc 'projectX#412'           # a research ticket

--research and --design cannot be combined: both write <slug>_brainstorm.md, so
design's brainstorming step would overwrite what research produced.

--review/--fix_review take merge request refs ('projectX#MR!177'). Issue stages
and merge request stages cannot be mixed in one command.

Every stage takes ANY NUMBER of refs. Each ref gets its own worktree and its own
window and they ALL RUN AT ONCE (--serial for one at a time); the worktrees are
still created one at a time first, because `git worktree add` in the shared main
checkout cannot be run concurrently. With several builds running together, set
--jobs. One ref failing does not stop the others.

SINGLE-QUOTE MR refs: bare projectX#MR!177 makes an interactive bash try a
history expansion on !177 and fail with "event not found". Double quotes do not
help; single quotes do.

Every window runs Claude Code INTERACTIVELY — the normal TUI, with the phase
prompt already submitted. Exit a session (Ctrl-D or /exit) when its phase is
done: the driver then runs that phase's gate and starts the next phase in the
same window by itself, or on failure puts you back in the SAME session with the
real failure output. You never type a phase yourself; ending a session is the
only manual step. The window closes when the stage's gate passes.

Examples:
  run_cycle.sh --design 'projectX#123' 'projectX#456'
  run_cycle.sh --code   'projectX#123' 'projectX#456'
  run_cycle.sh --verify 'projectX#123'
  run_cycle.sh --research --doc 'projectX#412' 'projectX#413'
  run_cycle.sh --design --code --verify --doc 'projectX#309'
  run_cycle.sh --review --fix_review 'projectX#MR!123' 'projectX#MR!456'
  run_cycle.sh --design 'projectX#123' --no-terminal    # inline, no windows

Options:
  --serial             One ref at a time. By default every ref gets its own
                       window and they all run at once.
  --max-repair <n>     Repair attempts per failed gate (default: 2). A repair
                       resumes the SAME session with the real failure output.
  --max-iter <n>       Review/plan-review rounds per stage (default: 3).
  --jobs <n>           Value for SCONS_JOBS, inherited by the phases too. Set
                       this when running several refs at once, e.g.
                       --jobs $(( $(nproc) / 3 )).
  --terminal <kind>    Force the terminal: gnome-terminal, terminator, xterm,
                       x-terminal-emulator, tmux. Default: auto-detected.
  --no-terminal        Run the stages inline in this shell, no windows.
  --headless           Drive `claude -p` instead of the TUI. The work is still
                       shown in the window, but the loop runs itself with
                       nothing to exit by hand — and Claude never stops to ask,
                       so brainstorming records its assumptions in the spec
                       instead of interviewing you, and nobody but the model
                       reviews the design. Selected automatically when there is
                       no TTY.
  --interactive        The TUI (the default). Only needed to override a
                       --headless earlier on the command line.
  --dry-run            Print what would run without running anything.
  --help, -h           Show this help.

Gates (run by this script, never by the model):
  research -> _brainstorm.md exists and was written by this run.
  design  -> _brainstorm.md and _design.md exist and were written by this run,
             and _plan_review.md ends in DESIGN OK.
  code    -> ./dev.sh build compiles, and _review.md is fresh and carries the
             verdict PRODUCTION READY.
  verify  -> ./dev.sh test, plus a check that tests actually EXECUTED. A summary
             of "Passed: 0 / Cached: n" means every stamp was restored from the
             shared SCons cache and nothing ran; the driver then re-runs the
             test binaries for the changed modules directly. Then ./dev.sh lint
             for the languages the branch touches (never --all), then
             ./dev.sh itest for the integration tests the change reaches, if any.
  doc     -> a fresh _doc.md naming the document it generated on a `Document:`
             line, and that document actually existing in the worktree.
  mr      -> a fresh <slug>_review.md carrying a verdict. With --fix_review the
             fix must also still build (no ./dev.sh in the repo -> gate skipped,
             and it says so rather than pretending it ran).

Exit codes:
  0 everything requested passed   1 usage/setup error   2 a stage failed
Every ref is attempted; the exit code reports whether any failed.
EOF
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
ref=""; max_repair=2; max_iter=3; jobs=""
stage_mode=""; terminal_kind=""; use_terminal=true; dry_run=false
interactive=true
mr_review=false; mr_fix=false; serial=false
refs=(); declare -A want=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --research)    want[research]=1; shift ;;
    --design)      want[design]=1; shift ;;
    --code)        want[code]=1;   shift ;;
    --verify)      want[verify]=1; shift ;;
    --doc)         want[doc]=1;    shift ;;
    --max-repair)  max_repair="$2"; shift 2 ;;
    --max-iter)    max_iter="$2"; shift 2 ;;
    --jobs)        jobs="$2"; shift 2 ;;
    --terminal)    terminal_kind="$2"; shift 2 ;;
    --no-terminal) use_terminal=false; shift ;;
    --headless)    interactive=false; shift ;;
    --interactive) interactive=true;  shift ;;
    --review)      mr_review=true; shift ;;
    --fix_review|--fix-review) mr_fix=true; shift ;;
    --serial)      serial=true; shift ;;
    --stage)       stage_mode="$2"; shift 2 ;;   # internal: run one stage here
    --dry-run)     dry_run=true; shift ;;
    --help|-h)     _show_help; exit 0 ;;
    --*)           echo "Error: unknown flag '$1'" >&2; exit 1 ;;
    *)             refs+=("$1"); shift ;;
  esac
done

mr_mode=false
[[ "${mr_review}" == true || "${mr_fix}" == true ]] && mr_mode=true

# The issue stages requested, always in ALL_STAGES order — the flags may be
# given in any order, but design still runs before code before verify.
stages=()
for s in "${ALL_STAGES[@]}"; do [[ -n "${want[${s}]:-}" ]] && stages+=("${s}"); done

[[ "${#refs[@]}" -eq 0 ]] && { _show_help; exit 1; }

# A --stage child is told its one stage directly and carries no stage flags.
if [[ -z "${stage_mode}" ]]; then
  if [[ "${mr_mode}" == true && "${#stages[@]}" -gt 0 ]]; then
    echo "Error: --design/--code/--verify drive issues, --review/--fix_review drive" >&2
    echo "  merge requests. They cannot be mixed — run two commands." >&2
    exit 1
  fi
  if [[ "${mr_mode}" != true && "${#stages[@]}" -eq 0 ]]; then
    echo "Error: pick a stage: --research, --design, --code, --verify, --doc," >&2
    echo "  --review and/or --fix_review." >&2
    echo "" >&2
    _show_help >&2
    exit 1
  fi
  # Both write <slug>_brainstorm.md, so design's brainstorming step would
  # overwrite what research just produced.
  if [[ -n "${want[research]:-}" && -n "${want[design]:-}" ]]; then
    echo "Error: --research and --design both write <slug>_brainstorm.md." >&2
    echo "  Pick one: --research stops at the spec, --design carries it into a" >&2
    echo "  design document." >&2
    exit 1
  fi
fi

if [[ "${mr_mode}" == true ]]; then
  for r in "${refs[@]}"; do
    [[ "${r}" == *"MR!"* ]] || {
      echo "Error: '${r}' is not a merge request ref (expected projectX#MR!177)." >&2
      echo "  --review / --fix_review act on merge requests. Use --design/--code/" >&2
      echo "  --verify for an issue instead." >&2
      exit 1; }
  done
else
  for r in "${refs[@]}"; do
    [[ "${r}" == *"MR!"* ]] && {
      echo "Error: '${r}' is an MR. Use --review or --fix_review for merge requests." >&2; exit 1; }
    [[ "${r}" == *"#"* ]] || {
      echo "Error: '${r}' is not a GitLab issue ref (expected projectX#309)." >&2; exit 1; }
  done
fi

# An MR ref carries its iid after `MR!`, and its artifacts live under a
# <project>-mr-<iid> slug — the same slug worktree.sh uses for its checkout.
_derive_ids() {  # <ref> — sets P_PROJECT P_IID P_SLUG P_TMP P_LOG
  local r="$1"
  P_PROJECT="${r%%#*}"
  if [[ "${r}" == *"MR!"* ]]; then P_IID="${r##*MR!}"; P_SLUG="${P_PROJECT}-mr-${P_IID}"
  else                             P_IID="${r##*#}";   P_SLUG="${P_PROJECT}-${P_IID}"; fi
  P_TMP="${CLAUDE_WORKFLOW}/.tmp/${P_SLUG}"
  P_LOG="${P_TMP}/cycle"
}

# The driver in MR mode walks several refs; every other context is one ref.
ref="${refs[0]}"
_derive_ids "${ref}"
project="${P_PROJECT}"; iid="${P_IID}"; slug="${P_SLUG}"
TMP_DIR="${P_TMP}"; LOG_DIR="${P_LOG}"

command -v jq >/dev/null || { echo "Error: jq is required." >&2; exit 1; }
command -v claude >/dev/null || { echo "Error: the claude CLI is not on PATH." >&2; exit 1; }

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
_ts()   { date '+%H:%M:%S'; }
_say()  { echo "[$(_ts)] $*"; }
_step() { echo ""; echo "[$(_ts)] ===== $* ====="; }
_fail() { echo "[$(_ts)] FAIL: $*" >&2; }

# ---------------------------------------------------------------------------
# Worktree
# ---------------------------------------------------------------------------
# Re-exec'd stage processes inherit WF_REPO; only the outer driver resolves it.
if [[ -z "${stage_mode}" ]]; then
  # Every ref has its own worktree; the driver resolves them all below and hands
  # each one down to its own window. Handing a single one down here would run
  # every ref in the first one's checkout.
  unset WF_REPO
  REPO_ROOT=""
elif [[ -n "${WF_REPO:-}" && -d "${WF_REPO}" ]]; then
  REPO_ROOT="${WF_REPO}"
elif [[ "${dry_run}" == true ]]; then
  # `path` never creates anything — a dry run must not leave a worktree behind.
  # It exits non-zero when the worktree does not exist yet; predict the path
  # from the documented layout instead of failing the whole dry run.
  _say "Ticket ${ref}"
  if REPO_ROOT="$(bash "${CLAUDE_WORKFLOW}/tools/git/worktree.sh" path "${ref}" 2>/dev/null)"; then
    _say "Worktree ${REPO_ROOT} (dry run — exists)"
  else
    REPO_ROOT="${WORKSPACE_ROOT}/${project}-worktree/${slug}"
    _say "Worktree ${REPO_ROOT} (dry run — would be created)"
  fi
  export WF_REPO="${REPO_ROOT}"
else
  _say "Ticket ${ref}"
  # Not --quiet: creating a worktree from scratch is a fetch plus a recursive
  # submodule init, and a silent two-minute wait reads as a hang. Progress goes
  # to stderr; only the path lands on stdout.
  REPO_ROOT="$(bash "${CLAUDE_WORKFLOW}/tools/git/worktree.sh" ensure "${ref}")" \
    || { _fail "could not prepare the worktree for ${ref}"; exit 1; }
  export WF_REPO="${REPO_ROOT}"
  _say "Worktree ${REPO_ROOT}"
fi

mkdir -p "${LOG_DIR}"
[[ -n "${jobs}" ]] && export SCONS_JOBS="${jobs}"

# A --stage child is handed its stage by the driver; anything else is a bug.
_check_stage() {
  local wanted="$1" st
  for st in "${ALL_STAGES[@]}" mr; do [[ "${st}" == "${wanted}" ]] && return 0; done
  echo "Error: unknown stage '${wanted}' (expected one of: ${ALL_STAGES[*]} mr)" >&2; exit 1
}

# ---------------------------------------------------------------------------
# Driving claude — one visible, streaming process per phase
# ---------------------------------------------------------------------------
SESSION_ID=""

_new_session_id() {
  if command -v uuidgen >/dev/null; then uuidgen
  else cat /proc/sys/kernel/random/uuid; fi
}

# "<ref> <branch>" — what every window is named. Claude Code overwrites the
# terminal title with its own; `--name` is what it puts there instead, so the
# window says which ticket it belongs to rather than "Claude Code".
_window_name() {
  local repo="${1:-${REPO_ROOT:-}}" br=""
  [[ -n "${repo}" ]] && br="$(git -C "${repo}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  echo "${ref}${br:+ ${br}}"
}

# Between phases the driver, not Claude, owns the window; keep the title right
# through the builds and tests too.
_set_title() {
  [[ "${WF_IN_TERMINAL:-0}" == "1" ]] || return 0
  printf '\033]0;%s\007' "$*"
}

_banner() {
  local line
  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  for line in "$@"; do echo " ${line}"; done
  echo "────────────────────────────────────────────────────────────────────────"
  echo ""
}

# stream-json carries the session id and the error flag; this turns it into
# something readable while the raw events are kept for the driver to parse.
_pretty() {
  jq -r --unbuffered '
    if .type == "assistant" then
      (.message.content[]? |
        if   .type == "text"     then (.text // "")
        elif .type == "tool_use" then "  -> " + (.name // "?") + "  " + ((.input // {} | tostring)[0:110])
        else empty end)
    elif .type == "user" then
      (.message.content[]? | select(.type == "tool_result")
        | "     <- " + (((.content // "" | tostring) | gsub("\n"; " "))[0:110]))
    elif .type == "result" then
      "\n===== " + (if (.is_error // false) then "ERROR" else "done" end) + " =====\n"
    else empty end' 2>/dev/null || true
}

# <label> <new|resume> <what-you-are-watching> <prompt>
# Interactive: the real TUI, prompt pre-submitted, you exit when the phase is
# done. Headless: `claude -p`, streamed to screen and to a jsonl for parsing.
# The session id is assigned by the driver, so a repair can resume the exact
# session without parsing anything out of the session's output.
_claude_exec() {
  local label="$1" mode="$2" what="$3" prompt="$4"
  local jsonl="${LOG_DIR}/${label}.jsonl"

  if [[ "${interactive}" == true && ( ! -t 0 || ! -t 1 ) ]]; then
    interactive=false
    _say "No TTY here — falling back to headless (claude -p)."
  fi

  if [[ "${mode}" == new ]]; then SESSION_ID="$(_new_session_id)"; fi
  local -a select_session
  if [[ "${mode}" == new ]]; then select_session=( --session-id "${SESSION_ID}" )
  else
    [[ -z "${SESSION_ID}" || "${SESSION_ID}" == "dry-run" ]] && return 1
    select_session=( --resume "${SESSION_ID}" )
  fi

  # ORDER MATTERS. `--allowedTools <tools...>` is variadic: it eats every
  # following argument until the next flag, so a prompt placed after it is
  # swallowed as a tool name and Claude starts with an empty input box.
  # The prompt goes before the trailing flags, and --allowedTools goes last.
  local -a tail_flags=( --name "$(_window_name)"
                        --permission-mode acceptEdits
                        --add-dir "${CLAUDE_WORKFLOW}"
                        --allowedTools "${CLAUDE_TOOLS}" )

  if [[ "${dry_run}" == true ]]; then
    if [[ "${interactive}" == true ]]; then echo "  + claude ${select_session[*]} '<prompt>' ${tail_flags[*]}"
    else echo "  + claude -p ${select_session[*]} '<prompt>' --output-format stream-json ${tail_flags[*]}"; fi
    SESSION_ID="dry-run"; return 0
  fi

  if [[ "${interactive}" == true ]]; then
    _banner "wf ${ref}  ·  ${what}" \
            "${REPO_ROOT}" \
            "" \
            "Claude Code opens below with the prompt already submitted." \
            "Watch it, answer its prompts, steer it as you normally would." \
            "" \
            "When this phase is FINISHED, exit the session (Ctrl-D or /exit)." \
            "The driver then runs the gate and starts the NEXT phase in this" \
            "same window by itself — or brings you back into this session with" \
            "the real failure output. You never type a phase yourself." \
            "" \
            "Ending each session is the only manual step, and it is what the" \
            "TUI costs: --headless runs the whole loop with no exiting (and no" \
            "questions), still showing the work, but with nobody reviewing it."
    local rc=0
    ( cd "${REPO_ROOT}" && claude "${select_session[@]}" "${prompt}" "${tail_flags[@]}" ) || rc=$?
    # Claude leaves its own title behind on exit; take the window back.
    _set_title "$(_window_name) — gate"
    [[ "${rc}" -ne 0 ]] && _say "Session exited with status ${rc} — the gate decides what happens next."
    # No result event to inspect: in interactive mode the gate is the only judge.
    return 0
  fi

  ( cd "${REPO_ROOT}" && claude -p "${select_session[@]}" "${prompt}" \
      --output-format stream-json --verbose "${tail_flags[@]}" ) \
    2> "${LOG_DIR}/${label}.stderr" | tee "${jsonl}" | _pretty || true

  local result_line
  result_line="$(jq -c 'select(.type == "result")' "${jsonl}" 2>/dev/null | tail -1)"
  if [[ -z "${result_line}" ]]; then
    _fail "'${label}' produced no result event (see ${jsonl} and ${label}.stderr)"
    return 1
  fi
  if [[ "$(jq -r '.is_error // false' <<< "${result_line}")" == "true" ]]; then
    _fail "'${label}' reported an error: $(jq -r '.result // ""' <<< "${result_line}" | head -5)"
    return 1
  fi
  return 0
}

_claude_phase() {  # <phase> <label> [directive] — fresh session running /wf <phase>
  local phase="$1" label="$2" directive="${3:-}"
  local prompt="/wf ${phase} ${ref}"
  [[ -n "${directive}" ]] && prompt+="

${directive}"
  _say "Running /wf ${phase} ${ref}  [${label}]"
  _claude_exec "${label}" new "/wf ${phase} ${ref}" "${prompt}"
}

_claude_resume() {  # <label> <message> — continue the phase's own session
  local label="$1" msg="$2"
  [[ -z "${SESSION_ID}" || "${SESSION_ID}" == "dry-run" ]] && return 1
  _say "Resuming session ${SESSION_ID:0:8}  [${label}]"
  _claude_exec "${label}" resume "repair — ${label}" "${msg}"
}

_repair_message() {  # <what> <logfile>
  cat << EOF
The ${1} gate failed. Real output:

$(tail -80 "${2}" 2>/dev/null)

Fix the underlying cause in $(basename "${REPO_ROOT}") and re-verify.
Do NOT weaken a test, relax an assertion, delete a case, or narrow a lint scope
to make this pass -- if the code is wrong, fix the code. If the failure is in
work outside this ticket's scope, say so explicitly instead of working around it.
EOF
}

# ---------------------------------------------------------------------------
# Gates — run by the driver, never by the model
# ---------------------------------------------------------------------------
_dev() {  # <logfile> <args...> — run ./dev.sh in the worktree, tee to a log
  local log="$1"; shift
  if [[ "${dry_run}" == true ]]; then echo "  + ./dev.sh $*"; return 0; fi
  ( cd "${REPO_ROOT}" && ./dev.sh "$@" ) > >(tee "${log}") 2>&1
}

_changed_files() {
  local base
  base="$(git -C "${REPO_ROOT}" merge-base HEAD origin/HEAD 2>/dev/null \
       || git -C "${REPO_ROOT}" merge-base HEAD origin/master 2>/dev/null || echo "")"
  [[ -z "${base}" ]] && return 0
  git -C "${REPO_ROOT}" diff --name-only "${base}" HEAD
  git -C "${REPO_ROOT}" diff --name-only            # uncommitted work counts too
}

GATE_LOG=""

_gate_build() {
  GATE_LOG="${LOG_DIR}/gate-build.log"
  _dev "${GATE_LOG}" build
}

# A green exit code is not enough: `.passed` stamps restore from the shared SCons
# CacheDir, so a run can report success having executed nothing. Require that
# something actually ran, and if not, run the affected binaries directly
# (`./dev.sh test <binary>` runs the binary, it does not rebuild a stamp).
_gate_test() {
  GATE_LOG="${LOG_DIR}/gate-test.log"
  _dev "${GATE_LOG}" test || return 1
  [[ "${dry_run}" == true ]] && return 0

  grep -q '^Test Summary$' "${GATE_LOG}" || {
    _fail "no Test Summary in the output — no test targets were requested"; return 1; }

  local passed failed cached notrun
  passed="$(sed -n 's/^Passed: *\([0-9]\+\)/\1/p'  "${GATE_LOG}" | tail -1)"
  failed="$(sed -n 's/^Failed: *\([0-9]\+\)/\1/p'  "${GATE_LOG}" | tail -1)"
  cached="$(sed -n 's/^Cached: *\([0-9]\+\)/\1/p'  "${GATE_LOG}" | tail -1)"
  notrun="$(sed -n 's/^Not Run: *\([0-9]\+\)/\1/p' "${GATE_LOG}" | tail -1)"
  _say "Test Summary — passed=${passed:-?} failed=${failed:-?} cached=${cached:-?} notRun=${notrun:-0}"

  [[ "${failed:-0}" -gt 0 ]] && { _fail "${failed} test(s) failed"; return 1; }
  [[ "${notrun:-0}" -gt 0 ]] && { _fail "${notrun} requested test(s) did not run"; return 1; }
  [[ "${passed:-0}" -gt 0 ]] && return 0
  [[ "${cached:-0}" -eq 0 ]] && { _fail "no tests passed and none were cached"; return 1; }

  _say "Every stamp came from the cache — running the affected test binaries directly."
  _verify_cached_tests
}

_verify_cached_tests() {
  local variant="${OPENPILOT_VARIANT_ROOT:-build/x86_64/release}"
  local -a dirs=() bins=()
  mapfile -t dirs < <(_changed_files | xargs -r -n1 dirname | sort -u)
  local d b
  for d in "${dirs[@]}"; do
    while IFS= read -r b; do bins+=("${b#"${REPO_ROOT}/"}"); done \
      < <(find "${REPO_ROOT}/${variant}/${d}" -maxdepth 2 -type f -executable -name 'test_*' 2>/dev/null)
  done
  mapfile -t bins < <(printf '%s\n' "${bins[@]:-}" | grep -v '^$' | sort -u)

  if [[ "${#bins[@]}" -eq 0 ]]; then
    _fail "the whole suite was cached and no test binary could be matched to the changed files."
    echo "  Nothing was independently verified. Refusing to advance." >&2
    return 1
  fi
  local rc=0
  for b in "${bins[@]}"; do
    _say "  re-running ${b}"
    _dev "${LOG_DIR}/gate-test-rerun.log" test "${b}" || rc=1
  done
  [[ "${rc}" -ne 0 ]] && _fail "a directly re-run test binary failed"
  return "${rc}"
}

_gate_lint() {
  GATE_LOG="${LOG_DIR}/gate-lint.log"
  : > "${GATE_LOG}"
  local -a changed=(); mapfile -t changed < <(_changed_files | sort -u)
  local rc=0 langs=()
  printf '%s\n' "${changed[@]:-}" | grep -qE '\.(cc|cpp|h|hpp)$' && langs+=(--cpp)
  printf '%s\n' "${changed[@]:-}" | grep -qE '\.py$'             && langs+=(--python)
  printf '%s\n' "${changed[@]:-}" | grep -qE '\.sh$'             && langs+=(--shell)
  if [[ "${#langs[@]}" -eq 0 ]]; then _say "No lintable files changed."; return 0; fi
  local l
  for l in "${langs[@]}"; do
    _say "  ./dev.sh lint ${l}"
    # Never --all: it scans the whole tree and is forbidden in this project.
    _dev "${LOG_DIR}/gate-lint${l}.log" lint "${l}" || rc=1
    [[ "${dry_run}" == true ]] || cat "${LOG_DIR}/gate-lint${l}.log" >> "${GATE_LOG}"
  done
  return "${rc}"
}

# The integration tests this change reaches: the *_docker.py files it touched,
# plus the ones living beside any module it touched.
_itest_targets() {
  local -a changed=() targets=()
  mapfile -t changed < <(_changed_files | sort -u)
  local f d t
  for f in "${changed[@]}"; do
    [[ -z "${f}" ]] && continue
    if [[ "${f}" == */test_*_docker.py ]]; then
      [[ -f "${REPO_ROOT}/${f}" ]] && targets+=("${f}")
      continue
    fi
    d="$(dirname "${f}")"
    while IFS= read -r t; do targets+=("${t#"${REPO_ROOT}/"}"); done \
      < <(find "${REPO_ROOT}/${d}/tests" "${REPO_ROOT}/${d}/test" \
               -maxdepth 1 -name 'test_*_docker.py' 2>/dev/null)
  done
  printf '%s\n' "${targets[@]:-}" | grep -v '^$' | sort -u
}

_gate_itest() {
  GATE_LOG="${LOG_DIR}/gate-itest.log"
  local -a targets=(); mapfile -t targets < <(_itest_targets)
  if [[ "${#targets[@]}" -eq 0 ]]; then
    _say "No integration tests reached by this change — skipping itest."
    : > "${GATE_LOG}"; return 0
  fi
  _say "Integration tests: ${targets[*]}"
  local rc=0 t
  : > "${GATE_LOG}"
  for t in "${targets[@]}"; do
    _dev "${LOG_DIR}/gate-itest-one.log" itest "${t}" || rc=1
    [[ "${dry_run}" == true ]] || cat "${LOG_DIR}/gate-itest-one.log" >> "${GATE_LOG}"
  done
  [[ "${rc}" -ne 0 ]] && _fail "an integration test failed"
  return "${rc}"
}

# _gate_with_repair <gate-fn> <what> <repair-label-prefix>
# Runs the gate; on failure feeds the REAL output back into the live session.
_gate_with_repair() {
  local gate="$1" what="$2" prefix="$3" attempt=0
  while :; do
    if "${gate}"; then _say "Gate '${what}' passed."; return 0; fi
    attempt=$((attempt + 1))
    if [[ "${attempt}" -gt "${max_repair}" ]]; then
      _fail "gate '${what}' still failing after ${max_repair} repair attempt(s)."
      echo "  Logs: ${LOG_DIR}" >&2
      return 1
    fi
    _say "Repair attempt ${attempt}/${max_repair} for gate '${what}'."
    _claude_resume "${prefix}-repair-${attempt}" "$(_repair_message "${what}" "${GATE_LOG}")" \
      || { _fail "cannot resume the session to repair"; return 1; }
  done
}

# ---------------------------------------------------------------------------
# Stage — research: brainstorming on its own, for a `research::` ticket
# ---------------------------------------------------------------------------
# Research produces the SAME artifact as the first step of design — the approved
# brainstorm spec — and stops there. The gate is that the spec is fresh.
_gate_brainstorm() {
  GATE_LOG="${LOG_DIR}/gate-research.log"
  [[ "${dry_run}" == true ]] && return 0
  local spec="${TMP_DIR}/${slug}_brainstorm.md"
  if [[ ! -f "${spec}" ]]; then
    _fail "no brainstorm spec at ${spec}"
    echo "no brainstorm spec" > "${GATE_LOG}"; return 1
  fi
  if [[ ! "${spec}" -nt "${LOG_DIR}/.stage-start" ]]; then
    _fail "${spec} was not written by this run (stale)"
    echo "stale brainstorm spec" > "${GATE_LOG}"; return 1
  fi
  cp "${spec}" "${GATE_LOG}"
  return 0
}

_stage_research() {
  _step "Research ${ref}"
  touch "${LOG_DIR}/.stage-start"
  _claude_phase research "research" "$(_planning_directive)" || return 1
  _gate_with_repair _gate_brainstorm "research" "research" || return 1
  _say "Research spec: ${TMP_DIR}/${slug}_brainstorm.md"
  return 0
}

# ---------------------------------------------------------------------------
# Stage 1 — design: planning, then plan-review, until the design is conflict-free
# ---------------------------------------------------------------------------
# Interactively there is a human in the loop, so brainstorming may do its job
# and ask. Headless, nobody can answer, and it has to decide and record instead.
_planning_directive() {
  [[ "${interactive}" == true ]] && return 0
  cat << 'EOF'
NON-INTERACTIVE RUN: nobody can answer questions. Work through the brainstorming
step by making the decisions yourself and RECORDING them -- every assumption you
had to make goes into the spec under "Assumptions", not into a question back to
the user. Do not stop for approval at any gate. Produce the brainstorm spec and
the design document, then update _state.md.
EOF
}

_plan_review_directive() {
  [[ "${interactive}" == true ]] \
    || echo "NON-INTERACTIVE RUN: do not ask for confirmation about anything you find."
  cat << EOF
In addition to the phase's normal work, WRITE the review to
  ${TMP_DIR}/${slug}_plan_review.md
That file must END with a line that is exactly one of:
  DESIGN OK
  CONFLICTS FOUND
Use CONFLICTS FOUND if the brainstorm spec and the design document disagree, if
the design contradicts the issue's acceptance criteria, or if the design leaves
a decision that coding cannot make on its own. Above that verdict line, list
every conflict as a numbered item naming the document, the section, what
conflicts, and the fix. Use DESIGN OK only when there is nothing left to fix.
EOF
}

_gate_plan_review() {
  GATE_LOG="${LOG_DIR}/gate-plan-review.log"
  [[ "${dry_run}" == true ]] && { PLAN_VERDICT="DESIGN OK"; return 0; }
  local report="${TMP_DIR}/${slug}_plan_review.md"
  if [[ ! -f "${report}" ]]; then
    _fail "no plan review at ${report}"; echo "no plan review file" > "${GATE_LOG}"; return 1
  fi
  if [[ ! "${report}" -nt "${LOG_DIR}/.stage-start" ]]; then
    _fail "${report} was not written by this run (stale)"
    echo "stale plan review" > "${GATE_LOG}"; return 1
  fi
  PLAN_VERDICT=""
  if   grep -qE '^\W*\**CONFLICTS FOUND' "${report}"; then PLAN_VERDICT="CONFLICTS FOUND"
  elif grep -qE '^\W*\**DESIGN OK'       "${report}"; then PLAN_VERDICT="DESIGN OK"
  fi
  if [[ -z "${PLAN_VERDICT}" ]]; then
    _fail "no verdict line in ${report}"; echo "no verdict line" > "${GATE_LOG}"; return 1
  fi
  cp "${report}" "${GATE_LOG}"
  _say "Plan review verdict: ${PLAN_VERDICT}"
  [[ "${PLAN_VERDICT}" == "DESIGN OK" ]]
}

_stage_design() {
  local design="${TMP_DIR}/${slug}_design.md" round=0

  _step "Planning ${ref}"
  _claude_phase planning "planning" "$(_planning_directive)" || return 1
  if [[ "${dry_run}" != true && ! -f "${design}" ]]; then
    _fail "planning produced no design document at ${design}"; return 1
  fi

  while :; do
    round=$((round + 1))
    _step "Plan review — round ${round}/${max_iter}"
    touch "${LOG_DIR}/.stage-start"
    _claude_phase plan-review "plan-review-${round}" "$(_plan_review_directive)" || return 1

    if _gate_plan_review; then
      _say "Design is conflict-free after ${round} review round(s)."
      return 0
    fi
    if [[ "${PLAN_VERDICT:-}" != "CONFLICTS FOUND" ]]; then
      return 1   # missing/stale report — not something the planner can fix
    fi
    if [[ "${round}" -ge "${max_iter}" ]]; then
      _fail "design still has conflicts after ${max_iter} round(s). Stopping for a human."
      echo "  Report: ${TMP_DIR}/${slug}_plan_review.md" >&2
      return 1
    fi
    _step "Fixing the design findings — round ${round}"
    _claude_phase planning "planning-fix-${round}" "$(cat << EOF
$(_planning_directive)

The design has already been written and then reviewed. The review found the
conflicts below. Do NOT re-plan from scratch: update ${slug}_brainstorm.md and
${slug}_design.md so every finding is resolved, and leave the rest alone.

$(cat "${TMP_DIR}/${slug}_plan_review.md")
EOF
)" || return 1
  done
}

# ---------------------------------------------------------------------------
# Stage 2 — code: coding, then review/fix_review until PRODUCTION READY
# ---------------------------------------------------------------------------
# A fresh report carrying SOME verdict. Whether that verdict is good enough is
# the caller's business: implementing an issue demands PRODUCTION READY, while
# reviewing someone's MR only demands that the review actually happened.
_gate_review_report() {
  GATE_LOG="${LOG_DIR}/gate-review.log"
  [[ "${dry_run}" == true ]] && { VERDICT="PRODUCTION READY"; return 0; }
  local report="${TMP_DIR}/${slug}_review.md"
  if [[ ! -f "${report}" ]]; then
    _fail "no review report at ${report}"; echo "no review report" > "${GATE_LOG}"; return 1
  fi
  if [[ ! "${report}" -nt "${LOG_DIR}/.stage-start" ]]; then
    _fail "${report} was not written by this run (stale report)"
    echo "stale review report" > "${GATE_LOG}"; return 1
  fi
  VERDICT=""
  if   grep -qiE '^\W*\**NOT PRODUCTION READY' "${report}"; then VERDICT="NOT PRODUCTION READY"
  elif grep -qiE '^\W*\**NEEDS WORK'           "${report}"; then VERDICT="NEEDS WORK"
  elif grep -qiE '^\W*\**PRODUCTION READY'     "${report}"; then VERDICT="PRODUCTION READY"
  fi
  if [[ -z "${VERDICT}" ]]; then
    _fail "no production-readiness verdict found in ${report}"
    echo "no verdict line in the report" > "${GATE_LOG}"; return 1
  fi
  _say "Review verdict: ${VERDICT}"
  cp "${report}" "${GATE_LOG}"
  return 0
}

_gate_review() {
  _gate_review_report || return 1
  [[ "${VERDICT}" == "PRODUCTION READY" ]]
}

# MRs come from every project in the workspace, and only some of them are built
# with ./dev.sh. Claiming a build gate ran when there is nothing to run it with
# would be worse than saying so.
_gate_build_optional() {
  if [[ ! -f "${REPO_ROOT}/dev.sh" ]]; then
    GATE_LOG="${LOG_DIR}/gate-build.log"
    _say "No ./dev.sh in $(basename "${REPO_ROOT}") — no build gate for this repo."
    : > "${GATE_LOG}"; return 0
  fi
  _gate_build
}

_stage_code() {
  local design="${TMP_DIR}/${slug}_design.md" round=0

  if [[ "${dry_run}" != true && ! -f "${design}" ]]; then
    _fail "no design document at ${design}."
    echo "  Coding implements a design. Run --design first, or write and approve" >&2
    echo "  the design by hand." >&2
    return 1
  fi

  _step "Coding ${ref}"
  _claude_phase coding "coding" || return 1
  _gate_with_repair _gate_build "build" "coding" || return 1

  while :; do
    round=$((round + 1))
    _step "Review — round ${round}/${max_iter}"
    touch "${LOG_DIR}/.stage-start"
    _claude_phase review "review-${round}" || return 1

    if _gate_review; then
      _say "Code is PRODUCTION READY after ${round} review round(s)."
      return 0
    fi
    if [[ -z "${VERDICT:-}" ]]; then
      return 1   # missing/stale report — fix_review has nothing to act on
    fi
    if [[ "${round}" -ge "${max_iter}" ]]; then
      _fail "review still ${VERDICT} after ${max_iter} round(s). Stopping for a human."
      echo "  Report: ${TMP_DIR}/${slug}_review.md" >&2
      return 1
    fi
    _step "Fixing review findings — round ${round} (verdict was ${VERDICT})"
    _claude_phase fix_review "fix-review-${round}" || return 1
    _gate_with_repair _gate_build "build" "fix-review-${round}" || return 1
  done
}

# ---------------------------------------------------------------------------
# Stage 3 — verify: tests, lint, integration tests
# ---------------------------------------------------------------------------
_stage_verify() {
  _step "Writing and running tests for ${ref}"
  _claude_phase test "test" || return 1
  _gate_with_repair _gate_test "test" "test" || return 1

  _step "Lint"
  _claude_phase lint "lint" || return 1
  _gate_with_repair _gate_lint "lint" "lint" || return 1

  _step "Integration tests"
  # The lint session is the live one; it is the session a failure is fed back to.
  _gate_with_repair _gate_itest "itest" "itest" || return 1

  # Lint and itest fixes touch code, so the unit tests have to still hold.
  _step "Re-checking the unit tests after the fixes"
  _gate_with_repair _gate_test "test" "test-recheck" || return 1
  return 0
}

# ---------------------------------------------------------------------------
# Stage — doc: write up the research or the design as a document in the repo
# ---------------------------------------------------------------------------
# The phase writes the document into the worktree and records where; the driver
# gate checks the record and then the document itself, so "I wrote the doc" in a
# transcript is never enough.
_doc_directive() {
  [[ "${interactive}" == true ]] \
    || echo "NON-INTERACTIVE RUN: nobody can answer. Choose the document's path, title and structure yourself and record them."
  cat << EOF
In addition to the phase's normal work, WRITE the record to
  ${TMP_DIR}/${slug}_doc.md
Its FIRST line must be exactly:
  Document: <path of the document you generated, relative to REPO_ROOT>
Below that, summarise what the document covers and which artifacts it was
written from (${slug}_brainstorm.md and/or ${slug}_design.md).
EOF
}

_gate_doc() {
  GATE_LOG="${LOG_DIR}/gate-doc.log"
  [[ "${dry_run}" == true ]] && return 0
  local record="${TMP_DIR}/${slug}_doc.md"
  if [[ ! -f "${record}" ]]; then
    _fail "no doc record at ${record}"; echo "no doc record" > "${GATE_LOG}"; return 1
  fi
  if [[ ! "${record}" -nt "${LOG_DIR}/.stage-start" ]]; then
    _fail "${record} was not written by this run (stale)"
    echo "stale doc record" > "${GATE_LOG}"; return 1
  fi
  local doc_rel
  doc_rel="$(sed -nE 's/^[[:space:]]*[-*]?[[:space:]]*\**Document:\**[[:space:]]*//p' "${record}" \
             | head -1 | tr -d '`' | sed -E 's/[[:space:]]+$//')"
  if [[ -z "${doc_rel}" ]]; then
    _fail "${record} has no 'Document: <path>' line naming what it generated"
    echo "no Document: line in the doc record" > "${GATE_LOG}"; return 1
  fi
  # A record pointing at nothing is a claim, not a document.
  local doc_abs="${doc_rel}"
  [[ "${doc_abs}" == /* ]] || doc_abs="${REPO_ROOT}/${doc_rel}"
  if [[ ! -f "${doc_abs}" ]]; then
    _fail "the document named in ${record} does not exist: ${doc_rel}"
    echo "missing document: ${doc_rel}" > "${GATE_LOG}"; return 1
  fi
  _say "Document: ${doc_rel}"
  cp "${record}" "${GATE_LOG}"
  return 0
}

_stage_doc() {
  local spec="${TMP_DIR}/${slug}_brainstorm.md" design="${TMP_DIR}/${slug}_design.md"

  if [[ "${dry_run}" != true && ! -f "${spec}" && ! -f "${design}" ]]; then
    _fail "nothing to write up for ${ref}."
    echo "  --doc documents what --research or --design produced, and neither" >&2
    echo "  ${slug}_brainstorm.md nor ${slug}_design.md exists. Run one first." >&2
    return 1
  fi

  _step "Documenting ${ref}"
  touch "${LOG_DIR}/.stage-start"
  _claude_phase doc "doc" "$(_doc_directive)" || return 1
  _gate_with_repair _gate_doc "doc" "doc" || return 1
  return 0
}


# ---------------------------------------------------------------------------
# MR stage — review and/or fix_review one merge request
#
#   --review              review it, report whatever verdict comes back
#   --fix_review          act on the review that already exists
#   --review --fix_review review, fix, re-review, until PRODUCTION READY
# ---------------------------------------------------------------------------
_stage_mr() {
  local round=0

  if [[ "${mr_review}" != true ]]; then
    _step "Fixing review comments on ${ref}"
    _claude_phase fix_review "fix-review" || return 1
    _gate_with_repair _gate_build_optional "build" "fix-review" || return 1
    MR_RESULT="fixed"
    return 0
  fi

  while :; do
    round=$((round + 1))
    _step "Reviewing ${ref} — round ${round}/${max_iter}"
    touch "${LOG_DIR}/.stage-start"
    _claude_phase review "review-${round}" || return 1

    # No verdict at all means the review did not happen — that IS a gate failure.
    _gate_with_repair _gate_review_report "review" "review-${round}" || return 1
    MR_RESULT="${VERDICT}"

    [[ "${VERDICT}" == "PRODUCTION READY" ]] && return 0
    # Reviewing on its own is informational: the verdict is the deliverable.
    [[ "${mr_fix}" != true ]] && return 0

    if [[ "${round}" -ge "${max_iter}" ]]; then
      _fail "${ref} still ${VERDICT} after ${max_iter} round(s). Stopping for a human."
      echo "  Report: ${TMP_DIR}/${slug}_review.md" >&2
      return 1
    fi
    _step "Fixing review findings — round ${round} (verdict was ${VERDICT})"
    _claude_phase fix_review "fix-review-${round}" || return 1
    _gate_with_repair _gate_build_optional "build" "fix-review-${round}" || return 1
  done
}

# ---------------------------------------------------------------------------
# Stage mode — this process IS one stage, running inside its own terminal
# ---------------------------------------------------------------------------
MR_RESULT=""
if [[ -n "${stage_mode}" ]]; then
  _check_stage "${stage_mode}"
  status_file="${LOG_DIR}/${stage_mode}.status"
  echo "fail: stage aborted" > "${status_file}"
  touch "${LOG_DIR}/.stage-start"

  _set_title "$(_window_name)"
  _step "Stage '${stage_mode}' — ${ref}"
  _say "Worktree ${REPO_ROOT}"
  rc=0
  "_stage_${stage_mode}" || rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    # The MR stage reports its verdict back through the status file.
    echo "ok${MR_RESULT:+: ${MR_RESULT}}" > "${status_file}"
    _step "Stage '${stage_mode}' passed."
  else
    echo "fail: gate not met (rc=${rc})" > "${status_file}"
    _fail "stage '${stage_mode}' did not pass. Logs: ${LOG_DIR}"
    # Give the window a moment to be read before it closes.
    [[ "${WF_IN_TERMINAL:-0}" == "1" ]] && read -r -t 30 -p "Press Enter to close this window... " || true
  fi
  exit "${rc}"
fi

# ---------------------------------------------------------------------------
# Terminal launching
# ---------------------------------------------------------------------------
_detect_terminal() {
  local t
  if [[ -n "${terminal_kind}" ]]; then echo "${terminal_kind}"; return; fi
  if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    for t in gnome-terminal terminator xterm x-terminal-emulator; do
      command -v "${t}" >/dev/null && { echo "${t}"; return; }
    done
  fi
  command -v tmux >/dev/null && { echo tmux; return; }
  echo none
}

STATUS_TEXT=""

_launch_stage() {  # <stage> [ref] — open a window, run the stage, wait for it to close
  local stage="$1" this_ref="${2:-${ref}}" br=""
  br="$(git -C "${WF_REPO:-${REPO_ROOT:-.}}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  # Same shape as the --name Claude will set, so the title does not jump around.
  local title="${this_ref}${br:+ ${br}}"
  local -a inner=( bash "${SCRIPT_PATH}" "${this_ref}" --stage "${stage}"
                   --max-repair "${max_repair}" --max-iter "${max_iter}" )
  # The mode is always passed down explicitly, so the child never has to guess.
  local child_int="${interactive}"

  [[ -n "${jobs}" ]]           && inner+=( --jobs "${jobs}" )
  [[ "${child_int}" == true ]] && inner+=( --interactive ) || inner+=( --headless )
  [[ "${mr_review}" == true ]]   && inner+=( --review )
  [[ "${mr_fix}" == true ]]      && inner+=( --fix_review )
  [[ "${dry_run}" == true ]]     && inner+=( --dry-run )

  _derive_ids "${this_ref}"
  mkdir -p "${P_LOG}"

  if [[ "${use_terminal}" != true || "${TERMINAL_KIND}" == "none" || "${dry_run}" == true ]]; then
    [[ "${dry_run}" == true ]] && _say "Would open a ${TERMINAL_KIND} window for stage '${stage}'."
    _say "Running stage '${stage}' inline."
    local rc=0
    "${inner[@]}" || rc=$?
    STATUS_TEXT="$(cat "${P_LOG}/${stage}.status" 2>/dev/null || echo "")"
    return "${rc}"
  fi

  if [[ "${child_int}" == true ]]; then
    _say "Opening a ${TERMINAL_KIND} window for stage '${stage}' — interactive, you exit each phase."
  else
    _say "Opening a ${TERMINAL_KIND} window for stage '${stage}' — headless, it runs the whole loop itself."
  fi
  export WF_IN_TERMINAL=1
  case "${TERMINAL_KIND}" in
    gnome-terminal) gnome-terminal --wait --title="${title}" -- "${inner[@]}" || true ;;
    terminator)     terminator -u -T "${title}" -x "${inner[@]}" || true ;;
    xterm)          xterm -T "${title}" -e "${inner[@]}" || true ;;
    x-terminal-emulator) x-terminal-emulator -e "${inner[@]}" || true ;;
    tmux)           tmux new-session -s "wf-${stage}-${P_SLUG}" "$(printf '%q ' "${inner[@]}")" || true ;;
    *)              _fail "unknown terminal '${TERMINAL_KIND}'"; return 1 ;;
  esac
  unset WF_IN_TERMINAL

  # The window's exit status is not reliable across emulators; the stage records
  # its own outcome instead.
  local status_file="${P_LOG}/${stage}.status"
  STATUS_TEXT="$(cat "${status_file}" 2>/dev/null || echo "fail: stage wrote no status")"
  [[ "${STATUS_TEXT}" == ok* ]] && return 0
  _fail "stage '${stage}' (${this_ref}): ${STATUS_TEXT}"
  return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
TERMINAL_KIND="$(_detect_terminal)"
if [[ "${use_terminal}" == true && "${TERMINAL_KIND}" == "none" ]]; then
  _say "No terminal emulator found — running the stages inline."
fi

# ---------------------------------------------------------------------------
# Run — every ref in its own window(s), all at the same time
# ---------------------------------------------------------------------------
# Merge requests go through the single 'mr' stage; issues through whichever of
# design/code/verify were asked for, in that order.
run_stages=( "${stages[@]}" )
if [[ "${mr_mode}" == true ]]; then
  run_stages=( mr )
  what="review"
  [[ "${mr_fix}" == true ]]    && what="review + fix_review"
  [[ "${mr_review}" != true ]] && what="fix_review"
else
  what="${run_stages[*]}"
fi
_say "${what} for ${#refs[@]} ref(s): ${refs[*]}"

# Resolve every worktree FIRST, one at a time. `worktree.sh ensure` fetches and
# runs `git worktree add` in the shared main checkout, and several of those at
# once race on its index.lock. Once the checkouts exist, the windows touch
# nothing in common and can run together.
#
# No --quiet here: a fresh checkout means a fetch plus a recursive submodule
# init, which takes a couple of minutes per ref. Silence for that long is
# indistinguishable from a hang, so worktree.sh's own progress (stderr) is left
# to stream through; only the path it prints on stdout is captured.
declare -A REPO_FOR=()
_step "Preparing ${#refs[@]} worktree(s)"
[[ "${dry_run}" == true ]] \
  || _say "A worktree that does not exist yet takes ~2 min (fetch + submodules)."
for r in "${refs[@]}"; do
  _derive_ids "${r}"; mkdir -p "${P_LOG}"
  # A stale status from an earlier run must never be read as this run's result.
  for st in "${run_stages[@]}"; do rm -f "${P_LOG}/${st}.status"; done
  if [[ "${dry_run}" == true ]]; then
    REPO_FOR["${r}"]="$(bash "${CLAUDE_WORKFLOW}/tools/git/worktree.sh" path "${r}" 2>/dev/null \
                        || echo "${WORKSPACE_ROOT}/${P_PROJECT}-worktree/${P_SLUG}")"
    _say "  ${r} -> ${REPO_FOR[${r}]} (dry run)"
  else
    _say "  ${r} — preparing ${P_SLUG} ..."
    t0="$(date +%s)"
    REPO_FOR["${r}"]="$(bash "${CLAUDE_WORKFLOW}/tools/git/worktree.sh" ensure "${r}")" \
      || { _fail "could not prepare the worktree for ${r}"; exit 1; }
    _say "  ${r} -> ${REPO_FOR[${r}]}  ($(( $(date +%s) - t0 ))s)"
  fi
done

# Every requested stage of one ref, in order, in that ref's worktree. A stage
# that fails stops this ref only — the other refs keep going.
_run_ref() {  # <ref>
  local r="$1" st
  for st in "${run_stages[@]}"; do
    _launch_stage "${st}" "${r}" || return 1
  done
}

if [[ "${serial}" == true || "${#refs[@]}" -eq 1 ]]; then
  for r in "${refs[@]}"; do
    _step "${r}"
    # One ref going wrong is not a reason to skip the rest.
    ( export WF_REPO="${REPO_FOR[${r}]}"; _run_ref "${r}" ) || true
  done
else
  [[ -z "${jobs}" ]] \
    && _say "Note: ${#refs[@]} builds may run at once. Consider --jobs \$(( \$(nproc) / ${#refs[@]} ))."
  _step "Opening ${#refs[@]} ref(s) at once"
  pids=()
  for r in "${refs[@]}"; do
    # Each child carries its OWN worktree in its own environment.
    ( export WF_REPO="${REPO_FOR[${r}]}"; _run_ref "${r}" ) &
    pids+=("$!")
    _say "  ${r} (pid $!)"
  done
  _say "Waiting for all ${#refs[@]} ref(s) to finish."
  for p in "${pids[@]}"; do wait "${p}" || true; done
fi

# A background child cannot report back through a variable; the status file each
# stage writes is the only thing shared with the driver.
failed=0
_step "Done — ${#refs[@]} ref(s)"
for r in "${refs[@]}"; do
  _derive_ids "${r}"
  bad=0
  for st in "${run_stages[@]}"; do
    status="$(cat "${P_LOG}/${st}.status" 2>/dev/null || echo "fail: stage did not run")"
    [[ "${status}" == ok* ]] || bad=1
    printf '  %-26s %-7s %s\n' "${r}" "${st}" "${status#ok: }"
  done
  [[ "${bad}" -eq 0 ]] || failed=$((failed + 1))
  [[ "${mr_review}" == true ]] \
    && printf '  %-26s %-7s %s\n' "" "" "${P_TMP}/${P_SLUG}_review.md"
  printf '  %-26s %-7s %s\n' "" "" "${P_LOG}"
done

if [[ "${failed}" -gt 0 ]]; then
  _fail "${failed} of ${#refs[@]} did not complete."
  exit 2
fi
if [[ "${mr_mode}" != true && -n "${want[verify]:-}" ]]; then
  echo ""
  echo "Next (both need you): review the diff, then '/wf create_mr <ref>'."
fi
exit 0
