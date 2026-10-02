"""Repair SQL is executed only in disposable test schemas, never public."""
import asyncio
import json
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

import pytest
from sqlalchemy import inspect, text

from app.core.category_catalog import CATEGORIES
from scripts.render_category_seed import render_seed_sql
from inventory_test_support import inventory_context, seed_inventory
from auth_test_support import exercise

SQL_DIR = Path(__file__).resolve().parents[1] / "scripts" / "sql"


def run_sql(database, filename):
    _, schema, engine = database
    assert schema.startswith("auth_test_") and schema.replace('_', '').isalnum()
    sql = (SQL_DIR / filename).read_text(encoding="utf-8")
    sql = sql.replace("public.", f'"{schema}".').replace("table_schema = 'public'", f"table_schema = '{schema}'")
    raw = engine.raw_connection()
    try:
        conn = raw.driver_connection
        conn.autocommit = True
        try:
            conn.execute(sql)
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.autocommit = False
    finally:
        raw.close()


def test_reviewed_seed_matches_shared_configuration():
    assert (SQL_DIR / "seed_item_categories.sql").read_text(encoding="utf-8") == render_seed_sql()
    assert len(CATEGORIES) == len({c['normalized_name'] for c in CATEGORIES}) == 25


@pytest.mark.postgres
def test_notes_repairs_old_schema_preserving_inventory(inventory_context):
    c = inventory_context
    item = seed_inventory(c)
    engine = c[0][2]
    with engine.begin() as conn:
        before = conn.execute(text("SELECT id, version, initial_amount FROM inventory_item")).all()
        conn.execute(text("ALTER TABLE inventory_item DROP COLUMN notes"))
    run_sql(c[0], "add_inventory_notes.sql")
    run_sql(c[0], "add_inventory_notes.sql")
    with engine.connect() as conn:
        assert conn.execute(text("SELECT id, version, initial_amount FROM inventory_item")).all() == before
        assert conn.execute(text("SELECT notes FROM inventory_item WHERE id=:id"), {'id': item.id}).scalar_one() is None


@pytest.mark.postgres
def test_notes_rejects_incompatible_existing_type(database):
    with database[2].begin() as conn:
        conn.execute(text("ALTER TABLE inventory_item ALTER COLUMN notes TYPE INTEGER USING NULL"))
    with pytest.raises(Exception, match="must be nullable TEXT"):
        run_sql(database, "add_inventory_notes.sql")
    assert str(next(c for c in inspect(database[2]).get_columns('inventory_item') if c['name'] == 'notes')['type']) == 'INTEGER'


@pytest.mark.postgres
def test_seed_preserves_existing_ids_and_values(database):
    run_sql(database, "seed_item_categories.sql")
    with database[2].begin() as conn:
        conn.execute(text("UPDATE item_category SET sort_order=999 WHERE name='Fruit'"))
        before = conn.execute(text("SELECT * FROM item_category ORDER BY id")).all()
    run_sql(database, "seed_item_categories.sql")
    with database[2].connect() as conn:
        assert conn.execute(text("SELECT * FROM item_category ORDER BY id")).all() == before
        assert len(before) == 25


@pytest.mark.postgres
def test_seed_failure_rolls_back_and_archived_category_is_not_restored(database):
    with database[2].begin() as conn:
        conn.execute(text("ALTER TABLE item_category ADD CONSTRAINT reject_seed CHECK (name <> 'Fruit')"))
    with pytest.raises(Exception):
        run_sql(database, "seed_item_categories.sql")
    with database[2].begin() as conn:
        assert conn.scalar(text("SELECT count(*) FROM item_category")) == 0
        conn.execute(text("ALTER TABLE item_category DROP CONSTRAINT reject_seed"))
        conn.execute(text("INSERT INTO item_category(id,name,normalized_name,status) VALUES (:id,'Fruit','fruit','ARCHIVED')"), {'id': uuid4()})
    with pytest.raises(Exception, match="archived"):
        run_sql(database, "seed_item_categories.sql")
    with database[2].connect() as conn:
        assert conn.execute(text("SELECT name,status FROM item_category")).all() == [('Fruit', 'ARCHIVED')]


@pytest.mark.postgres
def test_category_tool_returns_real_ids_with_guidance(database, monkeypatch):
    from app.agents import tools
    run_sql(database, "seed_item_categories.sql")
    async def scenario(client, sessions):
        monkeypatch.setattr(tools, "AsyncSessionFactory", sessions)
        runtime = SimpleNamespace(context=SimpleNamespace(user_id=uuid4()))
        result = json.loads(await tools.list_item_categories.coroutine(runtime, page=1))
        assert result['total'] == 25
        async with sessions() as session:
            ids = {str(i) for i in (await session.execute(text("SELECT id FROM item_category"))).scalars()}
        assert {i['id'] for i in result['items']} == ids
        assert all(i['description'] and i['examples'] and i['exclusions'] for i in result['items'])
    asyncio.run(exercise(database, scenario))


@pytest.mark.postgres
def test_category_ambiguity_correction_and_invalid_categories(inventory_context):
    from langgraph.store.memory import InMemoryStore
    from app.agents.memory import MemoryService
    from app.schemas.agent_actions import ActionDraft
    from app.services.agent_actions import prepare_action, execute_action, PreparationError
    c = inventory_context
    run_sql(c[0], "seed_item_categories.sql")
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        async with sessions() as session:
            cats = dict((await session.execute(text("SELECT name,id FROM item_category"))).all())
            action = ActionDraft(item_key='new', original_text='add coconut milk', action='CREATE_STOCK',
                quantity_value='1', quantity_unit='can', storage_space_id=c[4].id,
                clarification_question='Is this for drinking or cooking?',
                new_definition={'name': 'Coconut milk', 'category_id': cats['Milk & Plant-Based Milk']})
            with pytest.raises(PreparationError, match='drinking or cooking'):
                await prepare_action(session, c[1].id, action, memory)
        async with sessions() as session:
            action.clarification_question = None
            action.new_definition.category_id = cats['Sauces, Condiments & Spreads']
            revised = await prepare_action(session, c[1].id, action, memory)
            assert not revised['requires_confirmation']
            assert revised['display']['category_name'] == 'Sauces, Condiments & Spreads'
            result = await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), revised, memory)
            assert result['inventory']['category_id'] == str(cats['Sauces, Condiments & Spreads'])
        for invalid in (uuid4(), cats['Other']):
            async with sessions() as session:
                await session.execute(text("UPDATE item_category SET status='ARCHIVED' WHERE name='Other'"))
                action.new_definition.category_id = invalid
                with pytest.raises(PreparationError, match='active existing category'):
                    await prepare_action(session, c[1].id, action, memory)
                await session.rollback()
    asyncio.run(exercise(c[0], scenario))
