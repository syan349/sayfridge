"""B22 on-demand inventory expiry-summary acceptance tests."""
import asyncio
from datetime import date

import pytest
from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Session

from app.db.models import ItemCategory, ItemDefinition, StorageSpace
from auth_test_support import exercise, request
from catalog_test_support import seed_category, seed_definition
from inventory_test_support import BASE, inventory_context, seed_inventory, seed_space

pytestmark = pytest.mark.postgres
URL = BASE + "/expiry-summary"


def get_summary(context, query=""):
    response = request(context[0], "GET", URL + query, headers=context[-1])
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.ci
def test_expiry_summary_classifies_orders_and_preserves_archived_associations(
    inventory_context,
):
    context = inventory_context
    overdue = seed_inventory(context, expiry_date=date(2026, 9, 23))
    today = seed_inventory(context, expiry_date=date(2026, 9, 24))
    upcoming = seed_inventory(context, expiry_date=date(2026, 9, 25))
    upcoming_last = seed_inventory(context, expiry_date=date(2026, 9, 27))
    seed_inventory(context, expiry_date=date(2026, 9, 28))
    seed_inventory(context, expiry_date=None)
    seed_inventory(context, expiry_date=date(2026, 9, 24), status="EMPTY")
    seed_inventory(context, expiry_date=date(2026, 9, 24), status="DISCARDED")
    seed_inventory(context, expiry_date=date(2026, 9, 24), status="ARCHIVED")
    with Session(context[0][2]) as session:
        session.execute(
            update(StorageSpace)
            .where(StorageSpace.id == context[4].id)
            .values(status="ARCHIVED", name="Archived kitchen")
        )
        session.execute(
            update(ItemDefinition)
            .where(ItemDefinition.id == context[5].id)
            .values(status="ARCHIVED", name="Archived rice")
        )
        session.execute(
            update(ItemCategory)
            .where(ItemCategory.id == context[3].id)
            .values(status="ARCHIVED")
        )
        session.commit()

    body = get_summary(context, "?as_of=2026-09-24")

    assert body["counts"] == {"overdue": 1, "today": 1, "upcoming": 2}
    assert body["total"] == 4
    assert [item["id"] for item in body["items"]] == [
        str(overdue.id),
        str(today.id),
        str(upcoming.id),
        str(upcoming_last.id),
    ]
    assert [item["bucket"] for item in body["items"]] == [
        "overdue",
        "today",
        "upcoming",
        "upcoming",
    ]
    assert body["items"][0]["storage_space_name"] == "Archived kitchen"
    assert body["items"][0]["item_definition_name"] == "Archived rice"


@pytest.mark.ci
def test_bucket_filters_details_without_changing_counts_and_pages(inventory_context):
    context = inventory_context
    first = seed_inventory(context, expiry_date=date(2026, 9, 20))
    second = seed_inventory(context, expiry_date=date(2026, 9, 21))
    seed_inventory(context, expiry_date=date(2026, 9, 24))
    seed_inventory(context, expiry_date=date(2026, 9, 25))

    page = get_summary(
        context,
        "?as_of=2026-09-24&bucket=overdue&page=2&page_size=1",
    )
    assert page["counts"] == {"overdue": 2, "today": 1, "upcoming": 1}
    assert page["total"] == 2
    assert [item["id"] for item in page["items"]] == [str(second.id)]
    assert page["items"][0]["bucket"] == "overdue"

    empty = get_summary(
        context,
        "?as_of=2026-09-24&bucket=overdue&page=3&page_size=1",
    )
    assert empty["counts"] == page["counts"]
    assert empty["total"] == 2 and empty["items"] == []
    assert str(first.id) != str(second.id)


@pytest.mark.ci
def test_expiry_summary_applies_owned_space_and_category_filters(inventory_context):
    context = inventory_context
    seed_inventory(context, expiry_date=date(2026, 9, 24))
    other_owned_space = seed_space(context[0], context[1].id, "Pantry")
    second_space = seed_inventory(
        context,
        storage_space_id=other_owned_space.id,
        expiry_date=date(2026, 9, 24),
    )
    second_category = seed_category(context[0], "Drinks")
    second_definition = seed_definition(context[0], second_category.id, name="Milk")
    second_category_item = seed_inventory(
        context,
        item_definition_id=second_definition.id,
        expiry_date=date(2026, 9, 24),
    )
    foreign_space = seed_space(context[0], context[2].id, "Foreign")
    seed_inventory(
        context,
        storage_space_id=foreign_space.id,
        expiry_date=date(2026, 9, 24),
    )

    by_space = get_summary(
        context,
        f"?as_of=2026-09-24&storage_space_id={other_owned_space.id}",
    )
    assert by_space["total"] == 1
    assert by_space["items"][0]["id"] == str(second_space.id)

    by_category = get_summary(
        context,
        f"?as_of=2026-09-24&category_id={second_category.id}",
    )
    assert by_category["total"] == 1
    assert by_category["items"][0]["id"] == str(second_category_item.id)


def test_zero_day_window_has_no_upcoming_inventory(inventory_context):
    context = inventory_context
    seed_inventory(context, expiry_date=date(2026, 9, 23))
    seed_inventory(context, expiry_date=date(2026, 9, 24))
    seed_inventory(context, expiry_date=date(2026, 9, 25))
    body = get_summary(context, "?as_of=2026-09-24&days_before=0")
    assert body["counts"] == {"overdue": 1, "today": 1, "upcoming": 0}
    assert body["total"] == 2


def test_expiry_summary_rejects_invalid_queries_safely(inventory_context):
    queries = [
        "",
        "?as_of=2026-09-24T00:00:00Z",
        "?as_of=2026-09-24&days_before=-1",
        "?as_of=2026-09-24&days_before=366",
        "?as_of=2026-09-24&days_before=three",
        "?as_of=2026-09-24&bucket=later",
        "?as_of=2026-09-24&page=0",
        "?as_of=2026-09-24&page_size=101",
        "?as_of=2026-09-24&unknown=1",
        "?as_of=9999-12-31&days_before=1",
    ]
    for query in queries:
        response = request(
            inventory_context[0],
            "GET",
            URL + query,
            headers=inventory_context[-1],
        )
        assert response.status_code == 422, (query, response.text)
        assert response.json()["detail"]["code"] == "VALIDATION_ERROR"


def test_expiry_summary_requires_authentication(inventory_context):
    response = request(
        inventory_context[0],
        "GET",
        URL + "?as_of=2026-09-24",
    )
    assert response.status_code == 401


def test_expiry_summary_supports_maximum_date_with_zero_day_window(inventory_context):
    context = inventory_context
    item = seed_inventory(context, expiry_date=date.max)
    body = get_summary(context, "?as_of=9999-12-31&days_before=0")
    assert body["counts"] == {"overdue": 0, "today": 1, "upcoming": 0}
    assert body["items"][0]["id"] == str(item.id)


def test_expiry_counts_and_empty_page_use_one_database_statement(
    inventory_context,
    monkeypatch,
):
    context = inventory_context
    seed_inventory(context, expiry_date=date(2026, 9, 24))
    execute = AsyncSession.execute
    statements = []

    async def observe(session, statement, *args, **kwargs):
        sql = str(statement)
        if "expiry_inventory" in sql:
            statements.append(sql)
        return await execute(session, statement, *args, **kwargs)

    monkeypatch.setattr(AsyncSession, "execute", observe)

    async def scenario(client, sessions):
        response = await client.get(
            URL + "?as_of=2026-09-24&page=2&page_size=1",
            headers=context[-1],
        )
        assert response.status_code == 200, response.text
        assert response.json()["items"] == []
        assert response.json()["counts"]["today"] == 1
        assert response.json()["total"] == 1

    asyncio.run(exercise(context[0], scenario))
    assert len(statements) == 1
    assert "count(" in statements[0].lower()
