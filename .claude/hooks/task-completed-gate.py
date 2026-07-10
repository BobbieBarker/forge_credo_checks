#!/usr/bin/env python3
"""
TaskCompleted hook — quality gate for agent team task completion.

Fires when a teammate marks a task as completed. Checks that the
implementer has met quality requirements before allowing the task
to close.

Checks:
  1. If the task looks like an implementation task (not research/coordination),
     verify that a PR was created by looking for PR URL patterns in recent
     git/gh output or the task description.
  2. If a PR exists, verify the PR body contains a ## Self-Review section.

Project-specific values (ticket prefixes, repo) are read from project.json
via _project_config.

Exit codes:
  0 — allow task completion
  2 — block completion, send feedback to teammate via stderr
"""

import json
import re
import subprocess
import sys
from pathlib import Path

# Import project config
sys.path.insert(0, str(Path(__file__).parent))
import _project_config


def get_input():
    """Read hook input from stdin."""
    try:
        return json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        return {}


def is_implementation_task(task_subject, task_description):
    """Determine if this task is an implementation task that needs a Self-Review."""
    subject = (task_subject or "").lower()
    desc = (task_description or "").lower()
    combined = subject + " " + desc

    # Skip non-implementation tasks
    skip_patterns = [
        r"research",
        r"investigate",
        r"review.*pr",
        r"visual qa",
        r"merge.*wave",
        r"checkpoint",
        r"update.*linear",
        r"clean.?up",
        r"verify.*main",
        r"rebase",
        r"coordinate",
        r"report.*chad",
    ]

    for pattern in skip_patterns:
        if re.search(pattern, combined):
            return False

    # Build ticket prefix pattern from config
    ticket_pattern = _project_config.ticket_prefix_pattern_case_insensitive()

    # Implementation tasks typically mention tickets, PRs, or code work
    impl_patterns = [
        r"implement",
        r"build",
        r"create.*pr",
        r"add.*feature",
        r"fix.*bug",
        r"write.*test",
        r"schema",
        r"context",
        r"liveview",
        r"worker",
        r"controller",
    ]

    # Add ticket prefix pattern if configured
    if ticket_pattern:
        impl_patterns.insert(0, ticket_pattern)

    for pattern in impl_patterns:
        if re.search(pattern, combined):
            return True

    # Default: don't gate unknown task types
    return False


def find_pr_number(task_subject, task_description, cwd):
    """Try to find the PR number associated with this task."""
    combined = (task_subject or "") + " " + (task_description or "")

    cfg = _project_config.get_config()
    repo = cfg.get("repo", "")

    # Check if PR URL or number is mentioned in the task
    pr_match = re.search(r"#(\d+)|pulls?/(\d+)", combined)
    if pr_match:
        return pr_match.group(1) or pr_match.group(2)

    # Try to find PR from the ticket ID
    ticket_pattern = _project_config.ticket_prefix_pattern_case_insensitive()
    if ticket_pattern:
        ticket_match = re.search(rf"({ticket_pattern})", combined, re.IGNORECASE)
        if ticket_match and repo:
            ticket_id = ticket_match.group(0).lower()
            try:
                cmd = [
                    "gh", "pr", "list", "--head", ticket_id,
                    "--json", "number", "--limit", "1",
                ]
                if repo:
                    cmd.extend(["--repo", repo])
                result = subprocess.run(
                    cmd,
                    capture_output=True, text=True, timeout=10, cwd=cwd,
                )
                if result.returncode == 0:
                    prs = json.loads(result.stdout)
                    if prs:
                        return str(prs[0]["number"])
            except (subprocess.TimeoutExpired, json.JSONDecodeError, KeyError):
                pass

    return None


def check_self_review(pr_number, cwd):
    """Check if the PR body contains a ## Self-Review section."""
    cfg = _project_config.get_config()
    repo = cfg.get("repo", "")

    try:
        cmd = ["gh", "pr", "view", pr_number, "--json", "body"]
        if repo:
            cmd.extend(["--repo", repo])
        result = subprocess.run(
            cmd,
            capture_output=True, text=True, timeout=10, cwd=cwd,
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            body = data.get("body", "")
            if re.search(r"##\s*Self[- ]?Review", body, re.IGNORECASE):
                return True, body
            return False, body
    except (subprocess.TimeoutExpired, json.JSONDecodeError):
        pass

    # Can't verify — don't block
    return True, ""


def main():
    data = get_input()

    task_subject = data.get("task_subject", "")
    task_description = data.get("task_description", "")
    cwd = data.get("cwd", ".")

    # Only gate implementation tasks
    if not is_implementation_task(task_subject, task_description):
        sys.exit(0)

    # Try to find the PR
    pr_number = find_pr_number(task_subject, task_description, cwd)
    if not pr_number:
        # Can't find PR — don't block, but warn
        sys.exit(0)

    # Check for Self-Review section
    has_self_review, body = check_self_review(pr_number, cwd)
    if not has_self_review:
        print(
            f"QUALITY GATE: PR #{pr_number} is missing the ## Self-Review section.\n"
            f"\n"
            f"Before completing this task, add a Self-Review section to the PR body:\n"
            f"\n"
            f"## Self-Review\n"
            f"\n"
            f"**Prior art read**: [list files you read before implementing]\n"
            f"**APIs verified**: [list any external APIs called, with doc source]\n"
            f"**Protocol steps completed**: all / [list deviations]\n"
            f"**Domain decisions**: [list judgment calls with source]\n"
            f"**Flags**: [anything uncertain or known gaps]\n"
            f"\n"
            f"Update the PR body with `gh pr edit {pr_number} --body \"...\"` "
            f"then mark this task complete again.",
            file=sys.stderr,
        )
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
