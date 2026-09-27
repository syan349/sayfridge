"""Synthetic image fixtures; no personal receipts or production inventory."""
import base64
import io
from uuid import uuid4

from PIL import Image, ImageDraw

from app.schemas.agent_media import AgentImage


def image_input(label="MILK  2 bottles  500 ml each", *, image_id=None, format="PNG"):
    picture = Image.new("RGB", (900, 400), "white")
    ImageDraw.Draw(picture).text((30, 40), label, fill="black", font_size=28, spacing=20)
    data = io.BytesIO()
    picture.save(data, format=format)
    return AgentImage(image_id=image_id or uuid4(), mime_type=Image.MIME[format],
                      data_base64=base64.b64encode(data.getvalue()).decode())
