#!/usr/bin/env python3
"""
Agent Statistics Collector.

Parses agent registry, checks process status, collects token stats
from Hermes sessions, and writes a JSON summary to agent_stats.json.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# ── Paths ──────────────────────────────────────────────────────────────────
AGENTS_YAML = Path.home() / "agent-control-room/bus/registry/agents.yaml"
KNOWLEDGE_YAML = Path.home() / "agent-control-room/bus/knowledge.yaml"
LOGS_DIR = Path.home() / "agent-control-room/logs"
SESSIONS_DIR = Path.home() / ".hermes/webui/sessions"
OUTPUT = Path.home() / "agent-control-room/bus/agent_stats.json"

# ── Cost rates (USD per token) ────────────────────────────────────────────
# Used as fallback when estimated_cost is not available in session file.
COST_RATES: dict[str, dict[str, float]] = {
    "deepseek-v4-flash": {"input": 0.15 / 1_000_000, "output": 0.60 / 1_000_000},
    "deepseek-v4-pro": {"input": 0.40 / 1_000_000, "output": 1.60 / 1_000_000},
    "deepseek-chat": {"input": 0.27 / 1_000_000, "output": 1.10 / 1_000_000},
    "google/gemini-2.5-flash": {"input": 0.15 / 1_000_000, "output": 0.60 / 1_000_000},
    "qwen/qwen3-235b-a22b": {"input": 0.15 / 1_000_000, "output": 0.60 / 1_000_000},
}

DEFAULT_COST_RATE = {"input": 0.15 / 1_000_000, "output": 0.60 / 1_000_000}


# ── Helpers ────────────────────────────────────────────────────────────────


def load_yaml(path: Path) -> dict[str, Any]:
    """Safely load a YAML file, returning an empty dict on error."""
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
        return data if isinstance(data, dict) else {}
    except (FileNotFoundError, yaml.YAMLError, OSError) as exc:
        print(f"  ⚠  Could not load {path}: {exc}", file=sys.stderr)
        return {}


def get_agent_status(profile: str, alias: str | None = None) -> str:
    """Determine whether an agent process is currently running.

    Returns one of: ``working``, ``idle``, ``error``.
    """
    try:
        result = subprocess.run(
            ["ps", "aux"],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
        print(f"  ⚠  ps aux failed: {exc}", file=sys.stderr)
        return "error"

    lines = result.stdout.lower().splitlines()

    # Check by profile name (e.g. "coder", "planner", "default")
    for line in lines:
        if profile.lower() in line and "grep" not in line and "ps aux" not in line:
            return "working"

    # Fallback: check by alias basename (e.g. "~/.local/bin/coder" → "coder")
    if alias:
        alias_name = os.path.basename(alias)
        for line in lines:
            if alias_name.lower() in line and "grep" not in line and "ps aux" not in line:
                return "working"

    return "idle"


def get_current_task(agent_name: str) -> str:
    """Parse the most recent log for *agent_name* and extract the task."""
    try:
        log_pattern = f"*_{agent_name}.md"
        log_files = sorted(Path(LOGS_DIR).glob(log_pattern), reverse=True)
    except OSError:
        return ""

    if not log_files:
        return ""

    try:
        with open(log_files[0], encoding="utf-8") as f:
            content = f.read(4096)  # first 4 KB is enough
    except OSError:
        return ""

    # Try to extract the query / task prompt
    match = re.search(r"Query:\s*(.+?)(?:\n|$)", content)
    if match:
        return match.group(1).strip()[:300]  # cap length

    return ""


def get_agent_tokens(profile: str, model: str = "") -> tuple[int, int, float]:
    """Sum token usage and cost across all Hermes sessions for *profile*."""
    total_input = 0
    total_output = 0
    total_cost = 0.0

    if not SESSIONS_DIR.is_dir():
        return total_input, total_output, total_cost

    rate = COST_RATES.get(model, DEFAULT_COST_RATE)

    for fpath in sorted(SESSIONS_DIR.iterdir()):
        if not fpath.name.endswith(".json") or fpath.name.startswith("_"):
            continue
        try:
            with open(fpath, encoding="utf-8") as f:
                session: dict[str, Any] = json.load(f)
        except (json.JSONDecodeError, OSError):
            continue

        if session.get("profile") != profile:
            continue

        inp = session.get("input_tokens") or 0
        out = session.get("output_tokens") or 0
        cost = session.get("estimated_cost")

        total_input += inp
        total_output += out

        if cost is not None and isinstance(cost, (int, float)):
            total_cost += cost
        else:
            # Fallback calculation
            total_cost += inp * rate["input"] + out * rate["output"]

    return total_input, total_output, round(total_cost, 6)


def cast_position(value: Any) -> str:
    """Normalise position to a string (YAML may parse unicode as int/str)."""
    if isinstance(value, str):
        return value
    # Handle unicode characters that might be read oddly
    return str(value)


# ── Main ──────────────────────────────────────────────────────────────────


def main() -> None:
    print("Collecting agent statistics …", file=sys.stderr)

    # 1. Load agent registry
    agents_raw = load_yaml(AGENTS_YAML)
    agents: dict[str, Any] = agents_raw.get("agents", {})
    if not agents:
        print("  ⚠  No agents found in registry (or file is empty).", file=sys.stderr)

    # 2. Load shared knowledge
    knowledge = load_yaml(KNOWLEDGE_YAML)
    session_info = knowledge.get("session", {})
    session_task: str = session_info.get("task", "")

    # 3. Collect stats per agent
    result_agents: list[dict[str, Any]] = []

    for agent_name in sorted(agents.keys()):
        config = agents[agent_name]

        profile = config.get("profile", agent_name)
        alias = config.get("alias")
        role = config.get("role", "")
        position = cast_position(config.get("position", ""))
        pipeline_stage = config.get("pipeline_stage", "")
        model = config.get("model", "")
        provider = config.get("provider", "")

        # Status
        status = get_agent_status(profile, alias)

        # Current task (only meaningful when working)
        current_task = ""
        if status == "working":
            current_task = get_current_task(agent_name)

        # Token statistics
        tokens_in, tokens_out, cost = get_agent_tokens(profile, model)

        result_agents.append({
            "name": agent_name,
            "role": role,
            "position": position,
            "pipeline_stage": pipeline_stage,
            "model": model,
            "provider": provider,
            "status": status,
            "current_task": current_task,
            "tokens_in": tokens_in,
            "tokens_out": tokens_out,
            "cost_usd": cost,
        })

    # 4. Build final output
    output: dict[str, Any] = {
        "updated_at": datetime.now(timezone.utc)
        .astimezone()
        .isoformat(timespec="seconds"),
        "session_task": session_task,
        "agents": result_agents,
    }

    # 5. Write JSON
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    print(f"  ✓  Written {len(result_agents)} agents to {OUTPUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
