#!/usr/bin/env python3
"""
TeamCreate Audit Hook — PreToolUse:TeamCreate

Logs team creation events to the audit trail. This is the primary
runtime compliance signal: if a protocol agent was expected to create
a team and this hook never fires, the agent violated the protocol.

Never blocks — always exit 0. This is a passive observer.
"""

import json
import sys
from pathlib import Path

# Import shared audit utilities
sys.path.insert(0, str(Path(__file__).parent))
import _audit


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    if tool_name != "TeamCreate":
        sys.exit(0)

    tool_input = data.get("tool_input", {})
    team_name = tool_input.get("team_name", "")
    description = tool_input.get("description", "")

    if team_name:
        _audit.write_team_created(team_name, description)

    sys.exit(0)


if __name__ == "__main__":
    main()
