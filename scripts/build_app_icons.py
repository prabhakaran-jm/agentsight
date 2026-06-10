#!/usr/bin/env python3
"""Build Splunk-compliant app icons (square, full-bleed tile, crisp at small sizes).

Splunk expects (static/):
  appIcon.png      36x36     appIcon_2x.png   72x72
  appIconAlt.png   36x36     appIconAlt_2x.png 72x72
  appLogo.png     160x40     appLogo_2x.png   320x80

Design goal — match AITK / MCP / Splunk AT launcher tiles:
  * Solid #1e525c rounded-square tile that fills the whole canvas (no transparent
    padding, no white letterboxing). Only the 4 rounded corners are transparent.
  * Simple white "eye" glyph with a cyan pupil + scan arc ("watching" motif).
  * Everything is rendered at SS x resolution and downsampled with LANCZOS so the
    strokes stay crisp at 36px instead of aliasing.

Nav icons (Splunk 10.4+) are React icon NAMES on <view icon="..."> in
default/data/ui/nav/default.xml — not PNGs. This script does not touch them.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

NAV_COLOR = "#1e525c"   # solid tile background (matches nav color)
ACCENT = "#2dd4bf"      # cyan pupil / scan arc
WHITE = "#ffffff"
SS = 8                  # supersample factor for crisp downscaled edges
OUT_DIR = Path(__file__).resolve().parent.parent / "apps" / "agentsight" / "static"


def _rgba(color: str) -> tuple[int, int, int, int]:
    color = color.lstrip("#")
    return tuple(int(color[i : i + 2], 16) for i in (0, 2, 4)) + (255,)


def draw_app_icon(size: int) -> Image.Image:
    """Full-bleed teal rounded tile + bold white eye glyph, supersampled."""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    bg, accent, white = _rgba(NAV_COLOR), _rgba(ACCENT), _rgba(WHITE)

    # Tile fills the entire canvas — only the rounded corners are transparent.
    # This removes the "small floating tile / white letterbox" look.
    draw.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * 0.22), fill=bg)

    cx = cy = s // 2
    # Bold eye: large enough to read at 36px.
    eye_r = int(s * 0.30)
    stroke = max(SS, int(s * 0.085))
    draw.ellipse(
        (cx - eye_r, cy - eye_r, cx + eye_r, cy + eye_r),
        outline=white,
        width=stroke,
    )
    # Cyan pupil.
    pr = int(s * 0.115)
    draw.ellipse((cx - pr, cy - pr, cx + pr, cy + pr), fill=accent)
    # Cyan scan arc (top-right) — the "watching" motif.
    arc_r = int(s * 0.40)
    draw.arc(
        (cx - arc_r, cy - arc_r, cx + arc_r, cy + arc_r),
        start=298,
        end=22,
        fill=accent,
        width=max(SS, int(s * 0.06)),
    )

    return img.resize((size, size), Image.LANCZOS)


def draw_app_logo(width: int, height: int) -> Image.Image:
    """Wide header logo: tile glyph + white 'AgentSight' wordmark, supersampled."""
    w, h = width * SS, height * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    side = h  # square tile fills full logo height
    icon = draw_app_icon(side // SS).resize((side, side), Image.LANCZOS)
    img.paste(icon, (0, 0), icon)

    draw = ImageDraw.Draw(img)
    font_px = int(h * 0.52)
    font = _load_font(font_px)
    # Vertically center the wordmark against the tile.
    bbox = draw.textbbox((0, 0), "AgentSight", font=font)
    text_h = bbox[3] - bbox[1]
    tx = side + int(h * 0.18)
    ty = (h - text_h) // 2 - bbox[1]
    draw.text((tx, ty), "AgentSight", fill=_rgba(WHITE), font=font)

    return img.resize((width, height), Image.LANCZOS)


def _load_font(px: int) -> ImageFont.FreeTypeFont:
    for name in ("seguisb.ttf", "segoeuib.ttf", "arialbd.ttf", "arial.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, px)
        except OSError:
            continue
    return ImageFont.load_default()


def save_png(im: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, format="PNG", optimize=True)
    print(f"  wrote {path.name} ({im.size[0]}x{im.size[1]}, {path.stat().st_size} bytes)")


def main() -> None:
    print(f"Building Splunk icons in {OUT_DIR}")
    save_png(draw_app_icon(36), OUT_DIR / "appIcon.png")
    save_png(draw_app_icon(72), OUT_DIR / "appIcon_2x.png")
    save_png(draw_app_icon(36), OUT_DIR / "appIconAlt.png")
    save_png(draw_app_icon(72), OUT_DIR / "appIconAlt_2x.png")
    save_png(draw_app_logo(160, 40), OUT_DIR / "appLogo.png")
    save_png(draw_app_logo(320, 80), OUT_DIR / "appLogo_2x.png")
    for legacy in ("icon_dashboard.png", "icon_approval.png"):
        p = OUT_DIR / legacy
        if p.exists():
            p.unlink()
            print(f"  removed unused {legacy}")
    print("Done. Copy app to Splunk, then bump the asset cache: /en-US/_bump")


if __name__ == "__main__":
    main()
