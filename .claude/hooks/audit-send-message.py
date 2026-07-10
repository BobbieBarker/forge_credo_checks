#!/usr/bin/env python3
"""
SendMessage Audit Hook — PreToolUse:SendMessage

Logs message sends to the audit trail. Two purposes:
1. Evidence of inter-agent communication (protocol compliance)
2. Summarization detection — if a coordinator sends a 200-char message
   where the source context was 5000 chars, it's probably summarizing.

Never blocks — always exit 0. This is a passive observer.
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import _audit


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    if tool_name != "SendMessage":
        sys.exit(0)

    tool_input = data.get("tool_input", {})
    to = tool_input.get("to", "")
    summary = tool_input.get("summary", "")
    message = tool_input.get("message", "")

    # Calculate message length (handle both string and structured messages)
    if isinstance(message, str):
        message_length = len(message)
    else:
        message_length = len(json.dumps(message))

    # Resolve team context — SendMessage doesn't have a team_name field,
    # so we detect the active team from ~/.claude/teams/.
    team_name, _ = _audit.find_active_team()

    if team_name and to:
        _audit.write_message_sent(team_name, to, summary, message_length)

    sys.exit(0)


if __name__ == "__main__":
    main()
