# Search Console / indexing verification (draft — do not merge or deploy without Jing's OK)

Prepared 2026-11-13. This branch only adds homepage hreflang (the Chinese site is already live), keeps the existing canonical, and leaves placeholders for verification tokens. No token is included. Do not invent one.

## What is already live

- `robots.txt` allows crawlers and has `Sitemap: https://inlightbio.com/sitemap.xml`.
- `sitemap.xml` lists 66 public URLs (home, section pages, `/newco/report/`, and all 56 science articles), each with `<lastmod>`. The hidden `/sponsor/` URL stays commented out. Individual deal briefs are in-page hash URLs (`/news/#…`) and correctly are not sitemap entries.
- Sampled pages (home, `/news/`, `/science/…`, `/newco/report/`) are server-rendered HTML with a `rel=canonical` tag and substantial text in the first response. They are crawlable without JavaScript.
- `https://www.inlightbio.com/` already 301s to `https://inlightbio.com/`.
- Google already returns the homepage, main section pages, and at least one science article (for example `/science/w-mettl1-stm9005/`).
- GA4 `G-VC7RP7LCXQ` is already on the site (PR #67).

## DNS

- Registrar: Namecheap, Inc.
- Nameservers: `dns1.registrar-servers.com`, `dns2.registrar-servers.com` (Namecheap BasicDNS).
- Apex `inlightbio.com` points at GitHub Pages (`185.199.108–111.153`).
- `www.inlightbio.com` is a CNAME to `jhuang7908.github.io`.
- Existing TXT records: Zoho SPF and `zoho-verification=…`. A Google TXT record can be added alongside them; do not delete the Zoho records.

A Domain-property TXT record is added in the Namecheap DNS panel for `inlightbio.com`, host `@`, type TXT.

## Recommended verification

**Preferred: Google Search Console Domain property** for `inlightbio.com`.

1. Jing signs in at [https://search.google.com/search-console](https://search.google.com/search-console) with the Google account that should own the property (ideally the same account that owns GA4 `G-VC7RP7LCXQ`).
2. Add a **Domain** property `inlightbio.com` (not a URL-prefix).
3. Google shows a TXT value. Jing adds it at Namecheap (host `@`, type TXT) and waits for DNS to propagate, then clicks Verify. Do not paste the token into chat.
4. After verification, submit `https://inlightbio.com/sitemap.xml` in Sitemaps.

This one property covers apex, `www`, http, and https.

**Shortcut, URL-prefix only:** a property for `https://inlightbio.com/` can often be verified immediately through the existing GA4 tag if that Google account owns the GA property. This does not cover `www` or `http` by itself. Still add the Domain property when convenient.

**Bing Webmaster** is optional and can import the Google verification.

Do not add a made-up `google*.html` file or a fake `google-site-verification` meta tag. When a token exists, put it in a follow-up PR.

HTML comments in `index.html` mark where a meta tag would go if URL-prefix + meta is used instead of DNS.

Other English section pages still have a stale hreflang placeholder that would point them at the Chinese homepage. Do not enable those as-is; only pair pages that really correspond (home ↔ home, report ↔ report, and bilingual science articles). That cleanup can be a later change.
