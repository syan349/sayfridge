from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.api.routes.auth import router as auth_router
from app.api.routes.storage_spaces import (
    router as storage_spaces_router,
    storage_space_error_handler,
)
from app.services.storage_spaces import StorageSpaceError

app = FastAPI(title="SayFridge Backend")
app.include_router(auth_router)
app.include_router(storage_spaces_router)
app.add_exception_handler(StorageSpaceError, storage_space_error_handler)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "sayfridge-backend"}


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
    """Use business validation errors for B04 while preserving authentication errors."""
    if request.url.path == "/api/v1/storage-spaces" or request.url.path.startswith("/api/v1/storage-spaces/"):
        return JSONResponse(status_code=422, content={"detail": {
            "code": "VALIDATION_ERROR",
            "message": "Invalid request parameters",
            "errors": [{"loc": error["loc"], "msg": error["msg"]} for error in exc.errors()],
        }})
    return JSONResponse(
        status_code=422,
        content={"detail": [
            {key: error[key] for key in ("type", "loc", "msg") if key in error}
            for error in exc.errors()
        ]},
    )
