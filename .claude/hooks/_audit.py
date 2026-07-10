"""
Shared audit utilities for protocol compliance tracking.

All hooks import from this module to read/write audit state.
Audit files live in /tmp/claude-protocol-audit/ and use simple
marker files keyed by team name.

File types:
  expect-{id}.json        — what we expect the agent to do
  team-{name}.json        — team creation event
  spawn-{team}-{role}     — sub-agent spawn within a team
  msg-{team}-{n}.json     — message sent within a team
  block-{team}-{name}.json — blocked spawn within a team (silent failure prevention)
"""

import json
import time
from pathlib import Path

AUDIT_DIR = Path("/tmp/claude-protocol-audit")
TEAMS_DIR = Path.home() / ".claude" / "teams"


def ensure_dir():
    """Create the audit directory if it doesn't exist."""
    AUDIT_DIR.mkdir(parents=True, exist_ok=True)


def write_expectation(agent_name, task_type, expected_team_pattern, expected_roles):
    """Write an expectation file when a protocol agent is spawned."""
    ensure_dir()
    data = {
        "agent_name": agent_name,
        "task_type": task_type,
        "expected_team_pattern": expected_team_pattern,
        "expected_roles": expected_roles,
        "timestamp": time.time(),
        "iso_time": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    path = AUDIT_DIR / f"expect-{agent_name}.json"
    path.write_text(json.dumps(data, indent=2))
    return path


def write_team_created(team_name, description=""):
    """Write a marker when TeamCreate is called."""
    ensure_dir()
    data = {
        "event": "team_created",
        "team_name": team_name,
        "description": description,
        "timestamp": time.time(),
        "iso_time": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    path = AUDIT_DIR / f"team-{team_name}.json"
    path.write_text(json.dumps(data, indent=2))
    return path


def write_agent_spawned(team_name, agent_name, subagent_type="", role_hint=""):
    """Write a marker when a sub-agent is spawned within a team."""
    ensure_dir()
    data = {
        "event": "agent_spawned",
        "team_name": team_name,
        "agent_name": agent_name,
        "subagent_type": subagent_type,
        "role_hint": role_hint,
        "timestamp": time.time(),
        "iso_time": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    # Use agent_name to avoid collisions between roles
    safe_name = agent_name.replace("/", "_").replace(" ", "_")
    path = AUDIT_DIR / f"spawn-{team_name}-{safe_name}.json"
    path.write_text(json.dumps(data, indent=2))
    return path


def write_message_sent(team_name, to, summary="", message_length=0):
    """Write a marker when SendMessage is called within a team."""
    ensure_dir()
    data = {
        "event": "message_sent",
        "team_name": team_name,
        "to": to,
        "summary": summary,
        "message_length": message_length,
        "timestamp": time.time(),
        "iso_time": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    # Use timestamp to make unique filenames for multiple messages
    ts = str(int(time.time() * 1000))
    path = AUDIT_DIR / f"msg-{team_name}-{to}-{ts}.json"
    path.write_text(json.dumps(data, indent=2))
    return path


def write_spawn_blocked(team_name, agent_name, reason, classified_as=""):
    """Write a marker when a sub-agent spawn is blocked by the hook.

    This is the silent failure prevention mechanism. When a coordinator's
    sub-agent is blocked, this creates a visible record that can be:
    1. Detected by the coordinator (if it checks the audit dir)
    2. Surfaced in audit reports
    3. Used to diagnose systemic spawn failures
    """
    ensure_dir()
    data = {
        "event": "spawn_blocked",
        "team_name": team_name,
        "agent_name": agent_name,
        "reason": reason,
        "classified_as": classified_as,
        "timestamp": time.time(),
        "iso_time": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    safe_name = (agent_name or "unknown").replace("/", "_").replace(" ", "_")
    ts = str(int(time.time() * 1000))
    path = AUDIT_DIR / f"block-{team_name}-{safe_name}-{ts}.json"
    path.write_text(json.dumps(data, indent=2))
    return path


def find_active_team():
    """Find the currently active team from ~/.claude/teams/.

    Returns (team_name, team_config) if an active team exists, else (None, None).
    Active = has a config.json with members. Most recent by creation time wins
    if multiple exist.
    """
    if not TEAMS_DIR.exists():
        return None, None
    best_team = None
    best_config = None
    best_time = 0
    for config_path in TEAMS_DIR.glob("*/config.json"):
        try:
            config = json.loads(config_path.read_text())
            created = config.get("createdAt", 0)
            if config.get("members") and created > best_time:
                best_team = config.get("name", config_path.parent.name)
                best_config = config
                best_time = created
        except (json.JSONDecodeError, OSError):
            pass
    return best_team, best_config


def check_team_provenance(team_name):
    """Check if a team was created under a validated protocol agent.

    Looks up the audit trail for an expectation file whose expected_team_pattern
    matches the given team name. This proves the team is part of an approved
    protocol workflow (prd, decomposition, grooming) — not a rogue team.

    Returns the protocol task_type (e.g., "prd", "decomposition") if provenance
    is confirmed, or None if no matching expectation exists.
    """
    ensure_dir()
    for path in AUDIT_DIR.glob("expect-*.json"):
        try:
            exp = json.loads(path.read_text())
            pattern = exp.get("expected_team_pattern", "")
            if not pattern:
                continue
            # Exact match or glob-style prefix match (pattern ends with *)
            if team_name == pattern:
                return exp.get("task_type", "")
            if pattern.endswith("*") and team_name.startswith(pattern[:-1]):
                return exp.get("task_type", "")
        except (json.JSONDecodeError, OSError):
            pass
    return None


def read_expectations():
    """Read all expectation files."""
    ensure_dir()
    expectations = []
    for path in AUDIT_DIR.glob("expect-*.json"):
        try:
            expectations.append(json.loads(path.read_text()))
        except (json.JSONDecodeError, OSError):
            pass
    return expectations


def read_events(team_name=None):
    """Read all events, optionally filtered by team name."""
    ensure_dir()
    events = []
    patterns = ["team-*.json", "spawn-*.json", "msg-*.json", "block-*.json"]
    for pattern in patterns:
        for path in AUDIT_DIR.glob(pattern):
            try:
                data = json.loads(path.read_text())
                if team_name is None or data.get("team_name") == team_name:
                    events.append(data)
            except (json.JSONDecodeError, OSError):
                pass
    return sorted(events, key=lambda e: e.get("timestamp", 0))


def check_compliance(expectation):
    """
    Check if an expectation was met. Returns (passed: bool, violations: list[str]).
    """
    violations = []
    pattern = expectation.get("expected_team_pattern", "")
    expected_roles = expectation.get("expected_roles", [])

    # Check: was a team created matching the expected pattern?
    team_files = list(AUDIT_DIR.glob(f"team-{pattern}.json")) if pattern else []

    if not team_files:
        # Also try exact match without glob
        exact = AUDIT_DIR / f"team-{pattern}.json"
        if exact.exists():
            team_files = [exact]

    if not team_files:
        violations.append(
            f"NO TEAM CREATED — Expected team matching '{pattern}' but no "
            f"TeamCreate call was recorded. The agent may have run everything "
            f"as a single agent instead of using the team structure."
        )
        # If no team was created, we can't check roles either
        return len(violations) == 0, violations

    # Get the actual team name from the first matching file
    team_data = json.loads(team_files[0].read_text())
    actual_team = team_data.get("team_name", "")

    # Check: were the expected roles spawned?
    spawn_files = list(AUDIT_DIR.glob(f"spawn-{actual_team}-*.json"))
    spawned_roles = set()
    for sf in spawn_files:
        try:
            data = json.loads(sf.read_text())
            role = data.get("role_hint", "").lower()
            name = data.get("agent_name", "").lower()
            # Match role from either explicit hint or agent name
            for expected in expected_roles:
                if expected.lower() in role or expected.lower() in name:
                    spawned_roles.add(expected)
        except (json.JSONDecodeError, OSError):
            pass

    missing_roles = set(expected_roles) - spawned_roles
    if missing_roles:
        violations.append(
            f"MISSING ROLES — Expected roles {sorted(missing_roles)} to be spawned "
            f"in team '{actual_team}', but only found: {sorted(spawned_roles) or '(none)'}. "
            f"The protocol requires all specialist roles for complete decomposition."
        )

    return len(violations) == 0, violations


def get_audit_summary():
    """Generate a human-readable summary of all audit state."""
    ensure_dir()
    lines = []
    lines.append("=== Protocol Compliance Audit ===")
    lines.append("")

    expectations = read_expectations()
    if not expectations:
        lines.append("No protocol agents have been tracked yet.")
        return "\n".join(lines)

    for exp in sorted(expectations, key=lambda e: e.get("timestamp", 0)):
        agent = exp.get("agent_name", "unknown")
        task = exp.get("task_type", "unknown")
        pattern = exp.get("expected_team_pattern", "")
        expected_roles = exp.get("expected_roles", [])
        iso = exp.get("iso_time", "")

        lines.append(f"Agent: {agent} ({task})")
        lines.append(f"  Spawned: {iso}")
        lines.append(f"  Expected team: {pattern}")
        lines.append(f"  Expected roles: {', '.join(expected_roles)}")

        passed, violations = check_compliance(exp)
        if passed:
            lines.append("  Status: COMPLIANT")
        else:
            lines.append("  Status: VIOLATIONS FOUND")
            for v in violations:
                lines.append(f"    - {v}")

        # Show events for this team
        events = []
        if pattern:
            # Try glob pattern
            for tf in AUDIT_DIR.glob(f"team-{pattern}.json"):
                try:
                    td = json.loads(tf.read_text())
                    team_name = td.get("team_name", "")
                    events = read_events(team_name)
                    break
                except (json.JSONDecodeError, OSError):
                    pass

        if events:
            lines.append(f"  Events ({len(events)}):")
            for ev in events:
                etype = ev.get("event", "unknown")
                etime = ev.get("iso_time", "")
                if etype == "team_created":
                    lines.append(f"    [{etime}] Team created: {ev.get('team_name')}")
                elif etype == "agent_spawned":
                    lines.append(
                        f"    [{etime}] Spawned: {ev.get('agent_name')} "
                        f"(role: {ev.get('role_hint', 'unknown')})"
                    )
                elif etype == "message_sent":
                    lines.append(
                        f"    [{etime}] Message -> {ev.get('to')} "
                        f"({ev.get('message_length', 0)} chars)"
                    )
                elif etype == "spawn_blocked":
                    lines.append(
                        f"    [{etime}] BLOCKED: {ev.get('agent_name')} "
                        f"— {ev.get('reason', 'unknown')} "
                        f"(classified as: {ev.get('classified_as', '?')})"
                    )

        lines.append("")

    lines.append("=== End Audit ===")
    return "\n".join(lines)
