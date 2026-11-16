#!/usr/bin/env python3
"""Notify IndexNow (Bing, Yandex, Seznam, Naver...) about new or changed pages.

Only URLs listed in sitemap.xml are ever submitted. A URL is sent when it is
new in the sitemap, its <lastmod> changed, or its HTML file changed in git.
If nothing changed, the script prints a note and exits 0 without a request.

Standard library only (Python 3.8+). Run from the repository root.

Modes (pick one; default is --git-range HEAD~1..HEAD):
  --git-range BASE..HEAD     compare two commits (sitemap + changed files)
  --sitemap-diff OLD NEW     compare two sitemap files (e.g. before/after deploy)
  --url URL [--url URL ...]  submit these URLs (must be in the sitemap)
  --all                      submit every sitemap URL (first run / re-index)

Common options:
  --host inlightbio.com      site host (default: from the first sitemap <loc>)
  --dry-run                  print what would be sent, send nothing
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlparse
from xml.etree import ElementTree as ET

ENDPOINT = "https://api.indexnow.org/indexnow"
NS = "{http://www.sitemaps.org/schemas/sitemap/0.9}"
MAX_URLS = 10000  # IndexNow per-request limit


def parse_sitemap(text: str) -> dict[str, str]:
    """{loc: lastmod} for every <url>. Commented-out entries are ignored."""
    if not text.strip():
        return {}
    root = ET.fromstring(text.encode("utf-8"))
    out: dict[str, str] = {}
    for url in root.iter(f"{NS}url"):
        loc = (url.findtext(f"{NS}loc") or "").strip()
        if loc:
            out[loc] = (url.findtext(f"{NS}lastmod") or "").strip()
    return out


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def git_show(ref: str, path: str) -> str:
    try:
        return git("show", f"{ref}:{path}")
    except subprocess.CalledProcessError:
        return ""


def find_key(root: Path) -> str:
    """The key file is <32 hex>.txt at the site root whose content is its own name."""
    for p in sorted(root.glob("*.txt")):
        if re.fullmatch(r"[0-9a-f]{32}", p.stem) and p.read_text(encoding="utf-8").strip() == p.stem:
            return p.stem
    sys.exit("IndexNow key file (<key>.txt at the site root) not found")


def path_to_url(path: str, base: str) -> str | None:
    """Map a changed file to its public URL, e.g. science/x/index.html -> /science/x/."""
    if not path.endswith(".html"):
        return None
    if path == "index.html":
        return base + "/"
    if path.endswith("/index.html"):
        return f"{base}/{path[: -len('index.html')]}"
    return f"{base}/{path}"


def changed_urls(old: dict[str, str], new: dict[str, str], changed_files: list[str], base: str) -> list[str]:
    urls = [u for u, lm in new.items() if u not in old or old[u] != lm]
    for f in changed_files:
        u = path_to_url(f, base)
        if u and u in new and u not in urls:
            urls.append(u)
    return urls


def submit(host: str, key: str, urls: list[str], dry_run: bool) -> int:
    payload = {"host": host, "key": key, "keyLocation": f"https://{host}/{key}.txt", "urlList": urls[:MAX_URLS]}
    print(f"IndexNow: {len(payload['urlList'])} URL(s) for {host}")
    for u in payload["urlList"]:
        print("  " + u)
    if dry_run:
        print("Dry run: nothing sent.")
        return 0
    req = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            print(f"IndexNow response: HTTP {resp.status}")
            return 0
    except urllib.error.HTTPError as e:
        # 200/202 = accepted; 400 bad request; 403 key not valid; 422 URLs not on host; 429 too many
        print(f"IndexNow response: HTTP {e.code} {e.reason}", file=sys.stderr)
        return 1
    except urllib.error.URLError as e:
        print(f"IndexNow request failed: {e.reason}", file=sys.stderr)
        return 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--git-range", metavar="BASE..HEAD")
    g.add_argument("--sitemap-diff", nargs=2, metavar=("OLD", "NEW"))
    g.add_argument("--url", action="append", metavar="URL")
    g.add_argument("--all", action="store_true")
    ap.add_argument("--root", default=".", help="site root containing sitemap.xml and the key file")
    ap.add_argument("--host")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    root = Path(a.root)
    current = parse_sitemap((root / "sitemap.xml").read_text(encoding="utf-8"))
    if not current:
        print("sitemap.xml has no URLs; nothing to submit.")
        return 0
    host = a.host or urlparse(next(iter(current))).netloc
    base = f"https://{host}"
    key = find_key(root)

    if a.all:
        urls = list(current)
    elif a.url:
        urls = [u for u in a.url if u in current]
        skipped = [u for u in a.url if u not in current]
        for u in skipped:
            print(f"Skipped (not in sitemap): {u}")
    elif a.sitemap_diff:
        old_p, new_p = (Path(p) for p in a.sitemap_diff)
        old = parse_sitemap(old_p.read_text(encoding="utf-8")) if old_p.exists() else {}
        new = parse_sitemap(new_p.read_text(encoding="utf-8"))
        urls = changed_urls(old, new, [], base)
    else:
        rng = a.git_range or "HEAD~1..HEAD"
        b, h = rng.split("..", 1)
        h = h or "HEAD"
        new = parse_sitemap(git_show(h, "sitemap.xml"))
        old = parse_sitemap(git_show(b, "sitemap.xml"))
        try:
            files = [f for f in git("diff", "--name-only", "--diff-filter=AMR", b, h).splitlines() if f]
        except subprocess.CalledProcessError:
            files = []
        urls = changed_urls(old, new, files, base)

    urls = [u for u in urls if urlparse(u).netloc == host]
    if not urls:
        print("No new or changed sitemap URLs; nothing to submit.")
        return 0
    return submit(host, key, urls, a.dry_run)


if __name__ == "__main__":
    sys.exit(main())
