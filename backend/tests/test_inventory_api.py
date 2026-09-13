"""Inventory contracts, isolation, quantity preservation, and failure cases."""
import asyncio
from datetime import date, datetime, timezone
from decimal import Decimal
import uuid

import pytest
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.db.models import InventoryItem, InventoryOperation, ItemCategory, ItemDefinition, StorageSpace
from auth_test_support import exercise, request
from inventory_test_support import inventory_context, seed_space, seed_inventory, payload, BASE

pytestmark = pytest.mark.postgres


@pytest.mark.ci
def test_stock_entry_and_metadata_lifecycle_preserves_quantities_and_has_no_history(inventory_context):
    c = inventory_context
    target = seed_space(c[0], c[1].id, "Pantry")
    async def scenario(client, sessions):
        created = await client.post(BASE, json=payload(c, unit=" KG ", purchase_date="2026-02-02", expiry_date="2026-01-01", notes="First"), headers=c[-1])
        assert created.status_code == 201, created.text
        first = created.json()
        assert first["initial_unit"] == first["confirmed_current_unit"] == "kg"
        assert Decimal(first["display_amount"]) == Decimal("2.5") and not first["is_estimated"]
        assert first["version"] == 1 and first["estimated_current_amount"] is None
        assert first["category_name"] == "Food" and first["storage_space_name"] == "Kitchen"
        assert "owner_user_id" not in first and "user_id" not in first
        url = BASE + "/" + first["id"]
        body = {"expected_version": 1, "notes": None, "purchase_date": None, "storage_space_id": str(target.id)}
        edited = await client.patch(url, json=body, headers=c[-1])
        assert edited.status_code == 200, edited.text
        changed = edited.json()
        assert changed["version"] == 2 and changed["notes"] is None and changed["purchase_date"] is None
        assert changed["storage_space_name"] == "Pantry"
        for key in ("initial_amount", "initial_unit", "confirmed_current_amount", "confirmed_current_unit", "confirmed_at", "estimated_at", "estimated_current_amount"):
            assert changed[key] == first[key]
        stale = await client.patch(url, json=body, headers=c[-1])
        assert stale.status_code == 409 and stale.json()["detail"]["code"] == "VERSION_CONFLICT"
        body["expected_version"] = 2
        assert (await client.patch(url, json=body, headers=c[-1])).json() == changed
        assert (await client.get(url, headers=c[-1])).json() == changed
        async with sessions() as session:
            assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 0
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 1
    asyncio.run(exercise(c[0], scenario))


@pytest.mark.ci
def test_inventory_list_visibility_filters_dates_order_and_empty_page(inventory_context):
    c=inventory_context
    first=seed_inventory(c, expiry_date=date(2026,1,1), purchase_date=date(2025,12,1))
    second=seed_inventory(c, expiry_date=date(2026,2,1))
    last=seed_inventory(c)
    empty=seed_inventory(c, status="EMPTY", confirmed_current_amount=Decimal("0"))
    other_space=seed_space(c[0], c[2].id)
    seed_inventory(c, storage_space_id=other_space.id)
    def get(query=""):
        response=request(c[0], "GET", BASE+query, headers=c[-1])
        assert response.status_code==200, response.text
        return response.json()
    assert [row["id"] for row in get()["items"]]==[str(first.id),str(second.id),str(last.id)]
    assert get("?status=ALL")["total"]==4
    assert get("?status=EMPTY")["items"][0]["id"]==str(empty.id)
    assert get("?page=99")["items"]==[] and get("?page=99")["total"]==3
    assert get("?expiry_from=2026-01-01&expiry_to=2026-01-01")["total"]==1
    assert get("?purchase_from=2025-12-01&purchase_to=2025-12-01")["total"]==1
    assert get("?storage_space_id="+str(other_space.id))["total"]==0
    assert get("?category_id="+str(c[3].id))["total"]==3
    assert get("?category_id="+str(uuid.uuid4()))["total"]==0
    assert get("?q=rice")["total"]==3
    assert get("?q=%25")["total"]==0
    assert get("?q=_")["total"]==0


@pytest.mark.ci
def test_archived_associations_remain_readable_with_zero_estimate_and_current_names(inventory_context):
    c=inventory_context
    item=seed_inventory(c, estimated_current_amount=Decimal("0"), estimated_current_unit="kg", estimated_at=datetime.now(timezone.utc))
    with Session(c[0][2]) as session:
        session.execute(update(StorageSpace).where(StorageSpace.id==c[4].id).values(status="ARCHIVED",name="Old fridge"))
        session.execute(update(ItemDefinition).where(ItemDefinition.id==c[5].id).values(status="ARCHIVED",name="New rice"))
        session.execute(update(ItemCategory).where(ItemCategory.id==c[3].id).values(status="ARCHIVED"))
        session.commit()
    response=request(c[0],"GET",BASE+"/"+str(item.id),headers=c[-1])
    assert response.status_code==200
    body=response.json()
    assert body["is_estimated"] and Decimal(body["display_amount"])==0
    assert body["item_definition_name"]=="New rice" and body["storage_space_name"]=="Old fridge"
    assert request(c[0],"GET",BASE,headers=c[-1]).json()["total"]==1


@pytest.mark.parametrize("method", ["GET", pytest.param("PATCH",marks=pytest.mark.ci)])
def test_foreign_and_missing_inventory_are_indistinguishable(inventory_context,method):
    c=inventory_context
    space=seed_space(c[0],c[2].id)
    row=seed_inventory(c,storage_space_id=space.id)
    responses=[request(c[0],method,BASE+"/"+str(id),json={"expected_version":1,"notes":"x"} if method=="PATCH" else None,headers=c[-1]) for id in (row.id,uuid.uuid4())]
    assert all(r.status_code==404 for r in responses)
    assert responses[0].json()==responses[1].json()


@pytest.mark.parametrize("amount", ["0","-1","1.0001","1e2","NaN","Infinity","1000000000"," 1 ",1,True,None,".5"])
def test_invalid_stock_amount_creates_nothing(inventory_context,amount):
    c=inventory_context
    response=request(c[0],"POST",BASE,json=payload(c,amount=amount),headers=c[-1])
    assert response.status_code==422, response.text
    assert response.json()["detail"]["code"]=="VALIDATION_ERROR"
    with Session(c[0][2]) as session:
        assert session.scalar(select(func.count()).select_from(InventoryItem))==0


@pytest.mark.parametrize("changes", [{"unit":""},{"unit":" "},{"unit":"x"*17},{"notes":"x"*1001},{"status":"EMPTY"},{"user_id":str(uuid.uuid4())},{"purchase_date":"2026-02-30"},{"storage_space_id":None}])
def test_invalid_stock_fields_are_rejected(inventory_context,changes):
    c=inventory_context
    assert request(c[0],"POST",BASE,json=payload(c,**changes),headers=c[-1]).status_code==422


@pytest.mark.parametrize("kind", [pytest.param("space",marks=pytest.mark.ci),"category","definition","foreign_space","foreign_definition","missing_space","missing_definition"])
def test_stock_entry_requires_owned_active_visible_associations(inventory_context,kind):
    c=inventory_context
    values=payload(c)
    expected=409
    with Session(c[0][2]) as session:
        if kind in {"space","category","definition"}:
            model,id={"space":(StorageSpace,c[4].id),"category":(ItemCategory,c[3].id),"definition":(ItemDefinition,c[5].id)}[kind]
            session.execute(update(model).where(model.id==id).values(status="ARCHIVED"))
        elif kind=="foreign_space":
            session.execute(update(StorageSpace).where(StorageSpace.id==c[4].id).values(user_id=c[2].id));expected=404
        elif kind=="foreign_definition":
            session.execute(update(ItemDefinition).where(ItemDefinition.id==c[5].id).values(owner_user_id=c[2].id));expected=404
        else:
            values["storage_space_id" if kind=="missing_space" else "item_definition_id"]=str(uuid.uuid4());expected=404
        session.commit()
    assert request(c[0],"POST",BASE,json=values,headers=c[-1]).status_code==expected
    with Session(c[0][2]) as session:
        assert session.scalar(select(func.count()).select_from(InventoryItem))==0


@pytest.mark.parametrize("changes", [{},{"expected_version":1},{"expected_version":None,"notes":"x"},{"expected_version":True,"notes":"x"},{"expected_version":0,"notes":"x"},{"expected_version":2147483648,"notes":"x"},{"expected_version":1,"storage_space_id":None},{"expected_version":1,"amount":"3"},{"expected_version":1,"item_definition_id":str(uuid.uuid4())},{"expected_version":1,"status":"EMPTY"},{"expected_version":1,"notes":"x"*1001}])
def test_patch_rejects_invalid_or_immutable_fields(inventory_context,changes):
    c=inventory_context;item=seed_inventory(c)
    assert request(c[0],"PATCH",BASE+"/"+str(item.id),json=changes,headers=c[-1]).status_code==422
    with Session(c[0][2]) as session:
        assert session.get(InventoryItem,item.id).version==1


@pytest.mark.parametrize("state",["DISCARDED","ARCHIVED"])
def test_terminal_inventory_is_readable_but_not_editable(inventory_context,state):
    c=inventory_context;row=seed_inventory(c,status=state)
    url=BASE+"/"+str(row.id)
    assert request(c[0],"GET",url,headers=c[-1]).status_code==200
    assert request(c[0],"PATCH",url,json={"expected_version":1,"notes":"x"},headers=c[-1]).status_code==409


@pytest.mark.ci
def test_empty_inventory_can_leave_archived_space_but_cannot_move_to_foreign_or_archived_target(inventory_context):
    c=inventory_context;row=seed_inventory(c,status="EMPTY",confirmed_current_amount=Decimal("0"))
    foreign=seed_space(c[0],c[2].id)
    archived=seed_space(c[0],c[1].id,"Archived","ARCHIVED")
    target=seed_space(c[0],c[1].id,"Target")
    with Session(c[0][2]) as session:
        session.execute(update(StorageSpace).where(StorageSpace.id==c[4].id).values(status="ARCHIVED"));session.commit()
    for destination,expected in ((foreign,404),(archived,409),(target,200)):
        response=request(c[0],"PATCH",BASE+"/"+str(row.id),json={"expected_version":1,"storage_space_id":str(destination.id),"notes":"moved"},headers=c[-1])
        assert response.status_code==expected,response.text
    assert response.json()["version"]==2


@pytest.mark.parametrize("query",["status=BAD","page=0","page_size=101","purchase_from=2026-02-01&purchase_to=2026-01-01","expiry_from=2026-02-01&expiry_to=2026-01-01","category_id=bad","q="+"x"*101,"unknown=1"])
def test_invalid_inventory_queries_return_safe_validation_errors(inventory_context,query):
    c=inventory_context
    response=request(c[0],"GET",BASE+"?"+query,headers=c[-1])
    assert response.status_code==422 and response.json()["detail"]["code"]=="VALIDATION_ERROR"


@pytest.mark.parametrize("method,path,body",[("GET","",None),("POST","",{}),("GET","/"+str(uuid.uuid4()),None),("PATCH","/"+str(uuid.uuid4()),{"expected_version":1,"notes":"x"})])
def test_inventory_endpoints_require_authentication(inventory_context,method,path,body):
    assert request(inventory_context[0],method,BASE+path,json=body).status_code==401


def test_version_limit_allows_noop_but_rejects_changes(inventory_context):
    c=inventory_context;row=seed_inventory(c,version=2147483647,notes="same")
    url=BASE+"/"+str(row.id)
    assert request(c[0],"PATCH",url,json={"expected_version":2147483647,"notes":"same"},headers=c[-1]).status_code==200
    response=request(c[0],"PATCH",url,json={"expected_version":2147483647,"notes":"changed"},headers=c[-1])
    assert response.status_code==409 and response.json()["detail"]["code"]=="VERSION_LIMIT_REACHED"


@pytest.mark.parametrize("amount,unit", [("0.001","each"),("999999999.999"," ML "),("0002.500","custom")])
def test_valid_quantity_boundaries_and_literal_units(inventory_context,amount,unit):
    c=inventory_context
    response=request(c[0],"POST",BASE,json=payload(c,amount=amount,unit=unit),headers=c[-1])
    assert response.status_code==201,response.text
    assert Decimal(response.json()["initial_amount"])==Decimal(amount)
    assert response.json()["initial_unit"]==unit.strip().casefold()


@pytest.mark.parametrize("value", [0,"2026-01-01T00:00:00Z","20260101"])
def test_stock_dates_reject_timestamps_and_non_calendar_syntax(inventory_context,value):
    c=inventory_context
    response=request(c[0],"POST",BASE,json=payload(c,purchase_date=value),headers=c[-1])
    assert response.status_code==422


def test_stock_can_use_owned_private_definition_and_clear_expiry(inventory_context):
    c=inventory_context
    with Session(c[0][2]) as session:
        session.execute(update(ItemDefinition).where(ItemDefinition.id==c[5].id).values(owner_user_id=c[1].id));session.commit()
    created=request(c[0],"POST",BASE,json=payload(c,expiry_date="2026-01-01"),headers=c[-1])
    assert created.status_code==201
    result=request(c[0],"PATCH",BASE+"/"+created.json()["id"],json={"expected_version":1,"expiry_date":None},headers=c[-1])
    assert result.status_code==200 and result.json()["expiry_date"] is None
