"""Bounded, validated inline images shared by chat and item replies."""
import base64
import binascii
import hashlib
import io
import warnings
from typing import Literal
from uuid import UUID

from PIL import Image, ImageOps
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
    _safe_base64: str = PrivateAttr(default="")
    _safe_size: int = PrivateAttr(default=0)

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
                    # Correct camera orientation before removing metadata. Copy only
                    # pixels so EXIF/GPS, XMP, comments and trailing data cannot pass
                    # into model messages or their persisted checkpoints.
                    oriented = ImageOps.exif_transpose(picture)
                    mode = "RGBA" if "A" in oriented.getbands() or "transparency" in oriented.info else "RGB"
                    if self.mime_type == "image/jpeg":
                        mode = "RGB"
                    pixels = oriented.convert(mode)
                    clean = Image.frombytes(mode, pixels.size, pixels.tobytes())
                    output = io.BytesIO()
                    clean.save(output, format=picture.format)
                    safe = output.getvalue()
                    if len(safe) > MAX_IMAGE_BYTES:
                        raise PydanticCustomError("IMAGE_TOO_LARGE", "Sanitized image exceeds 3 MiB")
                    self._safe_base64 = base64.b64encode(safe).decode("ascii")
                    self._safe_size = len(safe)
        except PydanticCustomError:
            raise
        except Exception:
            raise PydanticCustomError("INVALID_IMAGE", "Image cannot be decoded safely") from None
        self._size, self._digest = len(raw), hashlib.sha256(raw).hexdigest()
        return self

    def model_data_url(self):
        """Only decoded, metadata-free pixels may leave the request boundary."""
        return f"data:{self.mime_type};base64,{self._safe_base64}"

    def metadata(self):
        return {"image_id": str(self.image_id), "mime_type": self.mime_type,
                "sha256": self._digest, "size_bytes": self._size}


def validate_image_batch(images):
    if len(images) > 4 or sum(max(i._size, i._safe_size) for i in images) > MAX_TOTAL_BYTES:
        raise PydanticCustomError("IMAGE_BATCH_TOO_LARGE", "Send at most 4 images totaling at most 8 MiB")
    if len({i.image_id for i in images}) != len(images):
        raise PydanticCustomError("DUPLICATE_IMAGE_ID", "Image IDs must be unique within a request")

