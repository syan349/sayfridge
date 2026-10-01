"""ADD API acceptance against isolated real PostgreSQL."""
import asyncio
from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import select, func, update
from sqlalchemy.orm import Session

from app.db.models import InventoryItem, InventoryOperation, StorageSpace, ItemCategory, ItemDefinition
from auth_test_support import exercise, request
from inventory_test_support import inventory_context, seed_inventory, seed_space, BASE

pytestmark = pytest.mark.postgres


def addition(**changes):
    return dict(expected_version=1, operation_type="ADD", quantity_kind="AMOUNT",
                quantity_value="500", quantity_unit="g") | changes


def url(item):
    return f"{BASE}/{item.id}/operations"


def headers(context, key="addition-1"):
    return context[-1] | {"Idempotency-Key": key}


def send(context, item, key="addition-1", **changes):
    return request(context[0], "POST", url(item), json=addition(**changes), headers=headers(context,key))


def assert_unchanged(context, item):
    with Session(context[0][2]) as session:
        actual=session.get(InventoryItem,item.id)
        assert actual.version == item.version
        assert actual.confirmed_current_amount == item.confirmed_current_amount
        assert actual.estimated_current_amount == item.estimated_current_amount
        assert session.scalar(select(func.count()).select_from(InventoryOperation)) == 0


@pytest.mark.ci
def test_add_and_replay_preserve_history_and_return_current_inventory(inventory_context):
    c=inventory_context; item=seed_inventory(c)
    response=send(c,item,quantity_value="500.0",quantity_unit=" G ")
    assert response.status_code==201,response.text
    result=response.json(); op=result["operation"]; inv=result["inventory"]
    assert result["replayed"] is False and inv["version"]==2
    assert Decimal(inv["confirmed_current_amount"])==Decimal("3000.000")
    assert Decimal(inv["initial_amount"])==Decimal("2.5")
    assert op["quantity_value"]=="500.0" and op["quantity_unit"]=="G"
    assert op["input_method"]=="MANUAL" and op["status"]=="SUCCESS"
    assert op["calculation_method"]=="CONVERTED" and op["affects_state"]=="CONFIRMED"
    assert Decimal(op["applied_change_amount"])==Decimal("500") and op["applied_change_unit"]=="g"
    assert "idempotency_key" not in op
    with Session(c[0][2]) as session:
        session.execute(update(InventoryItem).where(InventoryItem.id==item.id).values(status="ARCHIVED",version=3,notes="later edit"))
        session.commit()
    replay=send(c,item,quantity_value="500.0",quantity_unit="G",expected_version=99)
    assert replay.status_code==200,replay.text
    assert replay.json()["operation"]==op and replay.json()["replayed"] is True
    assert replay.json()["inventory"]["version"]==3
    assert replay.json()["inventory"]["status"]=="ARCHIVED"
    with Session(c[0][2]) as session:
        assert session.scalar(select(func.count()).select_from(InventoryOperation))==1
        assert session.scalar(select(InventoryOperation.idempotency_key))==f"{c[1].id}:addition-1"


@pytest.mark.parametrize("estimate",[pytest.param("0",marks=[]),"1.5"])
def test_add_to_estimate_preserves_confirmed_and_initial_fields(inventory_context,estimate):
    c=inventory_context; now=datetime.now(timezone.utc)
    item=seed_inventory(c,estimated_current_amount=Decimal(estimate),estimated_current_unit="kg",estimated_at=now)
    response=send(c,item,quantity_value="0.5")
    assert response.status_code==201,response.text
    result=response.json()
    assert result["operation"]["affects_state"]=="ESTIMATED"
    assert Decimal(result["operation"]["applied_change_amount"])==Decimal("0.5")
    with Session(c[0][2]) as session:
        actual=session.get(InventoryItem,item.id)
        assert actual.estimated_current_amount==Decimal(estimate)*1000+Decimal("0.5")
        assert actual.estimated_at>now
        assert actual.confirmed_current_amount==item.confirmed_current_amount
        assert actual.confirmed_at==item.confirmed_at and actual.initial_amount==item.initial_amount
        assert actual.version==2 and actual.status=="IN_STOCK"


@pytest.mark.parametrize("state,space_state,expected",[
    ("EMPTY","ACTIVE",201),("EMPTY","ARCHIVED",409),
    ("DISCARDED","ACTIVE",409),("ARCHIVED","ACTIVE",409),
])
def test_add_state_and_space_rules(inventory_context,state,space_state,expected):
    c=inventory_context
    item=seed_inventory(c,status=state,confirmed_current_amount=Decimal("0") if state=="EMPTY" else Decimal("2.5"))
    with Session(c[0][2]) as session:
        session.execute(update(StorageSpace).where(StorageSpace.id==c[4].id).values(status=space_state));session.commit()
    response=send(c,item)
    assert response.status_code==expected,response.text
    if expected==201:
        assert response.json()["inventory"]["status"]=="IN_STOCK"
    else:
        assert response.json()["detail"]["code"]=="STATE_CONFLICT"
        assert_unchanged(c,item)


def test_archived_catalog_does_not_block_existing_stock(inventory_context):
    c=inventory_context;item=seed_inventory(c)
    with Session(c[0][2]) as session:
        session.execute(update(ItemDefinition).where(ItemDefinition.id==c[5].id).values(status="ARCHIVED"))
        session.execute(update(ItemCategory).where(ItemCategory.id==c[3].id).values(status="ARCHIVED"));session.commit()
    assert send(c,item).status_code==201


def test_authentication_ownership_and_header_validation(inventory_context):
    c=inventory_context;item=seed_inventory(c)
    assert request(c[0],"POST",url(item),json=addition(),headers={"Idempotency-Key":"x"}).status_code==401
    assert request(c[0],"POST",url(item),json=addition(),headers=c[-1]).status_code==422
    assert request(c[0],"POST",url(item),json=addition(),headers=headers(c,"a b")).status_code==422
    foreign=seed_space(c[0],c[2].id,"Foreign")
    with Session(c[0][2]) as session:
        session.execute(update(InventoryItem).where(InventoryItem.id==item.id).values(storage_space_id=foreign.id));session.commit()
    response=send(c,item)
    assert response.status_code==404 and response.json()["detail"]["code"]=="NOT_FOUND"
    assert request(c[0],"POST",f"{BASE}/{uuid4()}/operations",json=addition(),headers=headers(c)).status_code==404
    assert_unchanged(c,item)


@pytest.mark.parametrize("version,expected,code",[(2,1,"VERSION_CONFLICT"),(2147483647,2147483647,"VERSION_LIMIT_REACHED")])
def test_version_checks_do_not_write(inventory_context,version,expected,code):
    c=inventory_context;item=seed_inventory(c,version=version)
    response=send(c,item,expected_version=expected)
    assert response.status_code==409 and response.json()["detail"]["code"]==code
    assert_unchanged(c,item)


@pytest.mark.parametrize("value,unit,code", [("1", "ml", "UNIT_NOT_CONVERTIBLE")])
def test_calculation_errors_are_422_and_atomic(inventory_context,value,unit,code):
    c=inventory_context;item=seed_inventory(c)
    response=send(c,item,quantity_value=value,quantity_unit=unit)
    assert response.status_code==422,response.text
    assert response.json()["detail"]["code"]==code
    assert_unchanged(c,item)
    assert send(c,item).status_code==201  # A failed request does not reserve its key.


@pytest.mark.parametrize("change",[{"quantity_value":"500.0"},{"quantity_unit":"G"}])
def test_same_key_with_different_literal_input_conflicts(inventory_context,change):
    c=inventory_context;item=seed_inventory(c)
    assert send(c,item).status_code==201
    response=send(c,item,**change)
    assert response.status_code==409 and response.json()["detail"]["code"]=="IDEMPOTENCY_CONFLICT"


def test_same_user_key_cannot_be_reused_for_another_inventory(inventory_context):
    c=inventory_context;first=seed_inventory(c);second=seed_inventory(c)
    assert send(c,first).status_code==201
    assert send(c,second).json()["detail"]["code"]=="IDEMPOTENCY_CONFLICT"
    with Session(c[0][2]) as session:
        assert session.get(InventoryItem,second.id).version==1


def test_non_success_key_is_never_reapplied(inventory_context):
    c=inventory_context;item=seed_inventory(c)
    with Session(c[0][2]) as session:
        session.add(InventoryOperation(inventory_item_id=item.id,operation_type="ADD",quantity_kind="AMOUNT",
            quantity_value="500",quantity_unit="g",input_method="MANUAL",calculation_method="CONVERTED",
            affects_state="CONFIRMED",status="FAILED",idempotency_key=f"{c[1].id}:addition-1"));session.commit()
    response=send(c,item)
    assert response.status_code==409 and response.json()["detail"]["code"]=="IDEMPOTENCY_CONFLICT"
    with Session(c[0][2]) as session:
        assert session.get(InventoryItem,item.id).version==1


def test_invalid_body_returns_sanitized_validation_error(inventory_context):
    c=inventory_context;item=seed_inventory(c)
    response=send(c,item,quantity_value="1e2",affects_state="CONFIRMED")
    assert response.status_code==422 and response.json()["detail"]["code"]=="VALIDATION_ERROR"
    assert all(set(error) == {"loc", "msg"} for error in response.json()["detail"]["errors"])
    assert_unchanged(c,item)
