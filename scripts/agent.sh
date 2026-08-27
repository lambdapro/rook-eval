#!/usr/bin/env bash
# rook transport for the kane-cli assurance agent.
#
# rook scenario goals are literal shell commands, e.g.
#   kane-cli context ingest sources/feature-spec.md --mode agent
# so this runs the goal and returns its output for the judge.
#
# Why a script and not --command directly: rook spawns argv with no shell, so
# it cannot resolve npm's extensionless `kane-cli` shim, and `{{goal}}` must
# stay a single argv token, leaving nowhere to put a `cd`.
set -uo pipefail

# Stable node FIRST. Without this, `node` resolves via whatever fnm multishell
# dir rook's parent shell exported (…/fnm_multishells/<pid>_<ts>/node). Those
# are per-shell and get reaped, so a run inherits a dead path and kane-cli's
# shim dies with 127 *after* streaming its output — which is what made SC-015
# report "agent_never_ran" despite the command actually working.
export PATH="/c/nvm4w/nodejs:/c/Users/mudassars/.npm-global:$PATH"

# Goals use paths relative to the demo workspace: sources/feature-spec.md,
# sources/feature-spec-v2.md, verdicts.json, verdicts-design.json, .context/.
cd /d/assurance/stlc-demo || { echo "transport error: workspace missing" >&2; exit 1; }

goal=${1:-}
cmd_word=${goal%% *}

# rook's `profile test` handshake sends prose, not a command. Answer it so the
# profile verifies, without pretending prose is a shell command.
if ! command -v "$cmd_word" >/dev/null 2>&1; then
  printf 'kane-cli assurance transport ready; goal was not a shell command: %s\n' "$goal"
  exit 0
fi

# Durable context-store state. Many scenarios assert facts that command output
# alone cannot show ("uc-1 gained no acceptance criteria", "extracted items are
# not trusted before review"), so snapshot the graph either side of the goal and
# hand the judge the difference. The update banner is stripped because it is
# release noise, not state.
snapshot() {
  kane-cli context list --json 2>/dev/null \
    | grep -vE 'Update available|Skill update available' \
    | grep -E '^\{' \
    | sort
}

before=$(snapshot)
output=$(eval "$goal" 2>&1)
rc=$?
after=$(snapshot)

printf '%s\n' "$output"

printf '\n===== OBSERVED STATE (added by the rook transport, not by the goal) =====\n'
printf 'goal_exit_code: %s\n' "$rc"

printf '\n--- context nodes after the goal ---\n'
if [ -n "$after" ]; then printf '%s\n' "$after"; else printf '(context store empty or unreadable)\n'; fi

printf '\n--- context nodes changed by this goal ---\n'
if [ "$before" = "$after" ]; then
  printf 'NO CHANGE: the goal created, deleted or modified no context nodes.\n'
else
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") \
    | grep -E '^[<>]' \
    | sed -e 's/^</REMOVED: /' -e 's/^>/ADDED:   /'
fi

# Always exit 0 on a goal that actually ran. rook discards stdout when the
# process exits non-zero (proved by SC-015: valid NDJSON was thrown away and the
# verdict became "agent_never_ran"), so a failing goal must still return its
# evidence. The real status is reported above as goal_exit_code for the judge —
# including for criteria that expect a non-zero exit.
exit 0
