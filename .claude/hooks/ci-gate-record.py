#!/usr/bin/env python3
"""
CI Success Recorder — PostToolUse:Bash

Records when CI commands are run successfully. The push gate hook
(ci-gate-push.py) checks these markers before allowing git push.

Detects the CI command chain: mix format, mix credo, mix compile,
mix test, mix doctor, mix dialyzer. If the command contains these
AND the bash tool exited successfully (is_error is false), writes
a marker file.

Primary signal: bash exit code (is_error field from PostToolUse payload).
Secondary check: FAILURE_INDICATORS regex as belt-and-braces defense
against shell expressions that mask exit codes (e.g. `mix test || true`).

The marker is keyed by branch name, so amending a commit on the
same branch doesn't invalidate the marker (the CI was still run
for this branch). A new branch requires a new CI run.

Never blocks — always exit 0. This is a passive recorder.
"""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

CI_DIR = Path("/tmp/claude-ci-passed")

# Minimum CI commands that must be present in the command string
# for us to consider it a "CI run." The user's full command is:
#   mix format && mix credo --strict && MIX_ENV=dev mix doctor &&
#   mix compile --warnings-as-errors && MIX_ENV=dev mix dialyzer && mix test
#
# We require at least format + credo + test. These catch the most
# common violations that waste CI money.
REQUIRED_CI_COMMANDS = [
    r"mix\s+format",
    r"mix\s+credo",
    r"mix\s+test",
    r"bin/patch-coverage",
]

# Patterns that indicate CI failure in the output
FAILURE_INDICATORS = [
    r"(?i)\*\* \(EXIT\)",
    r"[1-9]\d* (failure|error)s?",        # "3 failures", "1 error" (NOT "0 failures")
    r"(?i)warnings being treated as errors",
    r"(?i)mix credo.*found \d+ issue",    # credo violations
    r"(?i)could not compile",
    r"(?i)no matching clause",             # compilation error
    r"(?i)undefined function",
    r"(?i)\(CompileError\)",
    r"(?i)\(UndefinedFunctionError\)",
]


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
                capture_output=True, text=True, timeout=3,
                cwd=d,
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass
    return None


def get_branch(command=""):
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


def is_ci_command(command):
    """Check if the command contains the minimum required CI commands.

    First checks against the project-specific CI command from project.json
    (supports non-Elixir projects like forge-framework). Falls back to the
    hardcoded Elixir patterns for projects without project.json.
    """
    from _project_config import get_config
    config = get_config()
    project_ci = config.get("ci_command", "")
    if project_ci:
        # Check if the command contains the project's CI command (or key parts)
        # Split on && to get individual commands and check each is present
        # Normalize python/python3 differences for matching
        parts = [p.strip() for p in project_ci.split("&&")]
        norm_cmd = re.sub(r'\bpython3?\b', 'python', command)
        if all(re.sub(r'\bpython3?\b', 'python', part) in norm_cmd for part in parts):
            return True

    # Fallback: hardcoded Elixir CI patterns
    for pattern in REQUIRED_CI_COMMANDS:
        if not re.search(pattern, command):
            return False
    return True


def has_failure(output):
    """Check if the output indicates CI failure."""
    for pattern in FAILURE_INDICATORS:
        if re.search(pattern, output):
            return True
    return False


def is_tool_error(data):
    """Check if the bash tool reported an error via exit code.

    The PostToolUse:Bash payload includes an is_error field that reflects
    whether the command exited non-zero. This is the primary success signal —
    it cannot be defeated by stdout truncation.
    """
    return data.get("is_error", False)


def write_marker(branch, command=""):
    """Write a CI-passed marker for the given branch, scoped by repo."""
    CI_DIR.mkdir(parents=True, exist_ok=True)
    safe_branch = re.sub(r"[^a-zA-Z0-9_-]", "_", branch)
    repo_id = get_repo_id(command)
    if repo_id:
        safe_repo = re.sub(r"[^a-zA-Z0-9_-]", "_", repo_id)
        marker = CI_DIR / f"{safe_repo}_{safe_branch}.marker"
    else:
        marker = CI_DIR / f"{safe_branch}.marker"
    marker.write_text(json.dumps({
        "branch": branch,
        "repo": repo_id,
        "timestamp": time.time(),
        "iso_time": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }))


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
    output = str(data.get("tool_output", ""))

    # Only process CI-like commands
    if not is_ci_command(command):
        sys.exit(0)

    # Primary signal: bash exit code. If the tool reported an error, CI failed.
    if is_tool_error(data):
        sys.exit(0)

    # Secondary check: failure indicators in stdout as belt-and-braces defense.
    # Catches shell expressions that mask exit codes (e.g. `mix test || true`).
    if has_failure(output):
        sys.stderr.write("ci-gate-record: exit code was 0 but failure indicators found in output\n")
        sys.exit(0)

    branch = get_branch(command)
    if branch:
        write_marker(branch, command)

    sys.exit(0)


if __name__ == "__main__":
    main()
