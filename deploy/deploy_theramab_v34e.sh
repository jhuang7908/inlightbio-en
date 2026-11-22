#!/usr/bin/env bash
# InLightBio CN deploy — TheraMab card-thumbnail fix, v34e (2026-11-22)
# v34d is LIVE: root /www/wwwroot/inlightbio_cn_rel_20261122_24d381a_theramab_v34d,
# homepage sha bb07f9b6…, /theramab/ sha 41e6eb5e… (PR #138 merged as 3e0a1e0).
#
# v34e is a follow-up visual fix only: the mobile homepage card cropped the
# 1920×1080 video poster (object-fit:cover into a 110×86 box), cutting the
# cover title to “Mab：AI 驱动的治疗性…”, and the poster had a hard teal/mint
# edge against the card’s #f0fdf9 background. Overlay is THREE new/changed
# files from therasik-inlight commit d61afa4 (PR #139, not merged):
#   index.html, site.css, theramab/assets/img/theramab_card_thumb_v34e.png
# The 3D antibody is composited from the existing molecule.png (not overwritten).
# The video poster and /theramab/ page are unchanged. Desktop banner CSS is
# unchanged.
#
# Same proven pattern as v34d / clickstats_v1 / scicards:
#  * detect the live nginx root; copy it to a FRESH release dir (abort if that dir exists);
#  * overlay the 3 sha-verified files; never edit/delete the old (v34d) root;
#  * MP4s stay in /www/wwwroot/inlight_static/theramab/ and are hardlinked/copied
#    into $NEW_REL_DIR/theramab/assets/video/ if missing (no nginx alias);
#  * write rollback.sh; back up the vhost; sed only the two root lines; print diff -u;
#  * nginx -t && reload; sleep 1; verify homepage / theramab / thumb / poster / Range 206
#    with retries; print DEPLOY_OK.
#  * On any failure after the vhost is touched, restore the backup and reload (FAIL_*_RESTORED).
#  * Idempotent: if the live root is already the new dir and files match → DEPLOY_OK.
#  * Does NOT merge PR #139, does not delete old roots, does not run anything except on this host.
#
# Run as root on the Aliyun 轻量 instance. Log: /root/deploy_theramab_v34e_<ts>.log
# Never delete/overwrite:
#   /www/wwwroot/inlightbio_cn_rel_20261122_24d381a_theramab_v34
#   /www/wwwroot/inlightbio_cn_rel_20261122_24d381a_theramab_v34b
#   /www/wwwroot/inlightbio_cn_rel_20261122_24d381a_theramab_v34c
#   /www/wwwroot/inlightbio_cn_rel_20261122_24d381a_theramab_v34d
#   /root/inlight_backups_20261122_theramab_v34/
#   /root/inlight_backups_20261122_theramab_v34b/
#   /root/inlight_backups_20261122_theramab_v34c/
#   /root/inlight_backups_20261122_theramab_v34d/
set -uo pipefail

OVERLAY_TAR_SHA="${OVERLAY_TAR_SHA:-4a247650673b099c7947277bcdfa3fce0cc01b6a3bc535adbeccf719a38036d9}"
NEW_INDEX_SHA="${NEW_INDEX_SHA:-93af766116fc0a4c58c8aba79e6c7c184669b6ae9a8d035c89d765147a620a2a}"
OLD_INDEX_SHA="${OLD_INDEX_SHA:-bb07f9b68b4fc979afefe54ad45f83e9f30e1e996751ca1e867035310c34b981}"
NEW_SITE_CSS_SHA="${NEW_SITE_CSS_SHA:-53dab2d747daf982ce7e9a44eea0c361e52f8dd516434b549473302b900aae29}"
NEW_THERAMAB_INDEX_SHA="${NEW_THERAMAB_INDEX_SHA:-41e6eb5e8767297ca3ceaf94cf6e917c861303954a169e725cfc1d9caeb07326}"
NEW_NEWCO_SHA="${NEW_NEWCO_SHA:-048df5468f58575899d87e67ac7d9a80167c1dac107b51634e77fa0684e860c5}"
POSTER_SHA="${POSTER_SHA:-fb2e21702862f900aed2785f732f2652839649d9d06b0e5a80f84d3b587a90bd}"
MP4_1080_SHA="${MP4_1080_SHA:-1ee6af4a09cdaa7a40ee22370d3fc071416a5fdaffc184c5a6390e82a953e0ee}"
MP4_720_SHA="${MP4_720_SHA:-806afc6172a55e01f4019f4e32cae8aa299393da7ead647b1fe58e859c9cb445}"
# ffmpeg -vn -acodec copy -f md5  (same on both renditions)
AUDIO_MD5_COPY="e86cc6214c834dba0238356f45f926ad"
OVERLAY_NFILES=3
NEW_THUMB_SHA="${NEW_THUMB_SHA:-528763de74c09be5db3aad0370ee0caee8a3cc22feaf75da61ee12f3559db7dc}"
THUMB_REL="theramab/assets/img/theramab_card_thumb_v34e.png"
SRC_COMMIT="d61afa4"

VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
EXPECTED_OLD_ROOT="${EXPECTED_OLD_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261122_24d381a_theramab_v34d}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261122_d61afa4_theramab_v34e}"
STATIC_DIR="${STATIC_DIR:-/www/wwwroot/inlight_static/theramab}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261122_theramab_v34e}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
PUB_TAG="${PUB_TAG:-cn-deploy-2026-11-22-theramab-v34e}"
PRIV_TAG="${PRIV_TAG:-theramab-v34e-deploy-20261122}"
PUB_REPO="${PUB_REPO:-jhuang7908/inlightbio-en}"
PRIV_REPO="${PRIV_REPO:-jhuang7908/therasik-inlight}"
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"; fi
curl_resolve=(); [[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")

TS=$(date '+%Y%m%d_%H%M%S')
LOG="${LOG:-/root/deploy_theramab_v34e_${TS}.log}"
CURRENT_ROOT=""; BACKUP_CONF=""; WEB_TOUCHED=0
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
FINISHED=0
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE" | tee -a "$LOG"; FINISHED=1; exit 1; }
if ! { : >> "$LOG"; } 2>/dev/null; then LOG="/tmp/deploy_theramab_v34e_${TS}.log"; : >> "$LOG"; fi
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

echo "START theramab_v34e $TS src=$SRC_COMMIT new_root=$NEW_REL_DIR" | tee -a "$LOG"
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing: $VHOST_CONF" VHOST
NT=$(nginx -t 2>&1); NRC=$?
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
  [[ "$(sha "$NEW_REL_DIR/theramab/assets/video/theramab_demo_poster.jpg")" == "$POSTER_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/pages/newco-report.html")" == "$NEW_NEWCO_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/$THUMB_REL")" == "$NEW_THUMB_SHA" ]] || return 1
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
  echo "BACKUP_OK (no change; already live)" | tee -a "$LOG"
  echo "STAGE_OK (no change; already live)" | tee -a "$LOG"
  FINISHED=1
  summary "DEPLOY_OK" | tee -a "$LOG"
  exit 0
fi

if [[ "$CURRENT_ROOT" == "$NEW_REL_DIR" ]]; then
  abort "live root is already $NEW_REL_DIR but files/sha do not fully match; refusing to overwrite" DRIFT
fi

if [[ "$LIVE_INDEX_SHA" == "$NEW_INDEX_SHA" ]]; then
  abort "live homepage is already the d61afa4 (v34e) page but root is $CURRENT_ROOT (not $NEW_REL_DIR); refusing to guess" DRIFT
fi
if [[ "$LIVE_INDEX_SHA" != "$OLD_INDEX_SHA" ]]; then
  abort "live $CURRENT_ROOT/index.html sha=$LIVE_INDEX_SHA is neither the expected v34d page ($OLD_INDEX_SHA) nor the new v34e page; refusing to overlay (would risk losing live edits)" DRIFT
fi
if [[ "$CURRENT_ROOT" != "$EXPECTED_OLD_ROOT" ]]; then
  echo "WARN: live root is $CURRENT_ROOT (expected $EXPECTED_OLD_ROOT); homepage sha matches v34d, continuing" | tee -a "$LOG"
fi
[[ ! -e "$NEW_REL_DIR" ]] || abort "new root $NEW_REL_DIR already exists; refusing to reuse/overwrite" NEWROOT_EXISTS
grep -qF "$NEW_REL_DIR" "$VHOST_CONF" && abort "vhost already references the new root" NEWROOT_EXISTS
echo "PRE_OK OLD_ROOT=$CURRENT_ROOT LIVE_INDEX_SHA=$LIVE_INDEX_SHA" | tee -a "$LOG"

# Public inlightbio-en release is the fetch source (therasik-inlight is private;
# unauthenticated pulls from the CN server would fail). ghfast / ghproxy first.
asset_urls() {
  local file="$1" tag repo
  # v34e tag first (new overlay). MP4s/poster may also come from earlier v34*
  # releases (identical sha256).
  for repo in "$PUB_REPO" "$PRIV_REPO"; do
    for tag in "$PUB_TAG" "cn-deploy-2026-11-22-theramab-v34d" "cn-deploy-2026-11-22-theramab-v34c" "cn-deploy-2026-11-22-theramab-v34b" "cn-deploy-2026-11-22-theramab-v34" "$PRIV_TAG" "theramab-v34d-deploy-20261122" "theramab-v34c-deploy-20261122" "theramab-v34b-deploy-20261122" "theramab-v34-video-20261122"; do
      [[ "$repo" == "$PUB_REPO" && ( "$tag" == "$PUB_TAG" || "$tag" == "cn-deploy-2026-11-22-theramab-v34d" || "$tag" == "cn-deploy-2026-11-22-theramab-v34c" || "$tag" == "cn-deploy-2026-11-22-theramab-v34b" || "$tag" == "cn-deploy-2026-11-22-theramab-v34" ) ]] || \
      [[ "$repo" == "$PRIV_REPO" && ( "$tag" == "$PRIV_TAG" || "$tag" == "theramab-v34d-deploy-20261122" || "$tag" == "theramab-v34c-deploy-20261122" || "$tag" == "theramab-v34b-deploy-20261122" || "$tag" == "theramab-v34-video-20261122" ) ]] || continue
      echo "https://ghfast.top/https://github.com/${repo}/releases/download/${tag}/${file}"
      echo "https://gh-proxy.com/https://github.com/${repo}/releases/download/${tag}/${file}"
      echo "https://mirror.ghproxy.com/https://github.com/${repo}/releases/download/${tag}/${file}"
      echo "https://github.com/${repo}/releases/download/${tag}/${file}"
    done
  done
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
      echo "TRY $file mirror=$url (round $round)" | tee -a "$LOG"
      if curl --retry 3 --retry-delay 3 --connect-timeout 20 --max-time 600 -fsSL "$url" -o "$part"; then
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

CACHE_DIR="${CACHE_DIR:-/root/inlight_cache_theramab_v34e}"
# Prior caches may be reused ONLY when the sha256 matches the expected (new) value.
PRIOR_CACHES="${PRIOR_CACHES:-/root/inlight_cache_theramab_v34d /root/inlight_cache_theramab_v34c /root/inlight_cache_theramab_v34b /root/inlight_cache_theramab_v34}"
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
seed_from_prior "overlay_d61afa4_theramab_v34e.tar.gz" "$OVERLAY_TAR_SHA" || true
seed_from_prior "theramab_demo_1080p.mp4" "$MP4_1080_SHA" || true
seed_from_prior "theramab_demo_720p.mp4" "$MP4_720_SHA" || true
seed_from_prior "theramab_demo_poster.jpg" "$POSTER_SHA" || true

fetch_sha "$CACHE_DIR/overlay_d61afa4_theramab_v34e.tar.gz" "$OVERLAY_TAR_SHA" "overlay_d61afa4_theramab_v34e.tar.gz" \
  || abort "failed to download overlay tarball (commit $SRC_COMMIT)" DOWNLOAD
fetch_sha "$CACHE_DIR/theramab_demo_1080p.mp4" "$MP4_1080_SHA" "theramab_demo_1080p.mp4" \
  || abort "failed to download 1080p mp4" DOWNLOAD
fetch_sha "$CACHE_DIR/theramab_demo_720p.mp4" "$MP4_720_SHA" "theramab_demo_720p.mp4" \
  || abort "failed to download 720p mp4" DOWNLOAD
fetch_sha "$CACHE_DIR/theramab_demo_poster.jpg" "$POSTER_SHA" "theramab_demo_poster.jpg" \
  || abort "failed to download poster" DOWNLOAD
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
echo "COPY_START $CURRENT_ROOT -> $NEW_REL_DIR" | tee -a "$LOG"
cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then
  P=$(park "$NEW_REL_DIR/rollback.sh" "rollback.sh.inherited_from_$(basename "$CURRENT_ROOT").disabled") && chmod 600 "$P" && echo "INHERITED_ROLLBACK_PARKED $P" | tee -a "$LOG"
fi

mkdir -p "$TMPD/overlay"
tar -xzf "$CACHE_DIR/overlay_d61afa4_theramab_v34e.tar.gz" -C "$TMPD/overlay" --no-same-owner || abort "overlay extract failed" EXTRACT
NFOUND=$(find "$TMPD/overlay" -type f | wc -l)
[[ "$NFOUND" -eq "$OVERLAY_NFILES" ]] || abort "overlay has $NFOUND files, expected $OVERLAY_NFILES" EXTRACT
[[ "$(sha "$TMPD/overlay/index.html")" == "$NEW_INDEX_SHA" ]] || abort "overlay index.html sha mismatch" EXTRACT
[[ "$(sha "$TMPD/overlay/site.css")" == "$NEW_SITE_CSS_SHA" ]] || abort "overlay site.css sha mismatch" EXTRACT
[[ "$(sha "$TMPD/overlay/$THUMB_REL")" == "$NEW_THUMB_SHA" ]] || abort "overlay thumbnail sha mismatch" EXTRACT
if find "$TMPD/overlay" -iname '*.mp4' | grep -q .; then abort "overlay tarball unexpectedly contains mp4s" EXTRACT; fi
# Never ship a replacement for the existing video poster or molecule.png.
if find "$TMPD/overlay" \( -name 'theramab_demo_poster.jpg' -o -name 'molecule.png' \) | grep -q .; then
  abort "overlay unexpectedly contains poster or molecule.png" EXTRACT
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
for pat in 'TheraMab' 'tmab-art' '<h2>学术进展</h2>' 'id="latestgrid"' 'assets/ev/px.js?v=20261120a' 'assets/talent/talent_fund.js?v=20261120a' 'assets/fonts/fonts.css' 'id="bp-home"' 'id="home-talent"' '看演示视频' '/theramab/assets/img/theramab_card_thumb_v34e.png'; do
  grep -qF "$pat" "$I" || abort "staged homepage missing: $pat" STAGE
done
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
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_theramab_v34e.$TS.sh"
echo "STAGE_OK" | tee -a "$LOG"

# ---------- vhost backup + sed-only root switch (no layout change) ----------
BACKUP_CONF="${VHOST_CONF}.bak.theramab_v34e.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
[[ ! -e "$VHOST_BAK_FIXED" ]] || abort "backup $VHOST_BAK_FIXED already exists" BACKUP
cp -a "$BACKUP_CONF" "$VHOST_BAK_FIXED" || abort "second vhost backup failed" BACKUP
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


NT=$(nginx -t 2>&1); NRC=$?
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
grep -qF 'TheraMab' "$TMPD/home.html" || fail_restored "live homepage lacks TheraMab nav/banner" VERIFY_HOME
grep -qF 'tmab-art' "$TMPD/home.html" || fail_restored "live homepage lacks compact banner" VERIFY_HOME
grep -qE 'fonts\.googleapis\.com|fonts\.gstatic\.com' "$TMPD/home.html" && fail_restored "live homepage still references Google Fonts" VERIFY_HOME
echo "VERIFY_HOME_OK HTTP=$C sha=$GOT expected=$EXPECTED_HOME_SHA" | tee -a "$LOG"

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
echo "VERIFY_THERAMAB_OK HTTP=$C sha=$GOT expected=$EXPECTED_TM_SHA" | tee -a "$LOG"

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
