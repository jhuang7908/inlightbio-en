#!/usr/bin/env bash
# InLightBio CN deploy — TheraSik Chinese whitepaper v2 (2026-11-22).
# Adds therasik/assets/TheraSik_Whitepaper_2026_zh_v2.pdf (new file) and
# retargets the three /therasik/ "下载白皮书" links to it. Does not overwrite
# or delete TheraSik_Whitepaper_2026.pdf (old 6-page file stays on disk and
# at its old URL). Does not change the homepage, TheraMab, CSS, or any other
# path. Jing approved go-live ("快").
#
# Pattern: copy the live versioned root to a FRESH dir; overlay 2 sha-verified
# files; backup nginx vhost (including /home/admin); sed only the root lines;
# nginx -t; reload; verify. On post-switch failure, restore the vhost backup.
# Never delete old roots, backups, or caches. Idempotent if already at the
# new root with matching shas.
#
# Run as root on the Aliyun 轻量 instance (SWAS Workbench, admin, sudo -n).
set -uo pipefail

OVERLAY_TAR_SHA="${OVERLAY_TAR_SHA:-d52b35f7a087d7722da1f6c7561bbdd89abeed4d9bf1ba0b050ff568d033b183}"
OVERLAY_NFILES=2
# Live /therasik/ index before this deploy (feat / PR #144)
OLD_THERASIK_INDEX_SHA="${OLD_THERASIK_INDEX_SHA:-f50fd98c555317876ad31d638347ea2121e83dcbc96b128940b747376d2b9f9e}"
NEW_THERASIK_INDEX_SHA="${NEW_THERASIK_INDEX_SHA:-edf7d7634611f588f0d12fab780aae6af19f56c643034182b9e77ab4d687885d}"
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
EXPECTED_OLD_ROOT="${EXPECTED_OLD_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261122_3b35cfb_therasik_feat}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261122_therasik_wp_zh_v2}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261122_therasik_wp_zh_v2}"
ADMIN_BACKUP_DIR="${ADMIN_BACKUP_DIR:-/home/admin}"
CACHE_DIR="${CACHE_DIR:-/root/inlight_cache_therasik_wp_zh_v2}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
PUB_TAG="${PUB_TAG:-cn-deploy-2026-11-22-therasik-wp-zh-v2}"
PUB_REPO="${PUB_REPO:-jhuang7908/inlightbio-en}"
PIN_SHA="${PIN_SHA:-087a0da26b12f2f99e2f27765f03467d705cc992}"
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"; fi
curl_resolve=(); [[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")

TS=$(date '+%Y%m%d_%H%M%S')
LOG="${LOG:-/root/deploy_therasik_wp_zh_v2_${TS}.log}"
CURRENT_ROOT=""; BACKUP_CONF=""; WEB_TOUCHED=0
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
FINISHED=0
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE" | tee -a "$LOG"; FINISHED=1; exit 1; }
if ! { : >> "$LOG"; } 2>/dev/null; then LOG="/tmp/deploy_therasik_wp_zh_v2_${TS}.log"; : >> "$LOG"; fi
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

echo "START therasik_wp_zh_v2 $TS new_root=$NEW_REL_DIR" | tee -a "$LOG"
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

staged_ok() {
  [[ -d "$NEW_REL_DIR" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/index.html")" == "$HOME_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/site.css")" == "$SITE_CSS_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/theramab/index.html")" == "$THERAMAB_INDEX_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/$THERAMAB_PDF_REL")" == "$THERAMAB_PDF_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/therasik/index.html")" == "$NEW_THERASIK_INDEX_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/$THERASIK_PDF_NEW_REL")" == "$THERASIK_PDF_NEW_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/$THERASIK_PDF_OLD_REL")" == "$THERASIK_PDF_OLD_SHA" ]] || return 1
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
[[ ! -e "$NEW_REL_DIR" ]] || abort "new root $NEW_REL_DIR already exists; refusing to reuse/overwrite" NEWROOT_EXISTS
grep -qF "$NEW_REL_DIR" "$VHOST_CONF" && abort "vhost already references the new root" NEWROOT_EXISTS

asset_urls() {
  local file="$1"
  if [[ "$PIN_SHA" != "__PIN_SHA__" && -n "$PIN_SHA" ]]; then
    local m
    for m in cdn.jsdelivr.net fastly.jsdelivr.net gcore.jsdelivr.net testingcf.jsdelivr.net quantil.jsdelivr.net; do
      echo "https://${m}/gh/${PUB_REPO}@${PIN_SHA}/deploy/${file}"
    done
  fi
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
fetch_sha "$CACHE_DIR/overlay_therasik_wp_zh_v2.tar.gz" "$OVERLAY_TAR_SHA" "overlay_therasik_wp_zh_v2.tar.gz" \
  || abort "failed to download overlay tarball" DOWNLOAD
echo "DOWNLOAD_OK" | tee -a "$LOG"

# ---------- stage new root (copy only; never modify the live root) ----------
echo "COPY_START $CURRENT_ROOT -> $NEW_REL_DIR" | tee -a "$LOG"
cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then
  P=$(park "$NEW_REL_DIR/rollback.sh" "rollback.sh.inherited_from_$(basename "$CURRENT_ROOT").disabled") && chmod 600 "$P" && echo "INHERITED_ROLLBACK_PARKED $P" | tee -a "$LOG"
fi

mkdir -p "$TMPD/overlay"
tar -xzf "$CACHE_DIR/overlay_therasik_wp_zh_v2.tar.gz" -C "$TMPD/overlay" --no-same-owner || abort "overlay extract failed" EXTRACT
NFOUND=$(find "$TMPD/overlay" -type f | wc -l)
[[ "$NFOUND" -eq "$OVERLAY_NFILES" ]] || abort "overlay has $NFOUND files, expected $OVERLAY_NFILES" EXTRACT
[[ "$(sha "$TMPD/overlay/therasik/index.html")" == "$NEW_THERASIK_INDEX_SHA" ]] || abort "overlay therasik/index.html sha mismatch" EXTRACT
[[ "$(sha "$TMPD/overlay/$THERASIK_PDF_NEW_REL")" == "$THERASIK_PDF_NEW_SHA" ]] || abort "overlay new PDF sha mismatch" EXTRACT
# Refuse if extract would overwrite the old PDF path
[[ -e "$TMPD/overlay/$THERASIK_PDF_OLD_REL" ]] && abort "overlay unexpectedly contains the old PDF path" EXTRACT

# Install new PDF only if missing or already the expected sha (never overwrite a different file)
if [[ -e "$NEW_REL_DIR/$THERASIK_PDF_NEW_REL" ]]; then
  [[ "$(sha "$NEW_REL_DIR/$THERASIK_PDF_NEW_REL")" == "$THERASIK_PDF_NEW_SHA" ]] \
    || abort "new root already has $THERASIK_PDF_NEW_REL with unexpected sha; refusing to overwrite" STAGE
  echo "NEW_PDF_ALREADY_OK $NEW_REL_DIR/$THERASIK_PDF_NEW_REL" | tee -a "$LOG"
else
  mkdir -p "$(dirname "$NEW_REL_DIR/$THERASIK_PDF_NEW_REL")"
  cp -a "$TMPD/overlay/$THERASIK_PDF_NEW_REL" "$NEW_REL_DIR/$THERASIK_PDF_NEW_REL" || abort "copy new PDF failed" STAGE
fi
# Replace therasik/index.html only in the NEW root, and only if it is the known pre or post sha
LIVE_TS_SHA=$(sha "$NEW_REL_DIR/therasik/index.html")
if [[ "$LIVE_TS_SHA" == "$NEW_THERASIK_INDEX_SHA" ]]; then
  echo "THERASIK_INDEX_ALREADY_OK" | tee -a "$LOG"
elif [[ "$LIVE_TS_SHA" == "$OLD_THERASIK_INDEX_SHA" ]]; then
  cp -a "$TMPD/overlay/therasik/index.html" "$NEW_REL_DIR/therasik/index.html" || abort "copy therasik/index.html failed" STAGE
else
  abort "copied-root therasik/index.html sha=$LIVE_TS_SHA is not the expected pre-patch file; refusing to overwrite" STAGE
fi

# Ownership: match the copied root
OWN=$(stat -c '%U:%G' "$NEW_REL_DIR")
chown "$OWN" "$NEW_REL_DIR/therasik/index.html" "$NEW_REL_DIR/$THERASIK_PDF_NEW_REL" 2>/dev/null || true
chmod 644 "$NEW_REL_DIR/therasik/index.html" "$NEW_REL_DIR/$THERASIK_PDF_NEW_REL"

staged_ok || abort "staged root sha checks failed after overlay" STAGE
# Confirm the only intentional differences vs the copied live root
[[ "$(sha "$NEW_REL_DIR/index.html")" == "$(sha "$CURRENT_ROOT/index.html")" ]] || abort "homepage changed in staged root" STAGE
[[ "$(sha "$NEW_REL_DIR/theramab/index.html")" == "$(sha "$CURRENT_ROOT/theramab/index.html")" ]] || abort "theramab/index.html changed in staged root" STAGE
[[ "$(sha "$NEW_REL_DIR/$THERASIK_PDF_OLD_REL")" == "$THERASIK_PDF_OLD_SHA" ]] || abort "old TheraSik PDF changed or missing in staged root" STAGE
[[ "$(sha "$CURRENT_ROOT/$THERASIK_PDF_OLD_REL")" == "$THERASIK_PDF_OLD_SHA" ]] || abort "old TheraSik PDF on live root changed during staging" STAGE
grep -cF 'TheraSik_Whitepaper_2026_zh_v2.pdf' "$NEW_REL_DIR/therasik/index.html" | grep -qx 6 \
  || abort "new therasik/index.html does not contain 6 occurrences of the v2 filename (3 href + 3 download)" STAGE
grep -qE 'href="/therasik/assets/TheraSik_Whitepaper_2026.pdf"' "$NEW_REL_DIR/therasik/index.html" \
  && abort "new therasik/index.html still links the old PDF" STAGE
if [[ -s "$CURRENT_ROOT/assets/ev/px.js" ]]; then
  [[ "$(sha "$NEW_REL_DIR/assets/ev/px.js")" == "$(sha "$CURRENT_ROOT/assets/ev/px.js")" ]] || abort "px.js changed in staged root" STAGE
fi
if [[ -s "$CURRENT_ROOT/content/talent/jobs_public.json" ]]; then
  [[ "$(sha "$NEW_REL_DIR/content/talent/jobs_public.json")" == "$(sha "$CURRENT_ROOT/content/talent/jobs_public.json")" ]] || abort "jobs_public.json changed in staged root" STAGE
fi
echo "STAGE_FILES_OK" | tee -a "$LOG"

mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
VHOST_BAK_FIXED="$BACKUP_BASE/inlightbio.cn.conf.bak.therasik_wp_zh_v2.$TS"
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back TheraSik whitepaper zh v2: web root -> $CURRENT_ROOT. Deletes nothing.
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
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_therasik_wp_zh_v2.$TS.sh"
echo "STAGE_OK" | tee -a "$LOG"

# ---------- vhost backups (panel bak + /home/admin) then sed-only root switch ----------
BACKUP_CONF="${VHOST_CONF}.bak.therasik_wp_zh_v2.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
[[ ! -e "$VHOST_BAK_FIXED" ]] || abort "backup $VHOST_BAK_FIXED already exists" BACKUP
cp -a "$BACKUP_CONF" "$VHOST_BAK_FIXED" || abort "second vhost backup failed" BACKUP
if [[ -d "$ADMIN_BACKUP_DIR" ]]; then
  ADMIN_BAK="$ADMIN_BACKUP_DIR/inlightbio.cn.conf.bak.therasik_wp_zh_v2.$TS"
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
LINKS=$(grep -cF 'href="/therasik/assets/TheraSik_Whitepaper_2026_zh_v2.pdf"' "$TMPD/ts.html" || true)
[[ "$LINKS" == "3" ]] || fail_restored "live /therasik/ has $LINKS v2 PDF hrefs (expected 3)" VERIFY_THERASIK
grep -qE 'href="/therasik/assets/TheraSik_Whitepaper_2026.pdf"' "$TMPD/ts.html" \
  && fail_restored "live /therasik/ still links the old PDF" VERIFY_THERASIK
echo "VERIFY_THERASIK_OK HTTP=$C sha=$GOT hrefs=$LINKS" | tee -a "$LOG"

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
