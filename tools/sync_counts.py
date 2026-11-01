#!/usr/bin/env python3
"""Recompute every static count on the EN site from the data it summarises.

Counts covered (each one is derived, never hand-edited):
  news/index.html   type tiles ("N items")  = items in window.NEWS with that kind
                    "#newscount" header       = len(window.NEWS)
                    Conferences tile          = window.CONFS events starting in the
                                                next six months (same window as site.js)
  conferences/      static tile fallbacks     = same rule per type (site.js overwrites at runtime)
  index.html        "Sources · Science" cards = science/index.html cards per journal group
Run after every weekly assembly:  python3 tools/sync_counts.py   (--check: exit 1 on drift)
"""
import re, json, sys, datetime as dt
from collections import Counter
from pathlib import Path
R = Path(__file__).resolve().parent.parent
CHECK = '--check' in sys.argv
drift = []

def sub(s, pat, val, label, f):
    m = re.search(pat, s, re.S)
    if not m: sys.exit(f'pattern not found: {label} in {f}')
    old = m.group(2)
    if old != val: drift.append(f'{f}: {label}: {old!r} -> {val!r}')
    return s[:m.start(2)] + val + s[m.end(2):]

def plural(n, w): return f'{n} {w}{"" if n == 1 else "s"}'

def js(s, name):
    return json.loads(re.search(r'window\.%s=(\[.*?\]);' % name, s, re.S).group(1))

# ---- conferences window (mirror of CONF_WIN in assets/js/site.js: today+7d .. today+6 months)
today = dt.date.today()
def add_months(d, n):
    y, m = divmod(d.month - 1 + n, 12)
    import calendar
    return d.replace(year=d.year + y, month=m + 1, day=min(d.day, calendar.monthrange(d.year + y, m + 1)[1]))
lo, hi = (today + dt.timedelta(days=7)).isoformat(), add_months(today, 6).isoformat()
cf = R / 'conferences/index.html'; cs = cf.read_text()
CONFS = [x for x in js(cs, 'CONFS') if x.get('dates') and x['dates'] != 'TBA' and lo <= x['dates'].split(' to ')[0] <= hi]
for k in re.findall(r'class="trkcard art ctile"[^>]*data-k="([^"]+)"', cs):
    kk = k.replace('&amp;', '&')
    n = len(CONFS) if kk == 'all' else sum(1 for x in CONFS if x.get('kind') == kk)
    cs = sub(cs, r'(data-k="%s">(?:(?!</a>).)*?<em data-n>)([^<]*)(</em>)' % re.escape(k), plural(n, 'event'), f'conf tile {kk}', 'conferences/index.html')

# ---- news page
nf = R / 'news/index.html'; ns = nf.read_text()
NEWS = js(ns, 'NEWS')
kc = Counter(k for x in NEWS for k in x['kinds'])
for k in re.findall(r'class="trkcard art" href="\?type=(\w+)"', ns):
    ns = sub(ns, r'(href="\?type=%s\"(?:(?!</a>).)*?<em>)([^<]*)(</em>)' % k, plural(kc[k], 'item'), f'type tile {k}', 'news/index.html')
ns = sub(ns, r'(id="newscount">)(\d+ items?)(, newest first)', plural(len(NEWS), 'item'), 'newscount', 'news/index.html')
ns = sub(ns, r'(href="/conferences/" style="--dc:var\(--accent\)"><span class="artthumb">(?:(?!</a>).)*?<span>)([^<]*)(</span>)', 'Partnering, investor, scientific, CRO, regulatory, CMC, digital and HEOR meetings, next six months', 'conf tile text', 'news/index.html')
ns = sub(ns, r'(href="/conferences/" style="--dc:var\(--accent\)"><span class="artthumb">(?:(?!</a>).)*?<em>)([^<]*)(</em>)', plural(len(CONFS), 'event'), 'conf tile', 'news/index.html')

# ---- home: science sources
GROUP = {'Nature': 'Nature', 'bioRxiv': 'bioRxiv', 'mAbs': 'Taylor &amp; Francis', 'J Clin Invest': 'JCI',
         'Dis Model Mech': 'Company of Biologists', 'New England Journal of Medicine': 'NEJM',
         'Immunity': 'Cell Press', 'Cell Reports Medicine': 'Cell Press', 'Cell': 'Cell Press'}
sci = re.findall(r'class="sj">([^<]+)<', (R / 'science/index.html').read_text())
def grp(j):
    if j in GROUP: return GROUP[j]
    if j.startswith('Nature '): return 'Nature Portfolio'
    sys.exit(f'unmapped science journal {j!r}: add it to GROUP in tools/sync_counts.py')
gc = Counter(grp(j) for j in sci)
npj = len({j for j in sci if grp(j) == 'Nature Portfolio'})
hf = R / 'index.html'; hs = hf.read_text()
ra = hs.find('<div class="railhead">Sources · Science</div>'); rb = hs.find('</aside>', ra)
assert ra > 0 and rb > ra, 'science source rail not found'
pre, hs, post = hs[:ra], hs[ra:rb], hs[rb:]   # only the science rail; the deals rail is a cumulative citation tally
NAMES = re.findall(r'class="srcard2"[^>]*><span class="lg">'+'(?:(?!</a>).)*?'+r'<b>([^<]+)</b>', hs, re.S)
for name in NAMES:
    n = gc[name]
    if not n: drift.append(f'index.html: source {name} has no science cards'); continue
    hs = sub(hs, r'(title="%s: )(\d+ briefs?)( cite)' % re.escape(name), plural(n, 'brief'), f'source title {name}', 'index.html')
    hs = sub(hs, r'(<b>%s</b>(?:(?!</a>).)*?<span class=n>)([^<]*)(</span>)' % re.escape(name), plural(n, 'brief'), f'source {name}', 'index.html')
hs = sub(hs, r'(<span class=d>)(\d+)( Nature Portfolio journals)', str(npj), 'NP journal count', 'index.html')
total = sum(gc[n.replace('&amp;','&amp;')] for n in NAMES); hs = pre + hs + post
if total != len(sci): drift.append(f'index.html: source cards sum {total} != {len(sci)} science articles')

print('\n'.join(drift) or 'counts in sync')
if CHECK: sys.exit(1 if drift else 0)
cf.write_text(cs); nf.write_text(ns); hf.write_text(hs)
