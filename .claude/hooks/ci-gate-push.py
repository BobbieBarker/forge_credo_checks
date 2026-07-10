#!/usr/bin/env python3
"""
CI Push Gate — PreToolUse:Bash

Blocks git push and gh pr create commands unless CI was run locally first.
Works with ci-gate-record.py (PostToolUse:Bash) which writes markers
when CI commands complete successfully.

This prevents agents from pushing code that hasn't been locally verified,
which wastes CI pipeline time and money on failures that would have been
caught by running `mix format` or `mix credo` locally.

Exit codes:
  0 — not a push command, or CI marker exists (allow)
  2 — push attempted without CI (block)
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

from _project_config import get_config

CI_DIR = Path("/tmp/claude-ci-passed")


def is_push_command(command):
    """Detect git push or gh pr create commands."""
    # Match: git push, gh pr create
    # Don't match: git push --help, git log showing "push"
    if re.search(r"\bgit\s+push\b", command):
        # Exclude help/dry-run
        if re.search(r"(--help|--dry-run|-n\b)", command):
            return False
        return True
    if re.search(r"\bgh\s+pr\s+create\b", command):
        return True
    return False


def extract_branch_from_command(command):
    """Try to extract the branch name from a git push command."""
    # git push origin branch-name
    m = re.search(r"git\s+push\s+(?:-[uf]\s+)?(?:\w+)\s+([\w./-]+)", command)
    if m:
        return m.group(1)

    # git push -u origin branch-name
    m = re.search(r"git\s+push\s+-u\s+\w+\s+([\w./-]+)", command)
    if m:
        return m.group(1)

    return None


def _extract_cd_target(command):
    """Extract the target directory from a 'cd /path &&' prefix in the command."""
    m = re.match(r"cd\s+([\S]+)\s*&&", command)
    if m:
        path = m.group(1)
        if os.path.isdir(path):
            return path
    return None


def _git_cmd(args, command=""):
    """Run a git command, using the cd target from the command if present."""
    cwd = _extract_cd_target(command)
    dirs = [d for d in [cwd, None, os.environ.get("CLAUDE_PROJECT_DIR")] if d]
    for d in dirs:
        try:
            result = subprocess.run(
                ["git"] + args,
                capture_output=True, text=True, timeout=8,
                cwd=d,
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass
    return None


def get_current_branch(command=""):
    """Get current git branch name from the repo the command targets."""
    return _git_cmd(["rev-parse", "--abbrev-ref", "HEAD"], command)


def get_repo_id(command=""):
    """Get a short repo identifier from the git remote URL.

    Returns a sanitized repo name (e.g., 'forge-symphony', 'qrking') so
    markers are scoped per-repo. This prevents cross-project interference
    when a session rooted in one project pushes to another.
    """
    url = _git_cmd(["remote", "get-url", "origin"], command)
    if url:
        m = re.search(r"[/:]([^/]+?)(?:\.git)?$", url)
        if m:
            return m.group(1)
    return None


def marker_exists(branch, command=""):
    """Check if a CI-passed marker exists for this branch, scoped by repo."""
    if not branch or not CI_DIR.exists():
        return False
    safe_branch = re.sub(r"[^a-zA-Z0-9_-]", "_", branch)
    repo_id = get_repo_id(command)
    if not repo_id:
        return False
    safe_repo = re.sub(r"[^a-zA-Z0-9_-]", "_", repo_id)
    repo_marker = CI_DIR / f"{safe_repo}_{safe_branch}.marker"
    return repo_marker.exists()


def marker_is_stale(branch, command=""):
    """Check if any tracked files were modified after the CI marker was written."""
    safe_branch = re.sub(r"[^a-zA-Z0-9_-]", "_", branch)
    repo_id = get_repo_id(command)

    # Find the marker file
    marker_path = None
    if repo_id:
        safe_repo = re.sub(r"[^a-zA-Z0-9_-]", "_", repo_id)
        candidate = CI_DIR / f"{safe_repo}_{safe_branch}.marker"
        if candidate.exists():
            marker_path = candidate
    if not marker_path:
        return True  # No marker = stale

    marker_mtime = marker_path.stat().st_mtime

    # Check if any staged or unstaged changes exist after marker time
    # Use git status to find modified files, then check their mtimes
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "HEAD"],
            capture_output=True, text=True, timeout=8
        )
        changed_files = [f.strip() for f in result.stdout.strip().split("\n") if f.strip()]

        # Also check staged changes
        result2 = subprocess.run(
            ["git", "diff", "--cached", "--name-only"],
            capture_output=True, text=True, timeout=8
        )
        staged_files = [f.strip() for f in result2.stdout.strip().split("\n") if f.strip()]

        all_changed = set(changed_files + staged_files)
        for filepath in all_changed:
            p = Path(filepath)
            if p.exists() and p.stat().st_mtime > marker_mtime:
                return True  # File modified after CI marker
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return False  # Can't determine — allow push

    return False


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    if tool_name != "Bash":
        sys.exit(0)

    tool_input = data.get("tool_input", {})
    command = tool_input.get("command", "")

    if not is_push_command(command):
        sys.exit(0)

    # Determine the branch being pushed
    branch = extract_branch_from_command(command) or get_current_branch(command)

    if not branch:
        # Can't determine branch — allow push but warn
        sys.exit(0)

    if marker_exists(branch, command):
        # Check if files were modified after CI marker was written
        if marker_is_stale(branch, command):
            ci_cmd = get_config().get("ci_command")
            msg = (
                f"=== PUSH BLOCKED — Files modified after CI ===\n"
                f"\n"
                f"Branch: {branch}\n"
                f"\n"
                f"You ran CI earlier, but files have been modified since.\n"
                f"Run CI again before pushing:\n"
                f"\n"
                f"  {ci_cmd}\n"
            )
            print(msg, file=sys.stderr)
            sys.exit(2)
        sys.exit(0)  # CI was run and marker is fresh — allow push

    # BLOCK: No CI marker found
    ci_cmd = get_config().get("ci_command")
    msg = (
        f"=== PUSH BLOCKED — No local CI run detected ===\n"
        f"\n"
        f"Branch: {branch}\n"
        f"\n"
        f"Before pushing, run the full CI command locally:\n"
        f"\n"
        f"  {ci_cmd}\n"
        f"\n"
        f"All checks must pass before pushing. This saves CI pipeline\n"
        f"time and money — format/credo violations caught locally are free,\n"
        f"but catching them in CI wastes a full pipeline run (~12 min).\n"
        f"\n"
        f"DO NOT skip this step. DO NOT use --no-verify.\n"
        f"=== End Push Gate ==="
    )
    print(msg, file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
