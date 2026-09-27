"""Bounded, validated inline images shared by chat and item replies."""
import base64
import binascii
import hashlib
import io
import warnings
from typing import Literal
from uuid import UUID

from PIL import Image
from pydantic import BaseModel, ConfigDict, Field, PrivateAttr, model_validator
from pydantic_core import PydanticCustomError

MAX_IMAGE_BYTES = 3 * 1024 * 1024
MAX_TOTAL_BYTES = 8 * 1024 * 1024
MAX_IMAGE_PIXELS = 20_000_000
MAX_REQUEST_BYTES = 12 * 1024 * 1024


class AgentImage(BaseModel):
    model_config = ConfigDict(extra="forbid")
    image_id: UUID
    mime_type: Literal["image/jpeg", "image/png", "image/webp"]
    data_base64: str = Field(max_length=4 * ((MAX_IMAGE_BYTES + 2) // 3), repr=False)
    _size: int = PrivateAttr(default=0)
    _digest: str = PrivateAttr(default="")

    @model_validator(mode="after")
    def validate_image(self):
        try:
            raw = base64.b64decode(self.data_base64, validate=True)
        except (ValueError, binascii.Error):
            raise PydanticCustomError("INVALID_IMAGE", "Invalid base64 image") from None
        if not raw or len(raw) > MAX_IMAGE_BYTES:
            raise PydanticCustomError("IMAGE_TOO_LARGE", "Image must be nonempty and at most 3 MiB")
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error", Image.DecompressionBombWarning)
                with Image.open(io.BytesIO(raw)) as picture:
                    if picture.width * picture.height > MAX_IMAGE_PIXELS:
                        raise PydanticCustomError("IMAGE_DIMENSIONS_EXCEEDED", "Image exceeds 20 million pixels")
                    if picture.format != {"image/jpeg": "JPEG", "image/png": "PNG", "image/webp": "WEBP"}[self.mime_type]:
                        raise PydanticCustomError("INVALID_IMAGE", "Image type does not match its contents")
                    if getattr(picture, "n_frames", 1) != 1:
                        raise PydanticCustomError("ANIMATED_IMAGE_NOT_SUPPORTED", "Send a still image")
                    picture.verify()
                with Image.open(io.BytesIO(raw)) as picture:
                    picture.load()
        except PydanticCustomError:
            raise
        except Exception:
            raise PydanticCustomError("INVALID_IMAGE", "Image cannot be decoded safely") from None
        self._size, self._digest = len(raw), hashlib.sha256(raw).hexdigest()
        return self

    def metadata(self):
        return {"image_id": str(self.image_id), "mime_type": self.mime_type,
                "sha256": self._digest, "size_bytes": self._size}


def validate_image_batch(images):
    if len(images) > 4 or sum(i._size for i in images) > MAX_TOTAL_BYTES:
        raise PydanticCustomError("IMAGE_BATCH_TOO_LARGE", "Send at most 4 images totaling at most 8 MiB")
    if len({i.image_id for i in images}) != len(images):
        raise PydanticCustomError("DUPLICATE_IMAGE_ID", "Image IDs must be unique within a request")

