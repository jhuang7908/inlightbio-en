#!/usr/bin/env python3
"""Generate the InLight Bio English static site into /workspace/inlight_en_site.
Re-run after editing data_*.py. Writes only inside the EN site folder."""
import html, json, os, sys, datetime
from email.utils import format_datetime
HERE=os.path.dirname(os.path.abspath(__file__)); ROOT=os.path.dirname(HERE)
sys.path.insert(0,HERE)
from data_news import NEWS, KINDS
from data_conf import CONFS, CHECKED
from data_newco import NEWCO
SITE="https://inlightbio.com"; BUILD="2026-10-11"
BD="bd@inlightbio.com"; CONTACT="contact@inlightbio.com"
ZH="https://inlight.therasik.com"
e=lambda s: html.escape(str(s), quote=True)
MON=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
def ym(d): y,m=d.split("-")[:2]; return f"{MON[int(m)-1]} {y}"
def mailto(addr,subj=""): 
    from urllib.parse import quote
    return f"mailto:{addr}"+(f"?subject={quote(subj)}" if subj else "")
def w(path, text):
    p=os.path.join(ROOT,path); os.makedirs(os.path.dirname(p),exist_ok=True)
    open(p,"w",encoding="utf-8").write(text)

# ---------- css bundle ----------
css=open(os.path.join(ROOT,"assets/css/base-from-zh.css"),encoding="utf-8").read()+"\n"+open(os.path.join(ROOT,"assets/css/en.css"),encoding="utf-8").read()
w("assets/css/site.css", "/* Generated: base-from-zh.css (verbatim from the Chinese edition) + en.css. Edit those, then rebuild. */\n"+css)

MARK_SVG='''<svg class="bmark" viewBox="0 0 48 48" fill="none" aria-hidden="true"><rect x="1.5" y="1.5" width="45" height="45" rx="12" fill="var(--accent)" opacity=".12"/><g stroke="var(--accent)" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="21" cy="21" r="10"/><path d="M28.5 28.5L39 39"/><path d="M17 21h8M21 17v8"/></g></svg>'''
CAL_ICON='<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/><rect x="7" y="13" width="3" height="3" rx=".5" fill="currentColor" stroke="none"/></svg>'
FILTER_ICON='<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 6h16M7 12h10M10 18h4"/></svg>'
CHEV='<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.4" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg>'
NAV=[("home","/","Home"),("news","/news/","News"),("newco","/newco/","NewCo Services"),("conf","/conferences/","Conferences"),("about","/about/","About"),("contact","/contact/","Contact")]

def page(active,title,desc,path,body,extra_head="",scripts="",og_type="website"):
    url=SITE+path
    navlinks="".join(f'<a href="{h}" data-v="{k}"{" class=\"on\"" if k==active else ""}>{l}</a>' for k,h,l in NAV)
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<style>:root{{color-scheme:light}}body{{margin:0;font-size:14px}}img{{max-width:100%}}[hidden]{{display:none!important}}</style>
<title>{e(title)}</title>
<meta name="description" content="{e(desc)}">
<meta name="author" content="InLight Bio / Qiyuan Zhiyan">
<link rel="canonical" href="{url}">
<link rel="alternate" hreflang="en" href="{url}">
<link rel="alternate" hreflang="zh-CN" href="{ZH}/">
<meta property="og:title" content="{e(title)}">
<meta property="og:description" content="{e(desc)}">
<meta property="og:type" content="{og_type}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{SITE}/img/og-image-en.png">
<meta property="og:locale" content="en_US">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" type="image/png" href="/img/favicon.png">
<link rel="apple-touch-icon" href="/img/apple-touch-icon.png">
<link rel="alternate" type="application/rss+xml" title="InLight Bio" href="{SITE}/feed.xml">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Noto+Serif:wght@600;800&family=Noto+Sans:wght@400;500;700&display=swap">
<link rel="stylesheet" href="/assets/css/site.css?v=1">
{extra_head}
</head>
<body>
<nav><div class="navshell"><div class="nav-in">
  <a class="qy-made" href="/about/" title="Qiyuan Zhiyan (Beijing)"><img src="/img/brand/qiyuan_mark_A_tight.svg" alt="" aria-hidden="true" width="28" height="26"><span>by Qiyuan Zhiyan</span></a>
  <a class="brand" href="/"><span class="bmark-wrap"><img src="/img/logo.png" alt="" onerror="this.remove()" onload="var s=this.nextElementSibling;if(s)s.remove()">{MARK_SVG}</span><span class="btext"><span class="bn">InLight Bio</span><span class="bs">CHINA BIOPHARMA · GLOBAL</span></span></a>
  <div class="nav-tabs">{navlinks}</div>
  <a class="navsub" href="/subscribe/">Subscribe</a>
</div></div></nav>
<div class="shell"><div class="col">
{body}
</div></div>
<footer><div class="footshell"><div class="foot-in">
  <div class="fbrand"><b>InLight Bio</b>
    <p class="fco" style="display:flex;align-items:center;gap:8px"><img src="/img/brand/qiyuan_mark_A_tight.svg" alt="" aria-hidden="true" width="28" height="26" style="display:block;height:26px;width:auto;flex:none"><span>Published by Qiyuan Zhiyan (启元智研, Beijing). English edition of <a href="{ZH}/" lang="zh-CN">前沿追踪</a>.</span></p></div>
  <div class="footnav"><a href="/">Home</a><a href="/news/">News</a><a href="/newco/">NewCo Services</a><a href="/conferences/">Conferences</a><a href="/about/">About</a><a href="/contact/">Contact</a><a href="/subscribe/">Subscribe</a><a href="/feed.xml">RSS</a></div>
  <div class="footcols"><p class="footmail">NewCo &amp; deal inquiries: <a href="{mailto(BD)}">{BD}</a></p><p class="footmail">Newsletter, reports &amp; corrections: <a href="{mailto(CONTACT)}">{CONTACT}</a></p></div>
  <p class="footnote">News items are summaries of public disclosures with links to the original source; not investment advice. If a company we cover is a client or counterparty of our NewCo services, we say so at the top of the item.</p>
</div></div></footer>
{scripts}
</body>
</html>
'''

def kind_tags(x): return "".join(f'<span class="kind">{e(KINDS[k])}</span>' for k in x["kinds"])
def deal_card(x):
    nil="" if any(c.isdigit() for c in x["m"]) else " nil"
    return f'''<div class="item" data-slug="{e(x["slug"])}"><a class="cover" href="/news/{e(x["slug"])}.html" aria-hidden="true" tabindex="-1"><img class="coverimg" src="/img/deals/{e(x["img"])}" alt="" loading="lazy"></a>
  <div class="cbody"><h3><a href="/news/{e(x["slug"])}.html">{e(x["t"])}</a></h3><div class="money{nil}">{e(x["m"])}</div>
  <div class="metarow"><span class="idate">{ym(x["d"])}</span><span class="tagrow">{kind_tags(x)}</span><button class="expbtn" type="button" aria-expanded="false" data-slug="{e(x["slug"])}">Details ↓</button></div></div></div>'''
NEWS_JS="<script>window.KINDS="+json.dumps(KINDS)+";window.NEWS="+json.dumps([{k:x[k] for k in ("slug","t","m","ms","why","src","url","kinds","china","d")} for x in NEWS],ensure_ascii=False)+";</script>"
SCRIPT='<script src="/assets/js/site.js?v=1" defer></script>'

def conf_end(c): return c["dates"].split(" to ")[-1] if c["dates"]!="TBA" else "9999"
def conf_short(c):
    if c["dates"]=="TBA": return "Dates TBA"
    a,b=c["dates"].split(" to "); pa,pb=a.split("-"),b.split("-")
    if pa[1]==pb[1]: return f'{MON[int(pa[1])-1]} {int(pa[2])}–{int(pb[2])}, {pa[0]}'
    return f'{MON[int(pa[1])-1]} {int(pa[2])} – {MON[int(pb[1])-1]} {int(pb[2])}, {pb[0]}'

HERO_SVG=open(os.path.join(HERE,"hero_svg.html"),encoding="utf-8").read()

# ================= HOME =================
lead=next(x for x in NEWS if x["slug"]=="haisco-sentivera-newco")
upc=sorted([c for c in CONFS if c["dates"]!="TBA" and conf_end(c)>=BUILD],key=lambda c:c["dates"])[:8]
mini="".join(f'<a href="/conferences/" data-end="{conf_end(c)}"><span class="md">{conf_short(c)}</span><span><b>{e(c["name"])}</b><span>{e(c["city"])} · {e(c["kind"])}</span></span></a>' for c in upc)
short_rows="".join(f'<tr><td><b>{e(r["newco"].split(" (")[0])}</b></td><td>{e(r["licensor"])}</td><td class="num" style="color:var(--red)">{e(r["upfront"].split(" (")[0])}</td><td class="tn">{ym(r["date"])}</td></tr>' for r in NEWCO[:6])
home=f'''<div class="wrap view">
  <section class="hero-band">
    <div class="hb-art" aria-hidden="true">{HERO_SVG}<img src="/img/hero_v6.jpg?v=1" alt="" onerror="this.remove()"></div>
    <div class="hb-text">
      <span class="hb-kicker">ENGLISH EDITION · UPDATED WEEKLY</span>
      <h1>InLight Bio</h1>
      <p>China biopharma going global: out-licensing, NewCo formation and clinical data, summarized from primary sources with links. Built for US investors, pharma BD teams and NewCo founders.</p>
      <div class="hb-cta"><a class="btn" href="/newco/">NewCo services</a><a class="btn ghost" href="/news/">Latest deals</a></div>
      <div class="hb-stats"><span><b>{len(NEWS)}</b> deal briefs</span><span><b>{len(NEWCO)}</b> China→NewCo deals tracked</span><span><b>{len(CONFS)}</b> events listed</span></div>
    </div>
  </section>
  <section class="lead">
    <div class="leadtag">LEAD STORY · NEWCO</div>
    <h1>{e(lead["t"])}</h1>
    <p class="just">{e(lead["ms"])}. {e(lead["why"].split(". ")[0])}.</p>
    <div class="leadfoot"><span class="idate">{ym(lead["d"])} · Source: {e(lead["src"])}</span><a class="go" href="/news/{lead["slug"]}.html">Read the brief →</a></div>
  </section>
  <section class="ncta">
    <span class="k">FOR CHINA ASSET OWNERS · US INVESTORS · PHARMA BD</span>
    <h2>From a China asset to a US NewCo</h2>
    <p>We help Chinese biotechs out-license assets into newly formed US companies backed by investors and led by US management, and help investors and founders find China assets worth building around. Confidential assets are shared in tiers: anonymous one-page teaser first, then NDA, then data room.</p>
    <div class="cta"><a class="btn" href="/newco/">How it works</a><a class="btn ghost" href="{mailto(BD,'NewCo inquiry')}">Email {BD}</a></div>
  </section>
  <section>
    <div class="sechead"><h2>Latest deals &amp; data</h2><span><a href="/news/">All news →</a></span></div>
    <div class="feed" id="homefeed">{"".join(deal_card(x) for x in NEWS[:4])}</div>
  </section>
  <section class="two">
    <div><div class="sechead"><h2>Recent China-to-NewCo deals</h2><span><a href="/newco/#deals">Full table ({len(NEWCO)}) →</a></span></div>
      <div class="tblw dealtbl short"><table><tr><th>NewCo</th><th>China licensor</th><th>Upfront (as disclosed)</th><th>Date</th></tr>{short_rows}</table></div></div>
    <div><div class="sechead"><h2>Upcoming events</h2><span><a href="/conferences/">All events →</a></span></div>
      <div class="mini-conf" id="miniconf">{mini}</div></div>
  </section>
  <section class="subblock">
    <div><h2>One email a week, in English</h2><p>China out-licensing, NewCo and clinical-data briefs, each with a link to the original source. Free; unsubscribe any time.</p></div>
    <a class="btn" href="/subscribe/">Subscribe</a>
  </section>
</div>'''
home_js='''<script>(function(){var t=new Date(),p=n=>String(n).padStart(2,'0'),d=t.getFullYear()+'-'+p(t.getMonth()+1)+'-'+p(t.getDate()),k=0;document.querySelectorAll('#miniconf a').forEach(function(a){if(a.dataset.end<d||k>=5){a.hidden=true}else k++})})();</script>'''
w("index.html", page("home","InLight Bio — China biopharma deals, NewCos and clinical data","English-language briefs on China biopharma going global: out-licensing, NewCo formation, clinical data and partnering events, for US investors, BD teams and NewCo founders.","/",home,scripts=NEWS_JS+SCRIPT+home_js))

# ================= NEWS INDEX =================
TILE={"lic":"lic_bluelight_v4.jpg","newco":"inv_bluelight_v4.jpg","acq":"acq_bluelight_v4.jpg","clin":"clin_bluelight_v4.jpg","inv":"inv_bluelight_v4.jpg"}
DESC={"lic":"Out-licensing and co-development of drug or platform rights","newco":"China assets licensed into newly formed ex-China companies","acq":"Company or asset acquisitions that set buyer appetite","clin":"Clinical readouts that move asset value","inv":"Equity financings and investments"}
def tcount(k): return sum(1 for x in NEWS if k in x["kinds"])
trk="".join(f'<a class="trkcard art" href="?type={k}" data-g="{k}" style="--dc:var(--accent)"><span class="artthumb"><img src="/img/tiles/{TILE[k]}?v=4" alt="" loading="lazy"></span><div class="cbody"><b>{KINDS[k]}</b><span>{DESC[k]}</span><em>{tcount(k)} item{"s" if tcount(k)!=1 else ""}</em></div></a>' for k in ["lic","newco","acq","clin","inv"])
trk+=f'<a class="trkcard art" href="/conferences/" style="--dc:var(--accent)"><span class="artthumb"><img src="/img/tiles/conf_bluelight_v4.jpg?v=4" alt="" loading="lazy"></span><div class="cbody"><b>Conferences</b><span>Partnering, investor and scientific meetings, next 12 months</span><em>{len(CONFS)} events</em></div></a>'
news=f'''<div class="wrap view">
  <header class="hero"><h1>News &amp; Insights</h1>
    <p>Licensing, NewCo formation, acquisitions and clinical readouts that matter for China-originated assets and the buyers looking at them. Only publicly disclosed or mutually confirmed deals; each item links to the company announcement or trade-press source. Upfront and milestone amounts are listed separately, as disclosed. Translated from the Chinese edition (前沿追踪).</p></header>
  <section><div class="sechead"><h2>Browse by type</h2><span>Click to filter</span></div><div class="trkgrid">{trk}</div></section>
  <section id="newsfeedsec" style="scroll-margin-top:80px">
    <div class="sechead"><h2>Latest</h2><span id="newscount">{len(NEWS)} items, newest first</span>
      <details class="confcal" id="nfcal"><summary aria-label="Filter news">{FILTER_ICON}<span id="nflabel">Filter</span>{CHEV}</summary>
        <div class="calpop"><div class="calk">Type</div><div id="nf-type"></div><div class="calk">Companies</div><div id="nf-cn"></div></div></details></div>
    <div class="feed" id="newsfeed">{"".join(deal_card(x) for x in NEWS)}</div>
  </section>
  <section>
    <div class="sechead"><h2>Annual tally</h2><span>China innovative-drug out-licensing</span></div>
    <div class="tblw"><table style="min-width:520px"><tr><th>Year</th><th>Deals</th><th>Total value</th><th>Upfront payments, combined</th></tr>
      <tr><td>2024</td><td class="num">94</td><td class="num">$51.9B</td><td>—</td></tr>
      <tr><td>2025</td><td class="num">157</td><td class="num">$135.7B</td><td class="num">$7.0B</td></tr></table></div>
    <p class="note just" style="margin-top:12px">Data from <a href="https://globalforum.diaglobal.org/issue/march-2026/chinas-out-licensing-deals-bear-fruit-in-2025/" target="_blank" rel="noopener">DIA Global Forum, March 2026</a>. Upfront payments were only about 5% of total value; the rest is paid only if development reaches agreed milestones, and much of it never will be.</p>
  </section>
</div>'''
w("news/index.html", page("news","News & Insights — InLight Bio","China out-licensing, NewCo, M&A and clinical-data briefs with deal terms and source links.","/news/",news,scripts=NEWS_JS+SCRIPT))

# ================= NEWS ARTICLES =================
for i,x in enumerate(NEWS):
    prev=NEWS[i-1] if i>0 else None; nxt=NEWS[i+1] if i+1<len(NEWS) else None
    pn=lambda a,k,cls: f'<a class="pn {cls}" href="/news/{a["slug"]}.html"><span class="k">{k}</span><b>{e(a["t"])}</b><em>{ym(a["d"])}</em></a>' if a else f'<span class="pn none {cls}"><span class="k">{k}</span><b>None</b></span>'
    rel=[y for y in NEWS if y is not x and set(y["kinds"])&set(x["kinds"])][:4]
    body=f'''<div class="wrap view pv-art npage"><article>
  <div class="ahead"><a class="back" href="/news/">← News &amp; Insights</a>
    <span class="eyebrow">{" · ".join(KINDS[k] for k in x["kinds"]).upper()} · {ym(x["d"]).upper()}</span>
    <h1>{e(x["t"])}</h1>
    <div class="pv-hero"><img src="/img/deals/{e(x["img"])}" alt="" width="1280" height="640"><span class="cap">Illustration (decorative, not data).</span></div></div>
  <div class="abody">
    <aside class="meta side2">
      <section class="sbox look"><span class="k">Headline terms</span><p class="money">{e(x["m"])}</p><p>{e(x["ms"])}</p></section>
      <section class="sbox"><span class="k">Source</span><p class="cite"><a href="{e(x["url"])}" target="_blank" rel="noopener">{e(x["src"])}</a></p></section>
      <section class="sbox"><span class="k">Edition note</span><p class="zhnote">Translated from the Chinese edition <a href="{ZH}/#deals" lang="zh-CN">前沿追踪 · 经济动态</a> (original title: <span lang="zh-CN">{e(x["zh_t"])}</span>). No facts added in translation.</p></section>
    </aside>
    <div class="amain">
      <section class="sec"><h2>Summary</h2><p>{e(x["why"])}</p></section>
      <section class="sec"><h2>Deal terms, as disclosed</h2><p>{e(x["ms"])}.</p></section>
      <p class="note just">Summary of public disclosures, not investment advice. Amounts are as announced; milestone payments are contingent and may never be paid.</p>
      <section class="art-end" aria-label="Continue reading">
        <div class="art-pn">{pn(prev,"← Newer","prev")}{pn(nxt,"Older →","next")}</div>
        {"<div class='art-rel'><h2>Related <small>same deal type</small></h2><ul>"+"".join(f"<li><a href='/news/{y['slug']}.html'>{e(y['t'])}</a><span>{ym(y['d'])}</span></li>" for y in rel)+"</ul></div>" if rel else ""}
        <div class="art-sub"><div><b>Working on a China asset or a NewCo?</b><p>Asset owners and investors: write to {BD}. Newsletter and report questions: {CONTACT}.</p></div><a class="btn" href="/newco/">NewCo services</a></div>
      </section>
    </div></div></article></div>'''
    ld={"@context":"https://schema.org","@type":"NewsArticle","headline":x["t"],"datePublished":x["d"]+"-01","publisher":{"@type":"Organization","name":"InLight Bio"},"image":SITE+"/img/deals/"+x["img"],"mainEntityOfPage":SITE+f"/news/{x['slug']}.html","inLanguage":"en"}
    w(f"news/{x['slug']}.html", page("news",x["t"]+" — InLight Bio",x["m"]+". "+x["why"][:150],f"/news/{x['slug']}.html",body,extra_head='<script type="application/ld+json">'+json.dumps(ld,ensure_ascii=False)+'</script>',og_type="article"))

# ================= CONFERENCES =================
conf=f'''<div class="wrap view">
  <header class="hero"><h1>Conferences &amp; Partnering</h1>
    <p>Major US and international biopharma partnering, investor and scientific meetings for the next 12 months. Filter by time range or type with the calendar button; events that have ended are hidden automatically. Dates and cities were checked on each organizer's official website on {CHECKED}; anything not yet confirmed there is marked <b>Dates TBA</b> and listed last. Investor conferences are generally invitation-only. Please re-check the official site before travelling.</p></header>
  <section>
    <div class="sechead"><h2>Event calendar</h2><span id="confcount"></span>
      <details class="confcal" id="confcal"><summary aria-label="Choose time range, type and sort order">{CAL_ICON}<span id="confcallabel">All upcoming</span>{CHEV}</summary>
        <div class="calpop"><div class="calk">Time range</div><div id="confrange"></div><div class="calk">Type</div><div id="confkind"></div><div class="calk">Sort</div><div id="confsort"></div></div></details></div>
    <div class="conflist" id="conflist"><noscript><div class="empty">Enable JavaScript to filter; the full list is in <a href="/data/conferences.json">conferences.json</a>.</div></noscript></div>
    <p class="note just" style="margin-top:12px">Meeting someone at one of these events about a China asset or a NewCo? Write to <a href="{mailto(BD,'Meeting request')}">{BD}</a>. Spotted a wrong date? <a href="{mailto(CONTACT,'Conference correction')}">{CONTACT}</a>. Data file: <a href="/data/conferences.json">/data/conferences.json</a>.</p>
  </section>
</div>'''
conf_js="<script>window.CONF_CHECKED="+json.dumps(CHECKED)+";window.CONFS="+json.dumps(CONFS,ensure_ascii=False)+";</script>"
w("conferences/index.html", page("conf","Biopharma Conferences & Partnering Events 2026–2027 — InLight Bio","JPM, BIO, BIO-Europe, ASCO, AACR, ASH, ESMO, SITC, ADA, ChinaBio and more: verified dates, cities and official links for the next 12 months.","/conferences/",conf,scripts=conf_js+SCRIPT))
w("data/conferences.json", json.dumps({"checked":CHECKED,"note":"verified=true means dates and city were read from the official URL on the checked date; dates='TBA' means not yet published officially.","events":CONFS},ensure_ascii=False,indent=1))

# ================= NEWCO =================
DIAGRAM=open(os.path.join(HERE,"newco_diagram.svg"),encoding="utf-8").read()
rows=""
for r in NEWCO:
    srcs="".join(f'<a href="{e(u)}" target="_blank" rel="noopener">{e(n)}</a>' for n,u in r["src"])
    rows+=f'<tr><td><b>{e(r["newco"])}</b><span class="tn">{e(r["asset"])}</span></td><td>{e(r["licensor"])}</td><td>{e(r["investors"])}</td><td class="m">{e(r["upfront"])}</td><td>{e(r["total"])}</td><td class="tn" style="white-space:nowrap">{ym(r["date"])}</td><td class="out">{e(r["outcome"]) or "—"}</td><td class="src">{srcs}</td></tr>'
newco=f'''<div class="wrap view textpage">
  <header class="hero"><h1>NewCo Services</h1>
    <p>China now originates a large share of the world's licensable clinical assets. A NewCo turns one of those assets into a US company: investors fund it, an experienced US team runs global development, and the Chinese originator keeps Greater China rights plus cash, equity, milestones and royalties. We work on both sides of that transaction: sourcing and packaging China assets, and connecting them with the investors, founders and pharma partners who build around them.</p></header>

  <section class="aud">
    <div class="audc"><span class="k">China asset owners</span><h3>Get your asset in front of the right US capital</h3>
      <ul><li>Assess whether an asset fits a NewCo, a straight license or a co-development deal.</li><li>Prepare an anonymous one-page teaser and an investor-grade data package in English.</li><li>Introduce you to US VCs, company-creation firms and management teams, and support term-sheet discussions (upfront, equity, milestones, royalties, territory).</li></ul>
      <a class="btn" href="{mailto(BD,'Asset owner - NewCo inquiry')}">Email {BD}</a></div>
    <div class="audc"><span class="k">US investors &amp; NewCo founders</span><h3>Source China assets worth building a company around</h3>
      <ul><li>Curated, pre-screened deal flow by modality and indication, starting from non-confidential teasers.</li><li>Fast access to Chinese clinical data, CMC status and IP position under NDA.</li><li>Bilingual diligence support and coordination with the licensor's team in China.</li></ul>
      <a class="btn" href="{mailto(BD,'Investor - asset search')}">Email {BD}</a></div>
    <div class="audc"><span class="k">Pharma BD</span><h3>Option, partner or acquire later</h3>
      <ul><li>Track China-originated assets and NewCos in your therapeutic areas.</li><li>Early look at teasers that match your search criteria.</li><li>Structures that fit pharma: options, co-funding, and acquisition paths once the NewCo has generated global data.</li></ul>
      <a class="btn" href="{mailto(BD,'Pharma BD - search criteria')}">Email {BD}</a></div>
  </section>

  <section class="panel">
    <h2>How the NewCo model works</h2>
    <div class="diagram">{DIAGRAM}</div>
    <p>A Chinese company licenses ex-Greater China rights to a newly formed company (usually a Delaware corporation). Investors fund the NewCo, typically a Series A sized to reach a clinical inflection point, and recruit a US leadership team. The licensor is paid an upfront amount (cash and/or NewCo equity), development, regulatory and sales milestones, and royalties, and keeps its home-market rights. Value is realized when the NewCo raises later rounds, lists, or is acquired by a pharma company: Aiolos Bio (Hengrui asset) was acquired by GSK, and Ouro Medicines (Keymed asset) by Gilead; see the <a href="#deals">deal table</a>.</p>
    <p>Typical trade-offs: a licensor gives up near-term cash compared with a big-pharma license in exchange for equity upside and a dedicated global team; investors get a de-risked, often clinical-stage asset at a lower entry price than building from discovery. In many recent deals the upfront plus equity has been a small fraction of the headline value, so milestone design and governance matter.</p>
  </section>

  <section class="panel">
    <h2>Process</h2>
    <ol class="steps">
      <li><b>Screen</b>Non-confidential review of the asset: mechanism, stage, Chinese data, competitive landscape, IP and CMC status, and whether ex-China rights are free.</li>
      <li><b>Anonymous teaser</b>A one-page blinded profile (modality, indication, stage, headline data already public) shared with selected investors and founders.</li>
      <li><b>NDA and deep dive</b>Interested parties sign an NDA with the licensor; full data, regulatory history and CMC are reviewed with both teams.</li>
      <li><b>Term sheet</b>Territory, upfront (cash/equity), milestones, royalties, supply, governance and technology-transfer plan.</li>
      <li><b>Company formation</b>NewCo incorporation, Series A close, management recruitment, license execution.</li>
      <li><b>Global development</b>US IND, bridging or global trials, and continued data sharing with the licensor's China program.</li>
    </ol>
  </section>

  <section class="panel">
    <h2>Confidentiality tiers</h2>
    <div class="tiers">
      <div class="tier"><span class="lv">TIER 0</span><h3>Public</h3><p>Published papers, conference abstracts, company announcements. Used for screening and for this site.</p><span class="gate">Gate: none</span></div>
      <div class="tier"><span class="lv">TIER 1</span><h3>Anonymous teaser</h3><p>One page, licensor not named. Only information that is already public or approved by the owner for blinded circulation.</p><span class="gate">Gate: owner sign-off</span></div>
      <div class="tier"><span class="lv">TIER 2</span><h3>NDA package</h3><p>Licensor identified; non-public data summary, development plan, IP overview and indicative terms.</p><span class="gate">Gate: signed NDA with the asset owner</span></div>
      <div class="tier"><span class="lv">TIER 3</span><h3>Data room</h3><p>Full clinical, preclinical, CMC and regulatory documents, plus management Q&amp;A, for serious bidders.</p><span class="gate">Gate: NDA + term-sheet stage, owner approval</span></div>
    </div>
  </section>

  <section class="panel">
    <h2>What we need from each side</h2>
    <div class="needs">
      <div><h3 style="font-size:15px;margin-bottom:6px">Asset owners</h3><ul><li>Rights available (territory, field) and any existing partners or options.</li><li>Stage and public data references; what can be shown blinded.</li><li>Your preferred structure: license, NewCo, co-development; equity expectations.</li><li>A decision-maker who can approve teaser circulation and NDAs.</li></ul></div>
      <div><h3 style="font-size:15px;margin-bottom:6px">Investors &amp; founders</h3><ul><li>Search criteria: modality, indication, stage, geography of data.</li><li>Check size and whether you lead, co-lead or follow.</li><li>Whether a CEO or team is already in place.</li><li>Timeline and decision process.</li></ul></div>
      <div><h3 style="font-size:15px;margin-bottom:6px">Pharma BD</h3><ul><li>Therapeutic areas and modalities of interest; exclusions.</li><li>Preferred deal types: option, license, co-fund, later acquisition.</li><li>Stage gates you need to see before engaging.</li><li>A named contact for teaser review.</li></ul></div>
    </div>
  </section>

  <section class="panel" id="teaser">
    <h2>Submit a non-confidential asset teaser</h2>
    <div class="warnbox"><b>Please do not send confidential information before an NDA is in place.</b> Send only information that is already public or that you are willing to circulate without restriction. We will not forward anything that identifies your company without your written approval.</div>
    <p>Email <a href="{mailto(BD,'Non-confidential asset teaser')}">{BD}</a> with the subject “Non-confidential asset teaser” and these fields:</p>
    <ul class="fieldlist2">
      <li>Modality (small molecule, antibody, bispecific/TCE, ADC, siRNA, cell/gene therapy, other)</li>
      <li>Target / mechanism (or “undisclosed”)</li>
      <li>Lead indication(s)</li>
      <li>Development stage and where trials ran</li>
      <li>Headline data that is already public, with references</li>
      <li>Rights available (e.g., ex-Greater China, global)</li>
      <li>Patent status in one line (filed / granted; regions)</li>
      <li>CMC / supply status in one line</li>
      <li>Preferred deal type (NewCo, license, co-development, open)</li>
      <li>Contact person and role</li>
    </ul>
  </section>

  <section id="deals" style="scroll-margin-top:80px">
    <div class="sechead"><h2>Recent China-to-NewCo deals</h2><span>{len(NEWCO)} deals · public sources only · checked {BUILD}</span></div>
    <div class="tblw dealtbl"><table>
      <tr><th>NewCo / asset</th><th>China licensor</th><th>Investors / financing</th><th>Upfront</th><th>Milestones / total</th><th>Date</th><th>Later outcome</th><th>Sources</th></tr>{rows}</table></div>
    <p class="note just" style="margin-top:12px">Built only from public announcements (company releases, HKEX/SEC filings) and trade press, linked in the last column. Amounts are as disclosed and are not comparable one-to-one: some include equity or warrants, and milestones are contingent. “Reported” means figures come from press coverage rather than a company filing. Vor Bio is an existing Nasdaq company that was recapitalized around the in-licensed asset rather than a newly formed company; it is included because the structure is NewCo-like. Date = license announcement (month). Corrections: <a href="{mailto(CONTACT,'Deal table correction')}">{CONTACT}</a>.</p>
  </section>

  <section class="panel">
    <h2>Engagement</h2>
    <p>Engagement terms are agreed case by case; contact <a href="{mailto(BD,'Engagement terms')}">{BD}</a>.</p>
    <p>InLight Bio's editorial coverage is independent of NewCo mandates. If a company covered on this site is a client or counterparty, we disclose it at the top of the item.</p>
    <h3 style="font-size:15px;margin:14px 0 6px">Important notice</h3>
    <p class="note just">InLight Bio provides information and introductions only. InLight Bio is not a broker-dealer, investment adviser or placement agent, and nothing on this site is an offer or solicitation to buy or sell any securities. Please do not send confidential information before an NDA is in place. Information on this site may be incomplete or out of date; verify it independently before relying on it.</p>
  </section>

  <section class="bigcta">
    <div><h2>Have an asset, or looking for one?</h2><p>Asset owners, investors and NewCo founders: {BD}. We typically reply within 2 business days.</p></div>
    <a class="btn" href="{mailto(BD,'NewCo inquiry')}">Email {BD}</a>
  </section>
</div>'''
w("newco/index.html", page("newco","NewCo Services: China assets into US NewCos — InLight Bio","How the China-to-US NewCo model works, our process and confidentiality tiers, and a sourced table of recent China-to-NewCo deals. Contact bd@inlightbio.com.","/newco/",newco,scripts=SCRIPT))
w("data/newco_deals.json", json.dumps({"checked":BUILD,"deals":[dict(r,src=[{"name":n,"url":u} for n,u in r["src"]]) for r in NEWCO]},ensure_ascii=False,indent=1))
w("data/news.json", json.dumps({"built":BUILD,"items":NEWS},ensure_ascii=False,indent=1))

# ================= ABOUT =================
about=f'''<div class="wrap view textpage">
  <header class="hero"><h1>About InLight Bio</h1><p>InLight Bio is the English edition of 前沿追踪 (Frontier Digest, <a href="{ZH}/">inlight.therasik.com</a>), published by Qiyuan Zhiyan (启元智研, Beijing).</p></header>
  <section class="panel"><h2>What we cover</h2>
    <p>China biopharma going global: out-licensing deals, NewCo formation, acquisitions of China-originated assets, and the clinical data that drives their value. Readers are US investors, pharma business-development teams and NewCo founders who need a fast, sourced view of what is happening in China.</p>
    <p>Each brief gives the headline terms with upfront and milestone payments separated, a short summary of the science and the deal logic, and a link to the original announcement or trade-press source.</p></section>
  <section class="panel"><h2>Editorial principles</h2><ul>
    <li><b>Sources.</b> Every item links to its original source. Items based only on a press release or secondary coverage say so.</li>
    <li><b>Deal amounts.</b> Upfront and milestones are listed separately, as publicly disclosed. Nothing here is investment advice.</li>
    <li><b>Translation.</b> English items are translated from the Chinese edition without adding facts or numbers.</li>
    <li><b>Illustrations.</b> Images on deal items are AI-generated decorative illustrations, not data or journal figures.</li>
    <li><b>Conflicts.</b> We also run a <a href="/newco/">NewCo services</a> business. If a company we cover is a client or counterparty, we disclose it at the top of the item. Sponsored content, if any, is labelled and kept separate from editorial content.</li>
    <li><b>Corrections.</b> Send corrections to <a href="{mailto(CONTACT,'Correction')}">{CONTACT}</a>; we mark corrections on the item.</li></ul></section>
  <section class="panel coblock"><h2>Publisher</h2><img class="colockup" src="/img/brand/qiyuan_logo_A_tight.svg" alt="Qiyuan Zhiyan (启元智研) logo" width="252" height="64"><p>Qiyuan Zhiyan (启元智研) is a Beijing-based company providing scientific content and biopharma business services. It publishes and maintains both editions of the site.</p></section>
  <section class="panel"><h2>Contact</h2><div class="contact">
    <div class="cc"><span>NewCo &amp; deals</span><a href="{mailto(BD,'NewCo inquiry')}">{BD}</a></div>
    <div class="cc"><span>Reports, newsletter, corrections</span><a href="{mailto(CONTACT)}">{CONTACT}</a></div>
    <div class="cc"><span>Weekly email</span><a href="/subscribe/">Subscribe</a></div></div></section>
</div>'''
w("about/index.html", page("about","About — InLight Bio","InLight Bio is the English edition of 前沿追踪, published by Qiyuan Zhiyan (Beijing). Coverage, editorial principles and conflicts policy.","/about/",about))

# ================= CONTACT =================
contact=f'''<div class="wrap view textpage">
  <header class="hero"><h1>Contact</h1><p>Two addresses, so your message reaches the right person.</p></header>
  <section class="aud aud2">
    <div class="audc"><span class="k">NewCo &amp; deals only</span><h3><a href="{mailto(BD,'NewCo inquiry')}">{BD}</a></h3>
      <ul><li>China asset owners considering a NewCo or out-license.</li><li>US investors, company-creation firms and NewCo founders looking for assets.</li><li>Pharma BD teams sharing search criteria.</li><li>Non-confidential teasers only before an NDA; see <a href="/newco/#teaser">submission guidance</a>.</li></ul></div>
    <div class="audc"><span class="k">Reports &amp; content</span><h3><a href="{mailto(CONTACT)}">{CONTACT}</a></h3>
      <ul><li>Newsletter subscriptions and unsubscribes.</li><li>Questions about reports and articles.</li><li>Corrections and content suggestions.</li><li>Sponsorship and media inquiries.</li></ul></div>
  </section>
  <section class="panel"><h2>Publisher</h2><p>Qiyuan Zhiyan (启元智研), Beijing, China. Chinese edition: <a href="{ZH}/">inlight.therasik.com</a>.</p></section>
</div>'''
w("contact/index.html", page("contact","Contact — InLight Bio","NewCo and deal inquiries: bd@inlightbio.com. Newsletter, reports and corrections: contact@inlightbio.com.","/contact/",contact))

# ================= SUBSCRIBE =================
sub=f'''<div class="wrap view textpage">
  <header class="hero"><h1>Subscribe</h1><p>One email a week, in English: China out-licensing, NewCo and clinical-data briefs, each with a source link. Free; unsubscribe any time.</p></header>
  <section class="panel"><h2>Sign up</h2>
    <p>To subscribe, email <a href="{mailto(CONTACT,'Subscribe')}">{CONTACT}</a> with the subject “Subscribe” and we will add you to the weekly list.</p>
    <p>Prefer a feed? Use <a href="/feed.xml">RSS</a>.</p></section>
  <section class="panel"><h2>What you get</h2><ul>
    <li>New China out-licensing and NewCo deals, with upfront and milestones separated.</li>
    <li>Clinical readouts that change the value of China-originated assets.</li>
    <li>Upcoming partnering and investor meetings.</li></ul>
    <p class="note">Working on a NewCo? That goes to <a href="{mailto(BD,'NewCo inquiry')}">{BD}</a>, not the newsletter address.</p></section>
</div>'''
w("subscribe/index.html", page("","Subscribe — InLight Bio","Weekly English email on China biopharma deals, NewCos and clinical data.","/subscribe/",sub))

# ================= 404 =================
w("404.html", page("","Page not found — InLight Bio","Page not found.","/404.html",'<div class="wrap view textpage"><header class="hero"><h1>Page not found</h1><p>Try the <a href="/">home page</a>, <a href="/news/">News</a> or <a href="/newco/">NewCo Services</a>.</p></header></div>'))

# ================= sitemap / robots / rss / CNAME =================
urls=["/","/news/","/newco/","/conferences/","/about/","/contact/","/subscribe/"]+[f"/news/{x['slug']}.html" for x in NEWS]
w("sitemap.xml",'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'+"".join(f"  <url><loc>{SITE}{u}</loc><lastmod>{BUILD}</lastmod></url>\n" for u in urls)+"</urlset>\n")
w("robots.txt",f"User-agent: *\nAllow: /\nDisallow: /_build/\nDisallow: /_work/\nDisallow: /_shots/\n\nSitemap: {SITE}/sitemap.xml\n")
def rfc(d): 
    y,m=map(int,d.split("-")[:2]); return format_datetime(datetime.datetime(y,m,1,12,0,tzinfo=datetime.timezone.utc))
items="".join(f"""  <item><title>{e(x['t'])}</title><link>{SITE}/news/{x['slug']}.html</link><guid isPermaLink="true">{SITE}/news/{x['slug']}.html</guid><pubDate>{rfc(x['d'])}</pubDate><description>{e(x['m']+'. '+x['why'])}</description></item>\n""" for x in NEWS)
w("feed.xml",f'''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
  <title>InLight Bio</title><link>{SITE}/</link><description>China biopharma going global: out-licensing, NewCo and clinical-data briefs.</description><language>en</language>
  <atom:link href="{SITE}/feed.xml" rel="self" type="application/rss+xml"/>
  <lastBuildDate>{format_datetime(datetime.datetime(2026,10,11,12,0,tzinfo=datetime.timezone.utc))}</lastBuildDate>
{items}</channel>
</rss>
''')
w("CNAME","inlightbio.com\n"); w(".nojekyll","")
print("built", len(urls), "urls")
