"""
Shared project configuration loader for forge-framework hooks.

Reads project-specific values from `.claude/hooks/project.json`
relative to the hook's location. Falls back to sensible defaults
when the file is missing, malformed, or lacks a key.

Consumers:
  from _project_config import get_config
  cfg = get_config()
  ci_cmd = cfg["ci_command"]

Expected project.json shape:
  {
    "ci_command": "mix format && mix credo --strict && mix test",
    "ci_required_patterns": ["mix\\s+format", "mix\\s+credo", "mix\\s+test"],
    "ci_success_patterns": ["\\d+ tests?, 0 failures"],
    "ticket_prefixes": ["QRK", "FGE"],
    "repo": "org/repo-name"
  }
"""

import json
import sys
from pathlib import Path

# Defaults used when project.json is absent, malformed, or missing a key.
_DEFAULTS = {
    "ci_command": "echo 'No CI command configured in project.json'",
    "ci_required_patterns": [],
    "ci_success_patterns": [],
    "ticket_prefixes": [],
    "repo": "",
}

# Cache so we only read the file once per process.
_cached_config = None


def _find_project_json():
    """Locate project.json relative to this file's directory.

    Checks two locations:
    1. Same directory as this file (standard: hooks live in .claude/hooks/)
    2. .claude/hooks/project.json from repo root (dog-fooding: hooks live at repo root hooks/)
    """
    same_dir = Path(__file__).parent / "project.json"
    if same_dir.exists():
        return same_dir

    # Dog-fooding fallback: hooks/ is at repo root, project.json is in .claude/hooks/
    repo_root = Path(__file__).parent.parent
    claude_path = repo_root / ".claude" / "hooks" / "project.json"
    if claude_path.exists():
        return claude_path

    return same_dir  # Return the standard path (will trigger "not found" warning)


def get_config():
    """Load and return the project config dict, with defaults for missing keys.

    Returns a dict guaranteed to have every key from _DEFAULTS.
    Logs warnings to stderr on missing file or parse errors.
    """
    global _cached_config
    if _cached_config is not None:
        return _cached_config

    config = dict(_DEFAULTS)
    path = _find_project_json()

    if not path.exists():
        print(
            f"[forge-hooks] WARNING: {path} not found — using defaults",
            file=sys.stderr,
        )
        _cached_config = config
        return config

    try:
        raw = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError) as exc:
        print(
            f"[forge-hooks] WARNING: failed to parse {path}: {exc} — using defaults",
            file=sys.stderr,
        )
        _cached_config = config
        return config

    if not isinstance(raw, dict):
        print(
            f"[forge-hooks] WARNING: {path} is not a JSON object — using defaults",
            file=sys.stderr,
        )
        _cached_config = config
        return config

    # Merge loaded values over defaults (only for known keys).
    for key in _DEFAULTS:
        if key in raw:
            config[key] = raw[key]

    _cached_config = config
    return config


def ticket_prefix_pattern():
    """Build a regex alternation for ticket prefixes, e.g. 'QRK-\\d+|FGE-\\d+'.

    Returns an empty string if no prefixes are configured.
    """
    cfg = get_config()
    prefixes = cfg.get("ticket_prefixes", [])
    if not prefixes:
        return ""
    return "|".join(rf"{p}-\d+" for p in prefixes)


def ticket_prefix_pattern_case_insensitive():
    """Build a case-insensitive regex alternation for ticket prefixes.

    Returns an empty string if no prefixes are configured.
    """
    cfg = get_config()
    prefixes = cfg.get("ticket_prefixes", [])
    if not prefixes:
        return ""
    # Build pattern that matches upper or lower case prefix
    return "|".join(rf"(?i:{p})-\d+" for p in prefixes)
