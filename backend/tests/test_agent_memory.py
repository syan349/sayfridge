import asyncio
from uuid import uuid4

from langgraph.store.memory import InMemoryStore

from app.agents.memory import MemoryService, namespace
from app.schemas.agent import SaveUserMemoryToolInput


def test_paginated_memory_lookup_scope_conflict_and_invalidation():
    async def scenario():
        store = InMemoryStore()
        user, other, item = uuid4(), uuid4(), uuid4()
        service = MemoryService(store, user)
        for n in range(125):
            await store.aput(namespace(user), str(n), {"category": "UNIT_RELATIONSHIP", "content": str(n),
                "conditions": {"item_definition_id": str(uuid4()), "source_unit": "cup", "target_unit": "kg"}})
        payload = SaveUserMemoryToolInput(category="UNIT_RELATIONSHIP", content="One cup is about 100g",
            conditions={"item_definition_id": item, "source_unit": "cup", "target_unit": "g"},
            structured_value={"source_amount": "1", "source_unit": "cup", "target_amount": "100", "target_unit": "g"})
        saved = await service.save_memory(payload)
        repeated = await service.save_memory(payload)
        assert saved["memory_id"] == repeated["memory_id"]
        assert len(await service.search_memories("UNIT_RELATIONSHIP", limit=1000)) == 126
        context = {"item_definition_id": str(item), "source_unit": "cup", "target_unit": "kg"}
        match = await service.find_applicable_memories(context)
        assert match["status"] == "MATCH"
        assert await service.verify_snapshots(match["items"])
        assert (await MemoryService(store, other).find_applicable_memories(context))["status"] == "NO_MATCH"
        changed = payload.model_copy(update={"memory_id": saved["memory_id"], "content": "New cup", "structured_value": {"source_amount": "1", "source_unit": "cup", "target_amount": "150", "target_unit": "g"}})
        await service.save_memory(changed)
        assert not await service.verify_snapshots(match["items"])
        await service.save_memory(payload.model_copy(update={"content": "Conflicting amount", "structured_value": None}))
        assert (await service.find_applicable_memories(context))["status"] == "CONFLICT"
    asyncio.run(scenario())


def test_preload_truncation_and_missing_conditions_do_not_mean_no_memory():
    async def scenario():
        service = MemoryService(InMemoryStore(), uuid4())
        for n in range(25):
            await service.save_memory(SaveUserMemoryToolInput(category="USAGE_PREFERENCE", content=f"Preference {n}", conditions={}))
        preload = await service.load_turn_context("rice")
        assert preload["truncated"] and len(preload["items"]) <= 20
        await service.save_memory(SaveUserMemoryToolInput(category="UNIT_RELATIONSHIP", content="rice cup",
            conditions={"item_name": "rice", "utensil": "blue cup", "source_unit": "cup", "target_unit": "kg"}))
        result = await service.find_applicable_memories({"item_name": "rice", "source_unit": "cup", "target_unit": "kg"})
        assert result["status"] == "NEEDS_CONTEXT"
        assert len(await service.search_memories("USAGE_PREFERENCE", limit=100)) == 25
    asyncio.run(scenario())


def test_same_turn_cache_avoids_repeated_searches_and_invalidates_on_save():
    class CountedStore(InMemoryStore):
        calls = 0
        async def asearch(self, *args, **kwargs):
            self.calls += 1
            return await super().asearch(*args, **kwargs)
    async def scenario():
        store, cache, user = CountedStore(), {}, uuid4()
        first = MemoryService(store, user, cache)
        await first.load_turn_context("rice")
        calls = store.calls
        second = MemoryService(store, user, cache)
        await second.search_memories("UNIT_RELATIONSHIP")
        await second.find_applicable_memories({"item_name": "rice"})
        assert store.calls == calls
        await second.save_memory(SaveUserMemoryToolInput(category="USAGE_PREFERENCE", content="short", conditions={}))
        await first.load_turn_context("rice")
        assert store.calls > calls
    asyncio.run(scenario())
