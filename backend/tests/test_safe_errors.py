import asyncio
import logging

import httpx
import pytest
from fastapi.middleware.cors import CORSMiddleware
from pydantic import ValidationError

from app.agents.model import AgentModelSettings
from app.core.config import Settings
from app.middleware.safe_errors import SafeErrorsMiddleware

pytestmark = pytest.mark.ci


@pytest.mark.parametrize('streaming', [False, True])
def test_exception_details_never_reach_logs_or_response(caplog, streaming):
    secret = 'PRIVATE_PASSWORD_JWT_API_KEY_DATABASE_URL_AND_BODY'

    async def failing(scope, receive, send):
        if streaming:
            await send({'type': 'http.response.start', 'status': 200, 'headers': []})
            await send({'type': 'http.response.body', 'body': b'public', 'more_body': True})
        raise RuntimeError(secret)

    app = CORSMiddleware(SafeErrorsMiddleware(failing), allow_origins=['http://localhost:5173'])

    async def run():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test') as client:
            return await client.get('/', headers={'Origin': 'http://localhost:5173'})

    with caplog.at_level(logging.ERROR):
        response = asyncio.run(run())
    assert response.status_code == (200 if streaming else 500)
    assert response.headers['access-control-allow-origin'] == 'http://localhost:5173'
    assert secret not in response.text + caplog.text
    assert 'RuntimeError' in caplog.text
    if not streaming:
        assert response.json()['detail']['error_id'] in caplog.text


@pytest.mark.parametrize('model,values', [
    (Settings, {'DATABASE_URL': 'PRIVATE_SENTINEL', 'DATABASE_URL_DIRECT': 'PRIVATE_SENTINEL', 'JWT_SECRET_KEY': 'short'}),
    (AgentModelSettings, {'AGENT_MODEL': 'model', 'AGENT_API_BASE': 'https://example.com', 'AGENT_API_KEY': 'key', 'AGENT_TIMEOUT_SECONDS': 'PRIVATE_SENTINEL'}),
])
def test_settings_validation_does_not_print_input(model, values):
    with pytest.raises(ValidationError) as error:
        model(_env_file=None, **values)
    assert 'PRIVATE_SENTINEL' not in str(error.value)
