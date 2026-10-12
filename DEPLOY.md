# Deploying InLight Bio (English edition) to https://inlightbio.com

Status: launch-ready publish copy prepared at `/workspace/inlight_en_publish/` (local git repo, not pushed). DNS not changed.

## 1. Repository: recommended setup

Use a **new, separate repo**, e.g. `jhuang7908/inlightbio-en`, served by GitHub Pages from `main` / root.
Reasons:

- A GitHub Pages site can have only one custom domain. `therasik-inlight` already serves `inlight.therasik.com`, so the English site at `inlightbio.com` needs its own repo (or its own Pages site).
- Root-relative URLs (`/assets/...`, `/news/...`) assume the site is at the domain root, which a custom domain provides.
- Keeping the repos separate means EN changes never risk the live Chinese site.

Steps (for the owner, when ready):

1. Create `jhuang7908/inlightbio-en` (public, or private on a plan that supports Pages).
2. Copy the contents of this folder into it. `CNAME` (containing `inlightbio.com`) and `.nojekyll` are included.
   - Optional: leave out `_build/`, `_work/`, `_shots/`. They are harmless if published (robots.txt disallows them), but `_work/` holds verification scratch files. Recommended: commit `_build/` (the generator and data) and add `_work/` and `_shots/` to `.gitignore`.
3. Repo Settings → Pages → Source: “Deploy from a branch”, `main`, `/ (root)`.
4. Settings → Pages → Custom domain: `inlightbio.com`. Save. Wait for the DNS check to pass (after section 2), then tick **Enforce HTTPS**. The certificate can take up to about an hour.
5. Recommended: verify the domain for the GitHub account (Settings → Pages → “Add a verified domain”), which adds a `_github-pages-challenge-jhuang7908` TXT record. This stops anyone else from claiming the domain on Pages.

## 2. Namecheap DNS changes (Domain List → inlightbio.com → Advanced DNS)

### Remove ONLY these two

| Type | Host | Value |
|---|---|---|
| URL Redirect Record | @ | (Namecheap parking/redirect) |
| CNAME Record | www | Namecheap parking (usually parkingpage.namecheap.com) |

### Add

| Type | Host | Value | TTL |
|---|---|---|---|
| A Record | @ | 185.199.108.153 | Automatic |
| A Record | @ | 185.199.109.153 | Automatic |
| A Record | @ | 185.199.110.153 | Automatic |
| A Record | @ | 185.199.111.153 | Automatic |
| CNAME Record | www | jhuang7908.github.io. | Automatic |

Optional IPv6 (AAAA, host @): 2606:50c0:8000::153, 2606:50c0:8001::153, 2606:50c0:8002::153, 2606:50c0:8003::153.

### KEEP unchanged (Zoho Mail; do not touch)

- **MX records** (Zoho mx / mx2 / mx3), under “Mail Settings: Custom MX”. Do **not** switch Mail Settings to anything else.
- **SPF TXT** on @ (`v=spf1 include:zoho.com ~all` or as currently set)
- **zoho-verification TXT** (`zoho-verification=zb……zmverify.zoho.com`)
- **DKIM TXT**, host `zmail._domainkey`
- Any DMARC TXT (`_dmarc`), if present

Adding A records on @ does not conflict with MX/TXT on @. Do not create a CNAME on @; it would break mail.

### Check after the change

```
dig +short inlightbio.com A          # the four 185.199.10x.153
dig +short www.inlightbio.com CNAME  # jhuang7908.github.io.
dig +short inlightbio.com MX         # Zoho MX hosts, unchanged
dig +short inlightbio.com TXT        # SPF + zoho-verification, unchanged
dig +short zmail._domainkey.inlightbio.com TXT
```

Then send a test email to and from bd@ and contact@inlightbio.com.

## 3. Before going live (owner checklist)

- [x] Placeholders replaced with live wording (engagement terms, reply time, legal notice on `/newco/`; email-based sign-up on `/subscribe/`).
- [ ] Optional: have counsel review the legal notice on the NewCo page.
- [ ] Confirm the mailboxes bd@ and contact@inlightbio.com exist in Zoho.
- [ ] Re-check the TBA conference dates (TD Cowen, Leerink, Jefferies NY, Goldman Sachs, Morgan Stanley) and update `_build/data_conf.py`.
- [ ] Submit `https://inlightbio.com/sitemap.xml` in Google Search Console and Bing Webmaster Tools.

## 4. How the site is built

- `_build/build_site.py` generates every HTML page, `data/*.json`, `sitemap.xml`, `robots.txt`, `feed.xml`, `CNAME` and `.nojekyll` from:
  - `_build/data_news.py`: news items, translated from the Chinese `DEALS` array, with `zh_t` = original Chinese title
  - `_build/data_conf.py`: conferences (`verified`, `dates` = `"TBA"` when unconfirmed)
  - `_build/data_newco.py`: China-to-NewCo deal table with sources
- CSS: `assets/css/base-from-zh.css` is a verbatim copy of the Chinese site's stylesheet. `assets/css/en.css` holds the EN overrides. The build concatenates them into `assets/css/site.css`.
- JS: `assets/js/site.js`, adapted from the Chinese site (details panel, compact filter, conference sort/range).
- Run: `python3 _build/build_site.py` (standard library only). Preview: `python3 -m http.server` in this folder, then open http://localhost:8000/.

## 5. Keeping content in sync with the Chinese repo

The two editions share images and item structure. Suggested workflow:

1. **Shared keys.** Each EN item stores `zh_t` (the Chinese title) and the same image file (`img/pal/deals/v11/deal_XX.jpg` → `img/deals/`). A small script, `_build/sync_check.py` (to write), can:
   - parse `DEALS` from `therasik-inlight/index.html`, the same way `_work/deals_zh.json` was extracted
   - list Chinese items whose title is not in any EN `zh_t`, i.e. new items awaiting translation
   - flag EN items whose Chinese source changed (store a hash of the zh `why`/`m` fields)
   - copy any new deal images into `img/deals/` without overwriting
2. **Translation rule.** Translate faithfully, add no facts, keep upfront and milestones separate, keep the source link. Run the build and commit.
3. **Automation (optional, later).** A scheduled GitHub Action in `inlightbio-en` checks out `therasik-inlight` read-only, runs the sync check, and opens an issue listing untranslated items. It should never write to the Chinese repo.
4. **EN-only content** (NewCo page, NewCo table, conference list) lives only in this repo.
5. **Cross-links.** EN pages carry `hreflang="zh-CN"` pointing to inlight.therasik.com. Adding a reciprocal `hreflang="en"` link on the Chinese site is optional and would be a separate, owner-approved change to that repo.
