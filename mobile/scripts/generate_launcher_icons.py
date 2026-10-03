"""Package the existing SayFridge artwork as Android launcher resources.

Run with Python + Pillow from any directory. This does not redraw the brand asset.
"""
from pathlib import Path
from PIL import Image
from generate_item_artwork_palette import background

ROOT = Path(__file__).resolve().parents[1]
ARTWORK = ROOT / 'assets/launcher/launcher_avatar.png'
RES = ROOT / 'android/app/src/main/res'
# Match the green inside the source artwork's circle, including launcher corners.
BACKGROUND = f'#{background(ARTWORK)}'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def generate():
    source = Image.open(ARTWORK).convert('RGBA')
    (RES / 'values' / 'launcher_colors.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        f'    <color name="ic_launcher_background">{BACKGROUND}</color>\n'
        '</resources>\n',
        encoding='utf-8',
    )
    for density, scale in DENSITIES.items():
        directory = RES / f'mipmap-{density}'
        directory.mkdir(parents=True, exist_ok=True)
        size = round(48 * scale)
        legacy = Image.new('RGBA', (size, size), BACKGROUND)
        legacy.alpha_composite(source.resize((size, size), Image.Resampling.LANCZOS))
        legacy.convert('RGB').save(directory / 'ic_launcher.png')

        # Adaptive layers are 108dp; keep the mascot inside the central safe area.
        layer_size = round(108 * scale)
        artwork_size = round(84 * scale)
        foreground = Image.new('RGBA', (layer_size, layer_size))
        offset = (layer_size - artwork_size) // 2
        foreground.alpha_composite(
            source.resize((artwork_size, artwork_size), Image.Resampling.LANCZOS),
            (offset, offset),
        )
        foreground.save(directory / 'ic_launcher_foreground.png')


if __name__ == '__main__':
    generate()
    print('Generated Android launcher icons from existing SayFridge artwork.')
