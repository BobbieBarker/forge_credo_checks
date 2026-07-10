#!/usr/bin/env python3
"""
Agent Output Validator — PostToolUse hook for the Agent tool

Checks that agent output contains required deliverables based on task type.
Runs AFTER the agent completes and returns its output. For background agents,
this fires on the initial launch confirmation (not on completion) — so we
skip validation for those.

This is Layer 3 of the enforcement system:
  Layer 1 (pre-flight): ensures correct agent definition is used
  Layer 2 (definition): constrains tools, instructions, model
  Layer 3 (this hook): verifies the output meets deliverable requirements

Exit codes:
  0 — output looks complete (or not checkable)
  2 — output missing required deliverables (feedback added to conversation)
"""

import json
import re
import sys
from pathlib import Path

# Import shared audit utilities
sys.path.insert(0, str(Path(__file__).parent))
import _audit


# ============================================================================
# DELIVERABLE REQUIREMENTS PER TASK TYPE
# ============================================================================

DECOMPOSITION_DELIVERABLES = [
    {
        "name": "Coverage matrix",
        "pattern": r"(?i)coverage.matrix|requirement.*ticket.map|PRD req.*->",
        "description": "PRD requirement -> ticket mapping",
    },
    {
        "name": "Dependency graph / wave assignments",
        "pattern": r"(?i)(dependency.graph|wave.assign|wave \d|Wave \d|blocked.by)",
        "description": "Ticket dependency graph with wave execution order",
    },
    {
        "name": "Validation report",
        "pattern": r"(?i)validation.report|validation.check|all checks|checklist.*(pass|fail)",
        "description": "Validator agent's verification that all protocol checks pass",
    },
    {
        "name": "Migration timestamps",
        "pattern": r"(?i)(migration.timestamp|20\d{10})",
        "description": "Pre-assigned migration timestamps to avoid collisions",
    },
    {
        "name": "Team execution evidence",
        "pattern": r"(?i)(TeamCreate|team.*created|spawned.*(PM|designer|TPM|scout|validator)|team member)",
        "description": "Evidence that a team was used (not single-agent execution)",
    },
]

PRD_DELIVERABLES = [
    {
        "name": "Open questions",
        "pattern": r"(?i)open.question",
        "description": "Open questions that need review",
    },
    {
        "name": "Draft written confirmation",
        "pattern": r"(?i)(PRDs/drafts/|wrote.*to|draft.*written|written.*to|saved.*draft)",
        "description": "Confirmation that the PRD draft was written to PRDs/drafts/",
    },
    {
        "name": "Deferred requirements",
        "pattern": r"(?i)deferred.requirement",
        "description": "Deferred requirements with IDs for tracking",
    },
    {
        "name": "Key decisions",
        "pattern": r"(?i)(key decision|decision.*made|decided|design decision)",
        "description": "Summary of key design/product decisions made in the PRD",
    },
]

IMPLEMENTATION_DELIVERABLES = [
    {
        "name": "Completion report",
        "pattern": r"(?i)(completion.report|\*\*Ticket:\*\*|\*\*PR:\*\*|\*\*CI:\*\*)",
        "description": "Structured completion report with ticket, PR, CI status",
    },
    {
        "name": "PR reference",
        "pattern": r"(?i)(github\.com.*pull/\d+|PR #\d+|PR.*created|pull request)",
        "description": "Link to the created pull request",
    },
]

GROOMING_DELIVERABLES = [
    {
        "name": "Per-ticket verdicts",
        "pattern": r"(?i)(verdict.*PASS|verdict.*NEEDS UPDATE|verdict.*RE-DECOMPOSE|PASS|NEEDS UPDATE)",
        "description": "PASS / NEEDS UPDATE / RE-DECOMPOSE verdict for each ticket",
    },
    {
        "name": "Structured findings",
        "pattern": r"(?i)(ticket says|codebase shows|proposed fix|issues found)",
        "description": "Structured grooming findings with specific quotes and fixes",
    },
]

DESIGN_DELIVERABLES = [
    {
        "name": "Design spec",
        "pattern": r"(?i)(design spec|design specification|## Design)",
        "description": "Design specification document or section",
    },
    {
        "name": "Component selection",
        "pattern": r"(?i)(component|archetype|layout|LiveView|live_component)",
        "description": "Component or archetype selection with rationale",
    },
    {
        "name": "Schema grounding",
        "pattern": r"(?i)(schema|field|data model|assigns|struct)",
        "description": "Design grounded in actual schema fields and data model",
    },
]


# ============================================================================
# CLASSIFICATION (mirrors pre-flight hook)
# ============================================================================

def classify(subagent_type, prompt):
    """Simplified classification — just enough to check deliverables."""
    DEFINITION_MAP = {
        "decomp-coordinator": "decomposition",
        "grooming-coordinator": "grooming",
        "impl-coordinator": "implementation",
        "prd-writer": "prd",
        "design-reasoner": "design",
        "Explore": "research",
        "Plan": "research",
        "claude-code-guide": "skip",
        "statusline-setup": "skip",
        # Specialist engineering agents — check for implementation deliverables.
        # NOTE: beam-nif-engineer was retired and split into erlang-engineer
        # (pure Erlang/OTP) and erlang-nif-engineer (Rust NIFs via Rustler).
        "erlang-nif-engineer": "implementation",
        "erlang-engineer": "implementation",
        "quiche-specialist": "implementation",
        "performance-engineer": "implementation",
    }
    # Retired agents redirect to their successors for output classification.
    RETIRED_REDIRECTS = {
        "beam-nif-engineer": "implementation",
    }
    if subagent_type in DEFINITION_MAP:
        return DEFINITION_MAP[subagent_type]
    if subagent_type in RETIRED_REDIRECTS:
        return RETIRED_REDIRECTS[subagent_type]

    if re.search(r"(?i)(ticket.decomposition|decompos.*(PRD|tickets))", prompt):
        return "decomposition"
    if re.search(r"(?i)(prd.drafting|PRD.*protocol|draft.*PRD)", prompt):
        return "prd"
    if re.search(r"(?i)(groom|grooming|validate.*backlog)", prompt):
        return "grooming"
    if re.search(r"(?i)(implement|create.*PR|build|write.*code)", prompt):
        return "implementation"
    return "other"


# ============================================================================
# DELIVERABLE CHECKING
# ============================================================================

def check_deliverables(output, task_type):
    """Check output for required deliverables. Returns list of missing items."""
    deliverable_map = {
        "decomposition": DECOMPOSITION_DELIVERABLES,
        "prd": PRD_DELIVERABLES,
        "implementation": IMPLEMENTATION_DELIVERABLES,
        "grooming": GROOMING_DELIVERABLES,
        "design": DESIGN_DELIVERABLES,
    }

    requirements = deliverable_map.get(task_type)
    if not requirements:
        return []

    missing = []
    for req in requirements:
        if not re.search(req["pattern"], output):
            missing.append(f"{req['name']} — {req['description']}")

    return missing


# ============================================================================
# MAIN
# ============================================================================

def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)  # can't parse input — don't block

    tool_name = data.get("tool_name", "")
    if tool_name != "Agent":
        sys.exit(0)

    tool_input = data.get("tool_input", {})
    tool_output = str(data.get("tool_output", ""))

    # Skip background agents — output is just the launch confirmation
    if "Async agent launched" in tool_output:
        sys.exit(0)

    # Skip empty or error outputs
    if not tool_output or len(tool_output) < 50:
        sys.exit(0)

    subagent_type = tool_input.get("subagent_type", "")
    prompt = tool_input.get("prompt", "")

    task_type = classify(subagent_type, prompt)
    if task_type in ("skip", "other", "research"):
        sys.exit(0)

    # Check 1: Required deliverables in output
    missing = check_deliverables(tool_output, task_type)

    # Check 2: Runtime compliance from audit trail (foreground agents only)
    audit_violations = []
    agent_name = tool_input.get("name", "")
    if task_type in ("decomposition", "prd", "grooming") and agent_name:
        # Find the expectation file for this agent
        expect_path = _audit.AUDIT_DIR / f"expect-{agent_name}.json"
        if expect_path.exists():
            try:
                expectation = json.loads(expect_path.read_text())
                _, violations = _audit.check_compliance(expectation)
                audit_violations = violations
            except (json.JSONDecodeError, OSError):
                pass

    if missing or audit_violations:
        lines = [
            "=== Agent Output Quality Check ===",
            "",
            f"Task type: {task_type}",
            "",
        ]

        if missing:
            lines.append(f"Missing deliverables ({len(missing)}):")
            lines.append("")
            for m in missing:
                lines.append(f"  - {m}")
            lines.append("")

        if audit_violations:
            lines.append(f"Runtime compliance violations ({len(audit_violations)}):")
            lines.append("")
            for v in audit_violations:
                lines.append(f"  - {v}")
            lines.append("")

        lines.append(
            "The agent's output may be incomplete or the protocol was not followed.\n"
            "Run `python3 .claude/hooks/audit-report.py` for the full audit trail."
        )
        lines.append("=== End Output Check ===")
        print("\n".join(lines), file=sys.stderr)
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
