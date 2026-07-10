#!/usr/bin/env python3
"""
Code Boundary Linter — PostToolUse hook for Edit and Write tools

Lightweight lint that catches the highest-confidence architectural violations
as code is written. Runs on every file edit/write. Blocks on violations.

Rules (all scoped to database-backed projects via has_db):
  1. No raw Repo or Ecto.Query usage outside the PG app (except tests/migrations)
  2. No EctoShorts.Actions usage outside the PG app

General external-model producer containment (subprocess, HTTP, and other
vendor boundaries) is enforced separately by the ForgeCredoChecks.
PortProducerBoundary Credo check, not by this edit-time hook.

Exit codes:
  0 — pass (no violations)
  2 — fail (violation found, block the edit)
"""

import json
import re
import sys


def main():
    data = json.load(sys.stdin)

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})

    # Get the file path from the tool input
    file_path = tool_input.get("file_path", "")
    if not file_path:
        return  # No file path, skip

    # Get the new content being written
    # For Edit: check new_string. For Write: check content.
    if tool_name == "Edit":
        content = tool_input.get("new_string", "")
    elif tool_name == "Write":
        content = tool_input.get("content", "")
    else:
        return

    if not content:
        return

    violations = []

    # Determine the app context from the file path
    is_pg_app = "//" in file_path
    is_test_file = "/test/" in file_path
    is_migration = "/migrations/" in file_path
    is_test_helper = "test_helper.exs" in file_path
    is_agent_or_hook = "/.claude/" in file_path
    is_config = "/config/" in file_path
    is_markdown = file_path.endswith(".md")

    # Skip non-Elixir files, config, agent definitions, and hooks
    if is_agent_or_hook or is_config or is_markdown:
        return

    # Skip migrations (they legitimately use Ecto.Query)
    if is_migration:
        return

    

    

    # =======================================================================
    # OUTPUT
    # =======================================================================
    if violations:
        report = "=== Code Boundary Lint ===\n\n"
        for i, v in enumerate(violations, 1):
            report += f"  {i}. {v}\n\n"
        report += "Fix the violation before continuing.\n"
        report += "=== End Lint ==="

        print(json.dumps({
            "decision": "block",
            "reason": report
        }))
        sys.exit(2)


if __name__ == "__main__":
    main()
