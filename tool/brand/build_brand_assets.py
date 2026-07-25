#!/usr/bin/env python3
"""Build every antiQ platform asset from one transparent master mark.

Run with a Python environment that has Pillow installed:
  python tool/brand/build_brand_assets.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
BRAND = ROOT / 'assets' / 'brand'
MASTER_MARK = BRAND / 'antiq-mark.png'
FONT = Path('/System/Library/Fonts/SFNS.ttf')

DARK = (7, 9, 13, 255)
LIGHT = (246, 249, 252, 255)
INK = (9, 11, 16, 255)
CYAN = (69, 215, 232, 255)


def recolor_mark(source: Image.Image, foreground: tuple[int, int, int, int]) -> Image.Image:
    image = source.convert('RGBA')
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                continue
            is_cyan = red < 100 and green > 130 and blue > 150
            clean_alpha = 255 if alpha >= 80 else alpha
            pixels[x, y] = (
                CYAN[:3] + (clean_alpha,)
                if is_cyan
                else foreground[:3] + (clean_alpha,)
            )
    return image


def fitted_mark(mark: Image.Image, size: int, coverage: float = 0.68) -> Image.Image:
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    target = int(size * coverage)
    resized = mark.copy()
    resized.thumbnail((target, target), Image.Resampling.LANCZOS)
    position = ((size - resized.width) // 2, (size - resized.height) // 2)
    canvas.alpha_composite(resized, position)
    return canvas


def app_icon(mark: Image.Image, size: int, coverage: float = 0.68) -> Image.Image:
    canvas = Image.new('RGBA', (size, size), DARK)
    canvas.alpha_composite(fitted_mark(mark, size, coverage))
    return canvas.convert('RGB')


def save_icon(path: Path, mark: Image.Image, size: int, coverage: float = 0.68) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    app_icon(mark, size, coverage).save(path, optimize=True)


def save_foreground(path: Path, mark: Image.Image, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fitted_mark(mark, size, 0.58).save(path, optimize=True)


def font(size: int):
    if FONT.exists():
        return ImageFont.truetype(str(FONT), size)
    return ImageFont.load_default()


def splash_lockup(mark: Image.Image, foreground, filename: str) -> None:
    canvas = Image.new('RGBA', (900, 360), (0, 0, 0, 0))
    symbol = fitted_mark(mark, 240, 0.82)
    canvas.alpha_composite(symbol, (40, 60))
    draw = ImageDraw.Draw(canvas)
    draw.text(
        (294, 122),
        'antiQ',
        font=font(116),
        fill=foreground,
        anchor='la',
    )
    output = BRAND / filename
    canvas.save(output, optimize=True)


def main() -> None:
    source = Image.open(MASTER_MARK).convert('RGBA')
    dark_mark = recolor_mark(source, INK)
    light_mark = recolor_mark(source, LIGHT)
    dark_mark.save(BRAND / 'antiq-mark-dark.png', optimize=True)
    light_mark.save(BRAND / 'antiq-mark-light.png', optimize=True)
    save_icon(BRAND / 'antiq-app-icon.png', light_mark, 1024)
    splash_lockup(dark_mark, INK, 'antiq-splash-light.png')
    splash_lockup(light_mark, LIGHT, 'antiq-splash-dark.png')

    android_sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }
    for folder, size in android_sizes.items():
        base = ROOT / 'android' / 'app' / 'src' / 'main' / 'res' / folder
        save_icon(base / 'ic_launcher.png', light_mark, size)
        save_icon(base / 'ic_launcher_round.png', light_mark, size)
        save_foreground(base / 'ic_launcher_foreground.png', light_mark, size * 2)

    ios_icon_dir = ROOT / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
    ios_sizes = {
        'Icon-App-20x20@1x.png': 20,
        'Icon-App-20x20@2x.png': 40,
        'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29,
        'Icon-App-29x29@2x.png': 58,
        'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40,
        'Icon-App-40x40@2x.png': 80,
        'Icon-App-40x40@3x.png': 120,
        'Icon-App-60x60@2x.png': 120,
        'Icon-App-60x60@3x.png': 180,
        'Icon-App-76x76@1x.png': 76,
        'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167,
        'Icon-App-1024x1024@1x.png': 1024,
    }
    for filename, size in ios_sizes.items():
        save_icon(ios_icon_dir / filename, light_mark, size)

    mac_icon_dir = ROOT / 'macos' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save_icon(mac_icon_dir / f'app_icon_{size}.png', light_mark, size)

    web_icon_dir = ROOT / 'web' / 'icons'
    save_icon(web_icon_dir / 'Icon-192.png', light_mark, 192)
    save_icon(web_icon_dir / 'Icon-512.png', light_mark, 512)
    save_icon(web_icon_dir / 'Icon-maskable-192.png', light_mark, 192, 0.56)
    save_icon(web_icon_dir / 'Icon-maskable-512.png', light_mark, 512, 0.56)
    save_icon(ROOT / 'web' / 'favicon.png', light_mark, 64)

    windows_icon = app_icon(light_mark, 256)
    windows_path = ROOT / 'windows' / 'runner' / 'resources' / 'app_icon.ico'
    windows_icon.save(windows_path, sizes=[(16, 16), (32, 32), (48, 48), (256, 256)])

    launch_dir = ROOT / 'ios' / 'Runner' / 'Assets.xcassets' / 'LaunchImage.imageset'
    light_lockup = Image.open(BRAND / 'antiq-splash-light.png')
    for suffix, width in (('', 300), ('@2x', 600), ('@3x', 900)):
        resized = light_lockup.resize((width, int(width * 0.4)), Image.Resampling.LANCZOS)
        resized.save(launch_dir / f'LaunchImage{suffix}.png', optimize=True)
    dark_lockup = Image.open(BRAND / 'antiq-splash-dark.png')
    for suffix, width in (('', 300), ('@2x', 600), ('@3x', 900)):
        resized = dark_lockup.resize((width, int(width * 0.4)), Image.Resampling.LANCZOS)
        resized.save(launch_dir / f'LaunchImageDark{suffix}.png', optimize=True)

    android_drawable = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
    (android_drawable / 'drawable-nodpi').mkdir(parents=True, exist_ok=True)
    (android_drawable / 'drawable-night-nodpi').mkdir(parents=True, exist_ok=True)
    light_lockup.resize((600, 240), Image.Resampling.LANCZOS).save(
        android_drawable / 'drawable-nodpi' / 'antiq_splash.png',
        optimize=True,
    )
    dark_lockup.resize((600, 240), Image.Resampling.LANCZOS).save(
        android_drawable / 'drawable-night-nodpi' / 'antiq_splash.png',
        optimize=True,
    )

    print('antiQ brand assets generated successfully.')


if __name__ == '__main__':
    main()
