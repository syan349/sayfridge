"""Bound Agent JSON bodies before parsing, including chunked requests."""
from starlette.responses import JSONResponse

from app.schemas.agent_media import MAX_REQUEST_BYTES


class AgentBodyLimitMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope.get("method") != "POST" or scope.get("path") not in {
            "/api/v1/agent/chat", "/api/v1/agent/resume"
        }:
            return await self.app(scope, receive, send)
        async def reject():
            await JSONResponse(status_code=413, content={"detail": {
                "code": "REQUEST_TOO_LARGE", "message": "Agent requests must not exceed 12 MiB"
            }})(scope, receive, send)
        headers = dict(scope.get("headers", []))
        try:
            if int(headers.get(b"content-length", b"0")) > MAX_REQUEST_BYTES:
                return await reject()
        except ValueError:
            pass
        parts, size = [], 0
        while True:
            event = await receive()
            if event["type"] == "http.disconnect":
                return
            body = event.get("body", b"")
            size += len(body)
            if size > MAX_REQUEST_BYTES:
                return await reject()
            parts.append(body)
            if not event.get("more_body", False):
                break
        buffered = b"".join(parts)
        async def replay():
            nonlocal buffered
            if buffered is not None:
                body, buffered = buffered, None
                return {"type": "http.request", "body": body, "more_body": False}
            return await receive()
        await self.app(scope, replay, send)
