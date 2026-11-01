#!/usr/bin/env python3
"""Compressed web copies of heavy site images (originals are never touched).

    python tools/web_images.py            # create missing <stem>_web.webp copies
    python tools/web_images.py --report   # print referenced image weight

For every raster image referenced by index.html / content/site_articles.js /
pages that is heavier than THRESHOLD, a sibling ``<stem>_web.webp`` is written
(max 800px wide, quality ~80; brand logos 160px). ``webify()`` rewrites text to
point at those copies; build_pages.py calls it on every file it writes.
"""
from __future__ import annotations
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
THRESHOLD = 40_000
MAX_W = 800
LOGO_W = 160
FIG_W = 1400   # article figures (scrollable, text-heavy) keep legibility
LOGOS = {"assets/brand/inlight_logo_v2.png", "img/logo_v2_512.png"}
SKIP = re.compile(r"favicon|img/conf/logos/|_web\.webp$|wechat_oa_qr")
REF = re.compile(r"((?:\.\./)*)((?:img|assets)/(?!conf/logos/)[\w./-]+?\.(?:png|jpe?g|webp))(?=[?\\\"'\s)#,]|$)")


def web_path(rel: str) -> str:
    return re.sub(r"\.(png|jpe?g|webp)$", "_web.webp", rel)


def make_copy(rel: str) -> bool:
    src = ROOT / rel
    dst = ROOT / web_path(rel)
    if dst.exists() or SKIP.search(rel) or not src.is_file() or src.stat().st_size < THRESHOLD:
        return False
    from PIL import Image
    im = Image.open(src)
    im = im.convert("RGBA" if ("A" in im.getbands() or "transparency" in im.info) else "RGB")
    w = LOGO_W if rel in LOGOS else FIG_W if "_fig" in rel else MAX_W
    if im.width > w:
        im = im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
    for q in (80, 74, 68, 62):
        im.save(dst, "WEBP", quality=q, method=6)
        if dst.stat().st_size <= (400_000 if "_fig" in rel else 150_000):
            break
    if dst.stat().st_size >= src.stat().st_size:   # no gain: drop it
        dst.unlink()
        return False
    return True


def webify(text: str) -> str:
    def sub(m):
        rel = m.group(2)
        make_copy(rel)   # creates the copy for newly added images
        return m.group(1) + (web_path(rel) if (ROOT / web_path(rel)).exists() else rel)
    return REF.sub(sub, text)


def targets() -> list[Path]:
    return sorted(p for p in [*ROOT.rglob("*.html"), *(ROOT / "data").glob("*.json")] if ".git" not in p.parts)


def refs(text: str) -> set[str]:
    return {m.group(2) for m in REF.finditer(text)}


def main() -> None:
    allrefs = set()
    for t in targets():
        allrefs |= refs(t.read_text(encoding="utf-8"))
    if "--report" in sys.argv:
        for t in [ROOT / "index.html"]:
            rs = refs(t.read_text(encoding="utf-8"))
            tot = sum((ROOT / r).stat().st_size for r in rs if (ROOT / r).is_file())
            print(f"{t.relative_to(ROOT)}: {len(rs)} refs, {tot/1e6:.2f} MB")
        return
    made = sum(make_copy(r) for r in sorted(allrefs))
    print(f"web copies created: {made}")


if __name__ == "__main__" and "--apply" not in sys.argv:
    main()



_IMG = re.compile(r"<img\b([^>]*)>")


def lazify(text: str, eager: int = 0) -> str:
    """Add loading="lazy" decoding="async" to <img> tags after the first
    ``eager`` static ones (above the fold). ``class="colockup"`` stays eager."""
    seen = 0

    def sub(m):
        nonlocal seen
        attrs = m.group(1)
        static = "${" not in attrs
        if static:
            seen += 1
        if "loading=" not in attrs:
            if (static and seen <= eager) or "colockup" in attrs:
                return m.group(0)
            attrs = ' loading="lazy"' + attrs
        if "decoding=" not in attrs and "loading=\"lazy\"" in attrs:
            attrs = ' decoding="async"' + attrs
        return "<img" + attrs + ">"
    return _IMG.sub(sub, text)


def apply_all() -> None:
    """Create copies, then rewrite every HTML page and data/*.json in place
    (idempotent). Run after each site build: python tools/web_images.py --apply"""
    main()
    for t in targets():
        s = t.read_text(encoding="utf-8")
        new = webify(s)
        if t.suffix == ".html":
            eager = 6 if t == ROOT / "index.html" else 1
            new = lazify(new, eager=eager)
        if new != s:
            t.write_text(new, encoding="utf-8")


if __name__ == "__main__" and "--apply" in sys.argv:
    apply_all()
