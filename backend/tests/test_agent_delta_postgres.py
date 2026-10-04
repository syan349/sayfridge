"""Real PostgreSQL storage benchmark and legacy/delta checkpoint recovery."""
import asyncio
import json
import statistics
import time
from typing import TypedDict
from uuid import uuid4

import pytest
from langchain_core.messages import HumanMessage
from app.agents.persistence import MeasuredPostgresSaver as AsyncPostgresSaver
from langgraph.graph import StateGraph, START, END
from psycopg import AsyncConnection
from psycopg.rows import dict_row

from app.agents.state import agent_state_schema, history_state_reader
from app.agents.messages import human_message
from app.services.conversation_history import recover_messages
from agent_image_support import image_input
from inventory_test_support import inventory_context, seed_inventory
from auth_test_support import exercise

pytestmark = [pytest.mark.postgres, pytest.mark.ci]
CHANNELS = ("requests", "chat_requests", "resume_requests", "image_messages")


class LegacyState(TypedDict):
    requests: dict
    chat_requests: dict
    resume_requests: dict
    image_messages: list
    messages: list
    turn_id: str


def graph_for(schema, saver):
    graph = StateGraph(schema)
    graph.add_node("step", lambda _: {})
    graph.add_edge(START, "step")
    graph.add_edge("step", END)
    return graph.compile(checkpointer=saver)


def connection_args(database):
    return dict(conninfo=database[0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1),
                options=f"-csearch_path={database[1]}", autocommit=True, prepare_threshold=0, row_factory=dict_row)


async def sizes(conn, thread):
    output = {}
    for table in ("checkpoint_blobs", "checkpoint_writes"):
        row = await (await conn.execute(f"SELECT coalesce(sum(octet_length(blob)),0) AS total, "
            f"coalesce(sum(octet_length(blob)) FILTER (WHERE channel = ANY(%s)),0) AS target "
            f"FROM {table} WHERE thread_id=%s", (list(CHANNELS), thread))).fetchone()
        output[table] = dict(row)
    row = await (await conn.execute("SELECT count(*) AS records, coalesce(sum(octet_length(checkpoint::text) + "
        "octet_length(metadata::text)),0) AS bytes FROM checkpoints WHERE thread_id=%s", (thread,))).fetchone()
    output["checkpoints"] = dict(row)
    output["target_bytes"] = sum(output[t]["target"] for t in ("checkpoint_blobs", "checkpoint_writes"))
    output["all_serialized_bytes"] = sum(output[t]["total"] for t in ("checkpoint_blobs", "checkpoint_writes")) + row["bytes"]
    return output


def test_200_turns_storage_saving_and_rehydration_latency(database):
    async def run():
        async with await AsyncConnection.connect(**connection_args(database)) as conn:
            saver = AsyncPostgresSaver(conn)
            await saver.setup()
            picture = human_message("one photo", [image_input()], "picture-message")
            results = {}
            final = {}
            for mode, schema in (("full", LegacyState), ("delta", agent_state_schema())):
                thread = mode + str(uuid4())
                cfg = {"configurable": {"thread_id": thread}}
                graph = graph_for(schema, saver)
                accumulated = {"requests": {}, "chat_requests": {}, "resume_requests": {}, "image_messages": [picture]}
                for n in range(200):
                    key = str(n)
                    patch = {"requests": {key: {"fingerprint": key, "state": {"status": "COMPLETED", "items": []},
                        "answer": "Synthetic stock answer and details. " * 35}},
                        "chat_requests": {key: key}, "resume_requests": {key: "resume-" + key}}
                    for k, v in patch.items():
                        accumulated[k].update(v)
                    if n == 0:
                        patch["image_messages"] = [picture]
                    await graph.ainvoke(accumulated if mode == "full" else patch, cfg, durability="sync")
                    if n in (48, 49, 50):
                        fresh = graph_for(schema, AsyncPostgresSaver(conn))
                        assert {k: v for k, v in (await fresh.aget_state(cfg)).values.items() if k in CHANNELS} == accumulated
                fresh = graph_for(schema, AsyncPostgresSaver(conn))
                await fresh.aget_state(cfg)  # warm query/reconstruction path
                samples = []
                for _ in range(9):
                    start = time.perf_counter()
                    loaded = (await fresh.aget_state(cfg)).values
                    samples.append((time.perf_counter() - start) * 1000)
                assert {k: loaded[k] for k in CHANNELS} == accumulated
                final[mode] = {k: loaded[k] for k in CHANNELS}
                results[mode] = {**await sizes(conn, thread), "median_read_ms": statistics.median(samples)}
            assert final["full"] == final["delta"]
            reduction = 1 - results["delta"]["target_bytes"] / results["full"]["target_bytes"]
            assert reduction >= .70, results
            assert results["delta"]["median_read_ms"] <= results["full"]["median_read_ms"] * 1.25 + 100, results
            print("DELTA_POSTGRES_EVIDENCE " + json.dumps({"turns": 200, "reduction": reduction, **results}))
    asyncio.run(run())


def test_legacy_upgrade_snapshot_boundaries_history_and_frequency_one_fallback(database):
    async def run():
        args = connection_args(database)
        user, cid = uuid4(), uuid4()
        cfg = {"configurable": {"thread_id": f"user:{user}:conversation:{cid}"}}
        old_request = str(uuid4())
        async with await AsyncConnection.connect(**args) as conn:
            saver = AsyncPostgresSaver(conn)
            await saver.setup()
            graph = graph_for(LegacyState, saver)
            await graph.ainvoke({"requests": {old_request: {"answer": "Original old reply"}},
                "chat_requests": {old_request: "old fingerprint"}, "resume_requests": {}, "image_messages": [],
                "messages": [HumanMessage(id=old_request, content="Original old words")]}, cfg, durability="sync")
        # Fresh connection, saver, and graph simulate process replacement.
        async with await AsyncConnection.connect(**args) as conn:
            saver = AsyncPostgresSaver(conn)
            graph = graph_for(agent_state_schema(), saver)
            for n in range(51):
                rid = str(uuid4())
                await graph.ainvoke({"requests": {rid: {"answer": f"Observed reply {n}"}},
                    "chat_requests": {rid: str(n)}, "resume_requests": {rid: str(n)}}, cfg, durability="sync")
            state = (await graph.aget_state(cfg)).values
            assert len(state["requests"]) == 52 and state["requests"][old_request]["answer"] == "Original old reply"
            records = await recover_messages(saver, user, cid)
            assert len(records) == 53  # 52 observed answers and one user message
            assert records == await recover_messages(saver, user, cid)
            assert await recover_messages(saver, uuid4(), cid) == {}
        async with await AsyncConnection.connect(**args) as conn:
            saver = AsyncPostgresSaver(conn)
            fallback = graph_for(agent_state_schema(1), saver)
            assert (await fallback.aget_state(cfg)).values == state
            await fallback.ainvoke({"requests": {old_request: {"answer": "Updated reply"}}}, cfg, durability="sync")
            latest = await saver.aget_tuple(cfg)
            from langgraph.checkpoint.serde.types import _DeltaSnapshot
            assert isinstance(latest.checkpoint["channel_values"]["requests"], _DeltaSnapshot)
            hydrated = (await history_state_reader(saver).aget_state(latest.config)).values
            assert hydrated["requests"][old_request]["answer"] == "Updated reply"
            assert len(hydrated["requests"]) == 52
    asyncio.run(run())


def test_real_legacy_pending_proposal_executes_once_after_delta_upgrade(inventory_context, monkeypatch):
    from typing import get_type_hints
    from app.agents import workflow
    from app.agents.state import AgentState
    from app.api.routes import agent as api
    from app.db.models import InventoryOperation, AgentInventoryAction
    from langgraph.store.memory import InMemoryStore
    from sqlalchemy import select, func
    from test_agent_workflow import ScriptModel, call, intake
    from test_agent_history_postgres import configure_api
    from test_agent_api_postgres import parse_events
    c = inventory_context
    item = seed_inventory(c)
    annotations = get_type_hints(AgentState, include_extras=True)
    annotations.update(requests=dict, chat_requests=dict, resume_requests=dict, image_messages=list)
    legacy_schema = TypedDict("PreDeltaAgentState", annotations)

    async def run(client, sessions):
        async with await AsyncConnection.connect(**connection_args(c[0])) as conn:
            saver = AsyncPostgresSaver(conn)
            await saver.setup()
            draft = {"item_key": "rice", "original_text": "Use 1 kg rice, ask me first", "action": "CONSUME",
                     "item_query": "Rice", "inventory_item_id": str(item.id), "quantity_value": "1", "quantity_unit": "kg",
                     "confirmation_requested": True}
            with monkeypatch.context() as legacy_patch:
                legacy_patch.setattr(workflow, "agent_state_schema", lambda _: legacy_schema)
                graph = workflow.build_agent_graph(ScriptModel([call([draft])], intents=[intake([draft])]),
                    checkpointer=saver, store=InMemoryStore(), session_factory=sessions, tools=[])
            configure_api(c, graph, monkeypatch)
            cid, rid = str(uuid4()), str(uuid4())
            events = parse_events(await client.post("/api/v1/agent/chat", headers=c[6],
                json={"conversation_id": cid, "request_id": rid, "message": "Use 1 kg rice, ask me first"}))
            assert events[-1]["type"] == "done", events[-1]
            state = events[-1]["data"]
            pending = state["items"][0]
            assert pending["status"] == "NEEDS_CONFIRMATION", state
            payload = {"conversation_id": cid, "request_id": str(uuid4()), "interrupt_id": state["interrupt_id"],
                "responses": [{"item_id": pending["item_id"], "proposal_id": pending["proposal_id"], "decision": "confirm"}]}
        async with await AsyncConnection.connect(**connection_args(c[0])) as conn:
            graph = workflow.build_agent_graph(ScriptModel([]), checkpointer=AsyncPostgresSaver(conn),
                store=InMemoryStore(), session_factory=sessions, tools=[])
            configure_api(c, graph, monkeypatch)
            first = parse_events(await client.post("/api/v1/agent/resume", headers=c[6], json=payload))
            repeated = parse_events(await client.post("/api/v1/agent/resume", headers=c[6], json=payload))
            assert first[-1]["type"] == "done", first[-1]
            assert first[-1] == repeated[-1]
            assert first[-1]["data"]["items"][0]["status"] == "SUCCEEDED"
            assert first[-1]["data"]["items"][0]["proposal_id"] == pending["proposal_id"]
            async with sessions() as session:
                assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 1
                assert await session.scalar(select(func.count()).select_from(AgentInventoryAction)) == 1
    asyncio.run(exercise(c[0], run))
