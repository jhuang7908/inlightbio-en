#!/usr/bin/env bash
# InLightBio CN deploy — TheraSik Chinese web whitepaper page (r5, 2026-11-22).
# Replaces /therasik/index.html with the Chinese counterpart of the
# insynbio.com/therasik/ 18-slide web whitepaper, including a desktop
# sticky left table of contents (Jing: 有侧面目录吗). Adds the page
# screenshots under therasik/assets/ (new files only). Download buttons
# already point at TheraSik_Whitepaper_2026_zh_v2.pdf (left in place from
# r3; not in this overlay). Does not overwrite or delete the old 6-page
# PDF, the v2 PDF, fonts, CSS, homepage, TheraMab, or any other path.
# Keeps the previous /therasik/ intro page as therasik/index_prev_20261122.html
# (new file). Jing: inlightbio.cn/therasik/ must be the Chinese version of
# the insynbio.com/therasik/ whitepaper (pt166u).
#
# Pattern: copy the live versioned root to a FRESH dir; snapshot the old
# therasik/index.html as index_prev_20261122.html; overlay sha-verified
# new files only; backup nginx vhost (including /home/admin); sed only the
# root lines; nginx -t; reload; verify. On post-switch failure, restore
# the vhost backup. Never delete old roots, backups, or caches. Idempotent
# if already at the new root with matching shas.
#
# r1 leftover: /www/wwwroot/inlightbio_cn_rel_20261122_therasik_wp_zh_v2
# r2 leftover: /www/wwwroot/inlightbio_cn_rel_20261122_therasik_wp_zh_v2_r2
# r3 live root (copy source, never delete/overwrite):
#   /www/wwwroot/inlightbio_cn_rel_20261122_therasik_wp_zh_v2_r3
# r5: new root *_r5. Overlay fetch tries CN-friendly GitHub release mirrors
# first (ghfast.top, gh-proxy) with a ~90s per-try timeout, then jsdelivr,
# and sha256-checks before use. Overlay is the new Chinese index.html plus
# 14 new screenshot/og assets (15 files). Link checks are 4 href + 4
# download (8 occurrences via grep -o). Launch is detached by the
# Workbench paste command (setsid nohup), not by this script.
#
# Run as root on the Aliyun 轻量 instance (SWAS Workbench, admin, sudo -n).
set -uo pipefail

OVERLAY_TAR_SHA="${OVERLAY_TAR_SHA:-1f177d8910c16533fcc7153e422abff19cbf8a8d39faec3cc5aad89c15241588}"
OVERLAY_NFILES=15
OVERLAY_TAR_NAME="${OVERLAY_TAR_NAME:-overlay_therasik_wp_zh_v2_r5.tar.gz}"
# Live /therasik/ index before this deploy (r3 intro page, v2 PDF links)
OLD_THERASIK_INDEX_SHA="${OLD_THERASIK_INDEX_SHA:-edf7d7634611f588f0d12fab780aae6af19f56c643034182b9e77ab4d687885d}"
NEW_THERASIK_INDEX_SHA="${NEW_THERASIK_INDEX_SHA:-ac29dc3df39710b8b710868d5030261f42326941a7a8499ef600c134270aec14}"
THERASIK_INDEX_PREV_REL="therasik/index_prev_20261122.html"
THERASIK_PDF_NEW_REL="therasik/assets/TheraSik_Whitepaper_2026_zh_v2.pdf"
THERASIK_PDF_NEW_SHA="${THERASIK_PDF_NEW_SHA:-147de18ea5f58f97c7959995b44e9ab7a428f2db3dc6c742544876438d832ada}"
THERASIK_PDF_OLD_REL="therasik/assets/TheraSik_Whitepaper_2026.pdf"
THERASIK_PDF_OLD_SHA="${THERASIK_PDF_OLD_SHA:-dd44cc2495d24bae012d381068cae3547b0b5ede05a0e88db7836fd832bb9451}"
# Homepage / TheraMab / site.css must stay at the live feat pins
HOME_SHA="${HOME_SHA:-c5a20e4a2cea379b62bf974be16799dc4998b630828d2ee76c8a5a783b65659a}"
THERAMAB_INDEX_SHA="${THERAMAB_INDEX_SHA:-1094fd9c38b5b17bf9863b8c8fbbe463b0a2a02122d9caa8e337473d3117fcf7}"
SITE_CSS_SHA="${SITE_CSS_SHA:-3fa7aa76b1e7e8224d8dbd017b0ad1395d5ed1ffb108d1190c9335e0bd93a0d9}"
THERAMAB_PDF_REL="theramab/assets/TheraMab_Whitepaper_2026.pdf"
THERAMAB_PDF_SHA="${THERAMAB_PDF_SHA:-0b1f871da37bbf11297f08bb97db1a93d061017891b0c0cd7107315ef02a12a8}"

VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
EXPECTED_OLD_ROOT="${EXPECTED_OLD_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261122_therasik_wp_zh_v2_r3}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261122_therasik_wp_zh_v2_r5}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261122_therasik_wp_zh_v2_r5}"
ADMIN_BACKUP_DIR="${ADMIN_BACKUP_DIR:-/home/admin}"
CACHE_DIR="${CACHE_DIR:-/root/inlight_cache_therasik_wp_zh_v2_r5}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
PUB_TAG="${PUB_TAG:-cn-deploy-2026-11-22-therasik-wp-zh-v2-r5}"
PUB_REPO="${PUB_REPO:-jhuang7908/inlightbio-en}"
PIN_SHA="${PIN_SHA:-__PIN_SHA__}"
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"; fi
curl_resolve=(); [[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")

TS=$(date '+%Y%m%d_%H%M%S')
LOG="${LOG:-/root/deploy_therasik_wp_zh_v2_r5_${TS}.log}"
CURRENT_ROOT=""; BACKUP_CONF=""; WEB_TOUCHED=0
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
FINISHED=0
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE" | tee -a "$LOG"; FINISHED=1; exit 1; }
if ! { : >> "$LOG"; } 2>/dev/null; then LOG="/tmp/deploy_therasik_wp_zh_v2_r5_${TS}.log"; : >> "$LOG"; fi
TMPD=$(mktemp -d)
cleanup() {
  local ec=$?
  rm -rf "$TMPD"
  if [[ "$FINISHED" != "1" && "$ec" -ne 0 ]]; then
    echo "ERR: unexpected exit status $ec" | tee -a "$LOG"
    summary "FAIL_UNEXPECTED_NOCHANGE" | tee -a "$LOG"
  fi
}
trap cleanup EXIT
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
park() { local src="$1" name="$2" dst; mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"; dst="$BACKUP_BASE/$name"; [[ -e "$dst" ]] && dst="$dst.$TS"; [[ -e "$dst" ]] && dst="$dst.$$"; mv "$src" "$dst" && echo "$dst"; }

echo "START therasik_wp_zh_v2_r5 $TS new_root=$NEW_REL_DIR" | tee -a "$LOG"
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing: $VHOST_CONF" VHOST
NT=$(nginx -t 2>&1); NRC=$?
if [[ $NRC -ne 0 ]]; then echo "$NT" | tee -a "$LOG"; abort "nginx -t fails before any change" PRE_NGINX; fi
echo "PRE_NGINX_T_OK" | tee -a "$LOG"

CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ -n "$CURRENT_ROOT" && -d "$CURRENT_ROOT" ]] || abort "could not detect live root from $VHOST_CONF ($CURRENT_ROOT)" LIVEROOT
case "$(basename "$(dirname "$CURRENT_ROOT")")/$(basename "$CURRENT_ROOT")" in
  wwwroot/inlightbio_cn_rel_*) ;;
  *) abort "live root is not a versioned wwwroot/inlightbio_cn_rel_* dir: $CURRENT_ROOT" LIVEROOT ;;
esac
NROOTS=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | awk '{print $2}' | tr -d ';' | sort -u | wc -l)
[[ "$NROOTS" == "1" ]] || abort "vhost has $NROOTS distinct root values; expected 1" LIVEROOT
echo "PRE_OK OLD_ROOT=$CURRENT_ROOT LIVE_INDEX_SHA=$(sha "$CURRENT_ROOT/index.html")" | tee -a "$LOG"

# README block from earlier today must stay
NEXACT=$(grep -cE '^[[:space:]]*location[[:space:]]+=[[:space:]]+/theramab/README\.txt' "$VHOST_CONF" || true)
[[ "$NEXACT" == "2" ]] || abort "vhost is missing theramab_readme_block_v1 exact README locations (found $NEXACT, expected 2)" README_VHOST
[[ -f "$CURRENT_ROOT/theramab/README.txt" ]] || abort "theramab/README.txt missing on live root; will not create or move it" README_DISK
echo "PRE_README_OK vhost_exact=$NEXACT" | tee -a "$LOG"

# Drift guard: only overlay if the live therasik page is the one we patched from
[[ "$(sha "$CURRENT_ROOT/therasik/index.html")" == "$OLD_THERASIK_INDEX_SHA" || "$(sha "$CURRENT_ROOT/therasik/index.html")" == "$NEW_THERASIK_INDEX_SHA" ]] \
  || abort "live therasik/index.html sha=$(sha "$CURRENT_ROOT/therasik/index.html") is neither the expected pre-patch $OLD_THERASIK_INDEX_SHA nor the v2 page; refusing to overlay" DRIFT
[[ "$(sha "$CURRENT_ROOT/index.html")" == "$HOME_SHA" ]] || abort "live homepage sha=$(sha "$CURRENT_ROOT/index.html") != feat pin $HOME_SHA; refusing to continue" DRIFT
[[ "$(sha "$CURRENT_ROOT/$THERASIK_PDF_OLD_REL")" == "$THERASIK_PDF_OLD_SHA" ]] || abort "live old TheraSik PDF sha mismatch; refusing to continue" DRIFT
[[ ! -e "$CURRENT_ROOT/$THERASIK_PDF_NEW_REL" ]] || [[ "$(sha "$CURRENT_ROOT/$THERASIK_PDF_NEW_REL")" == "$THERASIK_PDF_NEW_SHA" ]] \
  || abort "live already has $THERASIK_PDF_NEW_REL with unexpected sha=$(sha "$CURRENT_ROOT/$THERASIK_PDF_NEW_REL")" DRIFT

# Overlay assets (path sha). Never includes fonts, CSS, or PDFs.
NEW_ASSET_SHAS="
therasik/assets/databases-overview.png 0d0e37231d8f342ebb9188da107d02df2762c70db987ef6956f276107d377db2
therasik/assets/her2-evidence-scoring.png e9c0ef6136c453e3b8fc19369a83b2104bb869860d50ae79e4adedd314ca1754
therasik/assets/her2-related-drugs.jpg 123337e1709575f70c958cc3a2bb29f5d25c4f480b6e8fe59ace01ee352e6c88
therasik/assets/her2-tissue-expression.png a411adde310abb7e4abf0cdf5716caf891590f8d3cb77104179f14c9e2eb7737
therasik/assets/og-image.png d1d6bf983fad4a4e1516d3fea70bf1268e6b0e3323835236a858c23991095144
therasik/assets/results-list.jpg 900c36ca67f8401a3676b88672835b233c7dc47e2ed57545787a145e6003e102
therasik/assets/seq-annotations.png 3a77b25618c4099c8d144f7e9f88cdc8133da7320407aa14564c3931907c7679
therasik/assets/seq-plasmid-map.png 762850d10e1b6f6ba293fcd7aabc5bcd7569050201dc6f88ce805b7557cc161f
therasik/assets/seq-sequence-view.png c86a3a50824cb79058eaab615fb458be809a05730b4a00ad984021467f0bb424
therasik/assets/tools-catalog.png 91ea004ee6d0d158228280b4858182023c4dbc951932e056b8079079c1c6d1ef
therasik/assets/workflow-adc.png e3b3b46958539d9e93dc7304e7d4abb6d5770242cb6bb8a44e665045e6850664
therasik/assets/workflow-car-binder.png 7f84726d86106fd7aae6eb13c4043956ab501cf2734ca8a1c4b04bf535e2cf21
therasik/assets/workflow-openvax.png a557e7bc7b8e6379142c680a359b889a57803256a3de3c438bff19e464c1b307
therasik/assets/workflow-vhh-denovo.png c8fa923e34dfc1551f1fc75b131cf835d99d9fbbd93dcf04d7cccbe543a88c94
"

check_new_assets() {
  local root="$1" rel exp
  while read -r rel exp; do
    [[ -n "$rel" ]] || continue
    [[ -f "$root/$rel" && "$(sha "$root/$rel")" == "$exp" ]] || return 1
  done <<< "$NEW_ASSET_SHAS"
  return 0
}

staged_ok() {
  [[ -d "$NEW_REL_DIR" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/index.html")" == "$HOME_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/site.css")" == "$SITE_CSS_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/theramab/index.html")" == "$THERAMAB_INDEX_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/$THERAMAB_PDF_REL")" == "$THERAMAB_PDF_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/therasik/index.html")" == "$NEW_THERASIK_INDEX_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/$THERASIK_INDEX_PREV_REL")" == "$OLD_THERASIK_INDEX_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/$THERASIK_PDF_NEW_REL")" == "$THERASIK_PDF_NEW_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/$THERASIK_PDF_OLD_REL")" == "$THERASIK_PDF_OLD_SHA" ]] || return 1
  check_new_assets "$NEW_REL_DIR" || return 1
  return 0
}
live_is_new() { [[ "$CURRENT_ROOT" == "$NEW_REL_DIR" ]] && staged_ok; }

if live_is_new; then
  echo "IDEMPOTENT already deployed at $NEW_REL_DIR" | tee -a "$LOG"
  summary "DEPLOY_OK" | tee -a "$LOG"
  FINISHED=1
  exit 0
fi
if [[ "$CURRENT_ROOT" == "$NEW_REL_DIR" ]]; then
  abort "live root is already $NEW_REL_DIR but files/sha do not fully match; refusing to overwrite" DRIFT
fi
if [[ "$CURRENT_ROOT" != "$EXPECTED_OLD_ROOT" ]]; then
  echo "WARN: live root is $CURRENT_ROOT (expected $EXPECTED_OLD_ROOT); homepage + therasik + old PDF shas match pins, continuing" | tee -a "$LOG"
fi
# Never reuse, delete, or overwrite leftover r1/r2/r4 dirs or the r3 live root.
LEFTOVER_ROOTS="
/www/wwwroot/inlightbio_cn_rel_20261122_therasik_wp_zh_v2
/www/wwwroot/inlightbio_cn_rel_20261122_therasik_wp_zh_v2_r2
/www/wwwroot/inlightbio_cn_rel_20261122_therasik_wp_zh_v2_r3
/www/wwwroot/inlightbio_cn_rel_20261122_therasik_wp_zh_v2_r4
"
for leftover in $LEFTOVER_ROOTS; do
  if [[ "$NEW_REL_DIR" == "$leftover" ]]; then
    abort "refusing to use leftover staging dir $leftover; set a new NEW_REL_DIR" NEWROOT_EXISTS
  fi
done
[[ ! -e "$NEW_REL_DIR" ]] || abort "new root $NEW_REL_DIR already exists; refusing to reuse/overwrite" NEWROOT_EXISTS
grep -qF "$NEW_REL_DIR" "$VHOST_CONF" && abort "vhost already references the new root" NEWROOT_EXISTS

# CN-first: GitHub release via ghfast/gh-proxy, then jsdelivr, then origin.
# Per-try timeout is short so a hung mirror does not block the Workbench.
CURL_FETCH_CONNECT="${CURL_FETCH_CONNECT:-10}"
CURL_FETCH_MAX="${CURL_FETCH_MAX:-90}"
asset_urls() {
  local file="$1" m
  echo "https://ghfast.top/https://github.com/${PUB_REPO}/releases/download/${PUB_TAG}/${file}"
  echo "https://gh-proxy.com/https://github.com/${PUB_REPO}/releases/download/${PUB_TAG}/${file}"
  echo "https://mirror.ghproxy.com/https://github.com/${PUB_REPO}/releases/download/${PUB_TAG}/${file}"
  if [[ "$PIN_SHA" != "__PIN_SHA__" && -n "$PIN_SHA" ]]; then
    for m in testingcf.jsdelivr.net quantil.jsdelivr.net gcore.jsdelivr.net fastly.jsdelivr.net cdn.jsdelivr.net; do
      echo "https://${m}/gh/${PUB_REPO}@${PIN_SHA}/deploy/${file}"
    done
  fi
  echo "https://github.com/${PUB_REPO}/releases/download/${PUB_TAG}/${file}"
}

fetch_sha() {
  local dest="$1" exp="$2" file="$3" part="${1}.part" url
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" && "$(sha "$dest")" == "$exp" ]]; then
    echo "CACHED $file" | tee -a "$LOG"
    return 0
  fi
  if [[ -e "$dest" ]]; then
    echo "WARN: removing stale cache $dest (sha=$(sha "$dest"))" | tee -a "$LOG"
    rm -f "$dest"
  fi
  local round
  for round in 1 2 3; do
    while read -r url; do
      [[ -n "$url" ]] || continue
      rm -f "$part"
      echo "TRY $file mirror=$url (round $round, max-time=${CURL_FETCH_MAX}s)" | tee -a "$LOG"
      if curl --connect-timeout "$CURL_FETCH_CONNECT" --max-time "$CURL_FETCH_MAX" --retry 0 -fsSL "$url" -o "$part"; then
        if [[ "$(sha "$part")" == "$exp" ]]; then
          mv -f "$part" "$dest"
          echo "GOT $file sha=$exp" | tee -a "$LOG"
          return 0
        fi
        echo "WARN: sha256 mismatch from $url for $file (got $(sha "$part"))" | tee -a "$LOG"
      else
        echo "WARN: curl failed $url for $file (round $round)" | tee -a "$LOG"
      fi
      rm -f "$part"
    done < <(asset_urls "$file")
    sleep 5
  done
  return 1
}

mkdir -p "$CACHE_DIR" || abort "cannot create cache dir" DOWNLOAD
fetch_sha "$CACHE_DIR/$OVERLAY_TAR_NAME" "$OVERLAY_TAR_SHA" "$OVERLAY_TAR_NAME" \
  || abort "failed to download overlay tarball" DOWNLOAD
echo "DOWNLOAD_OK" | tee -a "$LOG"

# ---------- stage new root (copy only; never modify the live root) ----------
echo "COPY_START $CURRENT_ROOT -> $NEW_REL_DIR" | tee -a "$LOG"
cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then
  P=$(park "$NEW_REL_DIR/rollback.sh" "rollback.sh.inherited_from_$(basename "$CURRENT_ROOT").disabled") && chmod 600 "$P" && echo "INHERITED_ROLLBACK_PARKED $P" | tee -a "$LOG"
fi

mkdir -p "$TMPD/overlay"
tar -xzf "$CACHE_DIR/$OVERLAY_TAR_NAME" -C "$TMPD/overlay" --no-same-owner || abort "overlay extract failed" EXTRACT
NFOUND=$(find "$TMPD/overlay" -type f | wc -l)
[[ "$NFOUND" -eq "$OVERLAY_NFILES" ]] || abort "overlay has $NFOUND files, expected $OVERLAY_NFILES" EXTRACT
[[ "$(sha "$TMPD/overlay/therasik/index.html")" == "$NEW_THERASIK_INDEX_SHA" ]] || abort "overlay therasik/index.html sha mismatch" EXTRACT
# Overlay must not contain PDFs, fonts, CSS, or the prev-index snapshot
[[ -e "$TMPD/overlay/$THERASIK_PDF_OLD_REL" ]] && abort "overlay unexpectedly contains the old PDF path" EXTRACT
[[ -e "$TMPD/overlay/$THERASIK_PDF_NEW_REL" ]] && abort "overlay unexpectedly contains the v2 PDF path" EXTRACT
[[ -e "$TMPD/overlay/$THERASIK_INDEX_PREV_REL" ]] && abort "overlay unexpectedly contains index_prev" EXTRACT
if find "$TMPD/overlay" -type f \( -name '*.css' -o -name '*.woff' -o -name '*.woff2' -o -name '*.pdf' \) | grep -q .; then
  abort "overlay contains css/font/pdf files; refusing to install" EXTRACT
fi
# Every listed new asset must be in the overlay with the pinned sha
while read -r rel exp; do
  [[ -n "$rel" ]] || continue
  [[ "$(sha "$TMPD/overlay/$rel")" == "$exp" ]] || abort "overlay $rel sha mismatch" EXTRACT
done <<< "$NEW_ASSET_SHAS"

# Snapshot the current (r3) therasik page as a new file; never overwrite a different prev
if [[ -e "$NEW_REL_DIR/$THERASIK_INDEX_PREV_REL" ]]; then
  [[ "$(sha "$NEW_REL_DIR/$THERASIK_INDEX_PREV_REL")" == "$OLD_THERASIK_INDEX_SHA" ]] \
    || abort "index_prev already exists with unexpected sha=$(sha "$NEW_REL_DIR/$THERASIK_INDEX_PREV_REL"); refusing to overwrite" STAGE
  echo "INDEX_PREV_ALREADY_OK $NEW_REL_DIR/$THERASIK_INDEX_PREV_REL" | tee -a "$LOG"
else
  [[ "$(sha "$NEW_REL_DIR/therasik/index.html")" == "$OLD_THERASIK_INDEX_SHA" ]] \
    || abort "copied-root therasik/index.html sha=$(sha "$NEW_REL_DIR/therasik/index.html") is not the expected live page; refusing to snapshot prev" STAGE
  cp -a "$NEW_REL_DIR/therasik/index.html" "$NEW_REL_DIR/$THERASIK_INDEX_PREV_REL" || abort "write index_prev failed" STAGE
  echo "INDEX_PREV_SAVED $NEW_REL_DIR/$THERASIK_INDEX_PREV_REL sha=$OLD_THERASIK_INDEX_SHA" | tee -a "$LOG"
fi

# Install new screenshot assets only if missing or already the expected sha (never overwrite a different file)
OWN=$(stat -c '%U:%G' "$NEW_REL_DIR")
while read -r rel exp; do
  [[ -n "$rel" ]] || continue
  dest="$NEW_REL_DIR/$rel"
  if [[ -e "$dest" ]]; then
    [[ "$(sha "$dest")" == "$exp" ]] \
      || abort "new root already has $rel with unexpected sha=$(sha "$dest"); refusing to overwrite" STAGE
    echo "ASSET_ALREADY_OK $rel" | tee -a "$LOG"
  else
    mkdir -p "$(dirname "$dest")"
    cp -a "$TMPD/overlay/$rel" "$dest" || abort "copy $rel failed" STAGE
    chown "$OWN" "$dest" 2>/dev/null || true
    chmod 644 "$dest"
    echo "ASSET_INSTALLED $rel" | tee -a "$LOG"
  fi
done <<< "$NEW_ASSET_SHAS"

# Replace therasik/index.html only in the NEW root, and only if it is the known pre or post sha
LIVE_TS_SHA=$(sha "$NEW_REL_DIR/therasik/index.html")
if [[ "$LIVE_TS_SHA" == "$NEW_THERASIK_INDEX_SHA" ]]; then
  echo "THERASIK_INDEX_ALREADY_OK" | tee -a "$LOG"
elif [[ "$LIVE_TS_SHA" == "$OLD_THERASIK_INDEX_SHA" ]]; then
  cp -a "$TMPD/overlay/therasik/index.html" "$NEW_REL_DIR/therasik/index.html" || abort "copy therasik/index.html failed" STAGE
else
  abort "copied-root therasik/index.html sha=$LIVE_TS_SHA is not the expected pre-patch file; refusing to overwrite" STAGE
fi

chown "$OWN" "$NEW_REL_DIR/therasik/index.html" "$NEW_REL_DIR/$THERASIK_INDEX_PREV_REL" 2>/dev/null || true
chmod 644 "$NEW_REL_DIR/therasik/index.html" "$NEW_REL_DIR/$THERASIK_INDEX_PREV_REL"

staged_ok || abort "staged root sha checks failed after overlay" STAGE
# Confirm the only intentional differences vs the copied live root
[[ "$(sha "$NEW_REL_DIR/index.html")" == "$(sha "$CURRENT_ROOT/index.html")" ]] || abort "homepage changed in staged root" STAGE
[[ "$(sha "$NEW_REL_DIR/theramab/index.html")" == "$(sha "$CURRENT_ROOT/theramab/index.html")" ]] || abort "theramab/index.html changed in staged root" STAGE
[[ "$(sha "$NEW_REL_DIR/$THERASIK_PDF_OLD_REL")" == "$THERASIK_PDF_OLD_SHA" ]] || abort "old TheraSik PDF changed or missing in staged root" STAGE
[[ "$(sha "$NEW_REL_DIR/$THERASIK_PDF_NEW_REL")" == "$THERASIK_PDF_NEW_SHA" ]] || abort "v2 TheraSik PDF changed or missing in staged root" STAGE
[[ "$(sha "$CURRENT_ROOT/$THERASIK_PDF_OLD_REL")" == "$THERASIK_PDF_OLD_SHA" ]] || abort "old TheraSik PDF on live root changed during staging" STAGE
[[ "$(sha "$CURRENT_ROOT/$THERASIK_PDF_NEW_REL")" == "$THERASIK_PDF_NEW_SHA" ]] || abort "v2 TheraSik PDF on live root changed during staging" STAGE
# The 4 download anchors put href and download on the SAME line, so grep -c
# (line count) is 4, not 8. Count hrefs, download attrs, and raw occurrences.
ts_index="$NEW_REL_DIR/therasik/index.html"
href_n=$(grep -cF 'href="/therasik/assets/TheraSik_Whitepaper_2026_zh_v2.pdf"' "$ts_index" || true)
dl_n=$(grep -cF 'download="TheraSik_Whitepaper_2026_zh_v2.pdf"' "$ts_index" || true)
occ_n=$(grep -oF 'TheraSik_Whitepaper_2026_zh_v2.pdf' "$ts_index" 2>/dev/null | wc -l | tr -d ' '); occ_n=${occ_n:-0}
old_href_n=$(grep -cF 'href="/therasik/assets/TheraSik_Whitepaper_2026.pdf"' "$ts_index" || true)
echo "STAGE_LINK_COUNTS href=$href_n download=$dl_n occ=$occ_n old_href=$old_href_n" | tee -a "$LOG"
[[ "$href_n" == "4" && "$dl_n" == "4" && "$occ_n" == "8" ]] \
  || abort "new therasik/index.html link counts are href=$href_n download=$dl_n occ=$occ_n (expected 4 href + 4 download = 8 occurrences)" STAGE
[[ "$old_href_n" == "0" ]] || abort "new therasik/index.html still has $old_href_n href(s) to the old PDF" STAGE
if grep -qF 'rockyhj' "$ts_index" || grep -qiE 'wechat|saas\\.insynbio\\.com' "$ts_index"; then
  abort "new therasik/index.html contains disallowed contact strings" STAGE
fi
if [[ -s "$CURRENT_ROOT/assets/ev/px.js" ]]; then
  [[ "$(sha "$NEW_REL_DIR/assets/ev/px.js")" == "$(sha "$CURRENT_ROOT/assets/ev/px.js")" ]] || abort "px.js changed in staged root" STAGE
fi
if [[ -s "$CURRENT_ROOT/content/talent/jobs_public.json" ]]; then
  [[ "$(sha "$NEW_REL_DIR/content/talent/jobs_public.json")" == "$(sha "$CURRENT_ROOT/content/talent/jobs_public.json")" ]] || abort "jobs_public.json changed in staged root" STAGE
fi
echo "STAGE_FILES_OK" | tee -a "$LOG"

mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
VHOST_BAK_FIXED="$BACKUP_BASE/inlightbio.cn.conf.bak.therasik_wp_zh_v2_r5.$TS"
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back TheraSik Chinese web whitepaper r5: web root -> $CURRENT_ROOT. Deletes nothing.
set -uo pipefail
V="${VHOST_CONF}"
TS=\$(date '+%Y%m%d_%H%M%S')
cp -a "\$V" "$BACKUP_BASE/inlightbio.cn.conf.before_rollback.\$TS"
if [[ -s "$VHOST_BAK_FIXED" ]]; then
  cp -a "$VHOST_BAK_FIXED" "\$V"
else
  sed -i -E "s#^([[:space:]]*root[[:space:]]+)$NEW_REL_DIR;#\\1$CURRENT_ROOT;#" "\$V"
fi
NT=\$(nginx -t 2>&1); RC=\$?
echo "\$NT"
if [[ \$RC -ne 0 ]]; then
  echo "nginx -t failed after rollback edit"
  exit 1
fi
nginx -s reload || exit 1
echo "ROLLBACK_OK root -> $CURRENT_ROOT"
RB
chmod 700 "$NEW_REL_DIR/rollback.sh"
[[ "$ALLOW_NON_ROOT" == "1" ]] || chown root:root "$NEW_REL_DIR/rollback.sh" 2>/dev/null || true
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_therasik_wp_zh_v2_r5.$TS.sh"
echo "STAGE_OK" | tee -a "$LOG"

# ---------- vhost backups (panel bak + /home/admin) then sed-only root switch ----------
BACKUP_CONF="${VHOST_CONF}.bak.therasik_wp_zh_v2_r5.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
[[ ! -e "$VHOST_BAK_FIXED" ]] || abort "backup $VHOST_BAK_FIXED already exists" BACKUP
cp -a "$BACKUP_CONF" "$VHOST_BAK_FIXED" || abort "second vhost backup failed" BACKUP
if [[ -d "$ADMIN_BACKUP_DIR" ]]; then
  ADMIN_BAK="$ADMIN_BACKUP_DIR/inlightbio.cn.conf.bak.therasik_wp_zh_v2_r5.$TS"
  [[ ! -e "$ADMIN_BAK" ]] || abort "admin backup $ADMIN_BAK already exists" BACKUP
  cp -a "$BACKUP_CONF" "$ADMIN_BAK" || abort "admin vhost backup failed" BACKUP
  echo "ADMIN_BACKUP_OK $ADMIN_BAK" | tee -a "$LOG"
else
  echo "WARN: $ADMIN_BACKUP_DIR missing; vhost still backed up at $BACKUP_CONF and $VHOST_BAK_FIXED" | tee -a "$LOG"
fi
echo "BACKUP_OK VHOST_BACKUP=$BACKUP_CONF ROLLBACK=$NEW_REL_DIR/rollback.sh" | tee -a "$LOG"

web_restore() {
  echo "RESTORING vhost from $BACKUP_CONF" | tee -a "$LOG"
  cp -a "$BACKUP_CONF" "$VHOST_CONF"
  nginx -t >>"$LOG" 2>&1 && nginx -s reload >>"$LOG" 2>&1
}
fail_restored() { echo "ERR: $1" | tee -a "$LOG"; [[ "$WEB_TOUCHED" == "1" ]] && web_restore; summary "FAIL_$2_RESTORED" | tee -a "$LOG"; FINISHED=1; exit 1; }

WEB_TOUCHED=1
sed -i -E "s#^([[:space:]]*root[[:space:]]+)${CURRENT_ROOT};#\1${NEW_REL_DIR};#" "$VHOST_CONF"
NNEW=$(grep -cE "^[[:space:]]*root[[:space:]]+${NEW_REL_DIR};" "$VHOST_CONF" || true)
[[ "$NNEW" == "2" ]] || fail_restored "root switch failed (expected exactly 2 root lines pointing at the new dir, got $NNEW)" ROOT_SWITCH
grep -qE "^[[:space:]]*root[[:space:]]+${CURRENT_ROOT};" "$VHOST_CONF" && fail_restored "old root still referenced after switch" ROOT_SWITCH
if grep -qE 'location[[:space:]]+\^~[[:space:]]+/\.well-known/acme-challenge/' "$BACKUP_CONF"; then
  if ! diff -q <(grep -E 'location[[:space:]]+\^~[[:space:]]+/\.well-known/acme-challenge/' "$BACKUP_CONF") \
               <(grep -E 'location[[:space:]]+\^~[[:space:]]+/\.well-known/acme-challenge/' "$VHOST_CONF") >/dev/null; then
    fail_restored "ACME location line changed" VHOST_LAYOUT
  fi
fi
echo "===== VHOST_DIFF (old vs new) =====" | tee -a "$LOG"
if ! diff -u "$BACKUP_CONF" "$VHOST_CONF" | tee -a "$LOG"; then
  :
fi

NEXACT=$(grep -cE '^[[:space:]]*location[[:space:]]+=[[:space:]]+/theramab/README\.txt' "$VHOST_CONF" || true)
NREGEX=$(grep -cE 'theramab_readme_block_v1' "$VHOST_CONF" || true)
[[ "$NEXACT" == "2" ]] || fail_restored "vhost has $NEXACT exact README locations after root switch (expected 2)" README_VHOST
[[ "$NREGEX" -ge 4 ]] || fail_restored "vhost lost theramab_readme_block_v1 markers after root switch (count=$NREGEX)" README_VHOST
echo "README_VHOST_OK exact=$NEXACT markers=$NREGEX" | tee -a "$LOG"

NT=$(nginx -t 2>&1); NRC=$?
echo "$NT" | tee -a "$LOG"
[[ $NRC -eq 0 ]] || fail_restored "nginx -t failed" NGINX_TEST
echo "NGINX_T_OK" | tee -a "$LOG"
nginx -s reload >>"$LOG" 2>&1 || fail_restored "nginx reload failed" NGINX_RELOAD
echo "NGINX_RELOAD_OK" | tee -a "$LOG"

# ---------- live verify ----------
echo "VERIFY_EXPECT home=$HOME_SHA therasik=$NEW_THERASIK_INDEX_SHA pdf=$THERASIK_PDF_NEW_SHA (from $NEW_REL_DIR)" | tee -a "$LOG"
sleep 1

verify_curl() {
  curl -sS --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 \
    "${curl_resolve[@]}" \
    -H 'Accept-Encoding: identity' \
    -o "$2" -D "$3" -w "%{http_code}" \
    "$SITE_ORIGIN$1" || echo curlfail
}

ok=0
for try in 1 2 3 4 5 6; do
  C=$(verify_curl "/" "$TMPD/home.html" "$TMPD/home.hdr")
  GOT=$(sha "$TMPD/home.html")
  echo "VERIFY_HOME_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$HOME_SHA $(grep -i '^Content-Encoding:' "$TMPD/home.hdr" 2>/dev/null | tr -d '\r' || true)" | tee -a "$LOG"
  if [[ "$C" == "200" && "$GOT" == "$HOME_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "homepage HTTP $C sha_got=${GOT:-empty} expected $HOME_SHA" VERIFY_HOME
echo "VERIFY_HOME_OK HTTP=$C sha=$GOT" | tee -a "$LOG"

ok=0
for try in 1 2 3 4 5 6; do
  C=$(verify_curl "/therasik/" "$TMPD/ts.html" "$TMPD/ts.hdr")
  GOT=$(sha "$TMPD/ts.html")
  echo "VERIFY_THERASIK_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$NEW_THERASIK_INDEX_SHA" | tee -a "$LOG"
  if [[ "$C" == "200" && "$GOT" == "$NEW_THERASIK_INDEX_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "therasik page HTTP $C sha_got=${GOT:-empty} expected $NEW_THERASIK_INDEX_SHA" VERIFY_THERASIK
href_n=$(grep -cF 'href="/therasik/assets/TheraSik_Whitepaper_2026_zh_v2.pdf"' "$TMPD/ts.html" || true)
dl_n=$(grep -cF 'download="TheraSik_Whitepaper_2026_zh_v2.pdf"' "$TMPD/ts.html" || true)
occ_n=$(grep -oF 'TheraSik_Whitepaper_2026_zh_v2.pdf' "$TMPD/ts.html" 2>/dev/null | wc -l | tr -d ' '); occ_n=${occ_n:-0}
old_href_n=$(grep -cF 'href="/therasik/assets/TheraSik_Whitepaper_2026.pdf"' "$TMPD/ts.html" || true)
echo "VERIFY_THERASIK_COUNTS href=$href_n download=$dl_n occ=$occ_n old_href=$old_href_n" | tee -a "$LOG"
[[ "$href_n" == "4" && "$dl_n" == "4" && "$occ_n" == "8" ]] || fail_restored "live /therasik/ link counts href=$href_n download=$dl_n occ=$occ_n (expected 4+4=8)" VERIFY_THERASIK
[[ "$old_href_n" == "0" ]] || fail_restored "live /therasik/ still has $old_href_n href(s) to the old PDF" VERIFY_THERASIK
echo "VERIFY_THERASIK_OK HTTP=$C sha=$GOT hrefs=$href_n download=$dl_n occ=$occ_n" | tee -a "$LOG"

# Previous intro page kept as a new static file
ok=0
for try in 1 2 3 4 5 6; do
  C=$(verify_curl "/therasik/index_prev_20261122.html" "$TMPD/prev.html" "$TMPD/prev.hdr")
  GOT=$(sha "$TMPD/prev.html")
  echo "VERIFY_PREV_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$OLD_THERASIK_INDEX_SHA" | tee -a "$LOG"
  if [[ "$C" == "200" && "$GOT" == "$OLD_THERASIK_INDEX_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "therasik/index_prev_20261122.html HTTP $C sha_got=${GOT:-empty} expected $OLD_THERASIK_INDEX_SHA" VERIFY_PREV
echo "VERIFY_PREV_OK HTTP=$C sha=$GOT" | tee -a "$LOG"

# New screenshot assets must be 200 with pinned shas (sample of the overlay)
for rel_exp in \
  "therasik/assets/tools-catalog.png 91ea004ee6d0d158228280b4858182023c4dbc951932e056b8079079c1c6d1ef" \
  "therasik/assets/databases-overview.png 0d0e37231d8f342ebb9188da107d02df2762c70db987ef6956f276107d377db2" \
  "therasik/assets/workflow-vhh-denovo.png c8fa923e34dfc1551f1fc75b131cf835d99d9fbbd93dcf04d7cccbe543a88c94"
do
  rel=${rel_exp%% *}
  exp=${rel_exp##* }
  ok=0
  for try in 1 2 3 4 5 6; do
    C=$(curl -sS -o "$TMPD/asset.bin" -w "%{http_code}" -H 'Accept-Encoding: identity' "${curl_resolve[@]}" --max-time 60 "$SITE_ORIGIN/$rel" || echo curlfail)
    GOT=$(sha "$TMPD/asset.bin")
    echo "VERIFY_ASSET_TRY $rel $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$exp" | tee -a "$LOG"
    if [[ "$C" == "200" && "$GOT" == "$exp" ]]; then ok=1; break; fi
    sleep 2
  done
  [[ "$ok" == "1" ]] || fail_restored "asset $rel HTTP $C sha_got=${GOT:-empty} expected $exp" VERIFY_ASSET
  echo "VERIFY_ASSET_OK $rel HTTP=$C sha=$GOT" | tee -a "$LOG"
done

ok=0
for try in 1 2 3 4 5 6; do
  C=$(curl -sS -o "$TMPD/new.pdf" -w "%{http_code}" -H 'Accept-Encoding: identity' "${curl_resolve[@]}" --max-time 60 "$SITE_ORIGIN/$THERASIK_PDF_NEW_REL" || echo curlfail)
  GOT=$(sha "$TMPD/new.pdf")
  CT=$(curl -sS -D - -o /dev/null -H 'Accept-Encoding: identity' "${curl_resolve[@]}" --max-time 30 "$SITE_ORIGIN/$THERASIK_PDF_NEW_REL" 2>/dev/null | grep -i "^content-type:" | tr -d '\r' || true)
  echo "VERIFY_NEW_PDF_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$THERASIK_PDF_NEW_SHA ${CT:-Content-Type: (none)}" | tee -a "$LOG"
  if [[ "$C" == "200" && "$GOT" == "$THERASIK_PDF_NEW_SHA" && "$CT" == *[Pp][Dd][Ff]* ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "new TheraSik v2 PDF HTTP $C sha_got=${GOT:-empty} expected $THERASIK_PDF_NEW_SHA ctype=${CT:-none}" VERIFY_NEW_PDF
echo "VERIFY_NEW_PDF_OK HTTP=$C sha=$GOT ctype=$CT" | tee -a "$LOG"

ok=0
for try in 1 2 3 4 5 6; do
  C=$(curl -sS -o "$TMPD/old.pdf" -w "%{http_code}" -H 'Accept-Encoding: identity' "${curl_resolve[@]}" --max-time 60 "$SITE_ORIGIN/$THERASIK_PDF_OLD_REL" || echo curlfail)
  GOT=$(sha "$TMPD/old.pdf")
  echo "VERIFY_OLD_PDF_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$THERASIK_PDF_OLD_SHA" | tee -a "$LOG"
  if [[ "$C" == "200" && "$GOT" == "$THERASIK_PDF_OLD_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "old TheraSik PDF should still be 200 with original sha; HTTP $C sha_got=${GOT:-empty}" VERIFY_OLD_PDF
echo "VERIFY_OLD_PDF_OK HTTP=$C sha=$GOT (unchanged, still on disk)" | tee -a "$LOG"

ok=0
for try in 1 2 3 4 5 6; do
  C=$(verify_curl "/theramab/" "$TMPD/tm.html" "$TMPD/tm.hdr")
  GOT=$(sha "$TMPD/tm.html")
  echo "VERIFY_THERAMAB_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$THERAMAB_INDEX_SHA" | tee -a "$LOG"
  if [[ "$C" == "200" && "$GOT" == "$THERAMAB_INDEX_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "theramab page HTTP $C sha_got=${GOT:-empty} expected $THERAMAB_INDEX_SHA" VERIFY_THERAMAB
echo "VERIFY_THERAMAB_OK HTTP=$C sha=$GOT" | tee -a "$LOG"

# Talent API should be untouched
TAL=$(curl -sS --max-time 20 "${curl_resolve[@]}" "$SITE_ORIGIN/api/talent/health" 2>/dev/null || true)
echo "TALENT_API $TAL" | tee -a "$LOG"
echo "$TAL" | grep -q '"ok"' && echo "TALENT_API_OK (unchanged) $TAL" | tee -a "$LOG" || echo "WARN: talent health not verified" | tee -a "$LOG"

summary "DEPLOY_OK" | tee -a "$LOG"
FINISHED=1
exit 0
