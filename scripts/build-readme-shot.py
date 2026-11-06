"""Build the README hero image: the Mac window beside the iPad and iPhone.

Reads assets/shots/{lang}-edit-2400.webp, {lang}-ipad.webp and
{lang}-iphone.webp and writes assets/shots/readme-{lang}.webp at 2000px wide.
The Mac window is cut out of its wallpaper (100,100 to 2300,1460, corner
radius 53). The iPad and iPhone screens are cut out of their device frames and
given thinner bezels (26px and 20px, down from about 53 and 25, with a 3px
aluminium edge), since the iPad's original bezel read thick beside the Mac.
All three sit on a soft ground blurred from the wallpaper bands above and
below the Mac window, with rounded corners (maintainer's pick of three,
2026-11-06). The open-source repository's READMEs load these from
miaoyan.app; rerun after the site shots are retaken.

    python3 -I scripts/build-readme-shot.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SHOTS = Path(__file__).resolve().parent.parent / "assets" / "shots"


def rounded_mask(size, radius, inset=0, ss=4):
    mask = Image.new("L", (size[0] * ss, size[1] * ss), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset * ss, inset * ss, size[0] * ss - 1 - inset * ss, size[1] * ss - 1 - inset * ss),
        radius=radius * ss,
        fill=255,
    )
    return mask.resize(size, Image.LANCZOS)


def rebezel(path, screen_box, screen_radius, bezel, edge=3):
    screen = Image.open(path).convert("RGBA").crop(screen_box)
    screen.putalpha(rounded_mask(screen.size, screen_radius))
    size = (screen.width + 2 * (bezel + edge), screen.height + 2 * (bezel + edge))
    device = Image.new("RGBA", size, (200, 201, 204, 255))
    device.putalpha(rounded_mask(size, screen_radius + bezel + edge))
    body_size = (size[0] - 2 * edge, size[1] - 2 * edge)
    body = Image.new("RGBA", body_size, (10, 10, 11, 255))
    body.putalpha(rounded_mask(body_size, screen_radius + bezel))
    device.alpha_composite(body, (edge, edge))
    device.alpha_composite(screen, (bezel + edge, bezel + edge))
    return device


def scaled(im, h):
    return im.resize((round(im.width * h / im.height), h), Image.LANCZOS)


def build(lang):
    mac = Image.open(SHOTS / f"{lang}-edit-2400.webp").convert("RGBA")
    ipad = scaled(rebezel(SHOTS / f"{lang}-ipad.webp", (72, 76, 1328, 1750), 36, 26), 1240)
    iphone = scaled(rebezel(SHOTS / f"{lang}-iphone.webp", (38, 36, 662, 1395), 97, 20), 940)

    win = mac.crop((100, 100, 2300, 1460))
    win.putalpha(rounded_mask(win.size, 53, inset=1))

    pad = 150
    width = pad + win.width - 330 + ipad.width - 120 + iphone.width + pad
    height = pad + win.height + 230 + pad

    # Only the wallpaper bands above and below the window, so its white never
    # bleeds into the ground.
    rgb = mac.convert("RGB")
    bands = Image.new("RGB", (rgb.width, 160))
    bands.paste(rgb.crop((0, 0, rgb.width, 80)), (0, 0))
    bands.paste(rgb.crop((0, rgb.height - 80, rgb.width, rgb.height)), (0, 80))
    canvas = bands.resize((width, height), Image.BICUBIC).filter(ImageFilter.GaussianBlur(90)).convert("RGBA")
    canvas.putalpha(rounded_mask((width, height), 56))

    def shadow(im, xy):
        layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        tint = Image.new("RGBA", im.size, (20, 18, 15, 0))
        tint.putalpha(im.getchannel("A").point(lambda v: int(v * 0.28)))
        layer.alpha_composite(tint, (xy[0], xy[1] + 28))
        return layer.filter(ImageFilter.GaussianBlur(46))

    ipad_xy = (pad + win.width - 330, height - pad - ipad.height)
    iphone_xy = (ipad_xy[0] + ipad.width - 120, height - pad - iphone.height)
    for im, xy in ((win, (pad, pad)), (ipad, ipad_xy), (iphone, iphone_xy)):
        canvas.alpha_composite(shadow(im, xy))
        canvas.alpha_composite(im, xy)

    out = canvas.resize((2000, round(height * 2000 / width)), Image.LANCZOS)
    out.save(SHOTS / f"readme-{lang}.webp", quality=88, method=6)
    print(f"readme-{lang}.webp {out.size}")


if __name__ == "__main__":
    for lang in ("zh", "en"):
        build(lang)
