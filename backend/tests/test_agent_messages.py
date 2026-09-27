import asyncio
import base64
import io
from uuid import uuid4

import httpx
import pytest
from PIL import Image
from pydantic import ValidationError

from app.agents.memory import fingerprint
from app.agents.messages import (human_message, user_text, image_catalog, chat_fingerprint,
                                 resume_fingerprint, validate_image_ids)
from app.agents.request_limits import AgentBodyLimitMiddleware
from app.schemas.agent import AgentChatRequest
from app.schemas.agent_actions import AgentResumeRequest
from app.schemas.agent_media import AgentImage, MAX_REQUEST_BYTES
from agent_image_support import image_input


def test_content_and_legacy_fingerprints():
    with pytest.raises(ValidationError):
        AgentChatRequest()
    text = AgentChatRequest(message="  hello  ")
    assert chat_fingerprint(text) == fingerprint({"message": "hello", "as_of": None})
    image = image_input()
    request = AgentChatRequest(images=[image])
    msg = human_message(request.message, request.images, "message-1")
    assert user_text(msg) == ""
    assert msg.content[1]["type"] == "image_url"
    assert image.data_base64 not in str(image_catalog([msg]))
    assert image_catalog([msg])[str(image.image_id)]["message_id"] == "message-1"
    changed = image_input("OTHER", image_id=image.image_id)
    assert chat_fingerprint(request) != chat_fingerprint(AgentChatRequest(images=[changed]))
    assert not validate_image_ids([changed], [msg])
    assert validate_image_ids([image], [msg])


@pytest.mark.parametrize("format", ["JPEG", "PNG", "WEBP"])
def test_supported_formats(format):
    assert image_input(format=format)._size > 0


def test_reject_corrupt_mismatched_animated_large_and_duplicate_images(monkeypatch):
    good = image_input()
    for values in ({"data_base64": "%%%"}, {"data_base64": base64.b64encode(b"not an image").decode()},
                   {"mime_type": "image/jpeg"}):
        with pytest.raises(ValidationError):
            AgentImage.model_validate({**good.model_dump(), **values})
    with pytest.raises(ValidationError):
        AgentChatRequest(images=[good, good])
    from app.schemas import agent_media
    monkeypatch.setattr(agent_media, "MAX_IMAGE_PIXELS", 100)
    with pytest.raises(ValidationError, match="IMAGE_DIMENSIONS_EXCEEDED"):
        AgentImage.model_validate(good.model_dump())
    monkeypatch.setattr(agent_media, "MAX_IMAGE_PIXELS", 20_000_000)
    data = io.BytesIO()
    Image.new("RGB", (10, 10), "red").save(data, format="PNG", save_all=True,
        append_images=[Image.new("RGB", (10, 10), "blue")])
    with pytest.raises(ValidationError, match="ANIMATED_IMAGE_NOT_SUPPORTED"):
        AgentImage(image_id=uuid4(), mime_type="image/png", data_base64=base64.b64encode(data.getvalue()).decode())


def test_resume_image_only_and_legacy_digest():
    original = {"conversation_id": str(uuid4()), "interrupt_id": "i", "request_id": str(uuid4()),
                "responses": [{"item_id": str(uuid4()), "proposal_id": str(uuid4()),
                               "decision": "answer", "message": "2 bottles", "selected_inventory_item_id": None}]}
    assert resume_fingerprint(AgentResumeRequest.model_validate(original)) == fingerprint(original)
    original["responses"][0].update(message=None, images=[image_input().model_dump()])
    assert AgentResumeRequest.model_validate(original).responses[0].images
    original["responses"][0]["decision"] = "confirm"
    with pytest.raises(ValidationError):
        AgentResumeRequest.model_validate(original)


def test_resume_aggregate_image_limits(monkeypatch):
    from app.schemas import agent_media
    image = image_input()
    monkeypatch.setattr(agent_media, "MAX_TOTAL_BYTES", image._size)
    with pytest.raises(ValidationError, match="IMAGE_BATCH_TOO_LARGE"):
        AgentChatRequest(images=[image, image_input("SECOND")])


def test_body_limit_checks_chunked_requests_before_app():
    called = []
    async def app(scope, receive, send):
        called.append(True)
    async def scenario():
        async def chunks():
            for _ in range(13):
                yield b"x" * (1024 * 1024)
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=AgentBodyLimitMiddleware(app)), base_url="http://test") as client:
            response = await client.post("/api/v1/agent/chat", content=chunks())
            assert response.status_code == 413
            assert response.json()["detail"]["code"] == "REQUEST_TOO_LARGE"
            response = await client.post("/api/v1/agent/resume", headers={"content-length": str(MAX_REQUEST_BYTES + 1)})
            assert response.status_code == 413
    asyncio.run(scenario())
    assert not called
