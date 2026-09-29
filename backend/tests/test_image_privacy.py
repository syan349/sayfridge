"""Verify that metadata does not enter model-bound/persisted human messages."""
import base64
import hashlib
import io
from uuid import uuid4

import pytest
from PIL import Image, PngImagePlugin

from app.agents.messages import human_message, image_catalog, validate_image_ids
from app.schemas.agent_media import AgentImage

pytestmark = pytest.mark.ci


@pytest.mark.parametrize('format', ['JPEG', 'PNG', 'WEBP'])
def test_metadata_removed_before_model_and_checkpoint(format):
    image = Image.new('RGB', (20, 10), 'red')
    exif = Image.Exif()
    exif[270] = 'PRIVATE_PHOTO_DESCRIPTION'
    exif[315] = 'PRIVATE_PHOTOGRAPHER'
    exif[274] = 6
    output = io.BytesIO()
    options = {'exif': exif}
    if format == 'PNG':
        info = PngImagePlugin.PngInfo()
        info.add_text('Comment', 'PRIVATE_PNG_COMMENT')
        options['pnginfo'] = info
    image.save(output, format=format, **options)
    original = output.getvalue() + b'PRIVATE_TRAILING_DATA'
    incoming = AgentImage(image_id=uuid4(), mime_type=Image.MIME[format],
                          data_base64=base64.b64encode(original).decode())
    msg = human_message('look', [incoming], 'message')
    url = next(b['image_url']['url'] for b in msg.content if b['type'] == 'image_url')
    safe = base64.b64decode(url.split(',', 1)[1])
    assert b'PRIVATE_' not in safe
    with Image.open(io.BytesIO(safe)) as decoded:
        assert decoded.size == (10, 20)  # EXIF orientation preserved as pixels.
        assert not decoded.getexif()
        assert 'Comment' not in decoded.info
    assert incoming._digest == hashlib.sha256(original).hexdigest()
    assert image_catalog([msg])[str(incoming.image_id)]['sha256'] == incoming._digest
    # Keep original-byte identity so old retry fingerprints remain valid.
    retry = AgentImage.model_validate(incoming.model_dump())
    assert validate_image_ids([retry], [msg])
    assert retry.model_data_url() == incoming.model_data_url()


def test_png_transparency_is_preserved():
    original = Image.new('RGBA', (4, 4), (255, 0, 0, 0))
    output = io.BytesIO()
    original.save(output, format='PNG')
    image = AgentImage(image_id=uuid4(), mime_type='image/png',
                       data_base64=base64.b64encode(output.getvalue()).decode())
    with Image.open(io.BytesIO(base64.b64decode(image.model_data_url().split(',', 1)[1]))) as safe:
        assert safe.getpixel((0, 0))[3] == 0
