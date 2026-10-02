"""Graph state and trusted run context for the inventory Agent."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Annotated, TypedDict
from uuid import UUID

from langchain_core.messages import AnyMessage
from langgraph.graph.message import add_messages


class AgentState(TypedDict):
    messages: Annotated[list[AnyMessage], add_messages]
    turn_id: str
    as_of: str | None
    request_fingerprint: str
    requests: dict
    items: list[dict]
    context_summary: dict
    pending_input: list[dict]
    execution_results: list[dict]
    route: str
    resume_requests: dict
    events: list[dict]
    final_only: bool
    image_task_active: bool
    turn_has_images: bool
    turn_intent: dict
    proposal_retries: int
    prose_retries: int
    context_compaction: dict
    conversation_summary: str
    summary_cursor: str | None
    summary_position: int
    summary_pending_ids: list[str]
    context_next: str
    public_turn: dict
    history_outbox: dict
    resume_payload: dict
    suspended_items: list[dict]
    chat_requests: dict
    image_messages: list
    completed_items: list[dict]
    unresolved_reply: dict | None
    revision_scope: list[str] | None


@dataclass(frozen=True, slots=True)
class AgentContext:
    """Server-owned values that must never be supplied by the model."""

    user_id: UUID
    as_of: date | None
    conversation_id: UUID | None = None
    cache: dict = field(default_factory=dict)
    user_message: str = ""
    memory_cache: dict = field(default_factory=dict)
    history_writer: object = field(default=None, repr=False, compare=False)
