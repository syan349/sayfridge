from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
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
from app.core.config import Settings, get_settings
from app.schemas.system import HealthResponse, VersionResponse


OPENAPI_TAGS = [
    {
        "name": "system",
        "description": "Public service health and deployed-version metadata.",
    },
    {
        "name": "auth",
        "description": "Local account registration, login, and current identity.",
    },
    {
        "name": "storage-spaces",
        "description": "Authenticated storage-space lifecycle for the current user.",
    },
    {
        "name": "catalog",
        "description": "Public categories plus public and user-owned item definitions.",
    },
    {
        "name": "inventory",
        "description": "User-owned stock, batch actions, quantities, expiry, and history.",
    },
    {
        "name": "admin",
        "description": "Administrator-only account inspection and status management.",
    },
    {
        "name": "agent",
        "description": "Authenticated AI assistant streaming and recovery endpoints.",
    },
]


@asynccontextmanager
async def lifespan(_: FastAPI):
    try:
        yield
    finally:
        await close_agent_resources()


settings = get_settings()
app = FastAPI(
    title="SayFridge Backend",
    version=settings.app_version,
    description=(
        "SayFridge REST API. Use **Authorize** with a Bearer token returned by "
        "`POST /api/v1/auth/login` for protected endpoints."
    ),
    openapi_tags=OPENAPI_TAGS,
    lifespan=lifespan,
)
app.add_middleware(AgentBodyLimitMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PATCH", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
)
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


@app.get(
    "/health",
    response_model=HealthResponse,
    tags=["system"],
    summary="Check service health",
    description="Confirm that the API process is running. This does not query the database.",
)
async def health() -> HealthResponse:
    return HealthResponse(status="ok", service="sayfridge-backend")


@app.get(
    "/api/v1/system/version",
    response_model=VersionResponse,
    tags=["system"],
    summary="Read deployed backend version",
    description=(
        "Return the configured application version and deployed Git commit SHA. "
        "The commit is null when the deployment provider did not supply one."
    ),
)
async def version(current: Settings = Depends(get_settings)) -> VersionResponse:
    return VersionResponse(
        service="sayfridge-backend",
        version=current.app_version,
        commit_sha=current.app_commit_sha,
    )


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
