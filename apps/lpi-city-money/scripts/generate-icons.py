from pathlib import Path
import argparse
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError as exc:
    raise SystemExit("Install Pillow before generating icons: python -m pip install Pillow") from exc

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
ASSETS.mkdir(parents=True, exist_ok=True)

def load_font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        "C:/Windows/Fonts/seguisb.ttf",
        "C:/Windows/Fonts/segoeuib.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf",
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size=size)
    return ImageFont.load_default()

def draw_base(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pad = int(size * .035)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((pad, pad, size - pad - 1, size - pad - 1), radius=int(size * .24), fill=255)
    gradient = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = gradient.load()
    for y in range(size):
        for x in range(size):
            t = max(0.0, min(1.0, (x + y * .62) / (size * 1.62)))
            start = (128, 244, 215)
            end = (81, 158, 244)
            px[x, y] = tuple(round(start[i] * (1 - t) + end[i] * t) for i in range(3)) + (255,)
    image.paste(gradient, (0, 0), mask)
    d = ImageDraw.Draw(image)
    inset = int(size * .105)
    d.rounded_rectangle((inset, inset, size - inset, size - inset), radius=int(size * .18),
                        outline=(255, 255, 255, 75), width=max(1, int(size * .008)))
    return image

def draw_foreground(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(image)
    font = load_font(int(size * .34))
    label = "LPI"
    bounds = d.textbbox((0, 0), label, font=font, stroke_width=max(1, int(size * .004)))
    tw, th = bounds[2] - bounds[0], bounds[3] - bounds[1]
    x, y = (size - tw) / 2 - bounds[0], (size - th) / 2 - bounds[1]
    d.text((x + size * .006, y + size * .012), label, font=font, fill=(0, 0, 0, 45),
           stroke_width=max(1, int(size * .004)), stroke_fill=(0, 0, 0, 35))
    d.text((x, y), label, font=font, fill=(105, 235, 211, 255),
           stroke_width=max(1, int(size * .003)), stroke_fill=(15, 49, 69, 255))
    # Small mint status dot adds a distinctive app-mark detail.
    r = int(size * .027)
    d.ellipse((size * .77 - r, size * .73 - r, size * .77 + r, size * .73 + r), fill=(255, 218, 114, 255))
    return image

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--android", action="store_true", help="Replace generated Android launcher icons in the Capacitor project")
    args = parser.parse_args()

    base = draw_base(512)
    foreground = draw_foreground(512)
    # Use the full badge for Windows and older Android launcher formats.
    base.save(ASSETS / "lpi-city-money.png", format="PNG", optimize=True)
    base.save(ASSETS / "lpi-city-money.ico", format="ICO",
              sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])

    if args.android:
        res = ROOT / "android" / "app" / "src" / "main" / "res"
        if not res.exists():
            raise SystemExit("Android project not found. Run npm run android:setup first.")
        sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
        for density, px in sizes.items():
            folder = res / ("mipmap-" + density)
            folder.mkdir(parents=True, exist_ok=True)
            base.resize((px, px), Image.Resampling.LANCZOS).save(folder / "ic_launcher.png", optimize=True)
            base.resize((px, px), Image.Resampling.LANCZOS).save(folder / "ic_launcher_round.png", optimize=True)
            fg_size = int(px * .82)
            foreground.resize((px, px), Image.Resampling.LANCZOS).save(folder / "ic_launcher_foreground.png", optimize=True)
        for color_file in [res / "values" / "ic_launcher_background.xml", res / "values" / "colors.xml"]:
            if color_file.exists():
                data = color_file.read_text(encoding="utf-8")
                data = data.replace("#FFFFFF", "#07111f").replace("#ffffff", "#07111f")
                color_file.write_text(data, encoding="utf-8")
        print("Applied LPI launcher icons to Android mipmap resources.")
    print("Generated professional LPI City Money app icons.")

if __name__ == "__main__":
    main()
