#!/usr/bin/env bash
# rook transport for the `catalogue` example agent.
#
# Register it as a profile (absolute paths — rook spawns argv with no shell):
#
#   rook profile add catalogue --command '/bin/bash /abs/path/example/transport.sh {{goal}}'
#
# On Windows, use the absolute bash: 'D:\Git\bin\bash.exe /abs/path/... {{goal}}'
#
# It demonstrates the three things a transport has to get right — see the
# README section "Writing a transport that works".
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
AGENT="$here/agent/catalogue.sh"

# 1. PIN THE INTERPRETER AND THE AGENT. Absolute paths only. A path resolved
#    through PATH can point at a version-manager shim that is reaped mid-run,
#    and the goal then dies with exit 127 *after* producing output.
export PATH="$here/agent:$PATH"

goal=${1:-}

# rook's `profile test` handshake sends prose, not a command. Answer it so the
# profile verifies, instead of failing with "command not found".
case "$goal" in
  catalogue.sh*|catalogue*) ;;
  *)
    printf 'catalogue transport ready; goal was not a catalogue command: %s\n' "$goal"
    exit 0
    ;;
esac

# Normalise "catalogue ..." to the real script.
goal_cmd=${goal#catalogue.sh }
goal_cmd=${goal_cmd#catalogue }

# 3. EXPOSE STATE THE CRITERIA NEED. Scenarios assert durable facts —
#    "nothing changed", "the book is still on loan" — that the command's own
#    output cannot show. Snapshot either side and hand the judge the diff.
before=$("$AGENT" status 2>/dev/null)
# stderr folded into stdout: refusals are written to stderr, and the judge
# grades a single text blob.
output=$(eval "\"\$AGENT\" $goal_cmd" 2>&1)
rc=$?
after=$("$AGENT" status 2>/dev/null)

printf '%s\n' "$output"

printf '\n===== OBSERVED STATE (added by the transport, not by the agent) =====\n'
printf 'goal_exit_code: %s\n' "$rc"

printf '\n--- catalogue after the goal ---\n'
printf '%s\n' "$after"

printf '\n--- changed by this goal ---\n'
if [ "$before" = "$after" ]; then
  printf 'NO CHANGE: the goal altered no loan state.\n'
else
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") \
    | grep -E '^[<>]' \
    | sed -e 's/^</BEFORE: /' -e 's/^>/AFTER:  /'
fi

# 2. RETURN EVIDENCE EVEN ON FAILURE. rook discards stdout when the process
#    exits non-zero, so a refusal (exit 1) would reach the judge as an empty
#    response and be graded "agent never ran" — losing exactly the evidence a
#    negative scenario needs. Exit 0; the real status is reported in-band above.
exit 0
