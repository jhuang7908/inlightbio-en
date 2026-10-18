#!/usr/bin/env python3
"""Show the InLight generation date on every science article page.

    python3 tools/stamp_gen_dates.py            # stamp pages, add missing dates
    python3 tools/stamp_gen_dates.py --check    # report pages that still need it

For each science/<slug>/index.html:
  * byline gets " · Generated: Mon D, YYYY" (the date InLight wrote/published
    the write-up; the paper's own date stays in the eyebrow);
  * the Article JSON-LD gets "dateCreated" if it has none (datePublished is
    left as is).
Dates live in data/science_gen_dates.json. A new page without an entry gets
today's date (America/New_York) written there, so weekly articles are covered
automatically. Idempotent: pages that already carry the line are left alone.
"""
from __future__ import annotations

import argparse
import json
import re
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "science_gen_dates.json"
MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
NB = "\u00a0"


def en_date(ds: str) -> str:
    return f"{MON[int(ds[5:7]) - 1]} {int(ds[8:10])}, {ds[:4]}"


def gen_html(ds: str) -> str:
    text = en_date(ds).replace(" ", NB)
    return (f'<span class="gendate"> · Generated:{NB}'
            f'<time datetime="{ds}">{text}</time></span>')


def stamp(page: str, ds: str) -> str:
    if 'class="gendate"' not in page:
        page, n = re.subn(r'(<p class="byline">.*?)(</p>)', lambda m: m.group(1) + gen_html(ds) + m.group(2), page, count=1, flags=re.S)
        if n != 1:
            raise SystemExit("no byline found")
    if '"dateCreated"' not in page:
        page, n = re.subn(r'("datePublished": "[^"]*")', rf'\1, "dateCreated": "{ds}"', page, count=1)
    return page


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    data = json.loads(DATA.read_text(encoding="utf-8"))
    dates = data.setdefault("articles", {})
    today = datetime.now(ZoneInfo("America/New_York")).date().isoformat()
    missing, changed = [], []
    for page_path in sorted((ROOT / "science").glob("*/index.html")):
        slug = page_path.parent.name
        if slug not in dates:
            missing.append(slug)
            dates[slug] = today
        before = page_path.read_text(encoding="utf-8")
        after = stamp(before, dates[slug])
        if after != before:
            changed.append(slug)
            if not args.check:
                page_path.write_text(after, encoding="utf-8")
    if not args.check:
        data["articles"] = dict(sorted(dates.items()))
        if missing:
            DATA.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{'need stamping' if args.check else 'stamped'}: {len(changed)} {changed}")
    if missing:
        print(f"new gen_date {today}: {missing}")
    if args.check and changed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
