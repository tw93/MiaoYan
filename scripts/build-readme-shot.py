"""Build the README hero image: the Mac window beside the iPad and iPhone.

Reads assets/shots/{lang}-edit-2400.webp, {lang}-ipad.webp and
{lang}-iphone.webp, cuts the Mac window out of its wallpaper (window at
100,100 to 2300,1460, corner radius 53), stands the iPad and iPhone over its
right edge on a transparent ground so the picture reads on GitHub's light and
dark themes, and writes assets/shots/readme-{lang}.webp at 2000px wide.
The open-source repository's READMEs load these from miaoyan.app; rerun after
the site shots are retaken.

    python3 -I scripts/build-readme-shot.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SHOTS = Path(__file__).resolve().parent.parent / "assets" / "shots"


def scaled(im, h):
    return im.resize((round(im.width * h / im.height), h), Image.LANCZOS)


def build(lang):
    mac = Image.open(SHOTS / f"{lang}-edit-2400.webp").convert("RGBA")
    ipad = scaled(Image.open(SHOTS / f"{lang}-ipad.webp").convert("RGBA"), 1240)
    iphone = scaled(Image.open(SHOTS / f"{lang}-iphone.webp").convert("RGBA"), 940)

    left, top, right, bottom, radius, ss = 100, 100, 2300, 1460, 53, 4
    win = mac.crop((left, top, right, bottom))
    mask = Image.new("L", (win.width * ss, win.height * ss), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (ss, ss, win.width * ss - 1 - ss, win.height * ss - 1 - ss), radius=radius * ss, fill=255
    )
    win.putalpha(mask.resize(win.size, Image.LANCZOS))

    pad = 90
    width = pad + win.width - 330 + ipad.width - 120 + iphone.width + pad
    height = pad + win.height + 230 + pad
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))

    def shadow(im, xy):
        layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        tint = Image.new("RGBA", im.size, (20, 18, 15, 0))
        tint.putalpha(im.getchannel("A").point(lambda v: int(v * 0.20)))
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
