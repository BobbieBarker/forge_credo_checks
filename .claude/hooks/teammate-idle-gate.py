#!/usr/bin/env python3
"""
TeammateIdle hook — quality gate for agent team teammates going idle.

Fires when a teammate is about to go idle after finishing its turn.
Checks if there are unclaimed tasks the teammate could pick up, or
if the teammate has unfinished quality checks.

Exit codes:
  0 — allow teammate to go idle
  2 — keep teammate working, send feedback via stderr

Claude Code 2.1.170 invokes TeammateIdle as a top-level hook event but rejects
hookSpecificOutput for that event, so this hook intentionally emits no stdout.
The advisory checklist text is retained below as the intended content for a
future supported delivery channel.
"""

import json
import os
import sys


FIXER_ADVISORY = (
    "Before going idle, verify:\n"
    "1. Your fix has been pushed to the feature branch\n"
    "2. CI passes on the updated branch\n"
    "3. You sent the structured completion report to the coordinator\n"
    "\n"
    "If all three are done, mark your task as complete."
)

IMPLEMENTER_ADVISORY = (
    "Before going idle, verify:\n"
    "1. Your PR has been created with a ## Self-Review section\n"
    "2. CI passes locally\n"
    "3. Post-PR verification is complete (auto-reviewer comments addressed)\n"
    "4. You sent the structured completion report to the coordinator\n"
    "\n"
    "If all four are done, mark your task as complete."
)

UNSUPPORTED_JSON_ENV_VAR = "FORGE_TEAMMATE_IDLE_EMIT_UNSUPPORTED_JSON"


def get_input():
    """Read hook input from stdin."""
    try:
        return json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        return {}


def advisory_for(teammate_name):
    """Return the intended idle checklist for a teammate role."""
    teammate_name = teammate_name.lower()
    if "fixer" in teammate_name:
        return FIXER_ADVISORY
    if "impl" in teammate_name or "implementer" in teammate_name:
        return IMPLEMENTER_ADVISORY
    return ""


def emit_unsupported_json_advisory(advisory):
    """Emit the legacy experimental payload used only by the FGE-1068 canary."""
    if os.environ.get(UNSUPPORTED_JSON_ENV_VAR) != "1":
        return
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "TeammateIdle",
            "additionalContext": advisory,
        }
    }))


def main():
    data = get_input()

    teammate_name = data.get("teammate_name", "")

    # Coordinators can go idle — they're managing, not implementing
    if "coordinator" in teammate_name.lower() or "lead" in teammate_name.lower():
        sys.exit(0)

    # For implementers: check if they reported completion properly
    # The TaskCompleted hook handles the PR self-review check.
    # This hook catches the case where a teammate tries to go idle
    # WITHOUT marking their task as complete first.
    #
    # We can't easily check task status from a shell hook (no API access
    # to the task list from outside the agent). So this hook serves as
    # a reminder rather than a hard gate.

    # Advisory, not blocking — exit 0 so we don't create infinite loops where
    # the teammate can never go idle. The TaskCompleted hook is the hard gate.
    advisory = advisory_for(teammate_name)
    if advisory:
        emit_unsupported_json_advisory(advisory)
        sys.exit(0)
    sys.exit(0)


if __name__ == "__main__":
    main()
