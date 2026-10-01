"""Renders Slotter's mark into the icon files its platforms need.

The drawing is `Slotter.svg` at the repo root; this writes the container formats from it, so
the `.ico` and the macOS icon can never drift from the drawing.

    python3 tools/make-icons.py Slotter.svg
    python3 tools/make-icons.py Slotter.svg --if-needed

`--if-needed` skips the work when every output is already newer than the drawing.

Rasterising needs either PySide6 or cairosvg. The Windows build has neither, so the generator is
run from any environment that does and the `.ico` is committed.
"""

from __future__ import annotations

import argparse
import os
import struct
import sys

PNG_SIZES = (16, 24, 32, 48, 64, 128, 256, 512, 1024)
ICO_SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)

# The modern icns set: every entry is a PNG, and Finder scales the small sizes from these.
ICNS_ENTRIES = (
    (b"ic11", 32), (b"ic12", 64), (b"ic07", 128), (b"ic13", 256),
    (b"ic08", 256), (b"ic14", 512), (b"ic09", 512), (b"ic10", 1024),
)


def make_renderer(source: str):
    try:
        from PySide6.QtCore import QBuffer, QByteArray, Qt
        from PySide6.QtGui import QGuiApplication, QImage, QPainter
        from PySide6.QtSvg import QSvgRenderer
    except ImportError:
        pass
    else:
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        QGuiApplication.instance() or QGuiApplication([sys.argv[0]])

        def render(size: int) -> bytes:
            image = QImage(size, size, QImage.Format.Format_ARGB32)
            image.fill(Qt.GlobalColor.transparent)
            painter = QPainter(image)
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)
            QSvgRenderer(source).render(painter)
            painter.end()
            # The QByteArray has to outlive the QBuffer writing into it, or Qt frees it underneath.
            store = QByteArray()
            buffer = QBuffer(store)
            buffer.open(QBuffer.OpenModeFlag.WriteOnly)
            image.save(buffer, "PNG")
            buffer.close()
            return bytes(store)

        return render

    try:
        import cairosvg
    except ImportError:
        raise SystemExit("no SVG rasteriser: pip install PySide6 or cairosvg")

    def render(size: int) -> bytes:
        return cairosvg.svg2png(url=source, output_width=size, output_height=size)

    return render


def write_ico(path: str, pngs: dict[int, bytes]) -> None:
    sizes = [size for size in ICO_SIZES if size in pngs]
    header = struct.pack("<HHH", 0, 1, len(sizes))
    offset = len(header) + 16 * len(sizes)
    directory, payload = b"", b""
    for size in sizes:
        data = pngs[size]
        directory += struct.pack(
            "<BBBBHHII", size if size < 256 else 0, size if size < 256 else 0,
            0, 0, 1, 32, len(data), offset,
        )
        payload += data
        offset += len(data)
    with open(path, "wb") as handle:
        handle.write(header + directory + payload)


def write_icns(path: str, pngs: dict[int, bytes]) -> None:
    body = b""
    for kind, size in ICNS_ENTRIES:
        data = pngs[size]
        body += kind + struct.pack(">I", len(data) + 8) + data
    with open(path, "wb") as handle:
        handle.write(b"icns" + struct.pack(">I", len(body) + 8) + body)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", help="the app's .svg drawing")
    parser.add_argument("--outdir", help="defaults to the drawing's own folder")
    parser.add_argument("--stem", help="defaults to the drawing's own name")
    parser.add_argument("--png", action="store_true", help="also write <stem>-<size>.png")
    parser.add_argument("--icns", action="store_true", help="also write <stem>.icns")
    parser.add_argument("--if-needed", action="store_true", dest="if_needed")
    args = parser.parse_args(argv)

    source = os.path.abspath(args.source)
    if not os.path.exists(source):
        print(f"no drawing at {source}", file=sys.stderr)
        return 2
    outdir = os.path.abspath(args.outdir) if args.outdir else os.path.dirname(source)
    stem = args.stem or os.path.splitext(os.path.basename(source))[0]

    outputs = [os.path.join(outdir, f"{stem}.ico")]
    if args.icns:
        outputs.append(os.path.join(outdir, f"{stem}.icns"))
    if args.png:
        outputs += [os.path.join(outdir, f"{stem}-{size}.png") for size in PNG_SIZES if size <= 256]
        outputs.append(os.path.join(outdir, f"{stem}.png"))

    drawn = os.path.getmtime(source)
    if args.if_needed and all(
        os.path.exists(path) and os.path.getmtime(path) >= drawn for path in outputs
    ):
        print(f"icons are newer than {os.path.basename(source)} - nothing to draw")
        return 0

    render = make_renderer(source)
    wanted = set(ICO_SIZES)
    if args.icns:
        wanted |= {size for _, size in ICNS_ENTRIES}
    if args.png:
        wanted |= set(PNG_SIZES)
    pngs = {size: render(size) for size in sorted(wanted)}

    os.makedirs(outdir, exist_ok=True)
    write_ico(os.path.join(outdir, f"{stem}.ico"), pngs)
    if args.icns:
        write_icns(os.path.join(outdir, f"{stem}.icns"), pngs)
    if args.png:
        for size in PNG_SIZES:
            if size <= 256:
                with open(os.path.join(outdir, f"{stem}-{size}.png"), "wb") as handle:
                    handle.write(pngs[size])
        with open(os.path.join(outdir, f"{stem}.png"), "wb") as handle:
            handle.write(pngs[256])
    print(f"wrote {', '.join(os.path.basename(p) for p in outputs)} from {os.path.basename(source)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
