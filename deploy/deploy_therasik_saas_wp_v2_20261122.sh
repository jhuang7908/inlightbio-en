#!/usr/bin/env bash
# InLightBio CN deploy v2 — PR #145 SaaS whitepaper overlay (2026-11-22)
# FIX vs v1: v1 hung up to 1800s in fetch_sha because it only tried GitHub
# releases/download (the saas-wp release was never created) across ~76
# mirrors x 3 rounds x curl --max-time 600. This v2 fetches the overlay
# from the already-pinned jsDelivr/raw commit, copies videos from the live
# root when shas match, uses short curl timeouts, logs timestamps, takes
# stdin from /dev/null, and aborts if live /therasik/ is not the #144 page
# (live may already be the later zh_v2 r5 page; do not clobber it).
# New root …_63b4ad9_therasik_saas_wp_v2 so a half-done v1 dir is not reused.
# Idempotent if already live at the v2 root with matching shas.
# Do not run until Jing says to. Never delete old roots.
#
# Run as root. Log: /root/deploy_therasik_saas_wp_v2_20261122_<ts>.log
set -euo pipefail
exec </dev/null


OVERLAY_TAR_SHA="${OVERLAY_TAR_SHA:-cc67edf62651f7a04c29931c4dd076f894b3f50d87fc610368a810533f2532e9}"
NEW_INDEX_SHA="${NEW_INDEX_SHA:-1fd7f60260339be833f29340d59633ac34fadf9bf5153a2adc8af37b37cdb0df}"
OLD_INDEX_SHA="${OLD_INDEX_SHA:-c5a20e4a2cea379b62bf974be16799dc4998b630828d2ee76c8a5a783b65659a}"
WP2026_INDEX_SHA="${WP2026_INDEX_SHA:-e327902e148df7de794de12f1a4f57c77ccb8398b04f0ffdbe1af69eb0e1fef8}"
NEW_SITE_CSS_SHA="${NEW_SITE_CSS_SHA:-3fa7aa76b1e7e8224d8dbd017b0ad1395d5ed1ffb108d1190c9335e0bd93a0d9}"
NEW_THERAMAB_INDEX_SHA="${NEW_THERAMAB_INDEX_SHA:-a0429e99a722adce23637e7574ff89eb79c1a355b2f6d9ad144c2daf120f1199}"
NEW_THERASIK_INDEX_SHA="${NEW_THERASIK_INDEX_SHA:-1b0d34e549b88101e28d5421838622fd0c83a56aaba735e88d607366ce1b73df}"
# #144 /therasik/ (required to proceed). The later zh_v2 r5 page must not be overwritten.
EXPECTED_THERASIK_OLD_SHA="${EXPECTED_THERASIK_OLD_SHA:-f50fd98c555317876ad31d638347ea2121e83dcbc96b128940b747376d2b9f9e}"
LIVE_THERASIK_ZH_V2_SHA="${LIVE_THERASIK_ZH_V2_SHA:-ac29dc3df39710b8b710868d5030261f42326941a7a8499ef600c134270aec14}"
PIN_OVERLAY_COMMIT="${PIN_OVERLAY_COMMIT:-c4c4439b60b4a9fef19e37dc72866b57a10965f1}"
OVERLAY_FILE="overlay_63b4ad9_therasik_saas_wp.tar.gz"
THERASIK_PDF_REL="therasik/assets/TheraSik_SaaS_Whitepaper_2026.pdf"
THERASIK_PDF_SHA="${THERASIK_PDF_SHA:-dccec55fa1059f92b6ebadfc5035592e65529545be6c15fb65bd0ccf28276331}"
NEW_THERASIK_STYLE_SHA="${NEW_THERASIK_STYLE_SHA:-c14d1e04042a79823616cf71d3a947a2cf7fc9a2eecbe7e08475f4a3f64fa576}"
NEW_TM_STYLE_SHA="${NEW_TM_STYLE_SHA:-22fc5933c333dba7c2a634f05757c56c235f6ef082b3fdc9469b9ea53749588d}"
PDF_SHA="${PDF_SHA:-0b1f871da37bbf11297f08bb97db1a93d061017891b0c0cd7107315ef02a12a8}"
PDF_REL="theramab/assets/TheraMab_Whitepaper_2026.pdf"
NEW_NEWCO_SHA="${NEW_NEWCO_SHA:-0a3bec06be8400a7e6bdcfe37dea94d531fd50a4f83762e612cfb4ef0e9f402e}"
POSTER_SHA="${POSTER_SHA:-fb2e21702862f900aed2785f732f2652839649d9d06b0e5a80f84d3b587a90bd}"
MP4_1080_SHA="${MP4_1080_SHA:-1ee6af4a09cdaa7a40ee22370d3fc071416a5fdaffc184c5a6390e82a953e0ee}"
MP4_720_SHA="${MP4_720_SHA:-806afc6172a55e01f4019f4e32cae8aa299393da7ead647b1fe58e859c9cb445}"
# ffmpeg -vn -acodec copy -f md5  (same on both renditions)
AUDIO_MD5_COPY="e86cc6214c834dba0238356f45f926ad"
OVERLAY_NFILES=65
NEW_THUMB_SHA="${NEW_THUMB_SHA:-528763de74c09be5db3aad0370ee0caee8a3cc22feaf75da61ee12f3559db7dc}"
THUMB_REL="theramab/assets/img/theramab_card_thumb_v34e.png"
FAVICON_REL="theramab/assets/img/therasik_favicon.svg"
FAVICON_SHA="${FAVICON_SHA:-9766f65a6216d492f895ccb738376dfb2056c75cafbc91a666fde6ac0fcf587d}"
SRC_COMMIT="63b4ad9"

VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
EXPECTED_OLD_ROOT="${EXPECTED_OLD_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261122_3b35cfb_therasik_feat}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261122_63b4ad9_therasik_saas_wp_v2}"
STATIC_DIR="${STATIC_DIR:-/www/wwwroot/inlight_static/theramab}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261122_therasik_saas_wp_v2}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
PUB_TAG="${PUB_TAG:-cn-deploy-2026-11-22-therasik-saas-wp}"
PRIV_TAG="${PRIV_TAG:-therasik-saas-wp-deploy-20261122}"
PUB_REPO="${PUB_REPO:-jhuang7908/inlightbio-en}"
PRIV_REPO="${PRIV_REPO:-jhuang7908/therasik-inlight}"
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"; fi
curl_resolve=(); [[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")

TS=$(date '+%Y%m%d_%H%M%S')
LOG="${LOG:-/root/deploy_therasik_saas_wp_v2_20261122_${TS}.log}"
CURRENT_ROOT=""; BACKUP_CONF=""; WEB_TOUCHED=0
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
FINISHED=0
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE" | tee -a "$LOG"; FINISHED=1; exit 1; }
if ! { : >> "$LOG"; } 2>/dev/null; then LOG="/tmp/deploy_therasik_saas_wp_v2_20261122_${TS}.log"; : >> "$LOG"; fi
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
logts() { echo "$(date -Is) $*"; }
park() { local src="$1" name="$2" dst; mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"; dst="$BACKUP_BASE/$name"; [[ -e "$dst" ]] && dst="$dst.$TS"; [[ -e "$dst" ]] && dst="$dst.$$"; mv "$src" "$dst" && echo "$dst"; }

echo "START therasik_saas_wp_v2_20261122 $TS src=$SRC_COMMIT new_root=$NEW_REL_DIR" | tee -a "$LOG"
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing: $VHOST_CONF" VHOST
NT=$(nginx -t 2>&1) && NRC=0 || NRC=$?
if [[ $NRC -ne 0 ]]; then echo "$NT" | tee -a "$LOG"; abort "nginx -t fails before any change" PRE_NGINX; fi
echo "PRE_NGINX_T_OK" | tee -a "$LOG"

CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ -n "$CURRENT_ROOT" && -d "$CURRENT_ROOT" ]] || abort "could not detect live root from $VHOST_CONF ($CURRENT_ROOT)" LIVEROOT
# Require a versioned inlightbio_cn_rel_* dir under a wwwroot folder
# (/www/wwwroot/... on the server; a prefix is allowed so this script can be
# dry-run against a fake /www tree).
case "$(basename "$(dirname "$CURRENT_ROOT")")/$(basename "$CURRENT_ROOT")" in
  wwwroot/inlightbio_cn_rel_*) ;;
  *) abort "live root is not a versioned wwwroot/inlightbio_cn_rel_* dir: $CURRENT_ROOT" LIVEROOT ;;
esac
NROOTS=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | awk '{print $2}' | tr -d ';' | sort -u | wc -l)
[[ "$NROOTS" == "1" ]] || abort "vhost has $NROOTS distinct root values; expected 1" LIVEROOT
LIVE_INDEX_SHA=$(sha "$CURRENT_ROOT/index.html")
[[ -n "$LIVE_INDEX_SHA" ]] || abort "live index.html unreadable" LIVEROOT

static_ok() {
  [[ "$(sha "$STATIC_DIR/theramab_demo_1080p.mp4")" == "$MP4_1080_SHA" ]] || return 1
  [[ "$(sha "$STATIC_DIR/theramab_demo_720p.mp4")"  == "$MP4_720_SHA"  ]] || return 1
  [[ "$(sha "$STATIC_DIR/theramab_demo_poster.jpg")" == "$POSTER_SHA"  ]] || return 1
  return 0
}

staged_ok() {
  [[ -d "$NEW_REL_DIR" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/index.html")" == "$NEW_INDEX_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/site.css")" == "$NEW_SITE_CSS_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/theramab/index.html")" == "$NEW_THERAMAB_INDEX_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/theramab/assets/css/style.css")" == "$NEW_TM_STYLE_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/$PDF_REL")" == "$PDF_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/theramab/assets/video/theramab_demo_poster.jpg")" == "$POSTER_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/pages/newco-report.html")" == "$NEW_NEWCO_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/$THUMB_REL")" == "$NEW_THUMB_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/$FAVICON_REL")" == "$FAVICON_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/therasik/index.html")" == "$NEW_THERASIK_INDEX_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/$THERASIK_PDF_REL")" == "$THERASIK_PDF_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/therasik/assets/css/style.css")" == "$NEW_THERASIK_STYLE_SHA" ]] || return 1
  return 0
}

videos_in_root_ok() {
  [[ "$(sha "$NEW_REL_DIR/theramab/assets/video/theramab_demo_1080p.mp4")" == "$MP4_1080_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/theramab/assets/video/theramab_demo_720p.mp4")"  == "$MP4_720_SHA"  ]] || return 1
  return 0
}

already_live() {
  [[ "$CURRENT_ROOT" == "$NEW_REL_DIR" ]] || return 1
  [[ "$LIVE_INDEX_SHA" == "$NEW_INDEX_SHA" ]] || return 1
  staged_ok || return 1
  static_ok || return 1
  videos_in_root_ok || return 1
  return 0
}

if already_live; then
  echo "IDEMPOTENT already deployed at $NEW_REL_DIR" | tee -a "$LOG"
  logts "BACKUP_OK"
echo "BACKUP_OK (no change; already live)" | tee -a "$LOG"
  echo "STAGE_OK (no change; already live)" | tee -a "$LOG"
  FINISHED=1
  summary "DEPLOY_OK" | tee -a "$LOG"
  exit 0
fi

if [[ "$CURRENT_ROOT" == "$NEW_REL_DIR" ]]; then
  abort "live root is already $NEW_REL_DIR but files/sha do not fully match; refusing to overwrite" DRIFT
fi

if [[ "$LIVE_INDEX_SHA" == "$WP2026_INDEX_SHA" || "$CURRENT_ROOT" == "/www/wwwroot/inlightbio_cn_rel_20261122_686b53c_theramab_wp2026" ]]; then
  abort "live root is still the wp2026 r3 site (or its homepage sha). Run the #142 sidebar r4b deploy first, then this #143 script." PRE_NEEDS_SIDEBAR
fi
if [[ "$LIVE_INDEX_SHA" == "$NEW_INDEX_SHA" ]]; then
  abort "live homepage is already the 63b4ad9 (saas wp) page but root is $CURRENT_ROOT (not $NEW_REL_DIR); refusing to guess" DRIFT
fi
if [[ "$LIVE_INDEX_SHA" != "$OLD_INDEX_SHA" ]]; then
  abort "live $CURRENT_ROOT/index.html sha=$LIVE_INDEX_SHA is neither the expected #144 feat page ($OLD_INDEX_SHA) nor the new saas wp page (63b4ad9); refusing to overlay (would risk losing live edits)" DRIFT
fi
LIVE_TS_SHA="$(sha "$CURRENT_ROOT/therasik/index.html")"
logts "PRE live_root=$CURRENT_ROOT home=$(sha "$CURRENT_ROOT/index.html") therasik=$LIVE_TS_SHA"
if [[ "$LIVE_TS_SHA" == "$LIVE_THERASIK_ZH_V2_SHA" ]]; then
  abort "live /therasik/ is already the later zh_v2 r5 page ($LIVE_THERASIK_ZH_V2_SHA), not the #144 page and not this #145 overlay. Refusing to overwrite. Homepage is still the #144 pin. Do not rerun this #145 overlay." PRE_THERASIK_ALREADY_ZH_V2
fi
if [[ "$LIVE_TS_SHA" != "$EXPECTED_THERASIK_OLD_SHA" && "$LIVE_TS_SHA" != "$NEW_THERASIK_INDEX_SHA" ]]; then
  abort "live therasik/index.html sha=$LIVE_TS_SHA is neither #144 ($EXPECTED_THERASIK_OLD_SHA) nor this #145 page ($NEW_THERASIK_INDEX_SHA); refusing to overlay" DRIFT
fi
if [[ "$CURRENT_ROOT" != "$EXPECTED_OLD_ROOT" ]]; then
  abort "live root is $CURRENT_ROOT (expected $EXPECTED_OLD_ROOT). Homepage sha may still be #144 but /therasik/ may live on a later root; refusing to overlay" PRE_UNEXPECTED_ROOT
fi
[[ ! -e "$NEW_REL_DIR" ]] || abort "new root $NEW_REL_DIR already exists; refusing to reuse/overwrite" NEWROOT_EXISTS
grep -qF "$NEW_REL_DIR" "$VHOST_CONF" && abort "vhost already references the new root" NEWROOT_EXISTS
echo "PRE_OK OLD_ROOT=$CURRENT_ROOT LIVE_INDEX_SHA=$LIVE_INDEX_SHA" | tee -a "$LOG"
NEXACT=$(grep -cE '^[[:space:]]*location[[:space:]]+=[[:space:]]+/theramab/README\.txt' "$VHOST_CONF" || true)
[[ "$NEXACT" == "2" ]] || abort "vhost is missing theramab_readme_block_v1 exact README locations (found $NEXACT, expected 2). Refusing to deploy without them." README_VHOST
[[ -f "$CURRENT_ROOT/theramab/README.txt" ]] || abort "theramab/README.txt missing on live root; this script will not create or move it" README_DISK
echo "PRE_README_OK vhost_exact=$NEXACT disk=$CURRENT_ROOT/theramab/README.txt sha=$(sha "$CURRENT_ROOT/theramab/README.txt")" | tee -a "$LOG"

# Public inlightbio-en release is the fetch source (therasik-inlight is private;
# unauthenticated pulls from the CN server would fail). ghfast / ghproxy first.
# Fast fetch: jsDelivr + raw GitHub of the already-pushed pin. No GitHub
# releases/download walk (that is what hung v1 for 1800s).
overlay_urls() {
  local file="$1" p="$PIN_OVERLAY_COMMIT" repo="jhuang7908/inlightbio-en"
  echo "https://cdn.jsdelivr.net/gh/${repo}@${p}/deploy/${file}"
  echo "https://fastly.jsdelivr.net/gh/${repo}@${p}/deploy/${file}"
  echo "https://gcore.jsdelivr.net/gh/${repo}@${p}/deploy/${file}"
  echo "https://testingcf.jsdelivr.net/gh/${repo}@${p}/deploy/${file}"
  echo "https://ghfast.top/https://github.com/${repo}/raw/${p}/deploy/${file}"
  echo "https://gh-proxy.com/https://github.com/${repo}/raw/${p}/deploy/${file}"
  echo "https://github.com/${repo}/raw/${p}/deploy/${file}"
}

fetch_sha() {
  local dest="$1" exp="$2" file="$3" part="${1}.part" url
  local curl_max="${4:-45}"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" && "$(sha "$dest")" == "$exp" ]]; then
    logts "CACHED $file"
    echo "CACHED $file" | tee -a "$LOG"
    return 0
  fi
  if [[ -e "$dest" ]]; then
    echo "WARN: removing stale cache $dest (sha=$(sha "$dest"))" | tee -a "$LOG"
    rm -f "$dest"
  fi
  while read -r url; do
    [[ -n "$url" ]] || continue
    rm -f "$part"
    logts "TRY $file max=${curl_max}s $url"
    echo "TRY $file mirror=$url" | tee -a "$LOG"
    if curl --retry 2 --retry-delay 1 --connect-timeout 8 --max-time "$curl_max" -fsSL "$url" -o "$part"; then
      if [[ "$(sha "$part")" == "$exp" ]]; then
        mv -f "$part" "$dest"
        logts "GOT $file sha=$exp"
        echo "GOT $file sha=$exp" | tee -a "$LOG"
        return 0
      fi
      echo "WARN: sha256 mismatch from $url for $file (got $(sha "$part"))" | tee -a "$LOG"
    else
      echo "WARN: curl failed $url for $file" | tee -a "$LOG"
    fi
    rm -f "$part"
  done < <(overlay_urls "$file")
  return 1
}

CACHE_DIR="${CACHE_DIR:-/root/inlight_cache_therasik_saas_wp_v2}"
# Prior caches may be reused ONLY when the sha256 matches the expected (new) value.
PRIOR_CACHES="${PRIOR_CACHES:-/root/inlight_cache_therasik_saas_wp_v2 /root/inlight_cache_therasik_feat /root/inlight_cache_therasik_intro /root/inlight_cache_sidebar_aiplat_r4b /root/inlight_cache_theramab_v34e /root/inlight_cache_theramab_v34d /root/inlight_cache_theramab_v34c /root/inlight_cache_theramab_v34b /root/inlight_cache_theramab_v34}"
mkdir -p "$CACHE_DIR" || abort "cannot create cache dir" DOWNLOAD
seed_from_prior() {
  local rel="$1" exp="$2" dest="$CACHE_DIR/$1" src dir
  [[ -f "$dest" && "$(sha "$dest")" == "$exp" ]] && return 0
  [[ ! -e "$dest" ]] || return 0
  for dir in $PRIOR_CACHES; do
    src="$dir/$rel"
    if [[ -f "$src" && "$(sha "$src")" == "$exp" ]]; then
      cp -a "$src" "$dest" || return 1
      echo "SEEDED $rel from $dir (sha match)" | tee -a "$LOG"
      return 0
    elif [[ -f "$src" ]]; then
      echo "WARN: not seeding $rel from $dir (sha $(sha "$src") != $exp)" | tee -a "$LOG"
    fi
  done
}
seed_from_live_or_prior() {
  local rel="$1" exp="$2" dest="$CACHE_DIR/$1" src
  if [[ -f "$dest" && "$(sha "$dest")" == "$exp" ]]; then
    logts "CACHED $rel"
    return 0
  fi
  for src in \
    "$CURRENT_ROOT/theramab/assets/video/${rel}" \
    "$CURRENT_ROOT/theramab/assets/img/${rel}" \
    "$STATIC_DIR/${rel}"
  do
    if [[ -f "$src" && "$(sha "$src")" == "$exp" ]]; then
      cp -a "$src" "$dest"
      logts "SEEDED $rel from $src"
      echo "SEEDED $rel from $src (sha match)" | tee -a "$LOG"
      return 0
    fi
  done
  seed_from_prior "$rel" "$exp" || true
  [[ -f "$dest" && "$(sha "$dest")" == "$exp" ]]
}
logts "DOWNLOAD_START"
seed_from_prior "$OVERLAY_FILE" "$OVERLAY_TAR_SHA" || true
seed_from_live_or_prior "theramab_demo_1080p.mp4" "$MP4_1080_SHA" || true
seed_from_live_or_prior "theramab_demo_720p.mp4" "$MP4_720_SHA" || true
seed_from_live_or_prior "theramab_demo_poster.jpg" "$POSTER_SHA" || true
fetch_sha "$CACHE_DIR/$OVERLAY_FILE" "$OVERLAY_TAR_SHA" "$OVERLAY_FILE" 60 \
  || abort "failed to download overlay tarball (pin $PIN_OVERLAY_COMMIT)" DOWNLOAD
# Videos must already be on the live root / static dir from prior deploys; do not walk release mirrors.
[[ -f "$CACHE_DIR/theramab_demo_1080p.mp4" && "$(sha "$CACHE_DIR/theramab_demo_1080p.mp4")" == "$MP4_1080_SHA" ]] \
  || abort "1080p mp4 not in live root/static/cache; refusing a long re-download" DOWNLOAD
[[ -f "$CACHE_DIR/theramab_demo_720p.mp4" && "$(sha "$CACHE_DIR/theramab_demo_720p.mp4")" == "$MP4_720_SHA" ]] \
  || abort "720p mp4 not in live root/static/cache; refusing a long re-download" DOWNLOAD
[[ -f "$CACHE_DIR/theramab_demo_poster.jpg" && "$(sha "$CACHE_DIR/theramab_demo_poster.jpg")" == "$POSTER_SHA" ]] \
  || abort "poster not in live root/static/cache; refusing a long re-download" DOWNLOAD
logts "DOWNLOAD_OK"
echo "DOWNLOAD_OK" | tee -a "$LOG"

# Place static MP4s + poster (never overwrite a different sha)
install_static() {
  local src="$1" dest="$2" exp="$3"
  if [[ -e "$dest" ]]; then
    if [[ "$(sha "$dest")" == "$exp" ]]; then
      echo "STATIC_EXISTS_OK $dest" | tee -a "$LOG"
      return 0
    fi
    abort "existing $dest sha=$(sha "$dest") != $exp; refusing to overwrite" STATIC
  fi
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest" || abort "copy $dest failed" STATIC
  chmod 644 "$dest"
  [[ "$(sha "$dest")" == "$exp" ]] || abort "installed $dest sha mismatch" STATIC
  echo "STATIC_INSTALLED $dest" | tee -a "$LOG"
}
install_static "$CACHE_DIR/theramab_demo_1080p.mp4" "$STATIC_DIR/theramab_demo_1080p.mp4" "$MP4_1080_SHA"
install_static "$CACHE_DIR/theramab_demo_720p.mp4"  "$STATIC_DIR/theramab_demo_720p.mp4"  "$MP4_720_SHA"
install_static "$CACHE_DIR/theramab_demo_poster.jpg" "$STATIC_DIR/theramab_demo_poster.jpg" "$POSTER_SHA"
if [[ ! -e "$STATIC_DIR/SHA256SUMS.txt" ]]; then
  cat > "$STATIC_DIR/SHA256SUMS.txt" <<SUMS
$MP4_1080_SHA  theramab_demo_1080p.mp4
$MP4_720_SHA  theramab_demo_720p.mp4
$POSTER_SHA  theramab_demo_poster.jpg
SUMS
  chmod 644 "$STATIC_DIR/SHA256SUMS.txt"
fi
echo "STATIC_OK $STATIC_DIR" | tee -a "$LOG"

# ---------- stage new root ----------
logts "COPY_START $CURRENT_ROOT -> $NEW_REL_DIR"
echo "COPY_START $CURRENT_ROOT -> $NEW_REL_DIR" | tee -a "$LOG"
cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then
  P=$(park "$NEW_REL_DIR/rollback.sh" "rollback.sh.inherited_from_$(basename "$CURRENT_ROOT").disabled") && chmod 600 "$P" && echo "INHERITED_ROLLBACK_PARKED $P" | tee -a "$LOG"
fi

mkdir -p "$TMPD/overlay"
tar -xzf "$CACHE_DIR/overlay_63b4ad9_therasik_saas_wp.tar.gz" -C "$TMPD/overlay" --no-same-owner || abort "overlay extract failed" EXTRACT
NFOUND=$(find "$TMPD/overlay" -type f | wc -l)
[[ "$NFOUND" -eq "$OVERLAY_NFILES" ]] || abort "overlay has $NFOUND files, expected $OVERLAY_NFILES" EXTRACT
[[ "$(sha "$TMPD/overlay/index.html")" == "$NEW_INDEX_SHA" ]] || abort "overlay index.html sha mismatch" EXTRACT
[[ "$(sha "$TMPD/overlay/theramab/index.html")" == "$NEW_THERAMAB_INDEX_SHA" ]] || abort "overlay theramab/index.html sha mismatch" EXTRACT
[[ "$(sha "$TMPD/overlay/therasik/index.html")" == "$NEW_THERASIK_INDEX_SHA" ]] || abort "overlay therasik/index.html sha mismatch" EXTRACT
[[ "$(sha "$TMPD/overlay/$THERASIK_PDF_REL")" == "$THERASIK_PDF_SHA" ]] || abort "overlay TheraSik PDF sha mismatch" EXTRACT
[[ "$(sha "$TMPD/overlay/therasik/assets/css/style.css")" == "$NEW_THERASIK_STYLE_SHA" ]] || abort "overlay therasik style.css sha mismatch" EXTRACT
# TheraMab PDF, site.css and favicon are unchanged by this overlay; they must already exist on the copied #142 root.
[[ -f "$NEW_REL_DIR/$PDF_REL" ]] || abort "copied root missing TheraMab whitepaper PDF" EXTRACT
[[ "$(sha "$NEW_REL_DIR/$PDF_REL")" == "$PDF_SHA" ]] || abort "copied-root TheraMab PDF sha mismatch" EXTRACT
[[ "$(sha "$NEW_REL_DIR/site.css")" == "$NEW_SITE_CSS_SHA" ]] || abort "copied-root site.css sha mismatch (expect #142 sidebar css)" EXTRACT
[[ "$(sha "$NEW_REL_DIR/$FAVICON_REL")" == "$FAVICON_SHA" ]] || abort "copied-root therasik favicon sha mismatch" EXTRACT
[[ ! -e "$TMPD/overlay/site.css" ]] || abort "overlay unexpectedly contains site.css" EXTRACT
if find "$TMPD/overlay" -iname '*.mp4' | grep -q .; then abort "overlay tarball unexpectedly contains mp4s" EXTRACT; fi
if find "$TMPD/overlay" \( -iname 'README*.txt' -o -iname 'README*.md' -o -iname '*.md' \) | grep -q .; then
  abort "overlay unexpectedly contains README or markdown under the pack" EXTRACT
fi
# Never replace the existing TheraMab video poster, TheraMab molecule, or card thumb.
# therasik/assets/img/molecule.png is new and is allowed in this overlay.
if find "$TMPD/overlay" \( -name 'theramab_demo_poster.jpg' -o -path '*/theramab/*molecule.png' -o -name 'theramab_card_thumb_v34e.png' \) | grep -q .; then
  abort "overlay unexpectedly contains poster, TheraMab molecule.png, or card thumb" EXTRACT
fi

while IFS= read -r -d '' f; do
  rel="${f#./}"
  dest="$NEW_REL_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" ]]; then
    cat "$TMPD/overlay/$rel" > "$dest" || abort "install $rel failed" INSTALL
  else
    cp "$TMPD/overlay/$rel" "$dest" || abort "install new $rel failed" INSTALL
    if [[ -e "$NEW_REL_DIR/index.html" ]]; then
      chown --reference="$NEW_REL_DIR/index.html" "$dest" 2>/dev/null || true
      chmod --reference="$NEW_REL_DIR/index.html" "$dest" 2>/dev/null || true
    fi
  fi
  [[ "$(sha "$dest")" == "$(sha "$TMPD/overlay/$rel")" ]] || abort "staged $rel sha mismatch" STAGE
done < <(cd "$TMPD/overlay" && find . -type f -print0)

if [[ -d "$NEW_REL_DIR/theramab" && -e "$NEW_REL_DIR/index.html" ]]; then
  chown -R --reference="$NEW_REL_DIR/index.html" "$NEW_REL_DIR/theramab" 2>/dev/null || true
fi

staged_ok || abort "staged key file sha check failed" STAGE

I="$NEW_REL_DIR/index.html"
for pat in 'TheraMab' 'AI 药物研发平台' 'plat-rec' 'TheraSik SaaS' 'AI 赋能的药物研发与设计' 'class="tmab-banner"' 'class="plat-card" href="/therasik/"' '<h2>学术进展</h2>' 'id="latestgrid"' 'assets/ev/px.js?v=20261120a' 'assets/talent/talent_fund.js?v=20261120a' 'assets/fonts/fonts.css' 'id="bp-home"' 'id="home-talent"' '/theramab/assets/img/theramab_card_thumb_v34e.png' '/theramab/assets/img/therasik_favicon.svg' 'plat-logo'; do
  grep -qF "$pat" "$I" || abort "staged homepage missing: $pat" STAGE
done
grep -qF 'class="tmab-nav"' "$I" && abort "staged homepage still has TheraMab top-nav/footer item" STAGE
# Featured TheraMab banner is required again (restored to the main column).
grep -qF 'aria-hidden="true">TS</span>' "$I" && abort "staged homepage still has the TS placeholder mark" STAGE
[[ "$(sha "$NEW_REL_DIR/site.css")" == "$NEW_SITE_CSS_SHA" ]] || abort "staged site.css sha mismatch" STAGE
# Confirm we did not overwrite the existing poster or molecule asset.
[[ "$(sha "$NEW_REL_DIR/theramab/assets/video/theramab_demo_poster.jpg")" == "$POSTER_SHA" ]] || abort "video poster sha changed in staged root" STAGE
if [[ -f "$CURRENT_ROOT/theramab/assets/img/molecule.png" ]]; then
  [[ "$(sha "$NEW_REL_DIR/theramab/assets/img/molecule.png")" == "$(sha "$CURRENT_ROOT/theramab/assets/img/molecule.png")" ]] || abort "molecule.png changed in staged root" STAGE
fi
grep -qE 'preview-ribbon|此页为未上线预览|勿合并' "$I" && abort "preview text in staged homepage" STAGE
grep -qE 'fonts\.googleapis\.com|fonts\.gstatic\.com' "$I" && abort "staged homepage still references Google Fonts" STAGE
# 11/24 availability wording: inspect ONLY TheraMab banner/card/nav HTML
# (class tokens tmab / tmab-*) and theramab/index.html. Never scan homepage
# CSS or editorial/JSON. Write the guard to a file (do not use `python3 -`
# with a stdin program — that is what v34b ran on the server). Log all
# python stdout/stderr so a crash cannot be mistaken for a content hit.
TI="$NEW_REL_DIR/theramab/index.html"
for pat in '/theramab/assets/TheraMab_Whitepaper_2026.pdf' 'download="TheraMab_Whitepaper_2026.pdf"' 'btn-download' 'contact@therasik.com' '本白皮书可直接下载' '数据在本机处理' '可按需提供，欢迎洽谈' 'AI 药物研发平台' 'plat-rec' '/theramab/assets/img/therasik_favicon.svg' 'plat-logo'; do
  grep -qF "$pat" "$TI" || abort "staged /theramab/ missing: $pat" STAGE
done
grep -qF '待确认' "$TI" && abort "staged /theramab/ still contains 待确认" STAGE
grep -qF '功能对齐和说明' "$TI" && abort "staged /theramab/ still has the deleted roadmap item" STAGE
grep -qF '合作推广">TheraMab' "$TI" && abort "staged /theramab/ chrome nav still has TheraMab as a site column" STAGE
# README must still be on the new root (copied, not deleted) and must not be in the overlay dest as a replacement with a different sha? We simply require it still exists if it existed on the old root.
if [[ -f "$CURRENT_ROOT/theramab/README.txt" ]]; then
  [[ -f "$NEW_REL_DIR/theramab/README.txt" ]] || abort "theramab/README.txt missing from staged root (must be copied, not deleted)" STAGE
  [[ "$(sha "$NEW_REL_DIR/theramab/README.txt")" == "$(sha "$CURRENT_ROOT/theramab/README.txt")" ]] || abort "theramab/README.txt changed in staged root" STAGE
  echo "README_DISK_STAGED_OK sha=$(sha "$NEW_REL_DIR/theramab/README.txt")" | tee -a "$LOG"
fi
GUARD_PY="$TMPD/guard_tmab_1124.py"
cat > "$GUARD_PY" <<'PY'
# -*- coding: utf-8 -*-
"""Inspect only TheraMab banner/card/nav HTML (class tokens tmab / tmab-*),
plus theramab/index.html. Do not scan homepage CSS or editorial/JSON.
Print a match excerpt on failure. Exit 2 on unexpected errors (so the
deploy script can show the traceback instead of a generic STAGE message).
"""
from __future__ import print_function

import re
import sys
import traceback

PAT = re.compile(r"11 月 24|11月24|Tuesday")
VOID = {
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr",
}

def class_is_tmab(class_attr):
    for tok in (class_attr or "").split():
        if tok == "tmab" or tok.startswith("tmab-"):
            return True
    return False

def elements_with_tmab_class(html):
    out = []
    for m in re.finditer(
        r'<([a-zA-Z][A-Za-z0-9:-]*)([^>]*?)class=(["\'])([^"\']*)\3([^>]*)(/?)>',
        html,
    ):
        if not class_is_tmab(m.group(4)):
            continue
        tag = m.group(1)
        start, end = m.start(), m.end()
        selfclose = bool(m.group(6)) or m.group(0).rstrip().endswith("/>") or tag.lower() in VOID
        if selfclose:
            out.append(html[start:end])
            continue
        pos, depth = end, 1
        for n in re.finditer(r"<(/?)" + re.escape(tag) + r"\b[^>]*>", html[pos:], re.I):
            if n.group(1):
                depth -= 1
            elif not n.group(0).rstrip().endswith("/>"):
                depth += 1
            if depth == 0:
                out.append(html[start:pos + n.end()])
                break
    return out

def tmab_markup(html):
    # HTML nodes only — never CSS or <script> bodies.
    return "\n".join(elements_with_tmab_class(html))

def _fail(msg, excerpt=""):
    sys.stderr.write(msg + "\n")
    if excerpt:
        clip = excerpt if len(excerpt) < 400 else excerpt[:400] + "..."
        sys.stderr.write("MATCH_EXCERPT: " + clip.replace("\n", " ") + "\n")
    return 1

def check(home_path, theramab_path=""):
    home = open(home_path, "r", encoding="utf-8", errors="replace").read()
    blocks = tmab_markup(home)
    m = PAT.search(blocks)
    if m:
        i = m.start()
        return _fail(
            "TheraMab homepage banner/card/nav still has 11/24 availability wording",
            blocks[max(0, i - 80): i + 80],
        )
    if theramab_path:
        page = open(theramab_path, "r", encoding="utf-8", errors="replace").read()
        m = PAT.search(page)
        if m:
            i = m.start()
            return _fail(
                "theramab/index.html still has 11/24 availability wording",
                page[max(0, i - 80): i + 80],
            )
    sys.stdout.write(
        "GUARD_CHECK_OK tmab_nodes=%d home_bytes=%d tmab_page=%s\n"
        % (len(elements_with_tmab_class(home)), len(home), theramab_path or "-")
    )
    return 0

if __name__ == "__main__":
    try:
        sys.exit(check(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else ""))
    except Exception:
        traceback.print_exc()
        sys.exit(2)
PY
if ! python3 "$GUARD_PY" "$I" "$TI" >"$TMPD/guard_out.txt" 2>"$TMPD/guard_err.txt"; then
  echo "----- 11/24 guard stdout -----" | tee -a "$LOG"
  cat "$TMPD/guard_out.txt" 2>/dev/null | tee -a "$LOG" || true
  echo "----- 11/24 guard stderr -----" | tee -a "$LOG"
  cat "$TMPD/guard_err.txt" 2>/dev/null | tee -a "$LOG" || true
  reason=$(head -n 1 "$TMPD/guard_err.txt" 2>/dev/null | tr -d "\r")
  abort "11/24 guard failed: ${reason:-python3 non-zero exit, no stderr}" STAGE
fi
if [[ -s "$TMPD/guard_out.txt" ]]; then cat "$TMPD/guard_out.txt" | tee -a "$LOG"; fi
if grep -qE '11 月 24|11月24' "$I"; then
  echo "GUARD_1124_OK homepage editorial still contains 11/24 (e.g. 先通医药); TheraMab blocks are clean" | tee -a "$LOG"
else
  echo "GUARD_1124_OK TheraMab blocks are clean (no 11/24 on homepage editorial either)" | tee -a "$LOG"
fi
grep -qF 'assets/video/theramab_demo_1080p.mp4' "$TI" || abort "theramab page missing 1080p source" STAGE
grep -qF 'assets/video/theramab_demo_720p.mp4' "$TI" || abort "theramab page missing 720p source" STAGE
# Videos live in the new root so nginx does not need a video-alias location
# (v34c's alias insert shifted listen 443 ssl http2 from line 10 to line 14).
place_video_in_root() {
  local name="$1" exp="$2"
  local dest="$NEW_REL_DIR/theramab/assets/video/$name"
  local src="$STATIC_DIR/$name"
  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" ]]; then
    if [[ "$(sha "$dest")" == "$exp" ]]; then
      echo "ROOT_VIDEO_EXISTS_OK $dest" | tee -a "$LOG"
      return 0
    fi
    abort "existing $dest sha=$(sha "$dest") != $exp; refusing to overwrite" STAGE
  fi
  [[ -f "$src" && "$(sha "$src")" == "$exp" ]] || abort "static source missing or sha mismatch for $name" STAGE
  if ln "$src" "$dest" 2>/dev/null; then
    echo "ROOT_VIDEO_HARDLINK $dest" | tee -a "$LOG"
  else
    cp -a "$src" "$dest" || abort "copy $dest failed" STAGE
    echo "ROOT_VIDEO_COPIED $dest" | tee -a "$LOG"
  fi
  chmod 644 "$dest" 2>/dev/null || true
  [[ "$(sha "$dest")" == "$exp" ]] || abort "installed $dest sha mismatch" STAGE
}
place_video_in_root "theramab_demo_1080p.mp4" "$MP4_1080_SHA"
place_video_in_root "theramab_demo_720p.mp4"  "$MP4_720_SHA"
videos_in_root_ok || abort "MP4s missing or sha mismatch under the new root video dir" STAGE
echo "ROOT_VIDEO_OK $NEW_REL_DIR/theramab/assets/video/" | tee -a "$LOG"
[[ -s "$CURRENT_ROOT/assets/ev/px.js" && -s "$NEW_REL_DIR/assets/ev/px.js" ]] || abort "clickstats px.js missing after copy" STAGE
[[ "$(sha "$NEW_REL_DIR/assets/ev/px.js")" == "$(sha "$CURRENT_ROOT/assets/ev/px.js")" ]] || abort "px.js changed in staged root" STAGE
if [[ -s "$CURRENT_ROOT/content/talent/jobs_public.json" ]]; then
  [[ "$(sha "$NEW_REL_DIR/content/talent/jobs_public.json")" == "$(sha "$CURRENT_ROOT/content/talent/jobs_public.json")" ]] || abort "jobs_public.json changed in staged root" STAGE
fi

mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
VHOST_BAK_FIXED="$BACKUP_BASE/inlightbio.cn.conf.bak.theramab_v34e.$TS"
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-22 theramab_v34e deploy: web root -> $CURRENT_ROOT. Deletes nothing.
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
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_therasik_saas_wp_v2.$TS.sh"
echo "STAGE_OK" | tee -a "$LOG"

# ---------- vhost backup + sed-only root switch (no layout change) ----------
BACKUP_CONF="${VHOST_CONF}.bak.therasik_intro.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
[[ ! -e "$VHOST_BAK_FIXED" ]] || abort "backup $VHOST_BAK_FIXED already exists" BACKUP
cp -a "$BACKUP_CONF" "$VHOST_BAK_FIXED" || abort "second vhost backup failed" BACKUP
logts "BACKUP_OK"
echo "BACKUP_OK VHOST_BACKUP=$BACKUP_CONF ROLLBACK=$NEW_REL_DIR/rollback.sh" | tee -a "$LOG"

web_restore() {
  echo "RESTORING vhost from $BACKUP_CONF" | tee -a "$LOG"
  cp -a "$BACKUP_CONF" "$VHOST_CONF"
  nginx -t >>"$LOG" 2>&1 && nginx -s reload >>"$LOG" 2>&1
}
fail_restored() { echo "ERR: $1" | tee -a "$LOG"; [[ "$WEB_TOUCHED" == "1" ]] && web_restore; summary "FAIL_$2_RESTORED" | tee -a "$LOG"; FINISHED=1; exit 1; }

WEB_TOUCHED=1
# clickstats_v1 / scicards pattern: replace only the two `root` lines in place.
# Do not insert locations, comments, or blank lines.
sed -i -E "s#^([[:space:]]*root[[:space:]]+)${CURRENT_ROOT};#\1${NEW_REL_DIR};#" "$VHOST_CONF"
NNEW=$(grep -cE "^[[:space:]]*root[[:space:]]+${NEW_REL_DIR};" "$VHOST_CONF" || true)
[[ "$NNEW" == "2" ]] || fail_restored "root switch failed (expected exactly 2 root lines pointing at the new dir, got $NNEW)" ROOT_SWITCH
grep -qE "^[[:space:]]*root[[:space:]]+${CURRENT_ROOT};" "$VHOST_CONF" && fail_restored "old root still referenced after switch" ROOT_SWITCH
# ACME challenge root (inline, not a directive-at-bol) must be unchanged.
if grep -qE 'location[[:space:]]+\^~[[:space:]]+/\.well-known/acme-challenge/' "$BACKUP_CONF"; then
  if ! diff -q <(grep -E 'location[[:space:]]+\^~[[:space:]]+/\.well-known/acme-challenge/' "$BACKUP_CONF") \
               <(grep -E 'location[[:space:]]+\^~[[:space:]]+/\.well-known/acme-challenge/' "$VHOST_CONF") >/dev/null; then
    fail_restored "ACME location line changed" VHOST_LAYOUT
  fi
fi

echo "===== VHOST_DIFF (old vs new) =====" | tee -a "$LOG"
# Do not pipe diff into tee here: tee exits 0, and with pipefail that would
# hide a legitimate non-zero from diff (files differ — the success case).
if diff -u "$BACKUP_CONF" "$VHOST_CONF" >"$TMPD/vhost.diff"; then
  fail_restored "vhost diff is empty after root switch" ROOT_SWITCH
fi
cat "$TMPD/vhost.diff" | tee -a "$LOG"
echo "===== VHOST_LINES after edit =====" | tee -a "$LOG"
nl -ba "$VHOST_CONF" | tee -a "$LOG"

# Layout must not change: same line count, listen 443 stays on the same line.
NOLD=$(wc -l < "$BACKUP_CONF" | tr -d "[:space:]")
NNOW=$(wc -l < "$VHOST_CONF" | tr -d "[:space:]")
[[ "$NOLD" == "$NNOW" ]] || fail_restored "vhost line count changed ($NOLD -> $NNOW); edit must only replace root paths" VHOST_LAYOUT
L_BEFORE=$(grep -nE '^[[:space:]]*listen[[:space:]]+443' "$BACKUP_CONF" | head -1 | cut -d: -f1)
L_AFTER=$(grep -nE '^[[:space:]]*listen[[:space:]]+443' "$VHOST_CONF" | head -1 | cut -d: -f1)
[[ -n "$L_BEFORE" && "$L_BEFORE" == "$L_AFTER" ]] || fail_restored "listen 443 line moved (was $L_BEFORE, now $L_AFTER)" VHOST_LAYOUT
if ! grep -qE 'location[[:space:]]+(\^~[[:space:]]+)?/theramab/assets/video/' "$BACKUP_CONF"; then
  if grep -qE 'location[[:space:]]+(\^~[[:space:]]+)?/theramab/assets/video/' "$VHOST_CONF"; then
    fail_restored "vhost unexpectedly gained a /theramab/assets/video/ location" VHOST_LAYOUT
  fi
fi


# README 404 locations must survive the two-line root switch untouched.
NEXACT=$(grep -cE '^[[:space:]]*location[[:space:]]+=[[:space:]]+/theramab/README\.txt' "$VHOST_CONF" || true)
NREGEX=$(grep -cE 'theramab_readme_block_v1' "$VHOST_CONF" || true)
[[ "$NEXACT" == "2" ]] || fail_restored "vhost has $NEXACT exact README locations after root switch (expected 2)" README_VHOST
[[ "$NREGEX" -ge 4 ]] || fail_restored "vhost lost theramab_readme_block_v1 markers after root switch (count=$NREGEX)" README_VHOST
echo "README_VHOST_OK exact=$NEXACT markers=$NREGEX" | tee -a "$LOG"

NT=$(nginx -t 2>&1) && NRC=0 || NRC=$?
echo "$NT" | tee -a "$LOG"
[[ $NRC -eq 0 ]] || fail_restored "nginx -t failed" NGINX_TEST
echo "NGINX_T_OK" | tee -a "$LOG"
nginx -s reload >>"$LOG" 2>&1 || fail_restored "nginx reload failed" NGINX_RELOAD
echo "NGINX_RELOAD_OK" | tee -a "$LOG"

# ---------- live verify ----------
# Expected sha is the staged new-root index, not LIVE_INDEX_SHA and not a
# pre-overlay / temp extract file.
EXPECTED_HOME_SHA=$(sha "$NEW_REL_DIR/index.html")
EXPECTED_TM_SHA=$(sha "$NEW_REL_DIR/theramab/index.html")
[[ "$EXPECTED_HOME_SHA" == "$NEW_INDEX_SHA" ]] || fail_restored "staged index sha $EXPECTED_HOME_SHA != pin $NEW_INDEX_SHA" VERIFY_HOME
[[ "$EXPECTED_TM_SHA" == "$NEW_THERAMAB_INDEX_SHA" ]] || fail_restored "staged theramab/index sha $EXPECTED_TM_SHA != pin $NEW_THERAMAB_INDEX_SHA" VERIFY_THERAMAB
echo "VERIFY_EXPECT home=$EXPECTED_HOME_SHA theramab=$EXPECTED_TM_SHA (from $NEW_REL_DIR)" | tee -a "$LOG"

# clickstats_v1 pattern: give nginx a moment after reload, then retry.
# curl --retry only covers transport failures, not HTTP 200 with a stale body.
sleep 1

verify_curl() {
  # $1 path  $2 dest-body  $3 dest-hdr
  # Always: --resolve inlightbio.cn:443:127.0.0.1 (unless CURL_RESOLVE is overridden)
  # and Accept-Encoding: identity so a gzip body cannot change the sha.
  curl -sS --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 \
    "${curl_resolve[@]}" \
    -H "Accept-Encoding: identity" \
    -D "$3" -o "$2" -w '%{http_code}' \
    "$SITE_ORIGIN$1" || echo "000"
}

log_hdr() {
  echo "----- response headers ($1) -----" | tee -a "$LOG"
  head -n 25 "$2" | tr -d '\r' | tee -a "$LOG" || true
}

ok=0
C="000"; GOT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/" "$TMPD/home.html" "$TMPD/home.hdr")
  GOT=$(sha "$TMPD/home.html")
  CE=$(grep -i '^content-encoding:' "$TMPD/home.hdr" 2>/dev/null | tr -d '\r' | head -1 || true)
  echo "VERIFY_HOME_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$EXPECTED_HOME_SHA ${CE:-Content-Encoding: (none)}" | tee -a "$LOG"
  log_hdr "GET / try $try" "$TMPD/home.hdr"
  if [[ "$C" == "200" && "$GOT" == "$EXPECTED_HOME_SHA" ]]; then
    ok=1
    break
  fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "homepage HTTP $C sha_got=${GOT:-empty} sha_expected=$EXPECTED_HOME_SHA" VERIFY_HOME
grep -qF 'AI 药物研发平台' "$TMPD/home.html" || fail_restored "live homepage lacks AI 药物研发平台 rec block" VERIFY_HOME
grep -qF 'plat-rec' "$TMPD/home.html" || fail_restored "live homepage lacks plat-rec block" VERIFY_HOME
grep -qF 'class="tmab-nav"' "$TMPD/home.html" && fail_restored "live homepage still has TheraMab top-nav/footer item" VERIFY_HOME
grep -qF 'class="tmab-banner"' "$TMPD/home.html" || fail_restored "live homepage is missing the featured TheraMab banner" VERIFY_HOME
grep -qF '/theramab/assets/img/therasik_favicon.svg' "$TMPD/home.html" || fail_restored "live homepage lacks official Therasik favicon" VERIFY_HOME
grep -qF 'class="plat-card" href="/therasik/"' "$TMPD/home.html" || fail_restored "live homepage TheraSik card is not /therasik/" VERIFY_HOME
grep -qF 'AI 赋能的药物研发与设计' "$TMPD/home.html" || fail_restored "live homepage TheraSik card lacks SaaS blurb" VERIFY_HOME
grep -qF 'aria-hidden="true">TS</span>' "$TMPD/home.html" && fail_restored "live homepage still has the TS placeholder mark" VERIFY_HOME
grep -qE 'fonts\.googleapis\.com|fonts\.gstatic\.com' "$TMPD/home.html" && fail_restored "live homepage still references Google Fonts" VERIFY_HOME
logts "VERIFY_HOME_OK"
echo "VERIFY_HOME_OK HTTP=$C sha=$GOT expected=$EXPECTED_HOME_SHA" | tee -a "$LOG"
# site.css (cache-busting change)
ok=0
C="000"; GOT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/site.css?v=8" "$TMPD/site.css" "$TMPD/site.css.hdr")
  GOT=$(sha "$TMPD/site.css")
  echo "VERIFY_SITECSS_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$NEW_SITE_CSS_SHA" | tee -a "$LOG"
  log_hdr "GET /site.css?v=8 try $try" "$TMPD/site.css.hdr"
  if [[ "$C" == "200" && "$GOT" == "$NEW_SITE_CSS_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "site.css HTTP $C sha_got=${GOT:-empty} sha_expected=$NEW_SITE_CSS_SHA" VERIFY_SITECSS
echo "VERIFY_SITECSS_OK HTTP=$C sha=$GOT expected=$NEW_SITE_CSS_SHA" | tee -a "$LOG"

# /theramab/
ok=0
C="000"; GOT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/theramab/" "$TMPD/tm.html" "$TMPD/tm.hdr")
  GOT=$(sha "$TMPD/tm.html")
  CE=$(grep -i '^content-encoding:' "$TMPD/tm.hdr" 2>/dev/null | tr -d '\r' | head -1 || true)
  echo "VERIFY_THERAMAB_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$EXPECTED_TM_SHA ${CE:-Content-Encoding: (none)}" | tee -a "$LOG"
  log_hdr "GET /theramab/ try $try" "$TMPD/tm.hdr"
  if [[ "$C" == "200" && "$GOT" == "$EXPECTED_TM_SHA" ]]; then
    ok=1
    break
  fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "/theramab/ HTTP $C sha_got=${GOT:-empty} sha_expected=$EXPECTED_TM_SHA" VERIFY_THERAMAB
grep -qF 'theramab_demo_1080p.mp4' "$TMPD/tm.html" || fail_restored "live /theramab/ missing 1080p source" VERIFY_THERAMAB
grep -qF 'AI 药物研发平台' "$TMPD/tm.html" || fail_restored "live /theramab/ lacks AI 药物研发平台 rec block" VERIFY_THERAMAB
grep -qF 'plat-rec' "$TMPD/tm.html" || fail_restored "live /theramab/ lacks plat-rec block" VERIFY_THERAMAB
grep -qF 'TheraSik SaaS' "$TMPD/tm.html" || fail_restored "live /theramab/ lacks TheraSik SaaS card" VERIFY_THERAMAB
grep -qF 'class="plat-card" href="/therasik/"' "$TMPD/tm.html" || fail_restored "live /theramab/ TheraSik card is not /therasik/" VERIFY_THERAMAB
grep -qF 'AI 赋能的药物研发与设计' "$TMPD/tm.html" || fail_restored "live /theramab/ TheraSik card lacks SaaS blurb" VERIFY_THERAMAB
grep -qF '/theramab/assets/img/therasik_favicon.svg' "$TMPD/tm.html" || fail_restored "live /theramab/ lacks official Therasik favicon" VERIFY_THERAMAB
grep -qF 'aria-hidden="true">TS</span>' "$TMPD/tm.html" && fail_restored "live /theramab/ still has the TS placeholder mark" VERIFY_THERAMAB
grep -qF '/theramab/assets/TheraMab_Whitepaper_2026.pdf' "$TMPD/tm.html" || fail_restored "live /theramab/ missing PDF href" VERIFY_THERAMAB
grep -qF 'download="TheraMab_Whitepaper_2026.pdf"' "$TMPD/tm.html" || fail_restored "live /theramab/ missing PDF download attribute" VERIFY_THERAMAB
grep -qF '本白皮书可直接下载' "$TMPD/tm.html" || fail_restored "live /theramab/ missing PDF download wording" VERIFY_THERAMAB
grep -qF '数据在本机处理' "$TMPD/tm.html" || fail_restored "live /theramab/ missing 数据在本机处理" VERIFY_THERAMAB
grep -qF '待确认' "$TMPD/tm.html" && fail_restored "live /theramab/ still contains 待确认" VERIFY_THERAMAB
grep -qF '合作推广">TheraMab' "$TMPD/tm.html" && fail_restored "live /theramab/ chrome nav still has TheraMab as a site column" VERIFY_THERAMAB
grep -qF 'class="tmab-nav"' "$TMPD/tm.html" && fail_restored "live /theramab/ still has TheraMab top-nav item" VERIFY_THERAMAB
echo "VERIFY_THERAMAB_OK HTTP=$C sha=$GOT expected=$EXPECTED_TM_SHA" | tee -a "$LOG"

# /therasik/ intro page + whitepaper
ok=0
for try in 1 2 3 4 5 6; do
  C=$(curl -sS -o "$TMPD/ts.html" -w "%{http_code}" "${curl_resolve[@]}" --max-time 30 "$SITE_ORIGIN/therasik/" || echo curlfail)
  GOT=$(sha "$TMPD/ts.html")
  echo "VERIFY_THERASIK_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$NEW_THERASIK_INDEX_SHA" | tee -a "$LOG"
  if [[ "$C" == "200" && "$GOT" == "$NEW_THERASIK_INDEX_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "/therasik/ HTTP $C sha_got=${GOT:-empty} sha_expected=$NEW_THERASIK_INDEX_SHA" VERIFY_THERASIK
grep -qF "申请邀请码" "$TMPD/ts.html" || fail_restored "live /therasik/ lacks 申请邀请码" VERIFY_THERASIK
grep -qF "https://saas.therasik.com/" "$TMPD/ts.html" || fail_restored "live /therasik/ lacks saas.therasik.com" VERIFY_THERASIK
grep -qF "contact@therasik.com" "$TMPD/ts.html" || fail_restored "live /therasik/ lacks contact@therasik.com" VERIFY_THERASIK
grep -qF "已部署 32" "$TMPD/ts.html" || fail_restored "live /therasik/ lacks 已部署 32" VERIFY_THERASIK
grep -qF "目录共 210" "$TMPD/ts.html" || fail_restored "live /therasik/ lacks 目录共 210" VERIFY_THERASIK
grep -qF "AI 赋能的药物研发与设计" "$TMPD/ts.html" || fail_restored "live /therasik/ lacks SaaS title" VERIFY_THERASIK
grep -qF "申请试用" "$TMPD/ts.html" && fail_restored "live /therasik/ still has 申请试用" VERIFY_THERASIK
grep -qF "3–5 个工作日" "$TMPD/ts.html" && fail_restored "live /therasik/ still has console-style 3–5 个工作日 copy" VERIFY_THERASIK
grep -qF "1,133" "$TMPD/ts.html" && fail_restored "live /therasik/ still has console-style 1,133 copy" VERIFY_THERASIK
grep -qE "近[[:space:]]*200" "$TMPD/ts.html" && fail_restored "live /therasik/ still has 近200" VERIFY_THERASIK
grep -qF "$THERASIK_PDF_REL" "$TMPD/ts.html" || fail_restored "live /therasik/ missing PDF href" VERIFY_THERASIK
echo "VERIFY_THERASIK_OK HTTP=$C sha=$GOT expected=$NEW_THERASIK_INDEX_SHA" | tee -a "$LOG"

ok=0
for try in 1 2 3 4 5 6; do
  C=$(curl -sS -o "$TMPD/ts.pdf" -w "%{http_code}" "${curl_resolve[@]}" --max-time 60 "$SITE_ORIGIN/$THERASIK_PDF_REL" || echo curlfail)
  GOT=$(sha "$TMPD/ts.pdf")
  CT=$(curl -sS -D - -o /dev/null "${curl_resolve[@]}" --max-time 30 "$SITE_ORIGIN/$THERASIK_PDF_REL" 2>/dev/null | grep -i "^content-type:" || true)
  echo "VERIFY_THERASIK_PDF_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$THERASIK_PDF_SHA ${CT:-Content-Type: (none)}" | tee -a "$LOG"
  if [[ "$C" == "200" && "$GOT" == "$THERASIK_PDF_SHA" && "$CT" == *[Pp][Dd][Ff]* ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "TheraSik PDF HTTP $C sha_got=${GOT:-empty} sha_expected=$THERASIK_PDF_SHA ctype=${CT:-none}" VERIFY_THERASIK_PDF
echo "VERIFY_THERASIK_PDF_OK HTTP=$C sha=$GOT ctype=$CT" | tee -a "$LOG"

# PDF (inherited from the copied live root; not in the overlay)
ok=0
C="000"; GOT=""; CT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/theramab/assets/TheraMab_Whitepaper_2026.pdf" "$TMPD/wp.pdf" "$TMPD/wp.hdr")
  GOT=$(sha "$TMPD/wp.pdf")
  CT=$(grep -i '^content-type:' "$TMPD/wp.hdr" 2>/dev/null | tr -d '\r' | head -1 || true)
  echo "VERIFY_PDF_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$PDF_SHA ${CT:-Content-Type: (none)}" | tee -a "$LOG"
  log_hdr "GET /theramab/assets/TheraMab_Whitepaper_2026.pdf try $try" "$TMPD/wp.hdr"
  if [[ "$C" == "200" && "$GOT" == "$PDF_SHA" ]] && echo "$CT" | grep -qi 'application/pdf'; then
    ok=1
    break
  fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "PDF HTTP $C sha_got=${GOT:-empty} sha_expected=$PDF_SHA ctype=${CT:-none}" VERIFY_PDF
echo "VERIFY_PDF_OK HTTP=$C sha=$GOT ctype=$CT" | tee -a "$LOG"

# README must remain 404 (vhost rule intact). File on disk must be unchanged.
README_DISK="$CURRENT_ROOT/theramab/README.txt"
if [[ -f "$NEW_REL_DIR/theramab/README.txt" ]]; then
  README_DISK="$NEW_REL_DIR/theramab/README.txt"
fi
README_DISK_SHA=$(sha "$README_DISK")
ok=0
C="000"
for try in 1 2 3 4 5; do
  C=$(verify_curl "/theramab/README.txt" "$TMPD/readme.txt" "$TMPD/readme.hdr")
  echo "VERIFY_README_TRY $try HTTP=$C sha_got=$(sha "$TMPD/readme.txt" || echo empty) (expect HTTP 404; file on disk sha=$README_DISK_SHA)" | tee -a "$LOG"
  log_hdr "GET /theramab/README.txt try $try" "$TMPD/readme.hdr"
  if [[ "$C" == "404" ]]; then
    if [[ -s "$TMPD/readme.txt" && "$(sha "$TMPD/readme.txt")" == "$README_DISK_SHA" ]]; then
      echo "ERR: 404 body is still the on-disk README" | tee -a "$LOG"
    else
      ok=1
      break
    fi
  fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "README HTTP $C (expected 404); file still on disk sha=$README_DISK_SHA" VERIFY_README
echo "VERIFY_README_OK HTTP=$C (blocked); disk unchanged sha=$README_DISK_SHA" | tee -a "$LOG"
[[ -f "$README_DISK" && "$(sha "$README_DISK")" == "$README_DISK_SHA" ]] || fail_restored "README.txt on disk changed during verify" README_DISK
echo "VERIFY_README_DISK_OK $README_DISK sha=$README_DISK_SHA" | tee -a "$LOG"

C=$(verify_curl "/theramab/assets/video/theramab_demo_poster.jpg" "$TMPD/poster.jpg" "$TMPD/poster.hdr")
GOT=$(sha "$TMPD/poster.jpg")
echo "VERIFY_POSTER HTTP=$C sha_got=${GOT:-empty} sha_expected=$POSTER_SHA" | tee -a "$LOG"
log_hdr "GET poster" "$TMPD/poster.hdr"
[[ "$C" == "200" && "$GOT" == "$POSTER_SHA" ]] || fail_restored "poster HTTP $C sha_got=${GOT:-empty} sha_expected=$POSTER_SHA" VERIFY_POSTER
echo "VERIFY_POSTER_OK HTTP=$C sha=$GOT" | tee -a "$LOG"

C=$(verify_curl "/theramab/assets/img/theramab_card_thumb_v34e.png" "$TMPD/thumb.png" "$TMPD/thumb.hdr")
GOT=$(sha "$TMPD/thumb.png")
echo "VERIFY_THUMB HTTP=$C sha_got=${GOT:-empty} sha_expected=$NEW_THUMB_SHA" | tee -a "$LOG"
log_hdr "GET card thumb" "$TMPD/thumb.hdr"
[[ "$C" == "200" && "$GOT" == "$NEW_THUMB_SHA" ]] || fail_restored "thumb HTTP $C sha_got=${GOT:-empty} sha_expected=$NEW_THUMB_SHA" VERIFY_THUMB
echo "VERIFY_THUMB_OK HTTP=$C sha=$GOT" | tee -a "$LOG"

verify_range() {
  local path="$1"
  local hdr="$TMPD/hdr" body="$TMPD/range.body"
  local code
  code=$(curl -sS --retry 2 --connect-timeout 10 --max-time 60 "${curl_resolve[@]}" \
    -H "Accept-Encoding: identity" \
    -D "$hdr" -o "$body" -w '%{http_code}' -H "Range: bytes=0-1023" "$SITE_ORIGIN$path" || echo "000")
  echo "VERIFY_RANGE_TRY $path HTTP=$code" | tee -a "$LOG"
  if [[ "$code" != "206" ]]; then
    echo "ERR: $path Range expected 206 got $code" | tee -a "$LOG"
    head -n 20 "$hdr" | tee -a "$LOG"
    return 1
  fi
  local n
  n=$(wc -c < "$body")
  [[ "$n" -eq 1024 ]] || { echo "ERR: $path Range body $n bytes, expected 1024" | tee -a "$LOG"; return 1; }
  echo "VERIFY_RANGE_OK $path HTTP 206 (1024 bytes)" | tee -a "$LOG"
  return 0
}
verify_range "/theramab/assets/video/theramab_demo_1080p.mp4" || fail_restored "1080p Range/206 failed" VERIFY_RANGE
verify_range "/theramab/assets/video/theramab_demo_720p.mp4"  || fail_restored "720p Range/206 failed" VERIFY_RANGE

H=$(curl -s -m 10 "${curl_resolve[@]}" "$SITE_ORIGIN/api/talent/health" || true)
[[ "$H" == *talent-v* ]] && echo "TALENT_API_OK (unchanged) $(printf %s "${H:0:60}" | tr -d '\r\n')" | tee -a "$LOG" || echo "WARN: talent API health did not answer (API untouched by this deploy): $(printf %s "${H:0:80}" | tr -d '\r\n')" | tee -a "$LOG"

FINISHED=1
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
