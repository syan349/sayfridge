"""First-time stock entry, durable questions, and atomic automatic associations."""
import asyncio
from types import SimpleNamespace
from uuid import uuid4

import pytest
from langchain_core.messages import AIMessage
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore
from sqlalchemy import delete, func, select

from app.agents import locking
from app.agents.memory import MemoryService
from app.agents.workflow import build_agent_graph
from app.api.routes import agent as api
from app.db.models import AgentInventoryAction, InventoryItem, ItemDefinition, StorageSpace
from app.schemas.agent_actions import ActionDraft
from app.services.agent_actions import prepare_action, execute_action, PreparationError
from auth_test_support import exercise
from inventory_test_support import inventory_context
from test_agent_api_postgres import parse_events
from test_agent_workflow import ScriptModel, call, intake

pytestmark = pytest.mark.postgres


@pytest.mark.ci
def test_empty_account_purchase_answer_write_and_replay(inventory_context, monkeypatch):
    c = inventory_context
    url = c[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
    monkeypatch.setattr(locking, "get_agent_persistence_settings", lambda: SimpleNamespace(psycopg_url=lambda: url))
    monkeypatch.setattr(api, "get_agent_persistence_settings", lambda: SimpleNamespace(workflow_step_limit=128))
    async def scenario(client, sessions):
        async with sessions() as session:
            await session.execute(delete(StorageSpace).where(StorageSpace.user_id == c[1].id))
            await session.commit()
        draft = {"item_key": "tomatoes", "original_text": "I just bought 2 kg of tomatoes", "item_query": "tomatoes",
            "action": "CREATE_STOCK", "quantity_value": "2", "quantity_unit": "kg",
            "new_definition": {"name": "Tomatoes", "category_id": str(c[3].id)}}
        filled = {**draft, "new_space": {"name": "fridge", "type": "FRIDGE"}, "new_space_source_text": "Put them in the fridge"}
        # Even a model that would narrate stale approval cannot override the receipt.
        graph = build_agent_graph(ScriptModel([call([draft]), call([filled]), AIMessage(content="This still needs your confirmation.")],
            intents=[intake([draft])]), checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=sessions, tools=[])
        async def resources():
            return SimpleNamespace(graph=graph)
        monkeypatch.setattr(api, "get_agent_resources", resources)
        body = {"message": draft["original_text"], "conversation_id": str(uuid4()), "request_id": str(uuid4())}
        events = parse_events(await client.post("/api/v1/agent/chat", json=body, headers=c[6]))
        assert not any(e["type"] == "error" for e in events), events
        assert events[-1]["status"] == "WAITING_INPUT"
        item = events[-1]["data"]["items"][0]
        question = item["display"]["question"]
        assert item["error"]["code"] == "SPACE_REQUIRED"
        assert question == "Where would you like to store Tomatoes?"
        assert [e["delta"] for e in events if e["type"] == "text_delta"] == [question]
        state = (await client.get(f"/api/v1/agent/conversations/{body['conversation_id']}/state", headers=c[6])).json()
        assert state["items"][0]["display"]["question"] == question
        replay = parse_events(await client.post("/api/v1/agent/chat", json=body, headers=c[6]))
        assert [e["delta"] for e in replay if e["type"] == "text_delta"] == [question]
        async with sessions() as session:
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 0
            assert await session.scalar(select(func.count()).select_from(StorageSpace).where(StorageSpace.user_id == c[1].id)) == 0
            assert await session.scalar(select(func.count()).select_from(ItemDefinition).where(ItemDefinition.owner_user_id == c[1].id)) == 0
        resume = {"conversation_id": body["conversation_id"], "request_id": str(uuid4()), "interrupt_id": state["interrupt_id"],
            "responses": [{"item_id": item["item_id"], "proposal_id": item["proposal_id"], "decision": "answer", "message": "Put them in the fridge"}]}
        events = parse_events(await client.post("/api/v1/agent/resume", json=resume, headers=c[6]))
        assert not any(e["type"] in {"error", "action_required"} for e in events), events
        item = events[-1]["data"]["items"][0]
        assert item["status"] == "SUCCEEDED"
        assert item["result"]["inventory"]["confirmed_current_amount"] == "2.000"
        assert [e["delta"] for e in events if e["type"] == "text_delta"] == [
            "Added 2 kg of Tomatoes to fridge.\nStock was saved, but its expiry date could not be estimated. Please add it later."]
        replay = parse_events(await client.post("/api/v1/agent/resume", json=resume, headers=c[6]))
        assert replay[-1]["data"]["items"][0]["status"] == "SUCCEEDED"
        async with sessions() as session:
            for model in (InventoryItem, AgentInventoryAction):
                assert await session.scalar(select(func.count()).select_from(model)) == 1
            assert await session.scalar(select(func.count()).select_from(StorageSpace).where(StorageSpace.user_id == c[1].id)) == 1
            assert await session.scalar(select(func.count()).select_from(ItemDefinition).where(ItemDefinition.owner_user_id == c[1].id)) == 1
    asyncio.run(exercise(c[0], scenario))


def test_new_definition_auto_and_existing_public_definition_reused(inventory_context):
    c = inventory_context
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        for name, expected_id in [("Tomatoes", None), (c[5].name, c[5].id)]:
            draft = ActionDraft(item_key=name, original_text=f"2 kg {name}", action="CREATE_STOCK", quantity_value="2", quantity_unit="kg",
                storage_space_id=c[4].id, new_definition={"name": name, "category_id": c[3].id})
            async with sessions() as session:
                preview = await prepare_action(session, c[1].id, draft, memory)
                assert not preview["requires_confirmation"] and not preview["confirmation_reasons"]
            async with sessions() as session:
                result = await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), preview, memory)
                if expected_id:
                    assert result["inventory"]["item_definition_id"] == str(expected_id)
        async with sessions() as session:
            assert await session.scalar(select(func.count()).select_from(ItemDefinition).where(ItemDefinition.owner_user_id == c[1].id)) == 1
    asyncio.run(exercise(c[0], scenario))


def test_ambiguity_has_no_side_effects_and_legacy_confirmation_remains(inventory_context):
    c = inventory_context
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        draft = ActionDraft(item_key="item", original_text="2 bags", action="CREATE_STOCK", quantity_value="2", quantity_unit="bag",
            storage_space_id=c[4].id, item_definition_id=c[5].id, clarification_question="Which product is this?")
        async with sessions() as session:
            with pytest.raises(PreparationError, match="Which product"):
                await prepare_action(session, c[1].id, draft, memory)
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 0
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, draft.model_copy(update={"clarification_question": None}), memory)
        preview.pop("creation_policy")
        preview["requires_confirmation"] = True
        preview["confirmation_reasons"] = ["NEW_ASSOCIATION"]
        async with sessions() as session:
            with pytest.raises(PreparationError, match="Confirm"):
                await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), preview, memory)
    asyncio.run(exercise(c[0], scenario))
