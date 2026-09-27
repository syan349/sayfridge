import asyncio
from uuid import uuid4

import pytest
from langchain_core.messages import AIMessage
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore
from langgraph.types import Command

from app.agents import workflow
from app.agents.messages import human_message, image_catalog
from app.agents.state import AgentContext
from app.schemas.agent_actions import ActionDraft
from app.services.agent_actions import validate_image_policy
from agent_image_support import image_input
from test_agent_workflow import ScriptModel, call, fake_session, setup_services


def creation(**kwargs):
    return {"item_key": "milk", "original_text": "MILK 2 bottles", "item_query": "milk",
            "action": "CREATE_STOCK", "quantity_value": "2", "quantity_unit": "bottle", **kwargs}


def test_cross_turn_image_review_supplement_cancel_and_replay(monkeypatch):
    setup_services(monkeypatch)
    writes = []
    async def prepare(session, user, draft, memory, as_of, *, image_policy=None):
        validate_image_policy(draft, image_policy)
        return {"draft": draft.model_dump(mode="json"), "requires_confirmation": image_policy["requires_review"],
                "confirmation_reasons": ["IMAGE_REVIEW"], "memory_snapshots": [], "image_policy": image_policy}
    async def execute(session, user, conversation, turn, proposal, preview, memory, *, approved=False, image_policy=None):
        validate_image_policy(ActionDraft.model_validate(preview["draft"]), image_policy, approved=approved)
        writes.append(preview["draft"]["quantity_value"])
        return {"created": True}
    monkeypatch.setattr(workflow, "prepare_action", prepare)
    monkeypatch.setattr(workflow, "execute_action", execute)

    async def scenario():
        initial_image, label = image_input(), image_input("3 bottles")
        model = ScriptModel([AIMessage(content="Do you want to enter these?"), call([creation()]),
                             call([creation(quantity_value="3", source_image_ids=[str(label.image_id)])])])
        saver, store = InMemorySaver(), InMemoryStore()
        def build():
            return workflow.build_agent_graph(model, checkpointer=saver, store=store, session_factory=fake_session, tools=[])
        graph, turn = build(), str(uuid4())
        config = {"configurable": {"thread_id": "images"}, "recursion_limit": 60}
        context = AgentContext(uuid4(), None, uuid4())
        state = await graph.ainvoke({"messages": [human_message("", [initial_image], turn)], "turn_id": turn,
            "turn_has_images": True, "image_task_active": True, "items": [], "request_fingerprint": "first"}, config, context=context)
        assert not state["items"] and not writes
        assert state["image_task_active"] is False
        turn = str(uuid4())
        state = await graph.ainvoke({"messages": [human_message("Enter those", [], turn)], "turn_id": turn,
            "turn_has_images": False, "items": [], "request_fingerprint": "second"}, config, context=context)
        assert state["items"][0]["status"] == "NEEDS_CONFIRMATION" and not writes
        assert state["items"][0]["image_policy"]["source_image_ids"] == [str(initial_image.image_id)]
        before = state["items"][0]["proposal_id"]
        snap = await graph.aget_state(config)
        pending = snap.values["items"][0]
        response = {"conversation_id": str(context.conversation_id), "request_id": str(uuid4()),
            "interrupt_id": snap.tasks[0].interrupts[0].id, "responses": [{"item_id": pending["item_id"],
            "proposal_id": before, "decision": "edit", "images": [label.model_dump(mode="json")]}]}
        graph = build()
        state = await graph.ainvoke(Command(resume=response), config, context=context)
        pending = state["items"][0]
        assert pending["proposal_id"] != before and pending["status"] == "NEEDS_CONFIRMATION"
        assert len(image_catalog(state["messages"])) == 2 and not writes
        snap = await graph.aget_state(config)
        response.update(request_id=str(uuid4()), interrupt_id=snap.tasks[0].interrupts[0].id,
            responses=[{"item_id": pending["item_id"], "proposal_id": pending["proposal_id"], "decision": "confirm"}])
        state = await build().ainvoke(Command(resume=response), config, context=context)
        assert writes == ["3"] and state["items"][0]["status"] == "SUCCEEDED"
        assert state["image_task_active"] is False
    asyncio.run(scenario())


def test_image_policy_cannot_be_bypassed_by_omitting_references():
    image = image_input()
    state = {"messages": [human_message("enter", [image], "1")], "turn_has_images": True}
    with pytest.raises(ValueError, match="only create"):
        validate_image_policy(ActionDraft(**creation(action="CONSUME")), workflow.image_policy(state, ActionDraft(**creation(action="CONSUME"))))
    draft = ActionDraft(**creation())
    policy = workflow.image_policy(state, draft)
    with pytest.raises(ValueError, match="Review"):
        validate_image_policy(draft, policy, approved=False)
    with pytest.raises(ValueError, match="Unknown"):
        workflow.image_policy(state, ActionDraft(**creation(source_image_ids=[uuid4()])))
    state["turn_has_images"] = False
    assert workflow.image_policy(state, draft)["requires_review"]
    assert not workflow.image_policy(state, ActionDraft(**creation(action="CONSUME")))["create_only"]


def test_overflow_never_prepares_or_executes_partial_items(monkeypatch):
    setup_services(monkeypatch)
    async def forbidden(*args, **kwargs):
        raise AssertionError("Overflow executed an action")
    monkeypatch.setattr(workflow, "prepare_action", forbidden)
    response = AIMessage(content="", tool_calls=[{"id": "overflow", "name": "propose_inventory_actions",
        "args": {"actions": [], "exceeds_item_limit": True}, "type": "tool_call"}])
    async def scenario():
        graph = workflow.build_agent_graph(ScriptModel([response, AIMessage(content="Please split the receipt")]),
            checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[])
        state = await graph.ainvoke({"messages": [human_message("enter", [image_input()], "1")],
            "turn_id": str(uuid4()), "request_fingerprint": "overflow", "items": []},
            {"configurable": {"thread_id": "overflow"}}, context=AgentContext(uuid4(), None))
        assert not state["items"] and state["route"] == "END"
    asyncio.run(scenario())


def test_supplement_without_new_proposal_cannot_keep_old_text_permissions(monkeypatch):
    setup_services(monkeypatch)
    async def prepare(session, user, draft, memory, as_of, *, image_policy=None):
        validate_image_policy(draft, image_policy)
        return {"draft": draft.model_dump(mode="json"), "requires_confirmation": True, "memory_snapshots": []}
    async def forbidden(*args, **kwargs):
        raise AssertionError("Image supplement must not authorize consumption")
    monkeypatch.setattr(workflow, "prepare_action", prepare)
    monkeypatch.setattr(workflow, "execute_action", forbidden)
    async def scenario():
        graph = workflow.build_agent_graph(ScriptModel([call([creation(action="CONSUME")]), AIMessage(content="Photo received")]),
            checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[])
        config = {"configurable": {"thread_id": "supplement-policy"}, "recursion_limit": 60}
        context = AgentContext(uuid4(), None, uuid4())
        await graph.ainvoke({"messages": [human_message("consume some", [], "1")], "turn_id": str(uuid4()),
            "request_fingerprint": "text", "items": []}, config, context=context)
        snap = await graph.aget_state(config)
        item = snap.values["items"][0]
        response = {"conversation_id": str(context.conversation_id), "request_id": str(uuid4()),
            "interrupt_id": snap.tasks[0].interrupts[0].id, "responses": [{"item_id": item["item_id"],
            "proposal_id": item["proposal_id"], "decision": "edit", "images": [image_input().model_dump(mode="json")]}]}
        state = await graph.ainvoke(Command(resume=response), config, context=context)
        assert state["items"][0]["status"] == "NEEDS_INPUT"
        assert state["items"][0]["error"]["code"] == "IMAGE_ACTION_NOT_SUPPORTED"
    asyncio.run(scenario())
