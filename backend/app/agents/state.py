"""Graph state and trusted run context for the inventory Agent."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Annotated, TypedDict
from uuid import UUID

from langchain_core.messages import AnyMessage
from langgraph.graph.message import add_messages
from langgraph.channels.delta import DeltaChannel


def merge_records(previous, writes):
    """Batch-invariant, replay-safe patches; never mutate a prior snapshot."""
    result = dict(previous or {})
    for patch in writes:
        result.update(patch)
    return result


def merge_images(previous, writes):
    result = {message.id: message for message in previous or []}
    for patch in writes:
        for message in patch:
            if not message.id:
                raise ValueError("Archived images require a stable message ID")
            result[message.id] = message
    return list(result.values())


class AgentState(TypedDict):
    messages: Annotated[list[AnyMessage], add_messages]
    turn_id: str
    as_of: str | None
    request_fingerprint: str
    requests: Annotated[dict, DeltaChannel(merge_records, snapshot_frequency=50)]
    items: list[dict]
    context_summary: dict
    pending_input: list[dict]
    execution_results: list[dict]
    route: str
    resume_requests: Annotated[dict, DeltaChannel(merge_records, snapshot_frequency=50)]
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
    chat_requests: Annotated[dict, DeltaChannel(merge_records, snapshot_frequency=50)]
    image_messages: Annotated[list, DeltaChannel(merge_images, snapshot_frequency=50)]
    completed_items: list[dict]
    unresolved_reply: dict | None
    revision_scope: list[str] | None
    inventory_reads: dict
    inventory_query: dict | None


def agent_state_schema(snapshot_frequency=50):
    """Frequency 1 is a delta-readable fallback, NOT a return to old code."""
    if snapshot_frequency < 1:
        raise ValueError("Snapshot frequency must be positive")
    if snapshot_frequency == 50:
        return AgentState
    return type("ConfiguredAgentState", (AgentState,), {"__annotations__": {
        **{key: Annotated[dict, DeltaChannel(merge_records, snapshot_frequency=snapshot_frequency)]
           for key in ("requests", "chat_requests", "resume_requests")},
        "image_messages": Annotated[list, DeltaChannel(merge_images, snapshot_frequency=snapshot_frequency)],
    }})


def history_state_reader(checkpointer):
    """Schema-only reader: graph state hydration, without models or executions.

    get_state at an explicit checkpoint reads committed values and does not run
    nodes or incorporate pending node writes. Never invoke this reader graph.
    """
    from langgraph.graph import StateGraph, START, END
    builder = StateGraph(AgentState)
    builder.add_node("history_read_only", lambda _: {})
    builder.add_edge(START, "history_read_only")
    builder.add_edge("history_read_only", END)
    return builder.compile(checkpointer=checkpointer)


@dataclass(frozen=True, slots=True)
class AgentContext:
    """Server-owned values that must never be supplied by the model."""

    user_id: UUID
    as_of: date | None
    conversation_id: UUID | None = None
    cache: dict = field(default_factory=dict)
    user_message: str = ""
    memory_cache: dict = field(default_factory=dict)
    inventory_cards: bool = False
    history_writer: object = field(default=None, repr=False, compare=False)
