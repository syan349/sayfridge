"""Prevent unhandled request exceptions from exposing payloads through server logs."""
import logging
from uuid import uuid4

from starlette.responses import JSONResponse

logger = logging.getLogger(__name__)


class SafeErrorsMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http':
            return await self.app(scope, receive, send)
        started = finished = False

        async def tracked_send(message):
            nonlocal started, finished
            if message['type'] == 'http.response.start':
                started = True
            elif message['type'] == 'http.response.body' and not message.get('more_body', False):
                finished = True
            await send(message)

        try:
            await self.app(scope, receive, tracked_send)
        except Exception as exc:
            error_id = uuid4().hex
            # Never log str(exc), traceback, headers, URL/query or request body.
            logger.error('Request failed id=%s type=%s', error_id, type(exc).__name__)
            if not started:
                await JSONResponse(
                    status_code=500,
                    content={'detail': {'code': 'INTERNAL_ERROR',
                                        'message': 'Internal server error', 'error_id': error_id}},
                )(scope, receive, send)
            elif not finished:
                # Status/headers cannot change after a streaming response begins.
                await send({'type': 'http.response.body', 'body': b'', 'more_body': False})
