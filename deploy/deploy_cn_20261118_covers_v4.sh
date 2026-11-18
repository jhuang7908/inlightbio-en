#!/usr/bin/env bash
set -uo pipefail
# InLightBio CN Deploy - 2026-11-18 blue deal covers v4:
# v3 failed on the Aliyun server in the DOWNLOAD phase with repeated
# curl: (35) SSL_ERROR_SYSCALL to cdn.jsdelivr.net (deal_62 webp, deal_61
# png, then a 600 s timeout around deal_65/66). The script itself always
# downloaded and matched sha256. Live root was not switched.
# v4 downloads into a persistent cache under
# /root/inlight_dl_cache_20261118_covers/, skips files already cached with
# a matching sha256, writes to a .part file and only moves into place after
# the hash passes, and rotates through five jsDelivr mirrors (cdn, fastly,
# gcore, testingcf, quantil) for up to 3 rounds per file. Does not use
# raw.githubusercontent.com. NEW_REL_DIR and nginx are not touched until
# all 30 files are cached and verified.
# Overlay: index.html + content/weekly_deals.js + img/pal/deals/v11/deal_59..72
#   .png and _web.webp
# (therasik-inlight merge commit bb63ee04f6b6aecc2c2702613cd5425b893f3c7e, PR #122).
# Assets are hosted on the public inlightbio-en slim pin branch at
# b3ba08c993540bd839b3ecf0afbb1f1926de50b9 (therasik-inlight is private).
# Copies the live root to a NEW release dir; never deletes or edits the old
# root. Does not delete Aliyun 命令助手 commands, hidden wx-src pages, the
# stale /www/wwwroot/inlightbio_cn_rel_20261118_427ed5e dir, the r2 root,
# the current live _news root, unused _covers / _covers_v2 / _covers_v3
# dirs, or the download cache.
# Do not re-run deploy_cn_20261117_p03b.sh, the ivo downgrade v1/v2/v3
# scripts, deploy_cn_20261118_news.sh, or covers v1/v2/v3.
# Writes rollback.sh in the new release dir (points back to the current
# live _news root).
# Pipe-safe: no payload is read from $0 or BASH_SOURCE, so this script
# behaves the same when run as a file or piped to bash.
# Defaults are the production values. Env vars override them for a sandbox
# dry run only; unset env on the server leaves this behavior unchanged.
ASSET_PIN="${ASSET_PIN:-b3ba08c993540bd839b3ecf0afbb1f1926de50b9}"
MIRRORS="${MIRRORS:-cdn.jsdelivr.net fastly.jsdelivr.net gcore.jsdelivr.net testingcf.jsdelivr.net quantil.jsdelivr.net}"
CACHE_DIR="${CACHE_DIR:-/root/inlight_dl_cache_20261118_covers}"
PRE_PAGE_SHA="f360b32c5921731102bf856dad5101109a1d093d935d683d39a6177f4ecf4ae5"
AFTER_PAGE_SHA="ab4d220f634bdf543965e0b0f4b7831b08396fdb37fdfd0e8b9ca8aa76478a9d"
PRE_WEEKLY_SHA="8f9d585d7da376c9dc783d2713a52227ee1c32ee8b2a77a2170e4a2f6837f5c2"
AFTER_WEEKLY_SHA="bf8b4e8029d913dbe758f1264b2388b424350c7620d0d6da29bbffe592405e4c"
ARTICLE_SHA="0335c6fb05eee1860362e23501948dc498613f8d05ef881be290034d4d353278"
VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
EXPECTED_OLD_ROOT="${EXPECTED_OLD_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261118_4e713f9_news}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261118_bb63ee0_covers_v4}"
LOG="${LOG:-/var/log/inlightbio_cn_deploy_20261118_covers_v4.log}"
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
# index.html + weekly_deals.js are fetched too (together ~450 KB, too large
# to keep this script in the tens of KB if embedded).
OVERLAY_FILES="
  index.html ab4d220f634bdf543965e0b0f4b7831b08396fdb37fdfd0e8b9ca8aa76478a9d
  content/weekly_deals.js bf8b4e8029d913dbe758f1264b2388b424350c7620d0d6da29bbffe592405e4c
  img/pal/deals/v11/deal_59_20261118_v1.png 6e1a64c1f7d10f3bf77d572a0c6a0edaff6f106a4c57b32853e5b526856c1ff6
  img/pal/deals/v11/deal_59_20261118_v1_web.webp 00213d0cd3959f9dee9def04a6545ad6340a3d24a1fe99eebaa4da94853fd167
  img/pal/deals/v11/deal_60_20261118_v1.png 596ce324073b44d0bc89544f5ca656ee25c6e23c968e98aa111b24a9c98ccaf1
  img/pal/deals/v11/deal_60_20261118_v1_web.webp f6015a01ef159826517e8be03c7ca6e8243f63389b8337c5d3eda565c7db7e75
  img/pal/deals/v11/deal_61_20261118_v1.png 2ddcde350a1f1540ac2e57fe46fbbd03a6b465cc2227ee3e295f1ccaf4b011fc
  img/pal/deals/v11/deal_61_20261118_v1_web.webp 899c90124a4afa2db0a39bb9e534a7f6fa63d56e411993e63225ac0daddfdd4e
  img/pal/deals/v11/deal_62_20261118_v1.png 766ecdc911baead5c45983b3ea230a2d81f84c95f636a3a595aed67956e51394
  img/pal/deals/v11/deal_62_20261118_v1_web.webp f52564a9eb5107ba72a3957dcac1f05cc01729437b2ff2b5410a654437641f2c
  img/pal/deals/v11/deal_63_20261118_v1.png 7c8cf26e22d6ba4f69a921859b57cf503b96e3383b31e7a00c27f3b52b05acdd
  img/pal/deals/v11/deal_63_20261118_v1_web.webp 4529945f3f66e581d0eed41d61f85d258e7065a56c6d72a9e94a0f3e29a000f5
  img/pal/deals/v11/deal_64_20261118_v1.png f18f38523c2fd4e5cca24e2cbcb1ae708873760ca19a334ab5c9f54c88c52709
  img/pal/deals/v11/deal_64_20261118_v1_web.webp c7e1501d25c80abceb07584a6c48243c48465b0f834be2a33e66298eba750f0b
  img/pal/deals/v11/deal_65_20261118_v1.png 596afc05a2a4423474cc364dacd2f741fdc0dc87e5a89f766d39a772a9c6dd98
  img/pal/deals/v11/deal_65_20261118_v1_web.webp 6e7e06662530d12ff2483c24a547b7eadbc48527b7d593e2c0afd9acf4a7aed4
  img/pal/deals/v11/deal_66_20261118_v1.png 43e6d65aa57ab38d86914ac030b42a36a5ab5160436e737dbaf2918e9b76acbd
  img/pal/deals/v11/deal_66_20261118_v1_web.webp f29f3af9e022a86472b08562a0fab6d78d7e308515cf32154810b7a8d573e242
  img/pal/deals/v11/deal_67_20261118_v1.png e35f7bfe9536a4cbdacc4389ceb63679b09910b598fd0a167fa1ceba1d008780
  img/pal/deals/v11/deal_67_20261118_v1_web.webp 3454c772b37cf043d4350749bce1ce0c70ec3504ed8bf104d57fc49e1ed58dde
  img/pal/deals/v11/deal_68_20261118_v1.png 5c504c2ab2a48cc121df7e66702d64c6d56b24d969ba4cb77ed18b42a18d43ea
  img/pal/deals/v11/deal_68_20261118_v1_web.webp 22c4ad47449a17faeb5e267f151b5890bf4ad204f20ca7e346baf2f86cb9447d
  img/pal/deals/v11/deal_69_20261118_v1.png 7d8a66cda4e48be5a8e839f73a55afc301c60cf3525e27cfb43c991558914681
  img/pal/deals/v11/deal_69_20261118_v1_web.webp 177bc4d14cb54d09317a9a3bfe4e582b4c606d65959524bb4fb7b6f63ba14047
  img/pal/deals/v11/deal_70_20261118_v1.png 6936239794a94065bec8ce841e2fd8eb8fdc6b068f904bf222f32e9fbbc3dd86
  img/pal/deals/v11/deal_70_20261118_v1_web.webp 2065e6c0f991129c99c24a9109cd3eb4efcf55e41d31b66264b239cdc14a3b01
  img/pal/deals/v11/deal_71_20261118_v1.png 1e8b4d127cb070da6830ed2d93fa4ecb5d12036f539bd5b79b9d9570a3c28ef2
  img/pal/deals/v11/deal_71_20261118_v1_web.webp 01fb9e0364e14cf15c1ce7fc8c4a6d7573e971671b4bee35f0abf5a49ca46f9f
  img/pal/deals/v11/deal_72_20261118_v1.png 5b46dcfe3da05584140ceb65092899013234fb8a4580cc7292be978a37dcfbdc
  img/pal/deals/v11/deal_72_20261118_v1_web.webp 4269caedbd2834f24a1797ee1f77885433f46465a3b92ff0dcfc9ffe37c5c77a
"
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE"; exit 1; }
restore() { echo "ERR: $1" | tee -a "$LOG"; cp -a "$BACKUP_CONF" "$VHOST_CONF"; nginx -t >>"$LOG" 2>&1 && nginx -s reload >>"$LOG" 2>&1; summary "FAIL_$2_RESTORED"; exit 1; }
# Download-phase failure: do not create NEW_REL_DIR or touch nginx. Keep the cache.
abort_download() {
  echo "ERR: $1" | tee -a "$LOG"
  echo "FAIL_DOWNLOAD_NOCHANGE NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=none LOG=$LOG CACHED=${CACHED_OK}/30" | tee -a "$LOG"
  exit 1
}
if ! { : > "$LOG"; } 2>/dev/null; then LOG=/tmp/inlightbio_cn_deploy_20261118_covers_v4.log; : > "$LOG"; fi
# Match only the unfilled sentinel. Do not substitute __ASSETS_COMMIT__ with
# the real assets SHA — that is what made v2 abort on a finished script.
case "$ASSET_PIN" in
  *__ASSETS_COMMIT__*) abort "ASSET_PIN still has __ASSETS_COMMIT__ placeholder; finalize before running" PLACEHOLDER ;;
esac
case "$NEW_REL_DIR" in
  *MERGED_SHA*) abort "NEW_REL_DIR still has MERGED_SHA placeholder; finalize with the merged therasik-inlight SHA before running" PLACEHOLDER ;;
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
  # Stale/corrupt cache: discard and re-download.
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
[[ "$CURRENT_ROOT" == "$EXPECTED_OLD_ROOT" ]] || abort "live root is not the expected _news root ($CURRENT_ROOT)" LIVEROOT
[[ ! -e "$NEW_REL_DIR" ]] || abort "new release dir already exists" EXISTS
have=$(sha256sum "$CURRENT_ROOT/index.html" | awk '{print $1}')
[[ "$have" == "$PRE_PAGE_SHA" ]] || abort "live index.html differs from expected pre-change file ($have)" DRIFT
[[ -f "$CURRENT_ROOT/content/weekly_deals.js" ]] || abort "live weekly_deals.js missing" WEEKLY_MISSING
whave=$(sha256sum "$CURRENT_ROOT/content/weekly_deals.js" | awk '{print $1}')
[[ "$whave" == "$PRE_WEEKLY_SHA" ]] || abort "live weekly_deals.js differs from expected pre-change file ($whave)" WEEKLY_DRIFT
ART="$CURRENT_ROOT/pages/article/ivonescimab-fda-crl.html"
[[ -f "$ART" ]] || abort "live brief page missing" ARTICLE_MISSING
ahave=$(sha256sum "$ART" | awk '{print $1}')
[[ "$ahave" == "$ARTICLE_SHA" ]] || abort "live brief page differs from expected unchanged file ($ahave)" ARTICLE_DRIFT
echo "PRE_OK"

# Populate the persistent cache BEFORE copying the live root or touching
# nginx. A download failure leaves no new release dir and does not switch
# the root. Already-verified cache entries are kept for the next run.
mkdir -p "$CACHE_DIR" || abort_download "cannot create cache dir $CACHE_DIR"
while read -r rel exp; do
  [[ -z "${rel:-}" || -z "${exp:-}" ]] && continue
  fetch_one "$rel" "$exp" || abort_download "download failed: $rel"
done <<EOF
${OVERLAY_FILES}
EOF
echo "DOWNLOAD_OK CACHED=${CACHED_SKIP}/30 GOT=${CACHED_GOT}/30" | tee -a "$LOG"
[[ "$CACHED_OK" -eq 30 ]] || abort_download "cache count $CACHED_OK/30 after apparent success"

BACKUP_CONF="${VHOST_CONF}.bak.$(date '+%Y%m%d_%H%M%S')"
[[ -e "$BACKUP_CONF" ]] && BACKUP_CONF="${BACKUP_CONF}_b"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy failed" COPY
# Install the already-verified overlay from the persistent cache.
mkdir -p "$NEW_REL_DIR/content" "$NEW_REL_DIR/img/pal/deals/v11"
while read -r rel exp; do
  [[ -z "${rel:-}" || -z "${exp:-}" ]] && continue
  cp -a "$CACHE_DIR/$rel" "$NEW_REL_DIR/$rel" || abort "install $rel failed" INSTALL
done <<EOF
${OVERLAY_FILES}
EOF
OWNER=$(stat -c '%U:%G' "$CURRENT_ROOT/index.html")
chown "$OWNER" "$NEW_REL_DIR/index.html"
chown "$OWNER" "$NEW_REL_DIR/content/weekly_deals.js"
chown "$OWNER" "$NEW_REL_DIR"/img/pal/deals/v11/deal_{59..72}_20261118_v1.png
chown "$OWNER" "$NEW_REL_DIR"/img/pal/deals/v11/deal_{59..72}_20261118_v1_web.webp
check_sha() {
  local f="$1" exp="$2"
  [[ "$(sha256sum "$NEW_REL_DIR/$f" | awk '{print $1}')" == "$exp" ]] || abort "staged $f sha mismatch" STAGE
}
while read -r rel exp; do
  [[ -z "${rel:-}" || -z "${exp:-}" ]] && continue
  check_sha "$rel" "$exp"
done <<EOF
${OVERLAY_FILES}
EOF
[[ "$(sha256sum "$NEW_REL_DIR/pages/article/ivonescimab-fda-crl.html" | awk '{print $1}')" == "$ARTICLE_SHA" ]] || abort "staged brief page was unexpectedly changed" STAGE
grep -q 'id="ivonescimab-crl-feature"' "$NEW_REL_DIR/index.html" && abort "featured banner reappeared in staged index.html" STAGE
grep -q 'id="newco-report-feature"' "$NEW_REL_DIR/index.html" || abort "NewCo feature banner lost" STAGE
grep -q 'FDA 对依沃西单抗发出完整回复函：总生存期未达统计学显著' "$NEW_REL_DIR/index.html" || abort "CRL title missing from DEAL_ART_V7" STAGE
grep -q 'msvalidate.01' "$NEW_REL_DIR/index.html" || abort "Bing meta lost" STAGE
grep -q '"@type": "Organization"' "$NEW_REL_DIR/index.html" || abort "JSON-LD Organization lost" STAGE
grep -q 'content/weekly_deals.js?v=20261118b' "$NEW_REL_DIR/index.html" || abort "weekly_deals.js cache-bust include missing" STAGE
grep -q 'weekly_deals.js?v=20261118a' "$NEW_REL_DIR/index.html" && abort "old weekly_deals.js cache-bust still present" STAGE
grep -q '蓉创基金沙龙' "$NEW_REL_DIR/index.html" || abort "蓉创 conference missing from staged CONFS" STAGE
grep -q '中原科技城生命科学创新生态大会' "$NEW_REL_DIR/index.html" || abort "中原科技城 conference missing from staged CONFS" STAGE
grep -q 'deal_59_20261118_v1_web.webp' "$NEW_REL_DIR/index.html" || abort "deal_59 cover missing from DEAL_ART_V7" STAGE
grep -q 'deal_72_20261118_v1_web.webp' "$NEW_REL_DIR/index.html" || abort "deal_72 cover missing from DEAL_ART_V7" STAGE
grep -q 'pfizer-starna-invivo-cart' "$NEW_REL_DIR/content/weekly_deals.js" || abort "Pfizer-Starna item missing from weekly_deals.js" STAGE
grep -q '辉瑞引进思缔纳' "$NEW_REL_DIR/content/weekly_deals.js" || abort "辉瑞–思缔纳 title missing from weekly_deals.js" STAGE
grep -q 'deal_59_20261118_v1.png' "$NEW_REL_DIR/content/weekly_deals.js" || abort "deal_59 img missing from weekly_deals.js" STAGE
grep -q 'deal_72_20261118_v1.png' "$NEW_REL_DIR/content/weekly_deals.js" || abort "deal_72 img missing from weekly_deals.js" STAGE
grep -q 'ivonescimab-fda-crl' "$NEW_REL_DIR/content/weekly_deals.js" || abort "CRL item missing from weekly_deals.js" STAGE
grep -q 'pages/article/ivonescimab-fda-crl.html' "$NEW_REL_DIR/content/weekly_deals.js" || abort "CRL brief page link missing from weekly_deals.js" STAGE
grep -q 'InLight 编辑部' "$NEW_REL_DIR/content/weekly_deals.js" || abort "InLight 编辑部 byline missing from weekly_deals.js" STAGE
[[ -f "$NEW_REL_DIR/pages/article/ivonescimab-fda-crl.html" ]] || abort "brief page missing" STAGE
grep -q '点评 · Rocky' "$NEW_REL_DIR/pages/article/ivonescimab-fda-crl.html" || abort "Rocky commentary missing from staged brief" STAGE
grep -q 'InLight 编辑部' "$NEW_REL_DIR/pages/article/ivonescimab-fda-crl.html" || abort "InLight 编辑部 byline missing from staged brief" STAGE
grep -qE 'PLACEHOLDER|draft7f' "$NEW_REL_DIR/pages/article/ivonescimab-fda-crl.html" && abort "internal version label in staged brief" STAGE
grep -qE 'PLACEHOLDER|draft7f' "$NEW_REL_DIR/index.html" && abort "internal version label in staged index" STAGE
grep -qE 'PLACEHOLDER|draft7f' "$NEW_REL_DIR/content/weekly_deals.js" && abort "internal version label in staged weekly_deals.js" STAGE
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back the 2026-11-18 blue-covers v4 overlay:
# restore vhost backup (root -> $CURRENT_ROOT), reload nginx.
set -euo pipefail
cp -a "$BACKUP_CONF" "$VHOST_CONF"
nginx -t
nginx -s reload
echo "ROLLBACK_OK root -> $CURRENT_ROOT"
RB
chmod 700 "$NEW_REL_DIR/rollback.sh"; chown root:root "$NEW_REL_DIR/rollback.sh"
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
grep -q 'msvalidate.01' "$VT" || restore "homepage Bing tag lost" VERIFY_TAG
grep -q '"@type": "Organization"' "$VT" || restore "homepage JSON-LD lost" VERIFY_JSONLD
grep -q 'FDA 对依沃西单抗发出完整回复函：总生存期未达统计学显著' "$VT" || restore "CRL title missing on live homepage (cover map / weekly merge)" VERIFY_CRL_TITLE
grep -q 'content/weekly_deals.js?v=20261118b' "$VT" || restore "live homepage missing new weekly_deals cache-bust" VERIFY_CACHEBUST
grep -q 'deal_59_20261118_v1_web.webp' "$VT" || restore "deal_59 cover missing from live homepage" VERIFY_COVER59
grep -q 'deal_72_20261118_v1_web.webp' "$VT" || restore "deal_72 cover missing from live homepage" VERIFY_COVER72
grep -q '蓉创基金沙龙' "$VT" || restore "蓉创 conference missing from live homepage" VERIFY_RONGCHUANG
grep -q '中原科技城生命科学创新生态大会' "$VT" || restore "中原科技城 conference missing from live homepage" VERIFY_ZHONGYUAN
[[ "$(sha256sum "$VT" | awk '{print $1}')" == "$AFTER_PAGE_SHA" ]] || restore "live index.html sha mismatch after switch" VERIFY_HOME_SHA
VW="$TMPD/w.js"
C=$(curl -s --retry 5 --retry-delay 2 -o "$VW" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/content/weekly_deals.js?v=20261118b" || true)
[[ "$C" == "200" ]] || restore "weekly_deals.js HTTP $C" VERIFY_WEEKLY
[[ "$(sha256sum "$VW" | awk '{print $1}')" == "$AFTER_WEEKLY_SHA" ]] || restore "live weekly_deals.js sha mismatch after switch" VERIFY_WEEKLY_SHA
grep -q 'pfizer-starna-invivo-cart' "$VW" || restore "live weekly_deals.js missing Pfizer-Starna item" VERIFY_WEEKLY_PFIZER
grep -q 'deal_59_20261118_v1.png' "$VW" || restore "live weekly_deals.js missing deal_59 img" VERIFY_WEEKLY_IMG
grep -q 'ivonescimab-fda-crl' "$VW" || restore "live weekly_deals.js lost CRL item" VERIFY_WEEKLY_CRL
VA="$TMPD/a.html"
C=$(curl -s --retry 5 --retry-delay 2 -o "$VA" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/pages/article/ivonescimab-fda-crl.html" || true)
[[ "$C" == "200" ]] || restore "CRL brief page HTTP $C" VERIFY_BRIEF
[[ "$(sha256sum "$VA" | awk '{print $1}')" == "$ARTICLE_SHA" ]] || restore "live brief page sha changed unexpectedly" VERIFY_BRIEF_SHA
grep -q '点评 · Rocky' "$VA" || restore "live brief missing Rocky commentary" VERIFY_COMMENT
grep -q 'InLight 编辑部' "$VA" || restore "live brief missing InLight 编辑部 byline" VERIFY_BYLINE
grep -q 'HR 0.79' "$VA" || restore "live brief missing OS HR 0.79" VERIFY_FACTS
grep -q 'p=0.057' "$VA" || restore "live brief missing OS p=0.057" VERIFY_FACTS
C2=$(curl -s --retry 5 --retry-delay 2 -o /dev/null -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/pages/article/c1-org-1.html" || true)
[[ "$C2" == "200" ]] || restore "article page HTTP $C2" VERIFY_ARTICLE
for n in 59 63 72; do
  for suf in _web.webp .png; do
    url="$SITE_ORIGIN/img/pal/deals/v11/deal_${n}_20261118_v1${suf}"
    Ci=$(curl -s --retry 5 --retry-delay 2 -o /dev/null -w '%{http_code}' "${curl_resolve[@]}" "$url" || true)
    [[ "$Ci" == "200" ]] || restore "cover deal_${n}${suf} HTTP $Ci" VERIFY_COVER
  done
done
echo "NGINX_OK"
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
