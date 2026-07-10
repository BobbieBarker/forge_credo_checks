#!/usr/bin/env python3
"""
Protocol Compliance Audit Report

Manual audit tool for checking whether protocol agents (decomposition,
PRD drafting, grooming) actually followed their protocols at runtime.

Especially useful for background agents, where PostToolUse:Agent fires
immediately (before the agent does anything) and can't check compliance.

Usage:
  python3 .claude/hooks/audit-report.py          # full report
  python3 .claude/hooks/audit-report.py --clean   # delete all audit files
  python3 .claude/hooks/audit-report.py --team X  # report for team X only
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import _audit


def main():
    parser = argparse.ArgumentParser(description="Protocol compliance audit")
    parser.add_argument("--clean", action="store_true", help="Delete all audit files")
    parser.add_argument("--team", type=str, help="Show report for a specific team")
    args = parser.parse_args()

    if args.clean:
        if _audit.AUDIT_DIR.exists():
            count = 0
            for f in _audit.AUDIT_DIR.glob("*.json"):
                f.unlink()
                count += 1
            print(f"Cleaned {count} audit files from {_audit.AUDIT_DIR}")
        else:
            print("No audit directory found.")
        return

    if args.team:
        events = _audit.read_events(args.team)
        if not events:
            print(f"No events found for team '{args.team}'")
            return
        print(f"Events for team '{args.team}':")
        for ev in events:
            etype = ev.get("event", "unknown")
            etime = ev.get("iso_time", "")
            if etype == "team_created":
                print(f"  [{etime}] Team created: {ev.get('team_name')}")
            elif etype == "agent_spawned":
                print(f"  [{etime}] Spawned: {ev.get('agent_name')} (role: {ev.get('role_hint', '?')})")
            elif etype == "message_sent":
                print(f"  [{etime}] Message -> {ev.get('to')} ({ev.get('message_length', 0)} chars)")
        return

    print(_audit.get_audit_summary())


if __name__ == "__main__":
    main()
