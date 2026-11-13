"""Write Fixtures/house-sheet.pdf, the drawing SheetPDFTests reads.

The same 20 by 12 ft house SheetReaderTests builds by hand, as a PDF: 6 pt walls
at 1/4 inch to the foot on an 800 by 600 pt page, an open kitchen and dining on
the left, an office on the right with a wall stub hanging into it, a patio label
outside, two dimensions with their witness lines, and the scale note.

Written by hand, with no library, so it exercises what a CAD export does: a
scaled coordinate system, walls as rectangles and as a closed path, one wall
inside a form XObject, a paper-white fill, and text set both across and up the
page. Run it again after changing it:

    python3 make_house_sheet.py
"""

from pathlib import Path

PAGE_W, PAGE_H = 800, 600
K = 2  # the drawing is written at twice size inside a 0.5 scale, as exporters do


def y(top: float) -> float:
    """Sheet y, measured down from the top, as PDF y, measured up."""
    return PAGE_H - top


def rect(x0: float, top: float, x1: float, bottom: float) -> str:
    return f"{x0 * K:g} {y(bottom) * K:g} {(x1 - x0) * K:g} {(bottom - top) * K:g} re f\n"


def line(x0: float, y0: float, x1: float, y1: float) -> str:
    return f"{x0 * K:g} {y(y0) * K:g} m {x1 * K:g} {y(y1) * K:g} l S\n"


def text(string: str, x: float, top: float, size: float = 7) -> str:
    """Across the page, roughly centred on x, its baseline a little below top."""
    left = x - 0.25 * size * len(string)
    return f"BT /F1 {size:g} Tf 1 0 0 1 {left:g} {y(top + size * 0.35):g} Tm ({string}) Tj ET\n"


def upright(string: str, x: float, top: float, size: float = 7) -> str:
    """Up the page, reading bottom to top, roughly centred on (x, top)."""
    bottom = top + 0.25 * size * len(string)
    return f"BT /F1 {size:g} Tf 0 1 -1 0 {x + size * 0.35:g} {y(bottom):g} Tm ({string}) Tj ET\n"


def build() -> bytes:
    drawing = "q 0.5 0 0 0.5 0 0 cm\n"
    drawing += f"1 1 1 rg 0 0 {PAGE_W * K} {PAGE_H * K} re f\n"  # the paper
    drawing += "0.5 0.5 0.5 rg\n"
    drawing += rect(100, 100, 460, 106) + rect(100, 310, 460, 316)
    drawing += rect(100, 100, 106, 316) + rect(454, 100, 460, 316)
    # The wall between the two rooms, as a closed path.
    drawing += (
        f"{277 * K} {y(100) * K} m {283 * K} {y(100) * K} l "
        f"{283 * K} {y(316) * K} l {277 * K} {y(316) * K} l h f\n"
    )
    # The stub in the office, inside a form placed by its own matrix.
    drawing += f"q 1 0 0 1 {367 * K} {y(166) * K} cm /W1 Do Q\n"
    # An arrowhead: black, compact, not a wall.
    drawing += f"0 0 0 rg {98 * K} {y(78) * K} m {104 * K} {y(80) * K} l {98 * K} {y(82) * K} l h f\n"
    drawing += "0 0 0 RG 1 w\n"
    drawing += line(100, 70, 100, 98) + line(460, 70, 460, 98)
    drawing += line(70, 100, 98, 100) + line(70, 316, 98, 316)
    drawing += line(100, 80, 460, 80)
    drawing += "Q\n"

    for tag, name, x, top in [
        ("101", "KITCHEN", 150, 160),
        ("102", "DINING", 220, 250),
        ("103", "OFFICE", 400, 220),
        ("104", "PATIO", 620, 200),
    ]:
        drawing += text(tag, x, top) + text(name, x, top + 12)
    drawing += text("20' - 0\"", 280, 80 - 8)
    drawing += upright("12' - 0\"", 80 - 8, 208)
    drawing += text("FIRST FLOOR PLAN", 620, 500)
    drawing += text("1/4\" = 1'-0\"", 620, 520)

    form = f"0.5 0.5 0.5 rg 0 0 {6 * K} {60 * K} re f\n"

    def stream(dictionary: str, body: str) -> bytes:
        data = body.encode("latin-1")
        return f"<< {dictionary} /Length {len(data)} >>\nstream\n".encode() + data + b"endstream"

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {PAGE_W} {PAGE_H}] /Contents 4 0 R "
            "/Resources << /Font << /F1 5 0 R >> /XObject << /W1 6 0 R >> >> >>"
        ).encode(),
        stream("", drawing),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        stream(
            f"/Type /XObject /Subtype /Form /BBox [0 0 {6 * K} {60 * K}] /Matrix [1 0 0 1 0 0] "
            "/Resources << >>",
            form,
        ),
    ]

    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{number} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode() + b"0000000000 65535 f \n"
    for offset in offsets:
        out += f"{offset:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(out)


if __name__ == "__main__":
    target = Path(__file__).parent / "Fixtures" / "house-sheet.pdf"
    target.parent.mkdir(exist_ok=True)
    target.write_bytes(build())
    print(f"wrote {target} ({target.stat().st_size} bytes)")
