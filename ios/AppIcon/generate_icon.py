"""Generate the VividHome app icon.

Interim art. The original concept in docs/ui/design-brief.md — a survey
benchmark on a ruled cadastral grid — derived from the meaning of the old
product name and died with the rename (docs/status.md). This replaces it with
something name-independent: a house with a section cut out of it, exposing a
stud and a service run. That is what the product does rather than what it is
called, and the house reads at 29 pt even once the detail inside the cut has
stopped resolving.

Two earlier attempts drew the framing across the whole face. Both read as a
barcode or a cage at any size, whichever way round the figure and ground went:
evenly spaced vertical bars are a stronger gestalt than "wall", and nothing
about the spacing or the colour fixed it. Containing the detail inside a
silhouette that already means something is what solved it.

Replace it when the design canvas produces a real one.

Committed output rather than a build step: the macOS runner would otherwise
need Python and Pillow to archive, which is a poor trade for one static PNG.
Regenerate with:  uv run --project pipeline python ios/AppIcon/generate_icon.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

# Tokens from docs/ui/design-canvas-brief.md section 4.
INK = (0x0F, 0x1E, 0x2E)  # ink/primary
SURFACE = (0xF4, 0xF8, 0xFB)  # surface/ground
STUD = (0x78, 0x89, 0x9A)  # surface/outline, 3.37:1 on ground
RUN = (0xD9, 0x48, 0x0F)  # accent-warm/500
CAVITY = (
    0x1B,
    0x2C,
    0x3D,
)  # the opening: darker than the face, lighter than the ground

S = 1024
OUT = Path(__file__).resolve().parents[1] / (
    "VividHome/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
)


def main() -> None:
    # RGB, never RGBA: the App Store rejects an icon with an alpha channel, and
    # iOS masks the corners itself, so the art must bleed to the edges.
    img = Image.new("RGB", (S, S), INK)
    d = ImageDraw.Draw(img)

    def px(fx: float, fy: float) -> tuple[int, int]:
        return int(S * fx), int(S * fy)

    # The house: a plain gable silhouette. Generic on its own, which is the
    # point — it survives the mask, the 29 pt Settings row and the grayscale
    # rendering, and it carries the detail below rather than competing with it.
    d.polygon(
        [
            px(0.15, 0.44),
            px(0.50, 0.15),
            px(0.85, 0.44),
            px(0.85, 0.85),
            px(0.15, 0.85),
        ],
        fill=SURFACE,
    )

    # The section cut: what the product is actually for. At small sizes this
    # fills in and the house is all that is left, which is the correct failure.
    cx0, cy0 = px(0.47, 0.52)
    cx1, cy1 = px(0.79, 0.79)
    d.rectangle((cx0, cy0, cx1, cy1), fill=CAVITY)

    # One stud and one run inside it. Two elements, not four: anything more and
    # the cut turns back into the barcode this replaced.
    cw = cx1 - cx0
    stud_w = int(cw * 0.20)
    sx = cx0 + int(cw * 0.30)
    d.rectangle((sx - stud_w // 2, cy0, sx + stud_w // 2, cy1), fill=STUD)

    run_h = int(cw * 0.18)
    ry = cy0 + int((cy1 - cy0) * 0.58)
    d.rectangle((cx0, ry - run_h // 2, cx1, ry + run_h // 2), fill=RUN)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, "PNG")
    print(f"wrote {OUT} ({img.size[0]}x{img.size[1]}, mode={img.mode})")


if __name__ == "__main__":
    main()
