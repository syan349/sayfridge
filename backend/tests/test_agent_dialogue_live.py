"""Opt-in natural dialogue acceptance using the original receipt photographs."""
import os
import json
import re
from uuid import uuid4
from decimal import Decimal

import pytest

from app.agents.model import create_agent_model
from inventory_test_support import inventory_context
from auth_test_support import exercise
from agent_dialogue_support import Dialogue, receipt_image, seed_catalog, describe

pytestmark = [pytest.mark.postgres, pytest.mark.skipif(os.getenv("AGENT_LIVE_MODEL") != "1", reason="Opt in to model API costs")]


@pytest.mark.parametrize("filename,count", [("newworld.jpg", 8), ("TAIPING.jpg", 8), ("woolworth.jpg", 3)])
@pytest.mark.parametrize("cross_turn", [False, True])
def test_original_receipt_http(filename, count, cross_turn, inventory_context, monkeypatch, live_runner):
    async def scenario(client, sessions):
        c = inventory_context
        await seed_catalog(c, sessions)
        dialogue = Dialogue(client, c, sessions, create_agent_model(), monkeypatch)
        photo = receipt_image(filename)
        if cross_turn:
            upload = await dialogue.chat(images=[photo])
            assert not upload["items"] and await dialogue.counts() == (0, 0, 0)
            state = await dialogue.chat("把刚才小票上的商品全部入库。")
        else:
            state = await dialogue.chat("把这张小票上的商品全部入库。", [photo])
        print(json.dumps({"receipt": filename, "cross_turn": cross_turn, "recognized": describe(state)}, ensure_ascii=False))
        assert len(state["items"]) == count
        assert await dialogue.counts() == (0, 0, 0), "Image review must precede every write"
        assert all(i["status"] in {"NEEDS_INPUT", "NEEDS_CONFIRMATION"} for i in state["items"])
        duplicate = photo.model_copy(update={"image_id": uuid4()})
        repeated = await dialogue.chat(images=[duplicate])
        assert [(i["item_id"], i["proposal_id"]) for i in repeated["items"]] == [(i["item_id"], i["proposal_id"]) for i in state["items"]]
        assert await dialogue.counts() == (0, 0, 0)
        # Remaining identity/quantity/packaging assertions and targeted answers are
        # shared below so every pathway is checked against the manual baseline.
        await check_receipt(dialogue, state, filename)
    live_runner.run(exercise(inventory_context[0], scenario))


RECEIPT_ROWS = {
    "newworld.jpg": [
        (r"sea.*(?:slt|salt).*vine|海盐.*醋", "2", "count", "150g"),
        (r"honey.*soy|蜂蜜.*(?:酱|鸡)", "2", "count", "150g"),
        (r"apple.*juice|苹果汁", "2", "count", "1l"),
        (r"mandarin|柑|桔|橘", "0.835", "kg", None),
        (r"anchor.*milk|无乳糖.*奶", "1", "count", "1l"),
        (r"tegel|smoked.*chicken|烟熏.*鸡", "1", "count", "350g"),
        (r"beef.*(?:prime|premium).*mince|牛肉末|牛肉糜", "1", "count", None),
        (r"beef.*(?:prime|premium).*mince|牛肉末|牛肉糜", "1", "count", None),
    ],
    "TAIPING.jpg": [
        (r"mushroom|香菇", "1", "count", "500g"),
        (r"watermelon|西瓜", "1", "count", "480ml"),
        (r"onion|洋葱", "0.17", None, None),
        (r"black.*gr|黑葡萄", "1.0015", "unclear", "480ml"),
        (r"turnip|白萝卜", "1", "count", None),
        (r"tofu|豆腐", "1", "count", "680g"),
        (r"sliced.*beef|牛肉片", "1", "count", "400g"),
        (r"sliced.*lamb|羊肉片", "1", "count", "400g"),
    ],
    "woolworth.jpg": [
        (r"peanut|花生", "1", "count", "200g"),
        (r"milk|牛奶", "1", "count", "1l"),
        (r"b.?bird|bluebird|original.*cut|薯片", "1", "count", "150g"),
    ],
}


def match_rows(state, filename):
    from app.services.inventory_quantities import COUNT_UNITS
    from app.core.quantity import normalize_standard_unit
    remaining = list(state["items"])
    matched = []
    for pattern, amount, unit, size in RECEIPT_ROWS[filename]:
        candidates = [i for i in remaining if re.search(pattern, i["display"]["recognized_text"] + " " + i["display"]["item_name"], re.I)]
        assert candidates, (filename, pattern, describe(state))
        item = candidates[0]
        remaining.remove(item)
        matched.append(item)
        display = item["display"]
        assert Decimal(display["quantity_value"]) == Decimal(amount), (pattern, display)
        assert display["source_image_ids"] and display["quantity_basis"], (pattern, display)
        if unit == "count":
            assert (display["quantity_unit"] or "").casefold() in COUNT_UNITS, (pattern, display)
        elif unit == "kg":
            assert normalize_standard_unit(display["quantity_unit"]) == "kg"
        elif unit is None:
            assert display["quantity_unit"] is None and display["missing_fields"] == ["quantity_unit"]
            assert item["status"] == "NEEDS_INPUT"
        else:
            assert item["status"] == "NEEDS_INPUT" and display["quantity_issue"]
            assert "quantity_value" in display["missing_fields"]
        if size:
            package = (display["package_description"] or "").lower().replace(" ", "").replace("毫升", "ml").replace("克", "g").replace("升", "l")
            assert size in package, (pattern, size, package)
    assert not remaining, (filename, describe(state))
    return matched


async def check_receipt(dialogue, state, filename):
    assert state["status"] == "WAITING_INPUT"
    rows = match_rows(state, filename)
    before = {i["item_id"]: i for i in state["items"]}
    if filename == "TAIPING.jpg":
        onion, soda = rows[2], rows[3]
        state = await dialogue.chat("洋葱的0.17是公斤。")
        revised = {i["item_id"]: i for i in state["items"]}
        assert revised[onion["item_id"]]["status"] == "NEEDS_CONFIRMATION", describe(state)
        assert revised[onion["item_id"]]["display"]["quantity_value"] == "0.17"
        assert all(revised[k]["proposal_id"] == before[k]["proposal_id"] for k in before if k != onion["item_id"])
        assert Decimal(revised[soda["item_id"]]["display"]["quantity_value"]) == Decimal("1.0015")
        state = await dialogue.chat("黑葡萄气泡水实际买了一瓶，480毫升是一瓶的规格。")
        revised = {i["item_id"]: i for i in state["items"]}
        assert revised[soda["item_id"]]["status"] == "NEEDS_CONFIRMATION", describe(state)
        assert Decimal(revised[soda["item_id"]]["display"]["quantity_value"]) == 1
    else:
        target = rows[2] if filename == "newworld.jpg" else rows[0]
        text = "苹果汁按瓶记录，数量不变。" if filename == "newworld.jpg" else "花生按袋记录，数量不变。"
        state = await dialogue.chat(text)
        revised = {i["item_id"]: i for i in state["items"]}
        assert revised[target["item_id"]]["proposal_id"] != target["proposal_id"]
        assert all(revised[k]["proposal_id"] == before[k]["proposal_id"] for k in before if k != target["item_id"])
    # Any uncertainty about a receipt abbreviation is a targeted identity answer,
    # never a request to re-list the other recognized goods.
    if filename == "woolworth.jpg" and any(i["status"] == "NEEDS_INPUT" for i in state["items"]):
        state = await dialogue.chat("B/bird那项是原味咸薯片。")
    assert all(i["status"] == "NEEDS_CONFIRMATION" for i in state["items"]), describe(state)
    assert await dialogue.counts() == (0, 0, 0)
    count = len(state["items"])
    state = await dialogue.chat("确认以上所有商品入库。")
    assert all(i["status"] == "SUCCEEDED" for i in state["items"]), describe(state)
    assert await dialogue.counts() == (count, 0, count)
    confirmed = {i["item_id"]: i for i in state["items"]}
    for item in state["items"]:
        saved = item["result"]["inventory"]
        display = item["display"]
        assert Decimal(saved["confirmed_current_amount"]) == Decimal(display["quantity_value"])
        assert saved["confirmed_current_unit"] == display["quantity_unit"].casefold()
    replay = await dialogue.chat(dialogue.body["message"], request_id=dialogue.body["request_id"])
    assert {i["item_id"] for i in replay["items"]} == set(confirmed)
    assert await dialogue.counts() == (count, 0, count)
    replay = await dialogue.chat("刚才那批我已经确认了，这次只是重复确认。")
    assert {i["item_id"] for i in replay["items"]} == set(confirmed), describe(replay)
    assert await dialogue.counts() == (count, 0, count)


@pytest.mark.parametrize("repeat", range(3))
@pytest.mark.parametrize("message,amount,unit", [
    ("I bought 3 tofu today", "3", "count"),
    ("我买了3盒豆腐。", "3", "盒"),
    ("西红柿 3，帮我入库。", "3", None),
])
def test_natural_purchase_http(message, amount, unit, repeat, inventory_context, monkeypatch, live_runner):
    async def scenario(client, sessions):
        c = inventory_context
        await seed_catalog(c, sessions)
        dialogue = Dialogue(client, c, sessions, create_agent_model(), monkeypatch)
        state = await dialogue.chat(message)
        print(json.dumps({"message": message, "repeat": repeat, "items": describe(state)}, ensure_ascii=False))
        assert len(state["items"]) == 1
        item = state["items"][0]
        if unit is None:
            assert item["status"] == "NEEDS_INPUT"
            assert item["display"]["missing_fields"] == ["quantity_unit"]
            state = await dialogue.chat("单位是个。")
            item = state["items"][0]
        assert item["status"] == "SUCCEEDED", describe(state)
        inventory = item["result"]["inventory"]
        assert Decimal(inventory["confirmed_current_amount"]) == Decimal(amount)
        if unit == "盒":
            assert inventory["confirmed_current_unit"] == unit
        else:
            from app.services.inventory_quantities import COUNT_UNITS
            assert inventory["confirmed_current_unit"].casefold() in COUNT_UNITS
        assert await dialogue.counts() == (1, 0, 1)
        if unit is None:
            original_id = item["item_id"]
            repeated = await dialogue.chat("单位就是个，刚才那项已经补过了，这次只是重复补答。")
            assert [i["item_id"] for i in repeated["items"]] == [original_id]
            assert await dialogue.counts() == (1, 0, 1)
            query = await dialogue.chat("先看看目前的库存。")
            assert not query["items"] and await dialogue.counts() == (1, 0, 1)
            new = await dialogue.chat("又买了3个西红柿，帮我入库。")
            assert len(new["items"]) == 1 and new["items"][0]["status"] == "SUCCEEDED", describe(new)
            assert new["items"][0]["item_id"] != original_id and await dialogue.counts() == (2, 0, 2)
    live_runner.run(exercise(inventory_context[0], scenario))


@pytest.mark.parametrize("repeat", range(3))
@pytest.mark.parametrize("message,amount,unit,size", [
    ("今天买了2袋米，每袋500克，花了7元。", "2", "袋", "500"),
    ("我在2026年10月1日买了300克菠菜，花了5.99元。", "300", "g", None),
])
def test_explicit_units_specs_prices_and_dates(message, amount, unit, size, repeat, inventory_context, monkeypatch, live_runner):
    async def scenario(client, sessions):
        await seed_catalog(inventory_context, sessions)
        dialogue = Dialogue(client, inventory_context, sessions, create_agent_model(), monkeypatch)
        state = await dialogue.chat(message)
        assert len(state["items"]) == 1 and state["items"][0]["status"] == "SUCCEEDED", describe(state)
        saved = state["items"][0]["result"]["inventory"]
        assert Decimal(saved["confirmed_current_amount"]) == Decimal(amount)
        from app.core.quantity import normalize_standard_unit
        assert normalize_standard_unit(saved["confirmed_current_unit"]) == unit
        if size:
            assert size in state["items"][0]["display"]["package_description"]
        assert saved["purchase_date"] == "2026-10-01"
    live_runner.run(exercise(inventory_context[0], scenario))


@pytest.mark.parametrize("repeat", range(3))
@pytest.mark.parametrize("case", ["rice", "even_apples", "odd_apples"])
def test_context_relative_quantity_and_actual_partial_answer(case, repeat, inventory_context, monkeypatch, live_runner):
    from sqlalchemy import select
    from app.db.models import ItemDefinition, InventoryItem
    from inventory_test_support import seed_inventory
    from sqlalchemy.orm import Session
    c = inventory_context
    apple = case != "rice"
    with Session(c[0][2]) as session:
        definition = session.get(ItemDefinition, c[5].id)
        definition.name = definition.normalized_name = "苹果" if apple else "Rice"
        session.commit()
    amount = "3" if case == "odd_apples" else "4" if apple else "2"
    unit = "个" if apple else "kg"
    item = seed_inventory(c, initial_amount=Decimal(amount), initial_unit=unit,
                          confirmed_current_amount=Decimal(amount), confirmed_current_unit=unit)
    async def scenario(client, sessions):
        await seed_catalog(c, sessions)
        dialogue = Dialogue(client, c, sessions, create_agent_model(), monkeypatch)
        state = await dialogue.chat("刚刚吃了库存里苹果的一半，帮我扣掉。" if apple else "I used half of the rice. Please deduct it.")
        assert len(state["items"]) == 1, describe(state)
        operation = state["items"][0]
        if case == "odd_apples":
            assert operation["status"] == "NEEDS_INPUT" and operation["error"]["code"] == "WHOLE_COUNT_REQUIRED", describe(state)
            assert operation["display"]["missing_fields"] == ["quantity_value"]
            old_id = operation["item_id"]
            state = await dialogue.chat("实际吃了一个半苹果。")
            operation = state["items"][0]
            assert operation["item_id"] == old_id
        assert operation["status"] == "SUCCEEDED", describe(state)
        saved = operation["result"]["inventory"]
        expected = Decimal("1.5") if case == "odd_apples" else Decimal(amount) / 2
        assert Decimal(saved["confirmed_current_amount"]) == expected and saved["confirmed_current_unit"] == unit
        assert saved["estimated_current_amount"] is None
        assert await dialogue.counts() == (1, 1, 1)
    live_runner.run(exercise(c[0], scenario))


@pytest.mark.parametrize("repeat", range(3))
def test_ambiguous_target_new_purchase_query_and_old_task_recovery(repeat, inventory_context, monkeypatch, live_runner):
    from inventory_test_support import seed_inventory, seed_space
    from app.db.models import InventoryItem
    c = inventory_context
    kitchen = seed_inventory(c, initial_amount=Decimal("2"), initial_unit="kg", confirmed_current_amount=Decimal("2"), confirmed_current_unit="kg")
    garage = seed_space(c[0], c[1].id, name="Garage")
    other = seed_inventory(c, storage_space_id=garage.id, initial_amount=Decimal("4"), initial_unit="kg",
                           confirmed_current_amount=Decimal("4"), confirmed_current_unit="kg")
    async def scenario(client, sessions):
        await seed_catalog(c, sessions)
        dialogue = Dialogue(client, c, sessions, create_agent_model(), monkeypatch)
        first = await dialogue.chat("I used half the rice. Please deduct it.")
        assert len(first["items"]) == 1 and first["items"][0]["error"]["code"] == "TARGET_REQUIRED", describe(first)
        item = first["items"][0]
        assert item["display"]["missing_fields"] == ["inventory_item_id"]
        assert await dialogue.counts() == (2, 0, 0)
        new = await dialogue.chat("I also bought 3 apples today. Please add them.")
        old = next(i for i in new["items"] if i["item_id"] == item["item_id"])
        assert old["proposal_id"] == item["proposal_id"] and old["status"] == "NEEDS_INPUT"
        assert await dialogue.counts() == (3, 0, 1)
        query = await dialogue.chat("Please show my inventory first.")
        assert any(e["type"] == "text_delta" for e in dialogue.events)
        assert next(i for i in query["items"] if i["item_id"] == item["item_id"])["proposal_id"] == item["proposal_id"]
        resumed = await dialogue.chat("The Kitchen batch. Continue that rice deduction.")
        saved = next(i for i in resumed["items"] if i["item_id"] == item["item_id"])
        assert saved["status"] == "SUCCEEDED", describe(resumed)
        assert saved["result"]["inventory"]["id"] == str(kitchen.id)
        assert Decimal(saved["result"]["inventory"]["confirmed_current_amount"]) == 1
        assert await dialogue.counts() == (3, 1, 2)
        async with sessions() as session:
            untouched = await session.get(InventoryItem, other.id)
            assert untouched.confirmed_current_amount == Decimal("4") and untouched.version == 1
    live_runner.run(exercise(c[0], scenario))


def test_joint_receipts_duplicate_photo_and_all_sales_execute(inventory_context, monkeypatch, live_runner):
    async def scenario(client, sessions):
        await seed_catalog(inventory_context, sessions)
        dialogue = Dialogue(client, inventory_context, sessions, create_agent_model(), monkeypatch)
        names = list(RECEIPT_ROWS)
        photos = [receipt_image(name) for name in names]
        state = await dialogue.chat("把这些小票上的商品全部入库。", [*photos, photos[0].model_copy(update={"image_id": uuid4()})])
        print(json.dumps({"joint_receipts": describe(state)}, ensure_ascii=False))
        assert len(state["items"]) == 19 and await dialogue.counts() == (0, 0, 0)
        for name, photo in zip(names, photos):
            subset = {"items": [i for i in state["items"] if str(photo.image_id) in i["display"]["source_image_ids"]]}
            assert len(subset["items"]) == len(RECEIPT_ROWS[name])
            match_rows(subset, name)
        state = await dialogue.chat("洋葱的0.17是公斤；黑葡萄气泡水实际买了一瓶。其他项目保持原样。")
        if any(i["status"] == "NEEDS_INPUT" for i in state["items"]):
            state = await dialogue.chat("B/bird那项是原味咸薯片。")
        assert len(state["items"]) == 19 and all(i["status"] == "NEEDS_CONFIRMATION" for i in state["items"]), describe(state)
        state = await dialogue.chat("确认全部商品入库。")
        assert len(state["items"]) == 19 and all(i["status"] == "SUCCEEDED" for i in state["items"]), describe(state)
        assert await dialogue.counts() == (19, 0, 19)
    live_runner.run(exercise(inventory_context[0], scenario))


def test_real_photo_can_answer_existing_text_task(inventory_context, monkeypatch, live_runner):
    async def scenario(client, sessions):
        await seed_catalog(inventory_context, sessions)
        dialogue = Dialogue(client, inventory_context, sessions, create_agent_model(), monkeypatch)
        first = await dialogue.chat("买了牛奶，帮我入库。")
        assert len(first["items"]) == 1 and first["items"][0]["status"] == "NEEDS_INPUT", describe(first)
        old_id = first["items"][0]["item_id"]
        state = await dialogue.chat("牛奶的信息在这张小票里。", [receipt_image("woolworth.jpg")])
        assert len(state["items"]) == 1 and state["items"][0]["item_id"] == old_id
        item = state["items"][0]
        assert item["status"] == "NEEDS_CONFIRMATION", describe(state)
        assert Decimal(item["display"]["quantity_value"]) == 1 and "1" in item["display"]["package_description"]
        assert item["display"]["source_image_ids"] and await dialogue.counts() == (0, 0, 0)
        state = await dialogue.chat("确认牛奶入库。")
        assert state["items"][0]["status"] == "SUCCEEDED" and await dialogue.counts() == (1, 0, 1)
    live_runner.run(exercise(inventory_context[0], scenario))
