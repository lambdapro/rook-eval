#!/usr/bin/env bash
# A worked rook transport.
#
# rook substitutes each scenario's goal into {{goal}} and spawns the profile's
# argv directly — no shell. Register this script as the profile:
#
#   rook profile add <name> --command '/abs/path/to/bash /abs/path/to/agent.sh {{goal}}'
#
# On Windows use absolute interpreter paths: rook cannot resolve npm's
# extensionless shims, Node refuses to spawn .cmd without a shell, and `bash`
# is often not on PATH (Git ships it in Git\bin, while only Git\cmd is on PATH).
#
# Configure with environment variables, or edit the defaults below.
set -uo pipefail

# Directory the goals' relative paths resolve against.
AGENT_WORKSPACE="${AGENT_WORKSPACE:-$PWD}"

# Absolute interpreter/tool directories, colon-separated, prepended to PATH.
# Pin real installs here, NOT version-manager shims: a per-shell shim (fnm's
# fnm_multishells/<pid>_<ts>, nvm, pyenv…) can be reaped while a run is using
# it, and the command then dies with exit 127 *after* producing output.
AGENT_PATH_PREPEND="${AGENT_PATH_PREPEND:-}"

# Command printing durable state the acceptance criteria need to observe.
# Leave empty to skip the state block entirely.
AGENT_STATE_CMD="${AGENT_STATE_CMD:-}"

[ -n "$AGENT_PATH_PREPEND" ] && export PATH="$AGENT_PATH_PREPEND:$PATH"
cd "$AGENT_WORKSPACE" || { echo "transport error: $AGENT_WORKSPACE missing" >&2; exit 1; }

goal=${1:-}
cmd_word=${goal%% *}

# rook's `profile test` handshake sends prose, not a command. Answer it, so the
# profile verifies, without pretending prose is a shell command.
if ! command -v "$cmd_word" >/dev/null 2>&1; then
  printf 'transport ready; goal was not a shell command: %s\n' "$goal"
  exit 0
fi

snapshot() {
  [ -n "$AGENT_STATE_CMD" ] || return 0
  eval "$AGENT_STATE_CMD" 2>/dev/null | sort
}

before=$(snapshot)
# stderr folded into stdout: the judge grades one text blob, and most tools
# write progress to stderr. eval, not "$@", because the goal arrives as one
# string that may contain its own quoting.
output=$(eval "$goal" 2>&1)
rc=$?
after=$(snapshot)

printf '%s\n' "$output"

printf '\n===== OBSERVED STATE (added by the transport, not by the goal) =====\n'
printf 'goal_exit_code: %s\n' "$rc"

if [ -n "$AGENT_STATE_CMD" ]; then
  printf '\n--- state after the goal ---\n'
  if [ -n "$after" ]; then printf '%s\n' "$after"; else printf '(empty or unreadable)\n'; fi

  printf '\n--- changed by this goal ---\n'
  if [ "$before" = "$after" ]; then
    printf 'NO CHANGE: the goal created, deleted or modified nothing.\n'
  else
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") \
      | grep -E '^[<>]' \
      | sed -e 's/^</REMOVED: /' -e 's/^>/ADDED:   /'
  fi
fi

# Always exit 0 once the goal actually ran. rook discards stdout when the
# process exits non-zero, so a failing goal would deliver no evidence at all and
# be judged "agent never ran". The real status is reported above as
# goal_exit_code — including for criteria that expect a non-zero exit.
exit 0
