"""User-scoped structured memory. Store contents are data, never instructions."""
from __future__ import annotations

import asyncio
import hashlib
import json
from datetime import date
from uuid import UUID, NAMESPACE_URL, uuid5

from app.core.catalog import normalize_catalog_name
from app.core.quantity import normalize_standard_unit


def fingerprint(value) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, default=str).encode()).hexdigest()


def namespace(user_id) -> tuple[str, ...]:
    return ("users", str(user_id), "memories")


class MemoryUnavailable(RuntimeError):
    pass


class MemoryService:
    def __init__(self, store, user_id, cache=None):
        self.store, self.user_id = store, user_id
        self.cache = cache if cache is not None else {}

    async def _read(self, category=None):
        cache_key = (str(self.user_id), category)
        if cache_key in self.cache:
            return self.cache[cache_key]
        all_key = (str(self.user_id), None)
        if category and all_key in self.cache:
            return [r for r in self.cache[all_key] if r.get("category") == category]
        for attempt in range(2):
            try:
                items, offset = [], 0
                while True:
                    page = await self.store.asearch(namespace(self.user_id),
                        filter={"category": category} if category else None,
                        limit=100, offset=offset)
                    items.extend({"memory_id": row.key, **row.value,
                                  "fingerprint": fingerprint(row.value)} for row in page)
                    if len(page) < 100:
                        self.cache[cache_key] = items
                        return items
                    offset += len(page)
            except Exception:
                if attempt:
                    raise MemoryUnavailable("Memory lookup unavailable") from None
                await asyncio.sleep(0)

    async def search_memories(self, category=None, conditions=None, limit=50):
        records = await self._read(category)
        if conditions is not None:
            records = [r for r in records if self._applies(r, conditions) == "MATCH"]
        return records[:limit]

    @staticmethod
    def _applies(record, context):
        missing = False
        conditions = record.get("conditions", {})
        for key, value in conditions.items():
            if value is None:
                continue
            if key in {"valid_from", "valid_until"}:
                as_of = context.get("as_of")
                if not as_of:
                    missing = True
                elif (key == "valid_from" and str(as_of) < value) or (key == "valid_until" and str(as_of) > value):
                    return "NO_MATCH"
                continue
            # A stable ID is authoritative; the historical display name may change.
            if key == "item_name" and conditions.get("item_definition_id"):
                continue
            observed = context.get(key)
            if key in {"source_unit", "target_unit"} and observed is not None:
                value, observed = normalize_standard_unit(str(value)), normalize_standard_unit(str(observed))
            if observed is None:
                if key == "source_unit":
                    return "NO_MATCH"
                missing = True
            elif key == "target_unit" and {str(value).casefold(), str(observed).casefold()} in ({"g", "kg"}, {"ml", "l"}):
                continue
            elif normalize_catalog_name(str(value)) != normalize_catalog_name(str(observed)):
                return "NO_MATCH"
        return "NEEDS_CONTEXT" if missing else "MATCH"

    async def find_applicable_memories(self, context):
        records = await self._read("UNIT_RELATIONSHIP")
        matches, incomplete = [], []
        for record in records:
            status = self._applies(record, context)
            if status == "MATCH":
                matches.append(record)
            elif status == "NEEDS_CONTEXT":
                incomplete.append(record)
        if matches:
            specificity = lambda r: sum(v is not None for v in r.get("conditions", {}).values())
            best = max(map(specificity, matches))
            matches = [r for r in matches if specificity(r) == best]
            meanings = {fingerprint(r.get("structured_value") or r.get("content")) for r in matches}
            return {"status": "CONFLICT" if len(meanings) > 1 else "MATCH", "items": matches}
        return {"status": "NEEDS_CONTEXT" if incomplete else "NO_MATCH", "items": incomplete}

    async def load_turn_context(self, message):
        records = await self._read()
        text = normalize_catalog_name(message)
        selected = []
        for r in records:
            c = r.get("conditions", {})
            alias = (r.get("structured_value") or {}).get("alias", "")
            terms = [alias, c.get("item_name"), c.get("source_unit")]
            if (r.get("category") == "USAGE_PREFERENCE" and not any(c.values())) or any(
                term and normalize_catalog_name(str(term)) in text for term in terms
            ):
                selected.append(r)
        output, size = [], 0
        for r in selected:
            n = len(json.dumps(r, ensure_ascii=False))
            if len(output) >= 20 or size + n > 4000:
                break
            output.append(r)
            size += n
        return {"items": output, "truncated": len(output) < len(selected)}

    async def verify_snapshots(self, snapshots):
        for record in snapshots:
            current = await self.store.aget(namespace(self.user_id), record["memory_id"])
            if current is None or fingerprint(current.value) != record["fingerprint"]:
                return False
        return True

    async def save_memory(self, payload):
        data = payload.model_dump(mode="json", exclude={"memory_id", "authorization_quote"})
        data["schema_version"] = 2
        data["conditions"] = {k: v for k, v in data["conditions"].items() if v is not None}
        if data["category"] == "UNIT_RELATIONSHIP":
            data["approximate"] = True
            relation = data.get("structured_value")
            if relation:
                from decimal import Decimal
                for key in ("source_amount", "target_amount"):
                    number = Decimal(str(relation.get(key, "NaN")))
                    if not number.is_finite() or number <= 0:
                        raise ValueError("Unit ratios require positive finite source/target amounts")
                for key in ("source_unit", "target_unit"):
                    if normalize_catalog_name(str(relation.get(key, ""))) != normalize_catalog_name(str(data["conditions"].get(key, ""))):
                        raise ValueError("Structured units must match their applicability conditions")
        if data["category"] == "ENTITY_ALIAS":
            v = data.get("structured_value") or {}
            if not v.get("alias") or v.get("target_type") not in {"SPACE", "ITEM_DEFINITION"}:
                raise ValueError("Aliases require alias, target_type and target_id")
            UUID(v.get("target_id", ""))
        # A content-derived ID prevents duplicate saves after graph replay.
        key = str(payload.memory_id or uuid5(NAMESPACE_URL, str(self.user_id) + fingerprint(data)))
        if payload.memory_id is None:
            for record in await self._read(data["category"]):
                if record["fingerprint"] == fingerprint(data):
                    return {"ok": True, "memory_id": record["memory_id"], "memory": data}
        if payload.memory_id and await self.store.aget(namespace(self.user_id), key) is None:
            raise ValueError("Memory not found")
        await self.store.aput(namespace(self.user_id), key, data)
        self.cache.clear()
        return {"ok": True, "memory_id": key, "memory": data}

    async def delete_memory(self, memory_id):
        key = str(memory_id)
        existing = await self.store.aget(namespace(self.user_id), key)
        if existing is not None:
            await self.store.adelete(namespace(self.user_id), key)
        self.cache.clear()
        return {"ok": True, "memory_id": key, "deleted": existing is not None}
