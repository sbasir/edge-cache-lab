#!/usr/bin/env python3
"""
Dependency vulnerability audit with a timeboxed CVE allowlist.

Reads dep-audit-allowlist.json, fails immediately if any entries have expired
(the timebox forces a conscious renew-or-fix), then runs `pnpm audit` and fails
on any high+ advisory not covered by an active allowlist entry.

Usage:
    uv run scripts/dep-audit.py        # or: python3 scripts/dep-audit.py
"""

import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

AUDIT_LEVEL = "high"
SEVERITIES = ["critical", "high", "moderate", "low"]
FAIL_SEVERITIES = set(SEVERITIES[: SEVERITIES.index(AUDIT_LEVEL) + 1])

ALLOWLIST_FILE = Path(__file__).parent.parent / "dep-audit-allowlist.json"


def load_allowlist() -> list:
    if not ALLOWLIST_FILE.exists():
        return []
    return json.loads(ALLOWLIST_FILE.read_text()).get("allowlist", [])


def parse_until(entry: dict) -> datetime | None:
    raw = entry.get("until")
    if not raw:
        return None
    return datetime.fromisoformat(raw.replace("Z", "+00:00"))


def main() -> None:
    now = datetime.now(UTC)
    allowlist = load_allowlist()

    # -- 1. Fail fast on expired entries ---------------------------------------
    expired = [
        e
        for e in allowlist
        if isinstance(e, dict) and (t := parse_until(e)) is not None and t < now
    ]
    if expired:
        print(
            "AUDIT FAIL: allowlist entries have expired — update the package or renew the entry.\n"
        )
        for entry in expired:
            print(f"  {entry['id']:36}  expired {entry['until']}")
            print(f"  reason: {entry.get('reason', '(none)')}\n")
        print("Run `pnpm audit` to check whether the package has been updated.")
        sys.exit(1)

    # -- 2. Collect active GHSA IDs --------------------------------------------
    active_ids: set[str] = set()
    for entry in allowlist:
        if isinstance(entry, str):
            active_ids.add(entry)
        elif isinstance(entry, dict):
            until = parse_until(entry)
            if until is None or until >= now:
                active_ids.add(entry["id"])

    # -- 3. Run pnpm audit ------------------------------------------------------
    result = subprocess.run(["pnpm", "audit", "--json"], capture_output=True, text=True)
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        print(
            f"Could not parse pnpm audit output:\n{result.stdout}\n{result.stderr}",
            file=sys.stderr,
        )
        sys.exit(1)

    # -- 4. Filter and report ---------------------------------------------------
    advisories = data.get("advisories", {}).values()
    failing, suppressed = [], []
    for adv in advisories:
        if adv.get("severity") not in FAIL_SEVERITIES:
            continue
        (suppressed if adv.get("github_advisory_id") in active_ids else failing).append(adv)

    if suppressed:
        print(f"Suppressed {len(suppressed)} advisory(ies) via active allowlist:")
        for adv in suppressed:
            print(
                f"  {adv.get('github_advisory_id', '?'):36}  "
                f"{adv.get('severity'):8}  {adv.get('module_name')}"
            )

    if failing:
        print(f"\nAUDIT FAIL: {len(failing)} {AUDIT_LEVEL}+ advisory(ies) not in allowlist:")
        for adv in failing:
            print(
                f"  {adv.get('github_advisory_id', '?'):36}  "
                f"{adv.get('severity'):8}  {adv.get('module_name')}  {adv.get('url')}"
            )
        sys.exit(1)

    if not suppressed and not failing:
        print("Audit clean — no high+ advisories found.")
    else:
        print(f"\nAudit passed — {len(suppressed)} suppressed, 0 failing (level={AUDIT_LEVEL}+).")


if __name__ == "__main__":
    main()
