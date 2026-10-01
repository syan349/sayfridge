"""Exercise the authenticated HTTP/SSE entry with isolated Agent resources."""
import os
from types import SimpleNamespace
from uuid import uuid4

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore
from sqlalchemy import select, func

from app.api.routes import agent as api
from app.agents import locking, tools as agent_tools
from app.agents.workflow import build_agent_graph, public_item
from app.db.models import InventoryItem, InventoryOperation, AgentInventoryAction
from test_agent_api_postgres import parse_events


class Dialogue:
    def __init__(self, client, context, sessions, model, monkeypatch, *, saver=None):
        self.client, self.context, self.sessions = client, context, sessions
        self.conversation_id = str(uuid4())
        self.graph = build_agent_graph(model, checkpointer=saver or InMemorySaver(),
                                       store=InMemoryStore(), session_factory=sessions)
        url = context[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
        monkeypatch.setattr(locking, "get_agent_persistence_settings", lambda: SimpleNamespace(psycopg_url=lambda: url))
        monkeypatch.setattr(api, "get_agent_persistence_settings", lambda: SimpleNamespace(workflow_step_limit=128))
        monkeypatch.setattr(agent_tools, "AsyncSessionFactory", sessions)

        async def resources():
            return SimpleNamespace(graph=self.graph)
        monkeypatch.setattr(api, "get_agent_resources", resources)

    async def chat(self, message="", images=(), *, request_id=None):
        body = {"conversation_id": self.conversation_id, "request_id": request_id or str(uuid4()),
                "message": message, "as_of": "2026-10-01",
                "images": [i.model_dump(mode="json") for i in images]}
        response = await self.client.post("/api/v1/agent/chat", json=body, headers=self.context[6])
        assert response.status_code == 200, response.status_code
        events = parse_events(response)
        if any(e["type"] == "error" for e in events):
            from collections import Counter
            snapshot = await self.graph.aget_state(api._config(self.context[1].id, self.conversation_id))
            messages = snapshot.values.get("messages", [])
            print({"diagnostic": {"messages": len(messages),
                "tool_calls": dict(Counter(c["name"] for m in messages for c in getattr(m, "tool_calls", []))),
                "next": snapshot.next, "compaction": snapshot.values.get("context_compaction"),
                "errors": [(t.name, str(t.error)[:300]) for t in snapshot.tasks if t.error],
                "items": describe({"items": [public_item(i)
                                             for i in snapshot.values.get('items', [])]})}})
        assert not any(e["type"] == "error" for e in events), [e for e in events if e["type"] == "error"]
        assert events[-1]["type"] == "done", [e["type"] for e in events]
        self.events, self.body = events, body
        if os.getenv("AGENT_LIVE_MODEL") == "1":
            snapshot = await self.graph.aget_state(api._config(self.context[1].id, self.conversation_id))
            intent = snapshot.values.get("turn_intent", {})
            print({"dialogue_step": message or "[image]", "items": [{"key": i["item_key"], "status": i["status"],
                "error": (i.get("error") or {}).get("code"), "message": (i.get("error") or {}).get("message"),
                "quantity": i.get("display", {}).get("quantity_value"), "unit": i.get("display", {}).get("quantity_unit"),
                "issue": i.get("display", {}).get("quantity_issue"), "question": i.get("display", {}).get("question")}
                for i in events[-1]["data"]["items"]],
                "intent": {"kind": intent.get("kind"), "overflow": intent.get("exceeds_item_limit"), "extracted": len(intent.get("items", []))}})
        return events[-1]["data"]

    async def state(self):
        response = await self.client.get(f"/api/v1/agent/conversations/{self.conversation_id}/state", headers=self.context[6])
        assert response.status_code == 200
        return response.json()

    async def counts(self):
        async with self.sessions() as session:
            return tuple([await session.scalar(select(func.count()).select_from(table))
                          for table in (InventoryItem, InventoryOperation, AgentInventoryAction)])


def receipt_image(name):
    import base64
    from pathlib import Path
    from app.schemas.agent_media import AgentImage
    raw = (Path(__file__).parent / "receipts" / name).read_bytes()
    return AgentImage(image_id=uuid4(), mime_type="image/jpeg", data_base64=base64.b64encode(raw).decode("ascii"))


async def seed_catalog(context, sessions):
    from app.core.category_catalog import CATEGORIES
    from app.db.models import ItemCategory, StorageSpace
    from app.core.catalog import normalize_catalog_name
    async with sessions() as session:
        existing = set(await session.scalars(select(ItemCategory.normalized_name)))
        for row in CATEGORIES:
            if normalize_catalog_name(row["name"]) not in existing:
                session.add(ItemCategory(name=row["name"], normalized_name=row["normalized_name"],
                                         sort_order=row["sort_order"], status="ACTIVE"))
        space = await session.get(StorageSpace, context[4].id)
        space.is_default = True
        await session.commit()


def describe(state):
    return [{"key": i["item_key"], "status": i["status"], "display": i.get("display"),
             "quantity": (i.get("preview") or {}).get("draft", {}).get("quantity_value"),
             "unit": (i.get("preview") or {}).get("draft", {}).get("quantity_unit"),
             "error": (i.get("error") or {}).get("code")} for i in state["items"]]
