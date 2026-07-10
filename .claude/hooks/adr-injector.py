#!/usr/bin/env python3
"""
ADR Context Injector — PreToolUse hook for Edit and Write tools

When an agent is about to edit or create a file, this hook checks what
KIND of file it is (context module, migration, LiveView, test, etc.)
and injects the relevant ADR rules as context. The agent gets the rules
BEFORE writing code, not after Credo flags it.

This is complementary to Credo, not redundant:
  - Credo catches violations AFTER code is written (reactive)
  - This hook provides rules BEFORE code is written (proactive)
  - Credo enforces via AST analysis (precise, comprehensive)
  - This hook advises via pattern matching on file paths (fast, contextual)

Never blocks — always exit 0. Outputs advisory text via JSON stdout
with hookSpecificOutput.additionalContext, which the harness injects
into the model's context window as a system reminder.
"""

import json
import os
import sys
from fnmatch import fnmatch
from pathlib import Path

SUPPORTED_EXTENSIONS = (".ex", ".exs", ".erl", ".hrl", ".ts", ".tsx")


def load_rules():
    """Load the ADR rules registry."""
    rules_path = Path(__file__).parent / "adr-rules.json"
    try:
        return json.loads(rules_path.read_text())
    except (json.JSONDecodeError, OSError):
        return None


def match_context(file_path, registry):
    """Find which context(s) match the given file path."""
    matches = []
    # Normalize to relative path from project root
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if project_dir and file_path.startswith(project_dir):
        rel_path = file_path[len(project_dir):].lstrip("/")
    else:
        rel_path = file_path

    for ctx_name, ctx in registry.get("contexts", {}).items():
        # Check exclude patterns first
        excluded = False
        for pattern in ctx.get("exclude_patterns", []):
            if fnmatch(rel_path, pattern):
                excluded = True
                break
        if excluded:
            continue

        # Check include patterns
        for pattern in ctx.get("file_patterns", []):
            if fnmatch(rel_path, pattern):
                matches.append((ctx_name, ctx))
                break

    return matches


def format_rules(matches, file_path, registry):
    """Format matched rules into advisory output."""
    if not matches:
        return None

    # Deduplicate rules across contexts (same file might match multiple)
    seen_rules = set()
    rules_to_show = []
    context_names = []

    # Global rules apply to all Elixir files
    for rule in registry.get("global_rules", []):
        key = (rule["adr"], rule["summary"])
        if key not in seen_rules:
            seen_rules.add(key)
            rules_to_show.append(rule)

    for ctx_name, ctx in matches:
        context_names.append(ctx_name)
        for rule in ctx.get("rules", []):
            key = (rule["adr"], rule["summary"])
            if key not in seen_rules:
                seen_rules.add(key)
                rules_to_show.append(rule)

    if not rules_to_show:
        return None

    # Format as concise advisory
    basename = os.path.basename(file_path)
    ctx_label = " + ".join(context_names)

    lines = [
        f"=== ADR Rules ({ctx_label}: {basename}) ===",
        "",
    ]

    # Collect unique ADR numbers for the reference line
    adr_numbers = sorted(set(r["adr"] for r in rules_to_show))

    for rule in rules_to_show:
        lines.append(f"  [ADR-{rule['adr']}] {rule['summary']}")
        lines.append(f"    {rule['rule']}")
        lines.append("")

    # Point to shadow ADRs for full patterns + code examples
    shadow_refs = [f".claude/adr-agent/{n}-*.md" for n in adr_numbers]
    ref_list = ", ".join(shadow_refs)
    lines.append(f"  For code examples and anti-patterns, read: {ref_list}")
    lines.append("")

    lines.append("=== End ADR Rules ===")
    return "\n".join(lines)


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    if tool_name not in ("Edit", "Write"):
        sys.exit(0)

    tool_input = data.get("tool_input", {})
    file_path = tool_input.get("file_path", "")

    if not file_path:
        sys.exit(0)

    if not file_path.endswith(SUPPORTED_EXTENSIONS):
        sys.exit(0)

    registry = load_rules()
    if not registry:
        sys.exit(0)

    matches = match_context(file_path, registry)
    if not matches:
        sys.exit(0)

    output = format_rules(matches, file_path, registry)
    if output:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "additionalContext": output,
            }
        }))

    # Always allow — this is advisory, not blocking
    sys.exit(0)


if __name__ == "__main__":
    main()
