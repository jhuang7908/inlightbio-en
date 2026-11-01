#!/usr/bin/env python3
"""Rewrite the "Related science" block on article pages with field-matched cards.

Mirrors the CN site's related_articles(): same primary field (data-f), nearest
publication date first; if a field has fewer than 3 other briefs, the remaining
slots are filled with the nearest-dated briefs from other fields.
Cards are copied verbatim from science/index.html so markup stays identical.

Usage: python3 tools/related_science.py SLUG [SLUG ...]
"""
import re
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CARD_RE = re.compile(r'<article class="scard" data-f="(\w+)"><a class="scover" href="/science/([^/"]+)/".*?</article>', re.S)
SREL_RE = re.compile(r'(<div class="srel"><h2>Related science</h2><div class="scigrid three">)((?:\s*<article class="scard".*?</article>\s*)+)(</div></div>)', re.S)


def load_cards():
    s = (ROOT / "science/index.html").read_text(encoding="utf-8")
    cards = {}
    for m in CARD_RE.finditer(s):
        html = m.group(0)
        d = re.search(r'<span class="sd">([^<]+)</span>', html)
        try:
            day = datetime.strptime(d.group(1).strip(), "%b %d, %Y").toordinal() if d else 0
        except ValueError:
            day = 0
        cards.setdefault(m.group(2), {"f": m.group(1), "day": day, "html": html})
    return cards


def related(slug, cards, limit=3):
    me = cards[slug]
    others = [(k, c) for k, c in cards.items() if k != slug]
    key = lambda kc: (abs(kc[1]["day"] - me["day"]), kc[0])
    same = sorted([kc for kc in others if kc[1]["f"] == me["f"]], key=key)
    rest = sorted([kc for kc in others if kc[1]["f"] != me["f"]], key=key)
    return [k for k, _ in (same + rest)[:limit]]


def apply(slugs):
    cards = load_cards()
    for slug in slugs:
        p = ROOT / "science" / slug / "index.html"
        s = p.read_text(encoding="utf-8")
        picks = related(slug, cards)
        body = "".join(cards[k]["html"] + "\n" for k in picks)
        new, n = SREL_RE.subn(lambda m: m.group(1) + body + m.group(3), s, count=1)
        if n != 1:
            raise SystemExit(f"{slug}: Related science block not found")
        if new != s:
            p.write_text(new, encoding="utf-8")
        print(f"{slug} ({cards[slug]['f']}): {', '.join(f'{k}[{cards[k][chr(102)]}]' for k in picks)}")


if __name__ == "__main__":
    apply(sys.argv[1:])
