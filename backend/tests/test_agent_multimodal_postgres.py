"""Real HTTP, checkpoint and stock writes for image review/recovery."""
import asyncio
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
from langgraph.store.memory import InMemoryStore
from langgraph.types import Command
from psycopg import AsyncConnection
from psycopg.rows import dict_row
from sqlalchemy import select, func

from app.agents import locking, workflow
from app.api.routes import agent as api
from app.db.models import InventoryItem, AgentInventoryAction
from app.agents.memory import MemoryService
from app.agents.state import AgentContext
from app.schemas.agent_actions import ActionDraft
from app.services.agent_actions import prepare_action, execute_action, PreparationError
from inventory_test_support import inventory_context
from auth_test_support import exercise
from test_agent_workflow import ScriptModel, call, intake
from test_agent_api_postgres import parse_events
from agent_image_support import image_input

pytestmark = pytest.mark.postgres


def test_image_http_review_supplement_restart_and_duplicate_submission(inventory_context, monkeypatch):
    c = inventory_context
    conninfo = c[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
    monkeypatch.setattr(locking, "get_agent_persistence_settings", lambda: SimpleNamespace(psycopg_url=lambda: conninfo))
    monkeypatch.setattr(api, "get_agent_persistence_settings", lambda: SimpleNamespace(workflow_step_limit=128))
    async def scenario(client, sessions):
        photo, supplement = image_input(), image_input("MILK 3 bottles")
        draft = {"item_key": "milk", "original_text": "MILK 2 bottles", "action": "CREATE_STOCK",
            "quantity_value": "2", "quantity_unit": "bottle", "storage_space_id": str(c[4].id),
            "item_definition_id": str(c[5].id), "source_image_ids": [str(photo.image_id)],
            "package_description": "500ml each"}
        async with await AsyncConnection.connect(conninfo, options=f"-csearch_path={c[0][1]}",
                autocommit=True, row_factory=dict_row, prepare_threshold=0) as conn:
            saver = AsyncPostgresSaver(conn)
            await saver.setup()
            store = InMemoryStore()
            model = ScriptModel([call([draft]), call([{**draft, "quantity_value": "3", "source_image_ids": [str(supplement.image_id)]}])], intents=[intake([draft])])
            def build():
                return workflow.build_agent_graph(model, checkpointer=saver, store=store, session_factory=sessions, tools=[])
            graph = build()
            async def resources():
                return SimpleNamespace(graph=graph)
            monkeypatch.setattr(api, "get_agent_resources", resources)
            cid, rid = str(uuid4()), str(uuid4())
            body = {"conversation_id": cid, "request_id": rid, "message": "Enter these",
                    "images": [photo.model_dump(mode="json")]}
            response = await client.post("/api/v1/agent/chat", json=body, headers=c[6])
            events = parse_events(response)
            assert not any(e["type"] == "error" for e in events), events
            item = events[-1]["data"]["items"][0]
            assert item["status"] == "NEEDS_CONFIRMATION"
            assert item["display"]["confirmation_reasons"] == ["IMAGE_REVIEW"]
            assert item["display"]["item_name"] == c[5].name
            assert photo.data_base64 not in response.text
            state_url = f"/api/v1/agent/conversations/{cid}/state"
            state = (await client.get(state_url, headers=c[6])).json()
            assert photo.data_base64 not in str(state)
            async with sessions() as session:
                assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 0
            replay = await client.post("/api/v1/agent/chat", json=body, headers=c[6])
            assert parse_events(replay)[-1]["data"]["items"][0]["proposal_id"] == item["proposal_id"]
            changed = {**body, "images": [supplement.model_dump(mode="json")]}
            assert (await client.post("/api/v1/agent/chat", json=changed, headers=c[6])).status_code == 409
            resume = {"conversation_id": cid, "request_id": str(uuid4()), "interrupt_id": state["interrupt_id"],
                      "responses": [{"item_id": item["item_id"], "proposal_id": item["proposal_id"],
                                     "decision": "edit", "images": [supplement.model_dump(mode="json")]}]}
            graph = build()  # restore original image bytes from real PostgreSQL checkpoints
            events = parse_events(await client.post("/api/v1/agent/resume", json=resume, headers=c[6]))
            assert not any(e["type"] == "error" for e in events), events
            assert events[-1]["data"]["items"][0]["proposal_id"] != item["proposal_id"]
            repeat = parse_events(await client.post("/api/v1/agent/resume", json=resume, headers=c[6]))
            assert repeat[-1]["status"] == "WAITING_INPUT"
            state = (await client.get(state_url, headers=c[6])).json()
            old = {"conversation_id": cid, "request_id": str(uuid4()), "interrupt_id": state["interrupt_id"],
                   "responses": [{"item_id": item["item_id"], "proposal_id": item["proposal_id"], "decision": "confirm"}]}
            assert (await client.post("/api/v1/agent/resume", json=old, headers=c[6])).status_code == 409
            old["responses"][0]["proposal_id"] = state["items"][0]["proposal_id"]
            graph = build()
            class SimulatedCrash(BaseException):
                pass
            original_execute = workflow.execute_action
            async def commit_then_crash(*args, **kwargs):
                await original_execute(*args, **kwargs)
                raise SimulatedCrash()
            monkeypatch.setattr(workflow, "execute_action", commit_then_crash)
            with pytest.raises(SimulatedCrash):
                await graph.ainvoke(Command(resume={state["interrupt_id"]: old}), api._config(c[1].id, cid),
                    context=AgentContext(c[1].id, None, UUID(cid)), durability="sync")
            monkeypatch.setattr(workflow, "execute_action", original_execute)
            graph = build()
            result = parse_events(await client.post("/api/v1/agent/resume", json=old, headers=c[6]))
            assert result[-1]["data"]["items"][0]["status"] == "SUCCEEDED", result
            assert result[-1]["data"]["items"][0]["result"]["replayed"]
            await client.post("/api/v1/agent/resume", json=old, headers=c[6])
            async with sessions() as session:
                assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 1
                row = await session.scalar(select(InventoryItem))
                assert str(row.confirmed_current_amount) == "3.000"
                receipt = await session.scalar(select(AgentInventoryAction))
                assert photo.data_base64 not in str(receipt.request_snapshot)
                assert supplement.data_base64 not in str(receipt.request_snapshot)
            from app.core.security import create_access_token
            from app.core.config import get_settings
            other = {"Authorization": "Bearer " + create_access_token(c[2].id, get_settings().jwt_secret_key, 15)}
            assert (await client.get(state_url, headers=other)).status_code == 404
            assert (await client.post("/api/v1/agent/resume", json=old, headers=other)).status_code == 409
            invalid = {"images": [{**photo.model_dump(mode="json"), "data_base64": "SECRET_NOT_AN_IMAGE"}]}
            response = await client.post("/api/v1/agent/chat", json=invalid, headers=c[6])
            assert response.status_code == 422 and "SECRET_NOT_AN_IMAGE" not in response.text
    asyncio.run(exercise(c[0], scenario))


def test_image_execution_requires_review_even_if_preview_flag_is_wrong(inventory_context):
    c = inventory_context
    async def scenario(client, sessions):
        draft = ActionDraft(item_key="milk", original_text="milk", action="CREATE_STOCK", quantity_value="2",
            quantity_unit="bottle", storage_space_id=c[4].id, item_definition_id=c[5].id)
        memory = MemoryService(InMemoryStore(), c[1].id)
        policy = {"create_only": True, "requires_review": True, "source_image_ids": [str(uuid4())]}
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, draft, memory, image_policy=policy)
        preview["requires_confirmation"] = False
        async with sessions() as session:
            with pytest.raises(PreparationError, match="Review"):
                await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), preview, memory, image_policy=policy)
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 0
    asyncio.run(exercise(c[0], scenario))
