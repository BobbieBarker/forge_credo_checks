#!/usr/bin/env python3
"""
Agent Prompt Validator — PreToolUse hook for the Agent tool

Three-layer enforcement:
  1. CLASSIFY — determine task type from agent definition or prompt content
  2. ENFORCE DEFINITION — protocol tasks MUST use the correct agent definition
  3. VALIDATE — apply task-type-specific rules

Classification priority (STRICT — later layers CANNOT override earlier ones):
  1. subagent_type from .claude/agents/  →  ABSOLUTE classification
  2. Explore/Plan agent types            →  ALWAYS "research" (no override)
  3. Team membership (team_name set)     →  "team-role"
  4. Keyword inference                   →  only for generic agents

Key invariant: Explore and Plan agents are ALWAYS "research". They lack
write/edit/team tools and cannot execute protocols. If a prompt tries to
use them for protocol work, the enforcement layer catches it.

Project-specific values (ticket prefixes) are read from project.json
via _project_config.

Exit codes:
  0 — pass (allow tool call)
  2 — fail (block tool call, message sent to Claude)
"""

import json
import re
import sys
from pathlib import Path

# Import shared utilities
sys.path.insert(0, str(Path(__file__).parent))
import _audit
import _project_config


# ============================================================================
# CONFIGURATION
# ============================================================================

# Agent definitions → task type mapping (ABSOLUTE, no override)
DEFINITION_TYPES = {
    "decomp-coordinator": "decomposition",
    "grooming-coordinator": "grooming",
    "impl-coordinator": "implementation",
    "prd-writer": "prd",
    "design-reasoner": "design",
    "Explore": "research",
    "Plan": "research",
    "claude-code-guide": "skip",
    "statusline-setup": "skip",
    # Specialist engineering agents — classified as implementation so they
    # get CI, prior-art, ticket-ID, and self-review enforcement.
    # NOTE: beam-nif-engineer was retired and split into erlang-engineer
    # (pure Erlang/OTP) and erlang-nif-engineer (Rust NIFs via Rustler).
    # See RETIRED_AGENTS below for redirect handling.
    "erlang-nif-engineer": "implementation",
    "erlang-engineer": "implementation",
    "quiche-specialist": "implementation",
    "performance-engineer": "implementation",
}

# Deprecated aliases → canonical name. Emits an advisory warning when used.
DEPRECATED_ALIASES = {
    "groom-coordinator": "grooming-coordinator",
}

# Retired agents → successor mapping. When a caller references a retired
# agent definition, the hook blocks with a redirect message listing the
# successor agents that replaced it.
RETIRED_AGENTS = {
    "beam-nif-engineer": {
        "successors": ["erlang-engineer", "erlang-nif-engineer"],
        "reason": (
            "beam-nif-engineer was retired and split into two specialist agents:\n"
            "  - erlang-engineer: idiomatic Erlang/OTP development (pure Erlang, no NIFs)\n"
            "  - erlang-nif-engineer: Rust NIFs via Rustler for Elixir/BEAM integration\n"
            "Choose the successor that matches your task."
        ),
    },
}

# Protocol tasks and their required agent definitions.
# If a prompt is classified as one of these task types but ISN'T using
# the required agent definition, the hook BLOCKS and tells the caller
# which definition to use. This is the primary enforcement mechanism.
PROTOCOL_DEFINITIONS = {
    "decomposition": {
        "required_type": "decomp-coordinator",
        "description": "ticket decomposition",
        "rationale": (
            "The decomp-coordinator agent definition has the protocol's team structure "
            "(coordinator -> scout -> PM -> designer + TPM -> validator), tool restrictions, "
            "and phase flow baked in. Generic agents ignore protocol requirements and run "
            "everything as a single agent."
        ),
    },
    "prd": {
        "required_type": "prd-writer",
        "description": "PRD drafting",
        "rationale": (
            "The prd-writer agent definition enforces the team structure "
            "(coordinator + researcher + writer + critic), the critique checklist, "
            "and the structured research findings template. Generic agents skip the "
            "critic phase and produce lower-quality PRDs."
        ),
    },
    "grooming": {
        "required_type": "grooming-coordinator",
        "description": "ticket grooming",
        "rationale": (
            "The grooming-coordinator agent definition enforces the team structure "
            "(coordinator + codebase-scout + groomer), the staleness checks, "
            "cross-reference validation, and Chad review gate. Generic agents skip "
            "the scout phase and produce grooming updates without verifying codebase state."
        ),
    },
}


# ============================================================================
# LAYER 1: CLASSIFICATION
# ============================================================================

# Role keywords used to identify team sub-agents. These match both the
# "You are a {role}" pattern and the agent naming convention (researcher-*, writer-*, etc.)
TEAM_ROLE_KEYWORDS = (
    "PM|project manager|designer|TPM|technical.*PM|tech.*PM|"
    "validator|critic|supervisor|researcher|research specialist|"
    "codebase.*(scout|analyst)|groomer|writer|implementer|fixer"
)


def _resolve_team_context(team_name, agent_name):
    """Resolve team context from explicit param, active teams, or audit trail.

    The team hierarchy model:
      1. Protocol agent (prd-writer, decomp-coordinator) is spawned and validated
      2. It creates a team via TeamCreate (recorded in audit trail)
      3. It spawns sub-agents within that team

    Step 3 is where team_name may be missing from tool_input — the coordinator
    knows its team implicitly but may not pass it explicitly. This function
    resolves team context from multiple sources:
      - Explicit team_name in tool_input (most reliable)
      - Active team in ~/.claude/teams/ (runtime truth)
      - Audit trail team records (historical truth)

    Returns (resolved_team_name, provenance_task_type) or (None, None).
    """
    # Source 1: Explicit team_name in tool_input
    if team_name:
        provenance = _audit.check_team_provenance(team_name)
        return team_name, provenance

    # Source 2: Active team from ~/.claude/teams/
    # If there's an active team, sub-agents spawned by its coordinator
    # implicitly belong to it even if team_name isn't in tool_input.
    active_team, active_config = _audit.find_active_team()
    if active_team:
        provenance = _audit.check_team_provenance(active_team)
        return active_team, provenance

    return None, None


def classify(prompt, subagent_type, team_name, agent_name=""):
    """
    Determine the task type. Classification is hierarchical — once a layer
    matches, later layers are skipped. This prevents keyword pollution
    (e.g., an Explore agent mentioning "grooming" in its research prompt).
    """

    # Deprecated aliases fall through to keyword classification and are
    # blocked by enforce_definition. The deprecation warning is collected
    # in main() and delivered via hookSpecificOutput.additionalContext.

    # Priority 1: Known agent definition — FINAL, no override
    if subagent_type in DEFINITION_TYPES:
        return DEFINITION_TYPES[subagent_type]

    # Priority 2: Team membership — agent is a sub-role within a validated team.
    #
    # This priority exists because team sub-agents (researchers, writers, critics)
    # naturally contain protocol keywords in their prompts ("PRD", "draft",
    # "decomposition") — they're doing protocol work! But they're ROLES within
    # a team, not top-level protocol agents. Without this priority, they'd be
    # classified as "prd"/"decomposition" and blocked by protocol enforcement
    # requiring the coordinator definition.
    #
    # The team provenance check prevents abuse: only teams created by a validated
    # protocol coordinator get this classification. A rogue agent can't escape
    # enforcement by creating an arbitrary team.
    resolved_team, provenance = _resolve_team_context(team_name, agent_name)
    if resolved_team and provenance:
        # Team exists and was created under a validated protocol.
        # Check if the prompt describes a team role — allow up to 3 words
        # between the article and the role keyword to handle patterns like
        # "You are a PRD writer" or "You are a research specialist".
        role_pattern = (
            r"(?i)you are (?:the |a )?(?:\w+\s+){0,3}"
            r"(" + TEAM_ROLE_KEYWORDS + r")"
        )
        if re.search(role_pattern, prompt):
            # FGE-376: If the prompt references a protocols/ file path,
            # this agent is doing protocol work — fall through to Priority 3
            # keyword inference for full enforcement instead of minimal
            # team-role rules. The word "protocols" in general text does NOT
            # trigger this; it must be a file path like protocols/foo.md.
            if re.search(r'protocols/\S+\.md', prompt):
                pass  # fall through to Priority 3
            else:
                return "team-role"

    # Priority 3: Keyword inference — ONLY for generic/untyped agents
    # Order matters: most specific first, most general last.
    # Once a classifier matches, return immediately.

    # 3a: Design reasoner (check BEFORE implementation keywords)
    # An agent reading .claude/agents/design-reasoner.md and producing design specs
    if re.search(
        r"(?i)(design-reasoner\.md|produce a design spec|design spec for|"
        r"design-system\.md.*archetype|archetype.*design-system\.md)",
        prompt,
    ):
        return "design"

    # 3b: Data entry (check BEFORE protocol keywords)
    # "apply grooming updates" via save-issue is data entry, not grooming.
    if re.search(
        r"(?i)(bin/mcp linear|save-issue|Linear ticket|create.*ticket.*Linear|"
        r"mcp__obsidian.*write_note|vault.*revision|data entry|"
        r"NOT.*code.*implementation|NOT.*implementation)",
        prompt,
    ):
        return "research"

    # 3b: Decomposition work
    if re.search(r"(?i)(ticket.decomposition|decompos.*(PRD|tickets|protocol))", prompt):
        return "decomposition"

    # 3c: PRD drafting work
    if re.search(r"(?i)(prd.drafting|PRD.*protocol|draft.*PRD)", prompt):
        return "prd"
    if re.search(
        r"(?i)(does NOT write code|documentation only|RESEARCH.*WRITING task|"
        r"no code changes|writes documentation only)",
        prompt,
    ):
        return "prd"

    # 3d: Grooming work (skip if data-entry was already matched above)
    if re.search(
        r"(?i)(groom|grooming|validate.*backlog|audit.*ticket|ticket.*audit|"
        r"staleness|cross.reference.*ticket|review.*ticket.*against|"
        r"ticket.*quality.*review)",
        prompt,
    ):
        return "grooming"

    # 3e: Research / investigation (not implementation)
    if len(prompt) < 200:
        if not re.search(
            r"(?i)(implement|create|build|write|add|fix|refactor|update.*code|"
            r"migration|schema|context module|liveview|controller|worker|oban)",
            prompt,
        ):
            return "research"
    if re.search(
        r"(?i)(research specialist|codebase analyst|quality validator|"
        r"you are a.*reviewer)",
        prompt,
    ):
        if not re.search(r"(?i)(implement|build|create.*module|write.*code)", prompt):
            return "research"

    # 3f: Default — implementation (strictest rules apply)
    return "implementation"


# ============================================================================
# LAYER 2: PROTOCOL ENFORCEMENT
# ============================================================================

def enforce_definition(prompt, subagent_type, task_type):
    """
    If the task type maps to a protocol that has a required agent definition,
    and the caller isn't using that definition, BLOCK.

    This is the key enforcement mechanism: instead of checking that a generic
    agent prompt contains all the right keywords, we require the caller to
    use the agent definition that HAS the protocol baked in.
    """
    if task_type not in PROTOCOL_DEFINITIONS:
        return None

    proto = PROTOCOL_DEFINITIONS[task_type]
    required = proto["required_type"]

    # Already using the correct definition — pass
    if subagent_type == required:
        return None

    return (
        f"PROTOCOL ENFORCEMENT — Use agent definition '{required}' for {proto['description']} work.\n"
        f"\n"
        f"  Current subagent_type: '{subagent_type or '(none)'}'\n"
        f"  Required: subagent_type: \"{required}\"\n"
        f"\n"
        f"  Why: {proto['rationale']}\n"
        f"\n"
        f"  Fix: Add `subagent_type: \"{required}\"` to your Agent tool call.\n"
        f"  The agent definition file (.claude/agents/{required}.md) contains the full\n"
        f"  protocol structure. You still provide the specific assignment (which PRD,\n"
        f"  which tickets, Linear IDs, migration timestamps) in the prompt."
    )


# ============================================================================
# LAYER 3: TASK-TYPE RULES
# ============================================================================

def validate_rules(prompt, task_type, subagent_type):
    """
    Apply validation rules specific to the classified task type.
    Returns (failures: list[str], warnings: list[str]).
    """
    failures = []
    warnings = []

    # When subagent_type matches a known definition, the definition provides
    # structural requirements (protocol, team roles, SendMessage, etc.).
    # The prompt only needs assignment-specific content (which PRD, Linear IDs, etc.).
    has_definition = subagent_type in DEFINITION_TYPES

    if task_type == "implementation":
        _validate_implementation(prompt, failures, warnings)
    elif task_type == "decomposition":
        _validate_decomposition(prompt, failures, warnings, has_definition)
    elif task_type == "prd":
        _validate_prd(prompt, failures, warnings, has_definition)
    elif task_type == "grooming":
        _validate_grooming(prompt, failures, warnings)
    elif task_type == "design":
        _validate_design(prompt, failures, warnings)
    elif task_type == "team-role":
        _validate_team_role(prompt, failures, warnings)
    # research and skip: no rules

    # Cross-cutting: verbatim handoff for protocol agents
    # Skip if agent definition is being used — the definition includes this instruction.
    if task_type not in ("research", "skip", "team-role") and not has_definition:
        if re.search(
            r"(?i)protocols/(ticket-decomposition|prd-drafting|implementation)", prompt
        ):
            if not re.search(r"(?i)(verbatim|never summarize)", prompt):
                warnings.append(
                    "MISSING VERBATIM HANDOFF RULE — Protocol-based agents must pass context "
                    "verbatim between roles. Include: 'Pass context VERBATIM — never summarize.'"
                )

    return failures, warnings


def _validate_implementation(prompt, failures, warnings):
    """Rules for agents that write code."""

    cfg = _project_config.get_config()
    ci_command = cfg["ci_command"]
    ticket_pattern = _project_config.ticket_prefix_pattern()

    # I1: CI command — check that the prompt mentions running CI
    # Use patterns from the project's ci_required_patterns if available,
    # otherwise check for the ci_command string itself.
    ci_patterns = cfg.get("ci_required_patterns", [])
    if ci_patterns:
        # Check that at least one CI pattern keyword appears in the prompt
        has_ci_ref = any(
            re.search(pattern, prompt) for pattern in ci_patterns
        )
    else:
        has_ci_ref = ci_command in prompt

    if not has_ci_ref and ci_command != _project_config._DEFAULTS["ci_command"]:
        failures.append(
            f"MISSING CI COMMAND — Agent prompt must include the CI verification command:\n"
            f"    {ci_command}\n"
            f"  Without this, agents ship code that breaks CI and wastes a fix cycle."
        )

    # I2: Prior art
    if not re.search(
        r"(?i)(read .*(existing|current) .*(code|module|file|pattern|implementation|"
        r"worker|schema|context|test)|look at .*(existing|current)|"
        r"examine .*(existing|current)|prior art|existing (pattern|code|module|implementation)|"
        r"follow.*(existing|established) pattern|establish patterns)",
        prompt,
    ):
        failures.append(
            "MISSING PRIOR ART — Instruct reading existing code before implementing.\n"
            "  Example: 'Before implementing, read at least 2 existing modules in the "
            "target directory to establish patterns.'"
        )

    # I6: Bug fix TDD
    if re.search(
        r"(?i)\b(bug|fix|defect|regression|broken|pagination.*(bug|fix)|fix.*(bug|pagination))\b",
        prompt,
    ):
        if not re.search(
            r"(?i)(TDD|test.*(first|fail)|failing test|write.*test.*before|"
            r"reproduce.*bug|prove.*bug)",
            prompt,
        ):
            warnings.append(
                "BUG FIX WITHOUT TDD — Bug fixes must be TDD-style:\n"
                "  1. Write a test that reproduces the bug (FAILS)\n"
                "  2. Implement the fix\n"
                "  3. Verify the test passes"
            )

    # I10: Ticket ID — prompt must reference a ticket (if prefixes configured)
    if ticket_pattern:
        if not re.search(rf"(?i)({ticket_pattern})", prompt):
            failures.append(
                "MISSING TICKET ID — Implementation prompt must reference a Linear ticket ID.\n"
                "  Without this, there's no traceability between the agent's work and the ticket."
            )

    # I12: Self-evaluation / self-review
    if not re.search(r"(?i)(self.review|self.evaluation|Self-Review|pre.submit checklist)", prompt):
        failures.append(
            "MISSING SELF-EVALUATION — Prompt must instruct the agent to write a '## Self-Review'\n"
            "  section in the PR body. This is Layer 3 of the six-layer quality system.\n"
            "  Add: 'Include a ## Self-Review section in the PR body covering: prior art read,\n"
            "  API verification, protocol compliance, and domain reasoning.'"
        )

    # I13: Ticket state transition
    if not re.search(
        r"(?i)(move.*ticket.*In Progress|ticket.*state.*In Progress|"
        r"transition.*In Progress|update.*Linear.*In Progress|"
        r"In Progress.*before|mark.*In Progress)",
        prompt,
    ):
        warnings.append(
            "MISSING TICKET STATE TRANSITION — Instruct the agent to move the ticket\n"
            "  to 'In Progress' in Linear before starting implementation."
        )

    # I14: FFI-D4 — External API verification (Principle 025)
    # When the prompt involves external API work, check for evidence that
    # the agent is instructed to verify API calls against actual documentation
    # rather than writing from memory/training data.
    _validate_ffi_d4_api_verification(prompt, warnings)


def _validate_ffi_d4_api_verification(prompt, warnings):
    """FFI-D4: external API work must include verification evidence.

    Two-phase check:
      1. Detect external API indicators — if none, skip (no false positives on DB/UI work)
      2. Check for verification evidence — reading docs, existing clients, or explicit verification

    This is a WARNING, not a block, because detecting "involves external APIs" is heuristic.
    The goal is to catch the common case: an agent told to "build a Stripe adapter" with
    no instruction to read the actual Stripe API docs first.

    Reference: Principle 025 (External API Verification), Protocol Evolution PRD D7/R6.1.
    """
    # Phase 1: Does the prompt involve external API work?
    api_indicators = re.search(
        r"(?i)("
        r"external.*(API|service)|"                       # "external API", "external service"
        r"\b(REST|GraphQL|gRPC)\b.*\b(client|query|endpoint|mutation|call)\b|"  # protocol + action
        r"\b(client|query|endpoint|mutation|call)\b.*\b(REST|GraphQL|gRPC)\b|"  # action + protocol
        r"\bHTTP\s+client\b|"                             # "HTTP client"
        r"\bwebhook\b|"                                   # webhooks always involve external APIs
        r"\b(port|adapter)\b.*\b(app|module|pattern)\b|"  # ports & adapters pattern
        r"\bAPI\s+(endpoint|integration|call|request)\b|"  # "API endpoint", "API integration"
        r"\b(Stripe|Linear|GitHub|S3|OAuth|FreshBooks)\s+(API|adapter|client|webhook|integration)\b"
        r")",
        prompt,
    )

    if not api_indicators:
        return

    # Phase 2: Is there evidence of API verification?
    has_verification = re.search(
        r"(?i)("
        r"WebFetch|WebSearch|"                            # tool-based doc lookup
        r"(read|check|fetch|review).*API\s+doc|"          # "read API documentation"
        r"API\s+doc.*\b(read|check|fetch|review)\b|"      # "API documentation, read it"
        r"official\s+(API\s+)?doc|"                       # "official documentation"
        r"API\s+reference|"                               # "API reference"
        r"(read|check).*existing\s+(client|adapter)|"     # "read existing client code"
        r"existing\s+(client|adapter).*\b(read|check)\b|"  # "existing client, read it"
        r"API\s+contract|contracts\s+reference|"          # contracts file reference
        r"\bcurl\b.*\b(test|verif|endpoint)\b|"           # curl-based testing
        r"\b(test|verif).*\bcurl\b|"                      # "test with curl"
        r"verify.*API\s+(endpoint|call|query)|"           # "verify the API endpoints"
        r"API.*(endpoint|call|query).*verify|"            # "API endpoints...verify"
        r"verify.*(endpoint|response|request)\s+shape|"   # "verify response shapes"
        r"FFI-D4|"                                        # explicit principle reference
        r"025-external-api|"                              # principle file reference
        r"introspect.*schema|schema.*introspect"          # GraphQL introspection
        r")",
        prompt,
    )

    if not has_verification:
        warnings.append(
            "MISSING API VERIFICATION (FFI-D4) — This prompt involves external API work but lacks\n"
            "  verification instructions. Agents write API calls from memory/training data, producing\n"
            "  code that compiles but uses wrong endpoints, params, or response shapes.\n"
            "  Add one of:\n"
            "    - 'Use WebFetch/WebSearch to read the official API documentation'\n"
            "    - 'Read the existing client/adapter code in the port app'\n"
            "    - 'Verify API endpoints and response shapes before writing code'\n"
            "    - 'Read the API contracts reference'\n"
            "  Reference: Principle 025 — External API Verification"
        )


def _validate_decomposition(prompt, failures, warnings, has_definition=False):
    """Rules for decomposition coordinator agents.

    When has_definition=True, the agent definition (.claude/agents/decomp-coordinator.md)
    provides: protocol reference, TeamCreate instruction, team roles, SendMessage mechanics.
    The prompt only needs assignment-specific content: which PRD, Linear IDs, migrations.
    """

    if not has_definition:
        # --- Structural rules (only when definition is NOT providing them) ---

        # D1: Protocol reference
        if not re.search(r"(?i)protocols/ticket-decomposition", prompt):
            failures.append(
                "MISSING PROTOCOL REFERENCE — Must reference protocols/ticket-decomposition.md\n"
                "  The protocol defines team structure, phase flow, and handoff mechanics."
            )

        # D2: TeamCreate
        if not re.search(r"(?i)TeamCreate", prompt):
            failures.append(
                "MISSING TeamCreate — Protocol requires TeamCreate to create a named team.\n"
                "  Team: coordinator -> scout -> PM -> designer + TPM -> validator."
            )

        # D4: Team roles
        missing_roles = []
        role_checks = {
            "PM": r"(?i)\bPM\b|project.manager",
            "Designer": r"(?i)\bdesigner\b",
            "TPM": r"(?i)\bTPM\b|technical.project.manager",
            "Validator": r"(?i)\bvalidator\b",
        }
        for role, pattern in role_checks.items():
            if not re.search(pattern, prompt):
                missing_roles.append(role)
        if missing_roles:
            warnings.append(
                f"MISSING TEAM ROLES: {', '.join(missing_roles)}\n"
                "  The decomposition protocol requires: coordinator, scout, PM, Designer, TPM, Validator."
            )

        # D7: SendMessage
        if not re.search(r"(?i)SendMessage", prompt):
            warnings.append(
                "MISSING SendMessage — Protocol requires context handoffs via SendMessage between roles."
            )

    # --- Assignment-specific rules (always checked) ---

    # D3: PRD reference — the prompt must say WHICH PRD to decompose
    if not re.search(r"(?i)PRDs/accepted/", prompt):
        failures.append(
            "MISSING PRD REFERENCE — Must reference the accepted PRD file path.\n"
            "  Example: PRDs/accepted/stripe-billing.md"
        )

    # D5: Linear context
    if not re.search(r"(?i)(linear|team.*ID|project.*ID)", prompt):
        warnings.append(
            "MISSING LINEAR CONTEXT — Include Linear team/project IDs for ticket creation."
        )

    # D6: Migration baseline
    if not re.search(r"(?i)(migration.*timestamp|latest migration|next.*migration|20\d{12})", prompt):
        warnings.append(
            "MISSING MIGRATION BASELINE — Include latest migration timestamp to avoid collisions."
        )


def _validate_prd(prompt, failures, warnings, has_definition=False):
    """Rules for PRD writer agents.

    When has_definition=True, the agent definition (.claude/agents/prd-writer.md)
    provides: protocol reference, team structure, critique checklist, template,
    calibration instruction, required reading list.
    The prompt only needs: which PRD to write, output path, specific research context.
    """

    if not has_definition:
        # --- Structural rules (only when definition is NOT providing them) ---

        # P1: Protocol reference
        if not re.search(r"(?i)(protocols/prd-drafting|PRD template|PRD.*template)", prompt):
            warnings.append(
                "MISSING PRD PROTOCOL — Reference protocols/prd-drafting.md for template and checklist."
            )

        # P3: Calibration PRD
        if not re.search(r"(?i)(calibrat|style.*match|match.*depth|PRDs/accepted/)", prompt):
            warnings.append(
                "MISSING CALIBRATION PRD — Read an accepted PRD for depth/style calibration."
            )

        # P4: Context reading
        if not re.search(
            r"(?i)(read.*before|required reading|roadmap|deferred.requirements|existing.*PRD|accepted PRD)",
            prompt,
        ):
            warnings.append(
                "MISSING CONTEXT READING — Read roadmap, deferred requirements, and related PRDs."
            )

    # --- Assignment-specific rules (always checked) ---

    # P2: Output path — the prompt must say WHERE to write the draft
    if not re.search(r"(?i)(PRDs/drafts/|output.*path|write.*to)", prompt):
        warnings.append(
            "MISSING OUTPUT PATH — Specify: write to PRDs/drafts/{name}.md"
        )


def _validate_grooming(prompt, failures, warnings):
    """Rules for grooming protocol agents."""

    # G1: Protocol reference
    if not re.search(r"(?i)protocols/grooming", prompt):
        failures.append(
            "MISSING PROTOCOL REFERENCE — Must reference protocols/grooming.md"
        )

    # G2: TeamCreate
    if not re.search(r"(?i)TeamCreate", prompt):
        failures.append(
            "MISSING TeamCreate — Grooming protocol requires a team.\n"
            "  Team: coordinator + codebase-scout + groomer."
        )

    # G3: Roles
    missing_roles = []
    if not re.search(r"(?i)\bscout\b|codebase.scout", prompt):
        missing_roles.append("codebase-scout")
    if not re.search(r"(?i)\bgroomer\b", prompt):
        missing_roles.append("groomer")
    if missing_roles:
        warnings.append(
            f"MISSING GROOMING ROLES: {', '.join(missing_roles)}\n"
            "  Protocol requires: coordinator, codebase-scout, groomer."
        )

    # G4: Chad review gate
    if not re.search(r"(?i)(present.*Chad|Chad.*review|Chad.*approv|report.*to.*Chad)", prompt):
        warnings.append(
            "MISSING CHAD REVIEW GATE — Findings must be presented to the reviewer before tickets move."
        )

    # G5: SendMessage
    if not re.search(r"(?i)SendMessage", prompt):
        warnings.append(
            "MISSING SendMessage — Protocol requires context handoffs via SendMessage."
        )


def _validate_design(prompt, failures, warnings):
    """Rules for design-reasoner agents that produce design specs (not code)."""

    # DS1: Design system spec reference
    if not re.search(r"(?i)(design-system\.md|\.claude/design-system)", prompt):
        failures.append(
            "MISSING DESIGN SYSTEM REFERENCE — Design reasoner must read .claude/design-system.md\n"
            "  This contains page archetypes, component library, tokens, and selection guides."
        )

    # DS2: Prior art instruction
    if not re.search(
        r"(?i)(prior art|read.*existing.*live|read.*Live.*module|read.*LiveView)",
        prompt,
    ):
        warnings.append(
            "MISSING PRIOR ART INSTRUCTION — Design reasoner should read 2-3 existing\n"
            "  LiveView modules as taste anchors before producing a spec."
        )

    # DS3: Ticket reference
    ticket_pattern = _project_config.ticket_prefix_pattern()
    if ticket_pattern:
        if not re.search(rf"(?i)({ticket_pattern})", prompt):
            warnings.append(
                "MISSING TICKET REFERENCE — Include the ticket ID for traceability."
            )

    # DS4: Schema reading instruction
    if not re.search(
        r"(?i)(read.*schema|schema.*module|data model|fields.*exist)",
        prompt,
    ):
        warnings.append(
            "MISSING SCHEMA INSTRUCTION — Design reasoner should read relevant schema\n"
            "  modules to ground the data model in actual fields."
        )


def _validate_team_role(prompt, failures, warnings):
    """Rules for sub-agents within an existing team."""

    # TR1: Reading instructions
    if not re.search(
        r"(?i)(read.*before|read at least|required reading|before (starting|writing|reviewing)|"
        r"read the (full |current )?PRD|read.*existing|establish patterns|"
        r"mcp__obsidian.*read_note|read.*CLAUDE\.md)",
        prompt,
    ):
        warnings.append(
            "TEAM ROLE WITHOUT READING INSTRUCTIONS — All team roles should read context first.\n"
            "  PM: read PRD + existing tickets. Designer: read design system. TPM: read codebase + CLAUDE.md."
        )

    # TR2: Output routing
    if not re.search(
        r"(?i)(send.*to.*team.lead|SendMessage|message.*coordinator|"
        r"send.*findings|send.*skeleton|send.*output)",
        prompt,
    ):
        warnings.append(
            "TEAM ROLE WITHOUT OUTPUT ROUTING — Specify where to send output.\n"
            "  Include: 'Send your output to the coordinator via SendMessage when done.'"
        )


# ============================================================================
# REPORTING
# ============================================================================

def report_and_exit(failures, warnings, task_type):
    """Format and emit the lint report, then exit with appropriate code."""
    lines = [
        "=== Agent Prompt Lint Report ===",
        "",
        f"Task type: {task_type}",
        "",
    ]

    if failures:
        lines.append(f"BLOCKING ({len(failures)} rule(s) failed — fix before deploying):")
        lines.append("")
        for i, f in enumerate(failures, 1):
            lines.append(f"  {i}. {f}")
            lines.append("")

    if warnings:
        lines.append(f"WARNINGS ({len(warnings)} — consider adding for better results):")
        lines.append("")
        for i, w in enumerate(warnings, 1):
            lines.append(f"  {i}. {w}")
            lines.append("")

    lines.append("Reference: .claude/agents/ for agent definitions")
    lines.append("=== End Lint Report ===")

    report = "\n".join(lines)
    if failures:
        print(report, file=sys.stderr)
        sys.exit(2)
    else:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "additionalContext": report,
            }
        }))
        sys.exit(0)


# ============================================================================
# MAIN
# ============================================================================

def _extract_team_pattern(prompt, task_type):
    """Extract the expected team name pattern from the prompt.

    Always returns a glob pattern (e.g., "prd-*") rather than trying to extract
    the exact team name. Exact extraction is fragile because protocol file paths
    in the prompt (e.g., "protocols/prd-drafting.md") match the same regex as
    team names (e.g., "prd-dun-phase1b"), and the file path appears first.

    The glob pattern is correct semantically: any team created by a validated
    protocol coordinator that starts with the expected prefix is legitimate.
    The provenance check in check_team_provenance() handles the matching.
    """
    PATTERNS = {
        "decomposition": "decomp-*",
        "prd": "prd-*",
        "grooming": "grooming-*",
    }
    return PATTERNS.get(task_type, "")


def _extract_expected_roles(task_type):
    """Get the expected team roles for a task type."""
    if task_type == "decomposition":
        return ["PM", "Designer", "TPM", "Validator"]
    elif task_type == "prd":
        return ["researcher", "writer", "critic"]
    elif task_type == "grooming":
        return ["scout", "groomer"]
    return []


def _detect_role_hint(prompt):
    """Try to detect which team role this sub-agent is playing."""
    role_patterns = {
        "PM": r"(?i)\byou are (the |a )?PM\b|project manager",
        "Designer": r"(?i)\byou are (the |a )?designer\b",
        "TPM": r"(?i)\byou are (the |a )?TPM\b|technical.*project manager",
        "Validator": r"(?i)\byou are (the |a )?validator\b",
        "scout": r"(?i)\byou are (the |a )?(codebase )?scout\b|codebase.analyst",
        "researcher": r"(?i)\byou are (the |a )?research",
        "writer": r"(?i)\byou are (the |a )?.*writer\b",
        "critic": r"(?i)\byou are (the |a )?critic\b|quality reviewer",
        "groomer": r"(?i)\byou are (the |a )?groomer\b|ticket.*reviewer",
        "supervisor": r"(?i)\byou are (the |a )?supervisor\b|cross.*review",
        "implementer": r"(?i)\byou are (the |a )?(senior )?.*engineer.*implement",
        "fixer": r"(?i)\byou are (the |a )?(senior )?.*engineer.*fix",
    }
    for role, pattern in role_patterns.items():
        if re.search(pattern, prompt):
            return role
    return "unknown"


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    if tool_name != "Agent":
        sys.exit(0)

    tool_input = data.get("tool_input", {})
    prompt = tool_input.get("prompt", "")
    subagent_type = tool_input.get("subagent_type", "")
    team_name = tool_input.get("team_name", "")
    agent_name = tool_input.get("name", "")

    # Collect advisory warnings that arise outside the validation rules.
    # These are merged into the warnings list and delivered via
    # hookSpecificOutput.additionalContext on exit 0.
    early_warnings = []
    if subagent_type in DEPRECATED_ALIASES:
        canonical = DEPRECATED_ALIASES[subagent_type]
        early_warnings.append(
            f"DEPRECATED: '{subagent_type}' will be removed in v0.4.0. "
            f"Use '{canonical}'."
        )

    # LAYER 0: Retired agent redirect — block early with successor guidance
    if subagent_type in RETIRED_AGENTS:
        info = RETIRED_AGENTS[subagent_type]
        successors = ", ".join(f"'{s}'" for s in info["successors"])
        msg = (
            f"RETIRED AGENT — '{subagent_type}' is no longer available.\n"
            f"\n"
            f"  {info['reason']}\n"
            f"\n"
            f"  Fix: Replace subagent_type: \"{subagent_type}\" with one of: {successors}"
        )
        print(msg, file=sys.stderr)
        sys.exit(2)

    # LAYER 1: Classify
    task_type = classify(prompt, subagent_type, team_name, agent_name)

    if task_type == "skip":
        sys.exit(0)

    # AUDIT: Write expectations for protocol agents
    if task_type in ("decomposition", "prd", "grooming"):
        pattern = _extract_team_pattern(prompt, task_type)
        roles = _extract_expected_roles(task_type)
        _audit.write_expectation(
            agent_name=agent_name or pattern or task_type,
            task_type=task_type,
            expected_team_pattern=pattern,
            expected_roles=roles,
        )

    # AUDIT: Log sub-agent spawns within teams
    if task_type == "team-role":
        resolved_team, _ = _resolve_team_context(team_name, agent_name)
        role_hint = _detect_role_hint(prompt)
        if resolved_team:
            _audit.write_agent_spawned(
                team_name=resolved_team,
                agent_name=agent_name or role_hint,
                subagent_type=subagent_type,
                role_hint=role_hint,
            )

    # LAYER 2: Enforce correct agent definition for protocol tasks
    enforcement_failure = enforce_definition(prompt, subagent_type, task_type)
    if enforcement_failure:
        # SILENT FAILURE PREVENTION: If this looks like a team sub-agent
        # that was misclassified, record the block and surface context.
        resolved_team, _ = _resolve_team_context(team_name, agent_name)
        if resolved_team:
            _audit.write_spawn_blocked(
                team_name=resolved_team,
                agent_name=agent_name or "(unnamed)",
                reason=f"Protocol enforcement blocked spawn — classified as '{task_type}' "
                       f"but no matching subagent_type. This agent may be a team sub-agent "
                       f"whose prompt triggered protocol keyword matching.",
                classified_as=task_type,
            )
        report_and_exit([enforcement_failure], early_warnings, task_type)

    # LAYER 3: Task-type-specific rules
    failures, warnings = validate_rules(prompt, task_type, subagent_type)
    warnings = early_warnings + warnings

    if failures:
        # SILENT FAILURE PREVENTION: Record blocked spawns within teams
        resolved_team, _ = _resolve_team_context(team_name, agent_name)
        if resolved_team:
            _audit.write_spawn_blocked(
                team_name=resolved_team,
                agent_name=agent_name or "(unnamed)",
                reason=f"Validation rules blocked spawn — {len(failures)} failure(s): "
                       + "; ".join(f[:80] for f in failures),
                classified_as=task_type,
            )

    if failures or warnings:
        report_and_exit(failures, warnings, task_type)

    sys.exit(0)


if __name__ == "__main__":
    main()
