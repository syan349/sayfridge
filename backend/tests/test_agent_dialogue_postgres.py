"""HTTP/SSE mutation, replay and recovery invariants on disposable PostgreSQL."""
import asyncio
from uuid import uuid4

import pytest
from langchain_core.messages import AIMessage

from app.agents import continuation
from app.agents.continuation import Continuation, ContinuationAnswer
from auth_test_support import exercise
from inventory_test_support import inventory_context
from agent_dialogue_support import Dialogue
from agent_image_support import image_input
from test_agent_workflow import ScriptModel, call, intake
from test_agent_api_postgres import parse_events

pytestmark = [pytest.mark.postgres, pytest.mark.ci]


def replay_intent(item_id):
    return AIMessage(content="", tool_calls=[{"id": "replay", "type": "tool_call", "name": "record_turn_intent",
        "args": {"kind": "REPLAY", "replay_item_ids": [item_id]}}])


def test_model_supplied_batch_id_cannot_bypass_real_target_ambiguity(inventory_context):
    from app.services.agent_actions import prepare_action, PreparationError
    from app.schemas.agent_actions import ActionDraft
    from app.agents.memory import MemoryService
    from langgraph.store.memory import InMemoryStore
    from inventory_test_support import seed_inventory, seed_space
    c = inventory_context
    first = seed_inventory(c)
    garage = seed_space(c[0], c[1].id, name="Garage")
    second = seed_inventory(c, storage_space_id=garage.id)
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        draft = ActionDraft(item_key="rice", original_text="I used half the rice", action="CONSUME", item_query="Rice",
            inventory_item_id=first.id, storage_space_id=c[4].id, quantity_kind="FRACTION", quantity_value="1/2")
        async with sessions() as session:
            with pytest.raises(PreparationError) as exc:
                await prepare_action(session, c[1].id, draft, memory,
                    target_context={"source_texts": ["I used half the rice"], "item_query": "Rice"})
            assert exc.value.code == "TARGET_REQUIRED" and exc.value.details["total"] == 2
            assert {i["id"] for i in exc.value.details["candidates"]} == {str(first.id), str(second.id)}
            preview = await prepare_action(session, c[1].id, draft, memory,
                target_context={"source_texts": ["I used half the rice", "Kitchen batch"], "item_query": "Rice"})
            assert preview["draft"]["inventory_item_id"] == str(first.id) and preview["after"]["amount"] == "1.250"
    asyncio.run(exercise(c[0], scenario))


def test_request_results_are_stable_new_id_supplement_replays_and_again_is_new(inventory_context, monkeypatch):
    c = inventory_context
    async def scenario(client, sessions):
        action = {"item_key": "tofu", "original_text": "Add tofu", "action": "CREATE_STOCK",
                  "item_definition_id": str(c[5].id), "storage_space_id": str(c[4].id), "quantity_value": "3"}
        revised = {**action, "quantity_unit": "盒"}
        model = ScriptModel([call([action]), call([revised]), call([revised])], intents=[intake([action])])
        dialogue = Dialogue(client, c, sessions, model, monkeypatch)
        async def route(model, items, message, **kwargs):
            return Continuation(mode="CONTINUE", responses=[ContinuationAnswer(item_id=items[0]["item_id"],
                decision="answer", message=message, evidence=message)])
        monkeypatch.setattr(continuation, "interpret_continuation", route)
        original_request = str(uuid4())
        waiting = await dialogue.chat("Add tofu", request_id=original_request)
        saved_question = waiting["items"][0]["display"]["question"]
        assert waiting["items"][0]["display"]["missing_fields"] == ["quantity_unit"]
        state = await dialogue.chat("盒")
        assert state["items"][0]["status"] == "SUCCEEDED"
        old_id, old_proposal = state["items"][0]["item_id"], state["items"][0]["proposal_id"]
        assert await dialogue.counts() == (1, 0, 1)
        replay = await dialogue.chat("Add tofu", request_id=original_request)
        assert replay["items"][0]["status"] == "NEEDS_INPUT"
        assert replay["items"][0]["display"]["question"] == saved_question
        assert replay["items"][0]["proposal_id"] == waiting["items"][0]["proposal_id"]
        assert (await dialogue.state())["items"][0]["status"] == "SUCCEEDED"
        model.intents = iter([replay_intent(old_id), intake([revised])])
        repeated = await dialogue.chat("刚才是盒，我只是重复补答。")
        assert repeated["items"][0]["item_id"] == old_id and repeated["items"][0]["proposal_id"] == old_proposal
        assert await dialogue.counts() == (1, 0, 1)
        new = await dialogue.chat("又买了3盒豆腐。")
        assert new["items"][0]["status"] == "SUCCEEDED" and new["items"][0]["item_id"] != old_id
        assert await dialogue.counts() == (2, 0, 2)
    asyncio.run(exercise(c[0], scenario))


def test_unknown_commit_retries_original_receipt_with_new_chat_request(inventory_context, monkeypatch):
    from app.agents import workflow
    actual_execute = workflow.execute_action
    c = inventory_context
    calls = []
    async def execute(*args, **kwargs):
        result = await actual_execute(*args, **kwargs)
        calls.append(str(args[4]))
        if len(calls) == 1:
            raise ConnectionError("Connection lost after commit")
        assert result["replayed"] is True
        return result
    monkeypatch.setattr(workflow, "execute_action", execute)
    async def route(model, items, message, **kwargs):
        assert items[0]["error"]["code"] == "EXECUTION_UNCERTAIN"
        return Continuation(mode="CONTINUE", responses=[ContinuationAnswer(item_id=items[0]["item_id"],
            decision="retry", evidence=message)])
    monkeypatch.setattr(continuation, "interpret_continuation", route)
    async def scenario(client, sessions):
        action = {"item_key": "rice", "original_text": "Add 2 kg rice", "action": "CREATE_STOCK",
            "storage_space_id": str(c[4].id), "item_definition_id": str(c[5].id), "quantity_value": "2", "quantity_unit": "kg"}
        dialogue = Dialogue(client, c, sessions, ScriptModel([call([action])], intents=[intake([action])]), monkeypatch)
        first = await dialogue.chat("Add 2 kg rice")
        item = first["items"][0]
        assert item["error"]["code"] == "EXECUTION_UNCERTAIN" and item["status"] == "NEEDS_CONFIRMATION"
        assert await dialogue.counts() == (1, 0, 1)
        saved = await dialogue.chat("Retry that same save")
        assert saved["items"][0]["proposal_id"] == item["proposal_id"] and saved["items"][0]["status"] == "SUCCEEDED"
        assert calls == [item["proposal_id"], item["proposal_id"]]
        assert await dialogue.counts() == (1, 0, 1)
    asyncio.run(exercise(c[0], scenario))


def test_chat_image_answer_keeps_original_facts_and_invalidates_old_confirmation(inventory_context, monkeypatch):
    c = inventory_context
    async def scenario(client, sessions):
        photo = image_input("2 boxes tofu, 500 g each")
        supplement = image_input("Actually 3 boxes tofu, 500 g each")
        action = {"item_key": "tofu", "original_text": "2 boxes tofu", "action": "CREATE_STOCK", "item_query": "tofu",
                  "item_definition_id": str(c[5].id), "storage_space_id": str(c[4].id),
                  "quantity_value": "2", "quantity_unit": "盒", "package_description": "500g each",
                  "source_image_ids": [str(photo.image_id)]}
        edit = {"item_key": "tofu", "original_text": "3 boxes tofu", "action": "CREATE_STOCK",
                "quantity_value": "3", "quantity_unit": None, "package_description": None,
                "source_image_ids": [str(supplement.image_id)]}
        model = ScriptModel([call([action]), call([edit])], intents=[intake([action])])
        dialogue = Dialogue(client, c, sessions, model, monkeypatch)
        async def route(model, items, message, **kwargs):
            assert kwargs["images"][0].image_id == supplement.image_id
            return Continuation(mode="CONTINUE", responses=[ContinuationAnswer(item_id=items[0]["item_id"],
                decision="answer", evidence="", image_ids=[str(supplement.image_id)])])
        monkeypatch.setattr(continuation, "interpret_continuation", route)
        first = await dialogue.chat("Add these", [photo])
        old = first["items"][0]
        assert old["status"] == "NEEDS_CONFIRMATION" and await dialogue.counts() == (0, 0, 0)
        revised = await dialogue.chat(images=[supplement])
        item = revised["items"][0]
        assert item["item_id"] == old["item_id"] and item["proposal_id"] != old["proposal_id"]
        assert item["display"]["quantity_value"] == "3" and item["display"]["quantity_unit"] == "盒"
        assert item["display"]["package_description"] == "500g each"
        assert set(item["display"]["source_image_ids"]) == {str(photo.image_id), str(supplement.image_id)}
        current = await dialogue.state()
        body = {"conversation_id": dialogue.conversation_id, "request_id": str(uuid4()),
                "interrupt_id": current["interrupt_id"],
                "responses": [{"item_id": item["item_id"], "proposal_id": old["proposal_id"], "decision": "confirm"}]}
        response = await client.post("/api/v1/agent/resume", json=body, headers=c[6])
        assert response.status_code == 409 and response.json()["detail"]["code"] == "STALE_PROPOSAL"
        assert await dialogue.counts() == (0, 0, 0)
        body["responses"][0]["proposal_id"] = item["proposal_id"]
        response = await client.post("/api/v1/agent/resume", json=body, headers=c[6])
        events = parse_events(response)
        assert events[-1]["data"]["items"][0]["status"] == "SUCCEEDED"
        assert events[-1]["data"]["items"][0]["result"]["inventory"]["confirmed_current_amount"] == "3.000"
        assert await dialogue.counts() == (1, 0, 1)
        events = parse_events(await client.post("/api/v1/agent/resume", json=body, headers=c[6]))
        assert events[-1]["data"]["items"][0]["status"] == "SUCCEEDED"
        assert await dialogue.counts() == (1, 0, 1)
    asyncio.run(exercise(c[0], scenario))
