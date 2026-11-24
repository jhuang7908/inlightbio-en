#!/usr/bin/env bash
# InLightBio CN deploy — TheraSik demo video + /therasik/ overlay (therasik_video_v1, 2026-11-24)
# Jing approved upload+embed (t1095u); previews at 390/1440 were reviewed and approved.
# Adds 6 media files under /www/wwwroot/inlight_static/therasik/ (same sha = skip;
# different sha = abort, never overwrite) and a new site root with
# therasik/index.html (sha 2b03ddb6…) plus therasik/assets/video/ hardlinks.
# Homepage and /theramab/ must stay unchanged. Does not merge PRs.
# Live /therasik/ must still be sha 35453694… (figs_v1). Detect nginx root from
# the vhost (do not require a stale release-dir name).
#
# Pattern from 2026-11-22 TheraMab video / wp2026_r3 and clickstats_v1:
# download from the public inlightbio-en release (ghfast / ghproxy / github),
# stage a FRESH root, write rollback.sh, backup vhost, switch root, nginx -t
# (restore on failure), reload, verify over curl -k --resolve, auto-rollback
# on verify failure (FAIL_*_RESTORED). Deletes nothing.
set -uo pipefail
export LANG=C.UTF-8 LC_ALL=C.UTF-8

LABEL="therasik_video_v1"
PUB_REPO="${PUB_REPO:-jhuang7908/inlightbio-en}"
PUB_TAG="${PUB_TAG:-cn-deploy-2026-11-24-therasik-video-v1}"
CACHE_DIR="${CACHE_DIR:-/root/inlight_cache_therasik_video_v1}"
STATIC_DIR="${STATIC_DIR:-/www/wwwroot/inlight_static/therasik}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261124_a07ff31_therasik_video_v1}"
VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261124_therasik_video_v1}"
LOG="${LOG:-/root/deploy_therasik_video_v1_$(date +%Y%m%d_%H%M%S).log}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"; fi
curl_resolve=(); [[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")

# Assets (public names) — sha256
HTML_FILE="therasik_index.html"
HTML_SHA="${HTML_SHA:-2b03ddb6ea506eb183b65ff6f4a2908bbc3b495e58766b80c9d77e20cf8216c4}"
LIVE_THERASIK_SHA="${LIVE_THERASIK_SHA:-35453694e2fbdcdf34f935cebec3d9c8549c6205fc01620a5b922a96954c7ba4}"
EN_1080_SHA="${EN_1080_SHA:-2e35b9dbaceb7105b576b090e205925056c7465287084df30877a3742a580584}"
EN_720_SHA="${EN_720_SHA:-9c3fd3a89e2b947548714ac482fa264cf0089f2de341798ba3fc2d1920158688}"
EN_POSTER_SHA="${EN_POSTER_SHA:-153f26a38f6ba929fe38296e128d4e6d10831593d7c6f5693db6fa31121ed0c9}"
ZH_1080_SHA="${ZH_1080_SHA:-d09e682fb9fde3fa49d3013bb82d059e6d5297db47eb5d35bf6084c60532f78e}"
ZH_720_SHA="${ZH_720_SHA:-bec5a50cc592097c2e3903055f5d526dc493995021975422d698aa4e8eb46e47}"
ZH_POSTER_SHA="${ZH_POSTER_SHA:-740401d3b112a4d9a3ddc3f486b9ad47325c0266fd429acb37526d745eb4175b}"

MEDIA_LIST="
therasik_demo_en_1080p.mp4  $EN_1080_SHA
therasik_demo_en_720p.mp4   $EN_720_SHA
therasik_demo_en_poster.jpg $EN_POSTER_SHA
therasik_demo_zh_1080p.mp4  $ZH_1080_SHA
therasik_demo_zh_720p.mp4   $ZH_720_SHA
therasik_demo_zh_poster.jpg $ZH_POSTER_SHA
"

CURRENT_ROOT=""; BACKUP_CONF=""; WEB_TOUCHED=0; FINISHED=0
TS=$(date '+%Y%m%d_%H%M%S')
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE" | tee -a "$LOG"; FINISHED=1; exit 1; }
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
park() { local src="$1" name="$2" dst; mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"; dst="$BACKUP_BASE/$name"; [[ -e "$dst" ]] && dst="$dst.$TS"; [[ -e "$dst" ]] && dst="$dst.$$"; mv "$src" "$dst" && echo "$dst"; }
media_rows() { printf '%s\n' "$MEDIA_LIST" | awk 'NF==2'; }

if ! { : > "$LOG"; } 2>/dev/null; then LOG=/tmp/deploy_therasik_video_v1_$TS.log; : > "$LOG"; fi
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

echo "START therasik_video_v1 $TS tag=$PUB_TAG new_root=$NEW_REL_DIR" | tee -a "$LOG"
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing $VHOST_CONF" VHOST

NT=$(nginx -t 2>&1); NRC=$?
if [[ $NRC -ne 0 ]]; then echo "$NT"; abort "nginx -t fails before any change" PRE_NGINX; fi
echo "PRE_NGINX_T_OK" | tee -a "$LOG"

CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ -n "$CURRENT_ROOT" && -d "$CURRENT_ROOT" && -f "$CURRENT_ROOT/index.html" ]] || abort "cannot detect live root ($CURRENT_ROOT)" LIVEROOT
NUNIQUE=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | awk '{print $2}' | tr -d ';' | sort -u | wc -l | tr -d '[:space:]')
[[ "$NUNIQUE" == "1" ]] || abort "vhost has $NUNIQUE distinct root values; expected 1" LIVEROOT
NROOT_LINES=$(grep -cE "^[[:space:]]*root[[:space:]]+${CURRENT_ROOT};" "$VHOST_CONF" || true)
[[ "$NROOT_LINES" -ge 1 ]] || abort "no exact root $CURRENT_ROOT; lines in vhost" LIVEROOT

[[ -f "$CURRENT_ROOT/therasik/index.html" ]] || abort "live root lacks therasik/index.html" DRIFT
LIVE_TS_SHA=$(sha "$CURRENT_ROOT/therasik/index.html")
LIVE_HOME_SHA=$(sha "$CURRENT_ROOT/index.html")
LIVE_TM_SHA=""
[[ -f "$CURRENT_ROOT/theramab/index.html" ]] && LIVE_TM_SHA=$(sha "$CURRENT_ROOT/theramab/index.html")

already_live() {
  [[ "$CURRENT_ROOT" == "$NEW_REL_DIR" ]] || return 1
  [[ "$LIVE_TS_SHA" == "$HTML_SHA" ]] || return 1
  local n sha_got
  while read -r name exp; do
    [[ -f "$STATIC_DIR/$name" && "$(sha "$STATIC_DIR/$name")" == "$exp" ]] || return 1
    [[ -f "$NEW_REL_DIR/therasik/assets/video/$name" && "$(sha "$NEW_REL_DIR/therasik/assets/video/$name")" == "$exp" ]] || return 1
  done < <(media_rows)
  return 0
}

if already_live; then
  echo "IDEMPOTENT already deployed at $NEW_REL_DIR" | tee -a "$LOG"
  echo "DOWNLOAD_OK (already live)" | tee -a "$LOG"
  echo "STAGE_OK (no change; already live)" | tee -a "$LOG"
  echo "BACKUP_OK (no change; already live)" | tee -a "$LOG"
  echo "NGINX_T_OK (no change; already live)" | tee -a "$LOG"
  FINISHED=1
  summary "DEPLOY_OK" | tee -a "$LOG"
  exit 0
fi

if [[ "$CURRENT_ROOT" == "$NEW_REL_DIR" ]]; then
  abort "live root is already $NEW_REL_DIR but files/sha do not fully match; refusing to overwrite" DRIFT
fi
if [[ "$LIVE_TS_SHA" == "$HTML_SHA" ]]; then
  abort "live /therasik/ is already the new HTML sha but root is $CURRENT_ROOT (not $NEW_REL_DIR); refusing to guess" DRIFT
fi
if [[ "$LIVE_TS_SHA" != "$LIVE_THERASIK_SHA" ]]; then
  abort "live $CURRENT_ROOT/therasik/index.html sha=$LIVE_TS_SHA is not the expected figs_v1 page ($LIVE_THERASIK_SHA) nor the new page; refusing to overlay" DRIFT
fi
[[ ! -e "$NEW_REL_DIR" ]] || abort "new root $NEW_REL_DIR already exists; refusing to reuse/overwrite" NEWROOT_EXISTS
grep -qF "$NEW_REL_DIR" "$VHOST_CONF" && abort "vhost already references the new root" NEWROOT_EXISTS
echo "PRE_OK OLD_ROOT=$CURRENT_ROOT LIVE_THERASIK_SHA=$LIVE_TS_SHA LIVE_HOME_SHA=$LIVE_HOME_SHA LIVE_THERAMAB_SHA=${LIVE_TM_SHA:-none}" | tee -a "$LOG"

# ---------- download 7 assets from the public release ----------
asset_urls() {
  local file="$1"
  echo "https://ghfast.top/https://github.com/${PUB_REPO}/releases/download/${PUB_TAG}/${file}"
  echo "https://gh-proxy.com/https://github.com/${PUB_REPO}/releases/download/${PUB_TAG}/${file}"
  echo "https://mirror.ghproxy.com/https://github.com/${PUB_REPO}/releases/download/${PUB_TAG}/${file}"
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

mkdir -p "$CACHE_DIR" || abort "cannot create cache dir" DOWNLOAD
fetch_sha "$CACHE_DIR/$HTML_FILE" "$HTML_SHA" "$HTML_FILE" || abort "failed to download $HTML_FILE" DOWNLOAD
while read -r name exp; do
  fetch_sha "$CACHE_DIR/$name" "$exp" "$name" || abort "failed to download $name" DOWNLOAD
done < <(media_rows)
echo "DOWNLOAD_OK" | tee -a "$LOG"

# ---------- install into inlight_static (never overwrite a different sha) ----------
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
mkdir -p "$STATIC_DIR"
while read -r name exp; do
  install_static "$CACHE_DIR/$name" "$STATIC_DIR/$name" "$exp"
done < <(media_rows)
if [[ ! -e "$STATIC_DIR/SHA256SUMS.txt" ]]; then
  media_rows | awk '{print $2"  "$1}' > "$STATIC_DIR/SHA256SUMS.txt"
  chmod 644 "$STATIC_DIR/SHA256SUMS.txt"
fi
echo "STATIC_OK $STATIC_DIR" | tee -a "$LOG"

# ---------- stage new root ----------
echo "COPY_START $CURRENT_ROOT -> $NEW_REL_DIR" | tee -a "$LOG"
cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then
  P=$(park "$NEW_REL_DIR/rollback.sh" "rollback.sh.inherited_from_$(basename "$CURRENT_ROOT").disabled") && chmod 600 "$P" && echo "INHERITED_ROLLBACK_PARKED $P" | tee -a "$LOG"
fi

# Overlay HTML without touching the live root (cp -a may hardlink on some setups: replace via temp write)
HTML_DEST="$NEW_REL_DIR/therasik/index.html"
[[ -f "$HTML_DEST" ]] || abort "staged root missing therasik/index.html after copy" STAGE
# break any hardlink with the live file
cp -a "$HTML_DEST" "$TMPD/old_therasik_index.html"
rm -f "$HTML_DEST"
cp -a "$CACHE_DIR/$HTML_FILE" "$HTML_DEST" || abort "install therasik/index.html failed" STAGE
if [[ -e "$NEW_REL_DIR/index.html" ]]; then
  chown --reference="$NEW_REL_DIR/index.html" "$HTML_DEST" 2>/dev/null || true
  chmod --reference="$NEW_REL_DIR/index.html" "$HTML_DEST" 2>/dev/null || true
fi
[[ "$(sha "$HTML_DEST")" == "$HTML_SHA" ]] || abort "staged therasik/index.html sha mismatch" STAGE
# live file must be unchanged
[[ "$(sha "$CURRENT_ROOT/therasik/index.html")" == "$LIVE_THERASIK_SHA" ]] || abort "live therasik/index.html changed during stage" STAGE
[[ "$(sha "$TMPD/old_therasik_index.html")" == "$LIVE_THERASIK_SHA" ]] || true

VIDEO_DIR="$NEW_REL_DIR/therasik/assets/video"
mkdir -p "$VIDEO_DIR"
if [[ -e "$NEW_REL_DIR/index.html" ]]; then
  chown --reference="$NEW_REL_DIR/index.html" "$VIDEO_DIR" 2>/dev/null || true
fi
while read -r name exp; do
  dest="$VIDEO_DIR/$name"
  if [[ -e "$dest" ]]; then
    if [[ "$(sha "$dest")" == "$exp" ]]; then
      echo "ROOT_VIDEO_EXISTS_OK $dest" | tee -a "$LOG"
      continue
    fi
    abort "staged $dest already exists with sha=$(sha "$dest") != $exp" STAGE
  fi
  if ln "$STATIC_DIR/$name" "$dest" 2>/dev/null; then
    :
  else
    cp -a "$STATIC_DIR/$name" "$dest" || abort "install staged video $name failed" STAGE
  fi
  [[ "$(sha "$dest")" == "$exp" ]] || abort "staged video sha mismatch $name" STAGE
  echo "ROOT_VIDEO_OK $dest" | tee -a "$LOG"
done < <(media_rows)
echo "ROOT_VIDEO_OK $VIDEO_DIR" | tee -a "$LOG"

# Guards: homepage and /theramab/ identical to the live (pre-deploy) files
[[ "$(sha "$NEW_REL_DIR/index.html")" == "$LIVE_HOME_SHA" ]] || abort "staged homepage sha changed" STAGE
if [[ -n "$LIVE_TM_SHA" ]]; then
  [[ "$(sha "$NEW_REL_DIR/theramab/index.html")" == "$LIVE_TM_SHA" ]] || abort "staged /theramab/ sha changed" STAGE
  echo "GUARD_THERAMAB_OK $LIVE_TM_SHA" | tee -a "$LOG"
fi
echo "GUARD_HOME_OK $LIVE_HOME_SHA" | tee -a "$LOG"
grep -qF 'id="sec-demo"' "$HTML_DEST" || abort "staged therasik page missing #sec-demo" STAGE
grep -qF 'therasik_demo_zh_1080p.mp4' "$HTML_DEST" || abort "staged therasik page missing zh 1080p source" STAGE
grep -qF 'TheraSik SaaS 实际界面演示（约 4 分钟）' "$HTML_DEST" || abort "staged therasik page missing caption" STAGE
grep -qE 'preview-ribbon|此页为未上线预览|勿合并' "$HTML_DEST" && abort "preview text in staged therasik page" STAGE

mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
VHOST_BAK_FIXED="$BACKUP_BASE/inlightbio.cn.conf.bak.${LABEL}.$TS"
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-24 therasik_video_v1 deploy: web root -> $CURRENT_ROOT. Deletes nothing.
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
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_${LABEL}.$TS.sh"
echo "STAGE_OK" | tee -a "$LOG"

# ---------- vhost backup + sed-only root switch ----------
BACKUP_CONF="${VHOST_CONF}.bak.${LABEL}.$TS"
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
sed -i -E "s#^([[:space:]]*root[[:space:]]+)${CURRENT_ROOT};#\1${NEW_REL_DIR};#" "$VHOST_CONF"
NNEW=$(grep -cE "^[[:space:]]*root[[:space:]]+${NEW_REL_DIR};" "$VHOST_CONF" || true)
[[ "$NNEW" == "$NROOT_LINES" ]] || fail_restored "root switch failed (expected $NROOT_LINES root lines pointing at the new dir, got $NNEW)" ROOT_SWITCH
grep -qE "^[[:space:]]*root[[:space:]]+${CURRENT_ROOT};" "$VHOST_CONF" && fail_restored "old root still referenced after switch" ROOT_SWITCH
if grep -qE 'location[[:space:]]+\^~[[:space:]]+/\.well-known/acme-challenge/' "$BACKUP_CONF"; then
  if ! diff -q <(grep -E 'location[[:space:]]+\^~[[:space:]]+/\.well-known/acme-challenge/' "$BACKUP_CONF") \
               <(grep -E 'location[[:space:]]+\^~[[:space:]]+/\.well-known/acme-challenge/' "$VHOST_CONF") >/dev/null; then
    fail_restored "ACME location line changed" VHOST_LAYOUT
  fi
fi

echo "===== VHOST_DIFF (old vs new) =====" | tee -a "$LOG"
if diff -u "$BACKUP_CONF" "$VHOST_CONF" >"$TMPD/vhost.diff"; then
  fail_restored "vhost diff is empty after root switch" ROOT_SWITCH
fi
cat "$TMPD/vhost.diff" | tee -a "$LOG"

NOLD=$(wc -l < "$BACKUP_CONF" | tr -d "[:space:]")
NNOW=$(wc -l < "$VHOST_CONF" | tr -d "[:space:]")
[[ "$NOLD" == "$NNOW" ]] || fail_restored "vhost line count changed ($NOLD -> $NNOW); edit must only replace root paths" VHOST_LAYOUT
L_BEFORE=$(grep -nE '^[[:space:]]*listen[[:space:]]+443' "$BACKUP_CONF" | head -1 | cut -d: -f1)
L_AFTER=$(grep -nE '^[[:space:]]*listen[[:space:]]+443' "$VHOST_CONF" | head -1 | cut -d: -f1)
[[ -n "$L_BEFORE" && "$L_BEFORE" == "$L_AFTER" ]] || fail_restored "listen 443 line moved (was $L_BEFORE, now $L_AFTER)" VHOST_LAYOUT

NT=$(nginx -t 2>&1); NRC=$?
echo "$NT" | tee -a "$LOG"
[[ $NRC -eq 0 ]] || fail_restored "nginx -t failed" NGINX_TEST
echo "NGINX_T_OK" | tee -a "$LOG"
nginx -s reload >>"$LOG" 2>&1 || fail_restored "nginx reload failed" NGINX_RELOAD
echo "NGINX_RELOAD_OK" | tee -a "$LOG"

# ---------- live verify ----------
sleep 1

verify_curl() {
  # $1 path  $2 dest-body  $3 dest-hdr
  curl -sS -k --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
    "${curl_resolve[@]}" \
    -H "Accept-Encoding: identity" \
    -D "$3" -o "$2" -w '%{http_code}' \
    "$SITE_ORIGIN$1" || echo "000"
}

log_hdr() {
  echo "----- response headers ($1) -----" | tee -a "$LOG"
  head -n 25 "$2" | tr -d '\r' | tee -a "$LOG" || true
}

ok=0; C="000"; GOT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/" "$TMPD/home.html" "$TMPD/home.hdr")
  GOT=$(sha "$TMPD/home.html")
  echo "VERIFY_HOME_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$LIVE_HOME_SHA" | tee -a "$LOG"
  log_hdr "GET / try $try" "$TMPD/home.hdr"
  if [[ "$C" == "200" && "$GOT" == "$LIVE_HOME_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "homepage HTTP $C sha_got=${GOT:-empty} sha_expected=$LIVE_HOME_SHA" VERIFY_HOME
echo "VERIFY_HOME_OK HTTP=$C sha=$GOT" | tee -a "$LOG"

if [[ -n "$LIVE_TM_SHA" ]]; then
  ok=0; C="000"; GOT=""
  for try in 1 2 3 4 5; do
    C=$(verify_curl "/theramab/" "$TMPD/tm.html" "$TMPD/tm.hdr")
    GOT=$(sha "$TMPD/tm.html")
    echo "VERIFY_THERAMAB_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$LIVE_TM_SHA" | tee -a "$LOG"
    log_hdr "GET /theramab/ try $try" "$TMPD/tm.hdr"
    if [[ "$C" == "200" && "$GOT" == "$LIVE_TM_SHA" ]]; then ok=1; break; fi
    sleep 2
  done
  [[ "$ok" == "1" ]] || fail_restored "/theramab/ HTTP $C sha_got=${GOT:-empty} sha_expected=$LIVE_TM_SHA" VERIFY_THERAMAB
  echo "VERIFY_THERAMAB_OK HTTP=$C sha=$GOT" | tee -a "$LOG"
fi

ok=0; C="000"; GOT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/therasik/" "$TMPD/ts.html" "$TMPD/ts.hdr")
  GOT=$(sha "$TMPD/ts.html")
  echo "VERIFY_THERASIK_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$HTML_SHA" | tee -a "$LOG"
  log_hdr "GET /therasik/ try $try" "$TMPD/ts.hdr"
  if [[ "$C" == "200" && "$GOT" == "$HTML_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "/therasik/ HTTP $C sha_got=${GOT:-empty} sha_expected=$HTML_SHA" VERIFY_THERASIK
grep -qF 'id="sec-demo"' "$TMPD/ts.html" || fail_restored "live /therasik/ missing #sec-demo" VERIFY_THERASIK
echo "VERIFY_THERASIK_OK HTTP=$C sha=$GOT" | tee -a "$LOG"

verify_asset() {
  local path="$1" exp="$2" tag="$3"
  local body="$TMPD/asset.$tag" hdr="$TMPD/asset.$tag.hdr"
  local try C GOT ok=0
  for try in 1 2 3 4 5; do
    C=$(verify_curl "$path" "$body" "$hdr")
    GOT=$(sha "$body")
    echo "VERIFY_ASSET_TRY $tag $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$exp" | tee -a "$LOG"
    if [[ "$C" == "200" && "$GOT" == "$exp" ]]; then ok=1; break; fi
    sleep 2
  done
  [[ "$ok" == "1" ]] || return 1
  echo "VERIFY_ASSET_OK $path HTTP=200 sha=$exp" | tee -a "$LOG"
  return 0
}

verify_asset "/therasik/assets/video/therasik_demo_zh_poster.jpg" "$ZH_POSTER_SHA" zh_poster \
  || fail_restored "zh poster HTTP/sha failed" VERIFY_POSTER
verify_asset "/therasik/assets/video/therasik_demo_en_poster.jpg" "$EN_POSTER_SHA" en_poster \
  || fail_restored "en poster HTTP/sha failed" VERIFY_POSTER
verify_asset "/therasik/assets/video/therasik_demo_zh_1080p.mp4" "$ZH_1080_SHA" zh_1080 \
  || fail_restored "zh 1080p full sha failed" VERIFY_MP4
verify_asset "/therasik/assets/video/therasik_demo_zh_720p.mp4" "$ZH_720_SHA" zh_720 \
  || fail_restored "zh 720p full sha failed" VERIFY_MP4
verify_asset "/therasik/assets/video/therasik_demo_en_1080p.mp4" "$EN_1080_SHA" en_1080 \
  || fail_restored "en 1080p full sha failed" VERIFY_MP4
verify_asset "/therasik/assets/video/therasik_demo_en_720p.mp4" "$EN_720_SHA" en_720 \
  || fail_restored "en 720p full sha failed" VERIFY_MP4

verify_range() {
  local path="$1"
  local hdr="$TMPD/range.hdr" body="$TMPD/range.body"
  local code n
  code=$(curl -sS -k --retry 2 --connect-timeout 10 --max-time 60 "${curl_resolve[@]}" \
    -H "Accept-Encoding: identity" \
    -D "$hdr" -o "$body" -w '%{http_code}' -H "Range: bytes=0-100" "$SITE_ORIGIN$path" || echo "000")
  echo "VERIFY_RANGE_TRY $path HTTP=$code" | tee -a "$LOG"
  if [[ "$code" != "206" ]]; then
    echo "ERR: $path Range expected 206 got $code" | tee -a "$LOG"
    head -n 20 "$hdr" | tee -a "$LOG"
    return 1
  fi
  n=$(wc -c < "$body" | tr -d '[:space:]')
  [[ "$n" -eq 101 ]] || { echo "ERR: $path Range body $n bytes, expected 101" | tee -a "$LOG"; return 1; }
  echo "VERIFY_RANGE_OK $path HTTP 206 (101 bytes)" | tee -a "$LOG"
  return 0
}
verify_range "/therasik/assets/video/therasik_demo_zh_1080p.mp4" || fail_restored "zh 1080p Range/206 failed" VERIFY_RANGE
verify_range "/therasik/assets/video/therasik_demo_zh_720p.mp4"  || fail_restored "zh 720p Range/206 failed" VERIFY_RANGE
verify_range "/therasik/assets/video/therasik_demo_en_1080p.mp4" || fail_restored "en 1080p Range/206 failed" VERIFY_RANGE
verify_range "/therasik/assets/video/therasik_demo_en_720p.mp4"  || fail_restored "en 720p Range/206 failed" VERIFY_RANGE

FINISHED=1
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
