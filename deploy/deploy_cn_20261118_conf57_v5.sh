#!/usr/bin/env bash
set -uo pipefail
# InLightBio CN Deploy - 2026-11-18 conf_57 thumbnail v5:
# The 2026世界生命科学大会 card requests img/conf/logos/t/conf_57.png (JS
# replaces /logos/ with /logos/t/). The full img/conf/logos/conf_57.png is
# already 200 on the live root; the thumbnail was never committed (added in
# therasik-inlight PR #123, branch fix/conf-57-thumb-20261118, commit
# 2e6815bf648b57c8dfa7d38d25db390bd67e04fc). This overlay is ADD-ONLY:
# one new file, no overwrite of existing site files.
#
# Reuses the v4 download pattern: persistent sha-verified cache,
# .part then mv, five jsDelivr mirrors x 3 rounds, no
# raw.githubusercontent.com. NEW_REL_DIR and nginx are not touched until
# the file is cached and verified.
#
# Assets are hosted on the public inlightbio-en slim pin branch (therasik-inlight
# is private). Copies the live root to a NEW release dir; never deletes or
# edits the old root. Does not delete Aliyun 命令助手 commands, hidden
# wx-src pages, stale dirs (_427ed5e, _r2, _news, _covers, _covers_v2,
# _covers_v3, _covers_v4), previous download caches, or this cache.
# Do not re-run covers v1–v4, deploy_cn_20261118_news.sh, the ivo
# downgrade scripts, or deploy_cn_20261117_p03b.sh.
# Writes rollback.sh in the new release dir (points back to the current
# live _covers_v4 root).
# Pipe-safe: no payload is read from $0 or BASH_SOURCE.
# Defaults are the production values. Env vars override them for a sandbox
# dry run only; unset env on the server leaves this behavior unchanged.
ASSET_PIN="${ASSET_PIN:-a799f5edd92f4a4711aa742d3f23db6baec39a34}"
MIRRORS="${MIRRORS:-cdn.jsdelivr.net fastly.jsdelivr.net gcore.jsdelivr.net testingcf.jsdelivr.net quantil.jsdelivr.net}"
CACHE_DIR="${CACHE_DIR:-/root/inlight_dl_cache_20261118_conf57}"
LIVE_PAGE_SHA="ab4d220f634bdf543965e0b0f4b7831b08396fdb37fdfd0e8b9ca8aa76478a9d"
LIVE_WEEKLY_SHA="bf8b4e8029d913dbe758f1264b2388b424350c7620d0d6da29bbffe592405e4c"
ARTICLE_SHA="0335c6fb05eee1860362e23501948dc498613f8d05ef881be290034d4d353278"
THUMB_REL="img/conf/logos/t/conf_57.png"
THUMB_SHA="d087f948e3fe726ea2cc2ae859e054d6ebdd206d9dcd481ed7e6e754378ef952"
N_FILES=1
VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
EXPECTED_OLD_ROOT="${EXPECTED_OLD_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261118_bb63ee0_covers_v4}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261118_2e6815b_conf57}"
LOG="${LOG:-/var/log/inlightbio_cn_deploy_20261118_conf57_v5.log}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
# CURL_RESOLVE: if unset, use the production --resolve. Set to empty to disable.
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then
  CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"
fi
curl_resolve=()
[[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")
CURRENT_ROOT=""; BACKUP_CONF=""
CACHED_OK=0
CACHED_SKIP=0
CACHED_GOT=0
# Overlay files (path sha256), hosted on the slim pin branch at ASSET_PIN.
OVERLAY_FILES="
  img/conf/logos/t/conf_57.png d087f948e3fe726ea2cc2ae859e054d6ebdd206d9dcd481ed7e6e754378ef952
"
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE"; exit 1; }
restore() { echo "ERR: $1" | tee -a "$LOG"; cp -a "$BACKUP_CONF" "$VHOST_CONF"; nginx -t >>"$LOG" 2>&1 && nginx -s reload >>"$LOG" 2>&1; summary "FAIL_$2_RESTORED"; exit 1; }
# Download-phase failure: do not create NEW_REL_DIR or touch nginx. Keep the cache.
abort_download() {
  echo "ERR: $1" | tee -a "$LOG"
  echo "FAIL_DOWNLOAD_NOCHANGE NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=none LOG=$LOG CACHED=${CACHED_OK}/${N_FILES}" | tee -a "$LOG"
  exit 1
}
if ! { : > "$LOG"; } 2>/dev/null; then LOG=/tmp/inlightbio_cn_deploy_20261118_conf57_v5.log; : > "$LOG"; fi
# Match only the unfilled sentinel. Do not treat a real SHA as a placeholder.
case "$ASSET_PIN" in
  *__ASSETS_COMMIT__*) abort "ASSET_PIN still has __ASSETS_COMMIT__ placeholder; finalize before running" PLACEHOLDER ;;
  *ASSETPIN_WILL_FILL*) abort "ASSET_PIN still has ASSETPIN_WILL_FILL placeholder; finalize before running" PLACEHOLDER ;;
esac
case "$NEW_REL_DIR" in
  *MERGED_SHA*) abort "NEW_REL_DIR still has MERGED_SHA placeholder; finalize with the therasik-inlight SHA before running" PLACEHOLDER ;;
esac
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

IFS=' ' read -r -a MIRROR_ARR <<< "$MIRRORS"

cache_hit() {
  local rel="$1" exp="$2" f="$CACHE_DIR/$1"
  [[ -f "$f" ]] || return 1
  [[ "$(sha256sum "$f" | awk '{print $1}')" == "$exp" ]]
}

# Download one file into the persistent cache. Skip if a cached copy already
# matches sha256. Otherwise try each mirror for up to 3 rounds. Write to a
# .part file and only mv into place after the hash passes.
fetch_one() {
  local rel="$1" exp="$2"
  local dest="$CACHE_DIR/$rel"
  local part="$dest.part"
  local host url round
  mkdir -p "$(dirname "$dest")"
  if cache_hit "$rel" "$exp"; then
    echo "CACHED $rel" | tee -a "$LOG"
    CACHED_SKIP=$((CACHED_SKIP + 1))
    CACHED_OK=$((CACHED_OK + 1))
    return 0
  fi
  rm -f "$dest"
  for round in 1 2 3; do
    for host in "${MIRROR_ARR[@]}"; do
      url="https://${host}/gh/jhuang7908/inlightbio-en@${ASSET_PIN}/${rel}"
      rm -f "$part"
      if curl --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 -fsSL "$url" -o "$part"; then
        if [[ "$(sha256sum "$part" | awk '{print $1}')" == "$exp" ]]; then
          mv -f "$part" "$dest"
          echo "GOT $rel mirror=$host" | tee -a "$LOG"
          CACHED_GOT=$((CACHED_GOT + 1))
          CACHED_OK=$((CACHED_OK + 1))
          return 0
        fi
        echo "WARN: sha256 mismatch from $host for $rel (round $round)" | tee -a "$LOG"
      else
        echo "WARN: curl failed $host for $rel (round $round)" | tee -a "$LOG"
      fi
      rm -f "$part"
    done
  done
  return 1
}

[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing" VHOST
CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ -n "$CURRENT_ROOT" && -d "$CURRENT_ROOT" ]] || abort "cannot find live root" LIVEROOT
[[ "$CURRENT_ROOT" == "$EXPECTED_OLD_ROOT" ]] || abort "live root is not the expected _covers_v4 root ($CURRENT_ROOT)" LIVEROOT
[[ ! -e "$NEW_REL_DIR" ]] || abort "new release dir already exists" EXISTS
have=$(sha256sum "$CURRENT_ROOT/index.html" | awk '{print $1}')
[[ "$have" == "$LIVE_PAGE_SHA" ]] || abort "live index.html differs from expected unchanged file ($have)" DRIFT
[[ -f "$CURRENT_ROOT/content/weekly_deals.js" ]] || abort "live weekly_deals.js missing" WEEKLY_MISSING
whave=$(sha256sum "$CURRENT_ROOT/content/weekly_deals.js" | awk '{print $1}')
[[ "$whave" == "$LIVE_WEEKLY_SHA" ]] || abort "live weekly_deals.js differs from expected unchanged file ($whave)" WEEKLY_DRIFT
ART="$CURRENT_ROOT/pages/article/ivonescimab-fda-crl.html"
[[ -f "$ART" ]] || abort "live brief page missing" ARTICLE_MISSING
ahave=$(sha256sum "$ART" | awk '{print $1}')
[[ "$ahave" == "$ARTICLE_SHA" ]] || abort "live brief page differs from expected unchanged file ($ahave)" ARTICLE_DRIFT
# The broken thumb should be absent from the live root (that is the bug).
if [[ -f "$CURRENT_ROOT/$THUMB_REL" ]]; then
  abort "live root already has $THUMB_REL; refusing to overlay a tree that is not the expected missing-thumb state" EXISTS
fi
[[ -f "$CURRENT_ROOT/img/conf/logos/conf_57.png" ]] || abort "live full conf_57.png missing" LOGO_MISSING
echo "PRE_OK"

# Populate the persistent cache BEFORE copying the live root or touching
# nginx. A download failure leaves no new release dir and does not switch
# the root. Already-verified cache entries are kept for the next run.
mkdir -p "$CACHE_DIR" || abort_download "cannot create cache dir $CACHE_DIR"
while read -r rel exp; do
  [[ -z "${rel:-}" || -z "${exp:-}" ]] && continue
  fetch_one "$rel" "$exp" || abort_download "download failed: $rel"
done <<OV
${OVERLAY_FILES}
OV
echo "DOWNLOAD_OK CACHED=${CACHED_SKIP}/${N_FILES} GOT=${CACHED_GOT}/${N_FILES}" | tee -a "$LOG"
[[ "$CACHED_OK" -eq "$N_FILES" ]] || abort_download "cache count $CACHED_OK/${N_FILES} after apparent success"

BACKUP_CONF="${VHOST_CONF}.bak.$(date '+%Y%m%d_%H%M%S')"
[[ -e "$BACKUP_CONF" ]] && BACKUP_CONF="${BACKUP_CONF}_b"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy failed" COPY
# Install the already-verified overlay from the persistent cache (add-only).
mkdir -p "$NEW_REL_DIR/img/conf/logos/t"
while read -r rel exp; do
  [[ -z "${rel:-}" || -z "${exp:-}" ]] && continue
  [[ ! -e "$NEW_REL_DIR/$rel" ]] || abort "refusing to overwrite existing $rel in the copied root" OVERWRITE
  cp -a "$CACHE_DIR/$rel" "$NEW_REL_DIR/$rel" || abort "install $rel failed" INSTALL
done <<OV
${OVERLAY_FILES}
OV
OWNER=$(stat -c '%U:%G' "$CURRENT_ROOT/index.html")
if [[ "$ALLOW_NON_ROOT" == "1" ]]; then
  chown "$OWNER" "$NEW_REL_DIR/$THUMB_REL" 2>/dev/null || true
else
  chown "$OWNER" "$NEW_REL_DIR/$THUMB_REL" || abort "chown $THUMB_REL failed" CHOWN
fi
check_sha() {
  local f="$1" exp="$2"
  [[ "$(sha256sum "$NEW_REL_DIR/$f" | awk '{print $1}')" == "$exp" ]] || abort "staged $f sha mismatch" STAGE
}
while read -r rel exp; do
  [[ -z "${rel:-}" || -z "${exp:-}" ]] && continue
  check_sha "$rel" "$exp"
done <<OV
${OVERLAY_FILES}
OV
# Add-only: unchanged pages must keep their live sha.
[[ "$(sha256sum "$NEW_REL_DIR/index.html" | awk '{print $1}')" == "$LIVE_PAGE_SHA" ]] || abort "staged index.html sha changed unexpectedly" STAGE
[[ "$(sha256sum "$NEW_REL_DIR/content/weekly_deals.js" | awk '{print $1}')" == "$LIVE_WEEKLY_SHA" ]] || abort "staged weekly_deals.js sha changed unexpectedly" STAGE
[[ "$(sha256sum "$NEW_REL_DIR/pages/article/ivonescimab-fda-crl.html" | awk '{print $1}')" == "$ARTICLE_SHA" ]] || abort "staged brief page was unexpectedly changed" STAGE
grep -q 'id="ivonescimab-crl-feature"' "$NEW_REL_DIR/index.html" && abort "featured banner reappeared in staged index.html" STAGE
grep -q 'id="newco-report-feature"' "$NEW_REL_DIR/index.html" || abort "NewCo feature banner lost" STAGE
grep -q 'FDA 对依沃西单抗发出完整回复函：总生存期未达统计学显著' "$NEW_REL_DIR/index.html" || abort "CRL title missing from DEAL_ART_V7" STAGE
grep -q 'content/weekly_deals.js?v=20261118b' "$NEW_REL_DIR/index.html" || abort "weekly_deals.js cache-bust include missing" STAGE
grep -q 'deal_59_20261118_v1_web.webp' "$NEW_REL_DIR/index.html" || abort "deal_59 cover missing from DEAL_ART_V7" STAGE
grep -q 'deal_72_20261118_v1_web.webp' "$NEW_REL_DIR/index.html" || abort "deal_72 cover missing from DEAL_ART_V7" STAGE
grep -q '2026世界生命科学大会' "$NEW_REL_DIR/index.html" || abort "WLSC title missing from staged CONFS" STAGE
grep -q 'img/conf/logos/conf_57.png' "$NEW_REL_DIR/index.html" || abort "conf_57 logo path missing from staged CONFS" STAGE
# case-sensitive sentinel guard (literal tokens only)
grep -qE 'PLACEHOLDER|draft7f' "$NEW_REL_DIR/pages/article/ivonescimab-fda-crl.html" && abort "internal version label in staged brief" STAGE
grep -qE 'PLACEHOLDER|draft7f' "$NEW_REL_DIR/index.html" && abort "internal version label in staged index" STAGE
grep -qE 'PLACEHOLDER|draft7f' "$NEW_REL_DIR/content/weekly_deals.js" && abort "internal version label in staged weekly_deals.js" STAGE
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back the 2026-11-18 conf_57 thumbnail v5 overlay:
# restore vhost backup (root -> $CURRENT_ROOT), reload nginx.
set -euo pipefail
cp -a "$BACKUP_CONF" "$VHOST_CONF"
nginx -t
nginx -s reload
echo "ROLLBACK_OK root -> $CURRENT_ROOT"
RB
chmod 700 "$NEW_REL_DIR/rollback.sh"
if [[ "$ALLOW_NON_ROOT" != "1" ]]; then
  chown root:root "$NEW_REL_DIR/rollback.sh"
fi
echo "STAGE_OK"
sed -i -E "s#^([[:space:]]*root[[:space:]]+)${CURRENT_ROOT};#\\1${NEW_REL_DIR};#" "$VHOST_CONF"
[[ $(grep -cE "^[[:space:]]*root[[:space:]]+${NEW_REL_DIR};" "$VHOST_CONF") -ge 1 ]] || restore "root switch failed" ROOT_SWITCH
grep -q 'nginx_api_location.conf' "$VHOST_CONF" || restore "api include missing" API_INCLUDE
nginx -t >>"$LOG" 2>&1 || restore "nginx -t failed (see $LOG)" NGINX_TEST
nginx -s reload >>"$LOG" 2>&1 || restore "nginx reload failed" NGINX_RELOAD
sleep 1
VT="$TMPD/v.html"
curl -fsS --retry 5 --retry-delay 2 "${curl_resolve[@]}" "$SITE_ORIGIN/" -o "$VT" >>"$LOG" 2>&1 || restore "homepage fetch failed" VERIFY_HOME
grep -q 'id="ivonescimab-crl-feature"' "$VT" && restore "live homepage still has CRL featured banner" VERIFY_FEATURE_GONE
grep -q 'id="newco-report-feature"' "$VT" || restore "live homepage lost NewCo feature" VERIFY_NEWCO
grep -q 'content/weekly_deals.js?v=20261118b' "$VT" || restore "live homepage missing weekly_deals cache-bust" VERIFY_CACHEBUST
grep -q 'deal_59_20261118_v1_web.webp' "$VT" || restore "deal_59 cover missing from live homepage" VERIFY_COVER59
grep -q '2026世界生命科学大会' "$VT" || restore "WLSC title missing from live homepage" VERIFY_WLSC
[[ "$(sha256sum "$VT" | awk '{print $1}')" == "$LIVE_PAGE_SHA" ]] || restore "live index.html sha changed after switch (should be unchanged)" VERIFY_HOME_SHA
VW="$TMPD/w.js"
C=$(curl -s --retry 5 --retry-delay 2 -o "$VW" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/content/weekly_deals.js?v=20261118b" || true)
[[ "$C" == "200" ]] || restore "weekly_deals.js HTTP $C" VERIFY_WEEKLY
[[ "$(sha256sum "$VW" | awk '{print $1}')" == "$LIVE_WEEKLY_SHA" ]] || restore "live weekly_deals.js sha changed after switch" VERIFY_WEEKLY_SHA
VA="$TMPD/a.html"
C=$(curl -s --retry 5 --retry-delay 2 -o "$VA" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/pages/article/ivonescimab-fda-crl.html" || true)
[[ "$C" == "200" ]] || restore "CRL brief page HTTP $C" VERIFY_BRIEF
[[ "$(sha256sum "$VA" | awk '{print $1}')" == "$ARTICLE_SHA" ]] || restore "live brief page sha changed unexpectedly" VERIFY_BRIEF_SHA
# The new thumbnail must now be 200 and byte-identical.
VT57="$TMPD/t57.png"
C=$(curl -s --retry 5 --retry-delay 2 -o "$VT57" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/$THUMB_REL" || true)
[[ "$C" == "200" ]] || restore "t/conf_57.png HTTP $C after switch" VERIFY_THUMB
[[ "$(sha256sum "$VT57" | awk '{print $1}')" == "$THUMB_SHA" ]] || restore "live t/conf_57.png sha mismatch after switch" VERIFY_THUMB_SHA
# Full logo still present.
C=$(curl -s --retry 5 --retry-delay 2 -o /dev/null -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/img/conf/logos/conf_57.png" || true)
[[ "$C" == "200" ]] || restore "full conf_57.png HTTP $C after switch" VERIFY_FULL
echo "NGINX_OK"
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
