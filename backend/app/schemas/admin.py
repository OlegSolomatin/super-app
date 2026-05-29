"""Pydantic models for the Agent Monitoring Dashboard."""

from __future__ import annotations

from pydantic import BaseModel


class AgentStatus(BaseModel):
    """Status of a single agent."""

    name: str
    role: str
    position: str = ""
    pipeline_stage: str = ""
    model: str = ""
    provider: str = ""
    status: str = "idle"  # idle / working / error
    current_task: str = ""
    tokens_in: int = 0
    tokens_out: int = 0
    cost_usd: float = 0.0


class AgentStatusResponse(BaseModel):
    """Response containing all agent statuses."""

    updated_at: str
    session_task: str = ""
    agents: list[AgentStatus]
