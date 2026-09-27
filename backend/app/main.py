from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.api.routes.auth import router as auth_router
from app.api.routes.storage_spaces import (
    router as storage_spaces_router,
    storage_space_error_handler,
)
from app.services.storage_spaces import StorageSpaceError
from app.api.routes.catalog import router as catalog_router, catalog_error_handler
from app.services.catalog import CatalogError

from app.api.routes.inventory import router as inventory_router, inventory_error_handler
from app.api.routes.inventory_operations import router as inventory_operations_router
from app.services.inventory import InventoryError
from app.api.routes.admin import router as admin_router, admin_error_handler
from app.services.admin import AdminError
from app.agents.persistence import close_agent_resources
from app.api.routes.agent import router as agent_router
from app.agents.request_limits import AgentBodyLimitMiddleware


@asynccontextmanager
async def lifespan(_: FastAPI):
    try:
        yield
    finally:
        await close_agent_resources()


app = FastAPI(title="SayFridge Backend", lifespan=lifespan)
app.add_middleware(AgentBodyLimitMiddleware)
app.include_router(auth_router)
app.include_router(storage_spaces_router)
app.include_router(catalog_router)
app.include_router(inventory_router)
app.include_router(inventory_operations_router)
app.include_router(admin_router)
app.include_router(agent_router)
app.add_exception_handler(InventoryError, inventory_error_handler)
app.add_exception_handler(CatalogError, catalog_error_handler)
app.add_exception_handler(StorageSpaceError, storage_space_error_handler)
app.add_exception_handler(AdminError, admin_error_handler)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "sayfridge-backend"}


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
    """Use business validation errors for business routes while preserving authentication errors."""
    if any(request.url.path == prefix or request.url.path.startswith(prefix + "/")
           for prefix in ("/api/v1/storage-spaces", "/api/v1/item-categories", "/api/v1/item-definitions",
                          "/api/v1/inventory-items", "/api/v1/inventory-operations",
                          "/api/v1/admin")):
        errors = [{"loc": error["loc"], "msg": error["msg"]} for error in exc.errors()]
        detail = {
            "code": "VALIDATION_ERROR",
            "message": "Invalid request parameters",
            "errors": errors,
        }
        if request.url.path in {
            "/api/v1/inventory-items/batch-create",
            "/api/v1/inventory-items/batch-move",
            "/api/v1/inventory-items/batch-archive",
        } and errors:
            item_index = next((part for part in errors[0]["loc"] if isinstance(part, int)), None)
            if item_index is not None:
                detail["item_index"] = item_index
        return JSONResponse(status_code=422, content={"detail": detail})
    return JSONResponse(
        status_code=422,
        content={"detail": [
            {key: error[key] for key in ("type", "loc", "msg") if key in error}
            for error in exc.errors()
        ]},
    )
