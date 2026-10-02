"""Read-only inventory tools and user-isolated long-term-memory tools."""
from __future__ import annotations

import json
from datetime import timedelta
from typing import Any, Annotated
from uuid import UUID

from langchain_core.tools import tool
from langchain_core.tools import InjectedToolArg
from langgraph.prebuilt import ToolRuntime
from pydantic import create_model, PlainSerializer

from app.db.session import AsyncSessionFactory
from app.schemas.agent import (
    DeleteUserMemoryToolInput,
    ExpirySummaryToolInput,
    InventoryDetailToolInput,
    ListInventoryToolInput,
    ListStorageSpacesToolInput,
    MemoryConditions,
    SaveUserMemoryToolInput,
    SearchUserMemoriesToolInput,
)
from app.schemas.business import StorageSpaceRead
from app.services import inventory as inventory_service
from app.services import storage_spaces as storage_service
from app.services.inventory import InventoryError
from app.services.storage_spaces import StorageSpaceError
from app.agents.memory import MemoryService
from app.agents.state import AgentContext

AgentToolRuntime = ToolRuntime[AgentContext]


def _runtime_schema(schema):
    # LangGraph injects runtime before StructuredTool validates arguments. Keep
    # strict public fields while hiding the internal runtime from the model schema.
    # The serializer avoids traversing connections/callbacks during argument parsing;
    # StructuredTool passes the original validated runtime attribute to the function.
    internal = Annotated[Any, InjectedToolArg, PlainSerializer(lambda value: None)]
    return create_model(f"{schema.__name__}WithRuntime", __base__=schema, runtime=(internal, ...))


def _require_memory_instruction(runtime, quote):
    """Require evidence in the current user message, not model-authored approval."""
    import re
    message = runtime.context.user_message
    if not quote or quote not in message:
        raise ValueError("Quote the user's explicit memory instruction in authorization_quote")
    if not re.search(r"记住|记一下|记忆|忘记|以后|remember|memorize|forget|memory", quote, re.IGNORECASE):
        raise ValueError("The user must explicitly request a memory change")


def _json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), default=str)


def _tool_error(exc: Exception) -> str:
    if isinstance(exc, InventoryError):
        return _json({"ok": False, "code": exc.code, "message": str(exc)})
    return _json({"ok": False, "code": "NOT_FOUND", "message": str(exc)})


@tool(args_schema=_runtime_schema(ListStorageSpacesToolInput))
async def list_storage_spaces(
    runtime: AgentToolRuntime,
    status: str = "ACTIVE",
    page: int = 1,
    page_size: int = 20,
) -> str:
    """List the authenticated user's storage spaces with explicit pagination."""
    try:
        async with AsyncSessionFactory() as session:
            spaces, total = await storage_service.list_storage_spaces(
                session,
                runtime.context.user_id,
                status=status,
                page=page,
                page_size=page_size,
            )
        items = [StorageSpaceRead.model_validate(space).model_dump(mode="json") for space in spaces]
        return _json({"ok": True, "items": items, "total": total, "page": page, "page_size": page_size})
    except StorageSpaceError as exc:
        return _tool_error(exc)


@tool(args_schema=_runtime_schema(ListInventoryToolInput))
async def list_inventory(
    runtime: AgentToolRuntime,
    status: str = "IN_STOCK",
    q: str = "",
    storage_space_id=None,
    category_id=None,
    purchase_from=None,
    purchase_to=None,
    expiry_from=None,
    expiry_to=None,
    page: int = 1,
    page_size: int = 20,
) -> str:
    """Filter and page through the authenticated user's inventory batches."""
    query = {
        "status": status,
        "q": q,
        "storage_space_id": storage_space_id,
        "category_id": category_id,
        "purchase_from": purchase_from,
        "purchase_to": purchase_to,
        "expiry_from": expiry_from,
        "expiry_to": expiry_to,
        "page": page,
        "page_size": page_size,
    }
    try:
        async with AsyncSessionFactory() as session:
            items, total = await inventory_service.list_inventory(
                session, runtime.context.user_id, **query,
            )
        return _json({
            "ok": True,
            "items": [item.model_dump(mode="json") for item in items],
            "total": total,
            "page": page,
            "page_size": page_size,
        })
    except InventoryError as exc:
        return _tool_error(exc)


@tool(args_schema=_runtime_schema(InventoryDetailToolInput))
async def get_inventory_detail(runtime: AgentToolRuntime, inventory_item_id) -> str:
    """Get one owned inventory batch by its exact identifier."""
    try:
        async with AsyncSessionFactory() as session:
            item = await inventory_service.get_inventory(
                session, inventory_item_id, runtime.context.user_id,
            )
        return _json({"ok": True, "item": item.model_dump(mode="json")})
    except InventoryError as exc:
        return _tool_error(exc)


@tool(args_schema=_runtime_schema(ExpirySummaryToolInput))
async def get_expiry_summary(
    runtime: AgentToolRuntime,
    days_before: int = 3,
    storage_space_id=None,
    category_id=None,
    bucket=None,
    page: int = 1,
    page_size: int = 20,
) -> str:
    """Summarize owned in-stock inventory using the user's supplied local date."""
    if runtime.context.as_of is None:
        return _json({
            "ok": False,
            "code": "LOCAL_DATE_REQUIRED",
            "message": "Ask the user for their local date before running an expiry query",
        })
    try:
        runtime.context.as_of + timedelta(days=days_before)
    except OverflowError:
        return _json({
            "ok": False,
            "code": "INVALID_DATE_RANGE",
            "message": "The expiry window exceeds the supported date range",
        })
    query = {
        "as_of": runtime.context.as_of,
        "days_before": days_before,
        "storage_space_id": storage_space_id,
        "category_id": category_id,
        "bucket": bucket,
        "page": page,
        "page_size": page_size,
    }
    try:
        async with AsyncSessionFactory() as session:
            items, counts, total = await inventory_service.get_expiry_summary(
                session, runtime.context.user_id, **query,
            )
        return _json({
            "ok": True,
            "as_of": runtime.context.as_of.isoformat(),
            "days_before": days_before,
            "counts": counts,
            "items": [item.model_dump(mode="json") for item in items],
            "total": total,
            "page": page,
            "page_size": page_size,
        })
    except InventoryError as exc:
        return _tool_error(exc)


@tool(args_schema=_runtime_schema(SearchUserMemoriesToolInput))
async def search_user_memories(
    runtime: AgentToolRuntime,
    category=None,
    conditions: MemoryConditions | None = None,
    limit: int = 10,
) -> str:
    """Search structured memories belonging only to the authenticated user."""
    if runtime.store is None:
        raise RuntimeError("Agent memory store is unavailable")
    matches = await MemoryService(runtime.store, runtime.context.user_id, runtime.context.memory_cache).search_memories(
        category, conditions.model_dump(mode="json", exclude_none=True) if conditions else None, limit)
    return _json({"ok": True, "items": matches, "count": len(matches)})


@tool(args_schema=_runtime_schema(SaveUserMemoryToolInput))
async def save_user_memory(
    runtime: AgentToolRuntime,
    category: str,
    content: str,
    conditions: MemoryConditions,
    approximate: bool = True,
    memory_id=None,
    structured_value=None,
    authorization_quote=None,
) -> str:
    """Save or update a memory only after the user explicitly asks to remember it."""
    if runtime.store is None:
        raise RuntimeError("Agent memory store is unavailable")
    _require_memory_instruction(runtime, authorization_quote)
    payload = SaveUserMemoryToolInput(category=category, content=content, conditions=conditions,
        approximate=approximate, memory_id=memory_id, structured_value=structured_value)
    if category == "ENTITY_ALIAS":
        from app.services import catalog
        value = structured_value or {}
        async with AsyncSessionFactory() as session:
            if value.get("target_type") == "SPACE":
                await storage_service.get_storage_space_by_id(session, UUID(value["target_id"]), runtime.context.user_id)
            elif value.get("target_type") == "ITEM_DEFINITION":
                await catalog.get_definition(session, UUID(value["target_id"]), runtime.context.user_id)
    result = await MemoryService(runtime.store, runtime.context.user_id, runtime.context.memory_cache).save_memory(payload)
    runtime.context.cache.clear()
    return _json(result)


@tool(args_schema=_runtime_schema(DeleteUserMemoryToolInput))
async def delete_user_memory(runtime: AgentToolRuntime, memory_id, authorization_quote=None) -> str:
    """Delete one exact owned memory after the user explicitly requests deletion."""
    if runtime.store is None:
        raise RuntimeError("Agent memory store is unavailable")
    _require_memory_instruction(runtime, authorization_quote)
    result = await MemoryService(runtime.store, runtime.context.user_id, runtime.context.memory_cache).delete_memory(memory_id)
    runtime.context.cache.clear()
    return _json(result)


@tool
async def resolve_inventory_targets(runtime: AgentToolRuntime, queries: list[str], storage_space_id: str | None = None, space_query: str | None = None) -> str:
    """Resolve colloquial names or synonyms to owned inventory candidates; never assume the first candidate."""
    from app.services.agent_actions import resolve_targets
    async with AsyncSessionFactory() as session:
        result = await resolve_targets(session, runtime.context.user_id, queries,
            UUID(storage_space_id) if storage_space_id else None,
            MemoryService(runtime.store, runtime.context.user_id, runtime.context.memory_cache), space_query)
    return _json(result)


@tool
async def list_item_definitions(runtime: AgentToolRuntime, query: str = "", page: int = 1) -> str:
    """Find existing visible item definitions for stock creation, with pagination."""
    from app.services import catalog
    from app.schemas.business import ItemDefinitionRead
    if page < 1:
        raise ValueError("page must be positive")
    async with AsyncSessionFactory() as session:
        rows, total = await catalog.list_definitions(session, runtime.context.user_id,
            status="ACTIVE", scope="ALL", q=query, category_id=None, page=page, page_size=50)
    return _json({"items": [ItemDefinitionRead(id=r.id, name=r.name, category_id=r.category_id,
                    status=r.status, scope="PUBLIC" if r.owner_user_id is None else "PRIVATE").model_dump(mode="json") for r in rows],
                  "total": total, "page": page, "page_size": 50})


@tool
async def list_item_categories(runtime: AgentToolRuntime, page: int = 1) -> str:
    """List existing active categories; the Agent cannot create public categories."""
    from app.services import catalog
    from app.schemas.business import ItemCategoryRead
    from app.core.category_catalog import category_guidance
    if page < 1:
        raise ValueError("page must be positive")
    async with AsyncSessionFactory() as session:
        rows, total = await catalog.list_categories(session, runtime.context.user_id, status="ACTIVE", page=page, page_size=50)
    return _json({"items": [{**ItemCategoryRead.model_validate(r).model_dump(mode="json"), **category_guidance(r.name)} for r in rows],
                  "total": total, "page": page, "page_size": 50})


AGENT_TOOLS = [
    list_storage_spaces,
    list_inventory,
    get_inventory_detail,
    get_expiry_summary,
    search_user_memories,
    save_user_memory,
    delete_user_memory,
    resolve_inventory_targets,
    list_item_definitions,
    list_item_categories,
]
