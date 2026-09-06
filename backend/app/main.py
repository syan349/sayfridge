from fastapi import FastAPI

from app.api.routes.auth import router as auth_router

app = FastAPI(title="SayFridge Backend")
app.include_router(auth_router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "sayfridge-backend"}
