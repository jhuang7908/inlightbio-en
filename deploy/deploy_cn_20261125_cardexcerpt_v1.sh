#!/usr/bin/env bash
# InLightBio CN deploy cardexcerpt_v1 - 2026-11-25
# 学术进展卡片摘要改用正文（quick_look/sum），不再显示「AI 生成插图」图注。
# Web-only: overlays index.html in a FRESH release root. Does not change nginx
# locations, SSL, ACME, or APIs. The only nginx edit is the existing one-line
# `root` switch used by prior CN deploys. Deletes nothing.
# Approved by Jing: 上 (2026-11-25 3:03 PM America/New_York). PR #152 merged as 7b15b57.
set -euo pipefail

ASSET_PIN="${ASSET_PIN:-__ASSET_PIN__}"
MIRRORS="${MIRRORS:-cdn.jsdelivr.net fastly.jsdelivr.net gcore.jsdelivr.net testingcf.jsdelivr.net quantil.jsdelivr.net}"
URL_BASE_FMT="${URL_BASE_FMT:-https://%s/gh/jhuang7908/inlightbio-en@%s}"
CACHE_DIR="${CACHE_DIR:-/root/inlight_dl_cache_20261125_cardexcerpt_v1}"
# dest_rel  new_sha  live_sha  src_rel_in_pin_repo
HOME_SHA="${HOME_SHA:-28afb528408f7447d8af5b9a4b1725bd19c6b03eb8195d8c131502744d897f6d}"
NEW_PAGE_SHA="${NEW_PAGE_SHA:-3f615b9c6ba38a3104bfba4ca62044ceba84617113eb7d5a031a1e84473d7540}"
SRC_INDEX="deploy/overlays/cardexcerpt_v1/index.html"
THERASIK_SHA="${THERASIK_SHA:-2b03ddb6ea506eb183b65ff6f4a2908bbc3b495e58766b80c9d77e20cf8216c4}"
THERAMAB_SHA="${THERAMAB_SHA:-a0429e99a722adce23637e7574ff89eb79c1a355b2f6d9ad144c2daf120f1199}"
NEWCO_REL="pages/newco-report.html"
NEWCO_SHA="${NEWCO_SHA:-0a3bec06be8400a7e6bdcfe37dea94d531fd50a4f83762e612cfb4ef0e9f402e}"
JOBS_SHA="${JOBS_SHA:-1f7e1158d44299cf58f85ee57d3763fafd7da4a307bc43ee7c3a97af4020249b}"
FONTS_CSS_REL="assets/fonts/fonts.css"
FONTS_SHA="${FONTS_SHA:-8228afd6527ba54591634f39ca6bfe8cb867ad88882da7a95d5da917d85aec60}"
VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261125_7b15b57_cardexcerpt_v1}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261125_cardexcerpt_v1}"
LOG="${LOG:-/var/log/inlightbio_cn_deploy_20261125_cardexcerpt_v1.log}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"

curl_resolve=(); [[ -n "${CURL_RESOLVE:-}" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")
TS=$(date '+%Y%m%d_%H%M%S')
CURRENT_ROOT=""; BACKUP_CONF=""; WEB_TOUCHED=0; CACHED_OK=0; CACHED_SKIP=0; CACHED_GOT=0
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE" | tee -a "$LOG"; exit 1; }

TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
IFS=' ' read -r -a MIRROR_ARR <<< "$MIRRORS"
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
park() { local src="$1" name="$2" dst; mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"; dst="$BACKUP_BASE/$name"; [[ -e "$dst" ]] && dst="$dst.$TS"; [[ -e "$dst" ]] && dst="$dst.$$"; mv "$src" "$dst" && echo "$dst"; }

echo "START cardexcerpt_v1 $TS pin=$ASSET_PIN (overlay index.html only; nginx locations untouched)" | tee -a "$LOG"
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing" VHOST
[[ "$ASSET_PIN" != "__ASSET_PIN__" && -n "$ASSET_PIN" ]] || abort "ASSET_PIN is not set (pin the files on inlightbio-en first)" PIN
NT=$(nginx -t 2>&1); NRC=$?
if [[ $NRC -ne 0 ]]; then echo "$NT"; abort "nginx -t fails before any change" PRE_NGINX; fi
echo "PRE_NGINX_T_OK" | tee -a "$LOG"

CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ -n "$CURRENT_ROOT" && -d "$CURRENT_ROOT" ]] || abort "cannot detect live root from $VHOST_CONF ($CURRENT_ROOT)" LIVEROOT
NROOTS=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | awk '{print $2}' | tr -d ';' | sort -u | wc -l)
[[ "$NROOTS" == "1" ]] || abort "vhost has $NROOTS distinct root values; expected 1" LIVEROOT
[[ "$(sha "$CURRENT_ROOT/index.html")" == "$HOME_SHA" ]] || abort "live homepage index.html is not the expected $HOME_SHA" DRIFT
[[ "$(sha "$CURRENT_ROOT/therasik/index.html")" == "$THERASIK_SHA" ]] || abort "live therasik/index.html drifted" DRIFT
[[ "$(sha "$CURRENT_ROOT/theramab/index.html")" == "$THERAMAB_SHA" ]] || abort "live theramab/index.html drifted" DRIFT
[[ "$(sha "$CURRENT_ROOT/content/talent/jobs_public.json")" == "$JOBS_SHA" ]] || abort "live jobs_public.json drifted" DRIFT
[[ "$(sha "$CURRENT_ROOT/$NEWCO_REL")" == "$NEWCO_SHA" ]] || abort "live $NEWCO_REL drifted" DRIFT
[[ "$(sha "$CURRENT_ROOT/$FONTS_CSS_REL")" == "$FONTS_SHA" ]] || abort "live $FONTS_CSS_REL drifted" DRIFT
[[ ! -e "$NEW_REL_DIR" ]] || abort "new root $NEW_REL_DIR already exists; refusing to reuse/overwrite (set NEW_REL_DIR to a new name)" NEWROOT_EXISTS
grep -qF "$NEW_REL_DIR" "$VHOST_CONF" && abort "vhost already references the new root" NEWROOT_EXISTS
# Also keep a byte-for-byte backup of the file that will be replaced in the new root
mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
cp -a "$CURRENT_ROOT/index.html" "$BACKUP_BASE/index.html.live.$HOME_SHA.$TS" || abort "backup of live index.html failed" BACKUP
echo "PRE_OK OLD_ROOT=$CURRENT_ROOT LIVE_INDEX_BACKUP=$BACKUP_BASE/index.html.live.$HOME_SHA.$TS" | tee -a "$LOG"

fetch_one() {
  local rel="$1" exp="$2" dest="$CACHE_DIR/$3" part="$CACHE_DIR/$3.part" host url round
  mkdir -p "$(dirname "$dest")"
  if [[ "$(sha "$dest")" == "$exp" ]]; then echo "CACHED $rel" | tee -a "$LOG"; CACHED_SKIP=$((CACHED_SKIP+1)); CACHED_OK=$((CACHED_OK+1)); return 0; fi
  for round in 1 2 3; do
    for host in "${MIRROR_ARR[@]}"; do
      url="$(printf "$URL_BASE_FMT" "$host" "$ASSET_PIN")/$rel"; rm -f "$part"
      if curl --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 180 -fsSL "$url" -o "$part"; then
        if [[ "$(sha "$part")" == "$exp" ]]; then mv -f "$part" "$dest"; echo "GOT $rel mirror=$host" | tee -a "$LOG"; CACHED_GOT=$((CACHED_GOT+1)); CACHED_OK=$((CACHED_OK+1)); return 0; fi
        echo "WARN: sha256 mismatch from $host for $rel (round $round)" | tee -a "$LOG"
      else echo "WARN: curl failed $host for $rel (round $round)" | tee -a "$LOG"; fi
      rm -f "$part"
    done
    sleep 5
  done
  return 1
}

mkdir -p "$CACHE_DIR" || abort "cannot create cache dir" DOWNLOAD
fetch_one "$SRC_INDEX" "$NEW_PAGE_SHA" "index.html" || abort "download failed: $SRC_INDEX" DOWNLOAD
[[ "$CACHED_OK" -eq 1 ]] || abort "cache count $CACHED_OK/1" DOWNLOAD
echo "DOWNLOAD_OK CACHED=${CACHED_SKIP}/1 GOT=${CACHED_GOT}/1" | tee -a "$LOG"

cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then P=$(park "$NEW_REL_DIR/rollback.sh" "rollback.sh.inherited_from_$(basename "$CURRENT_ROOT").disabled") && chmod 600 "$P" && echo "INHERITED_ROLLBACK_PARKED $P" | tee -a "$LOG"; fi
T="$NEW_REL_DIR/index.html"
[[ "$(sha "$T")" == "$HOME_SHA" ]] || abort "copied index.html is not the known live version" STAGE
cp "$CACHE_DIR/index.html" "$TMPD/f" && chown --reference="$CURRENT_ROOT/index.html" "$TMPD/f" 2>/dev/null; chmod --reference="$CURRENT_ROOT/index.html" "$TMPD/f"
cat "$TMPD/f" > "$T" || abort "install index.html failed" INSTALL
[[ "$(sha "$T")" == "$NEW_PAGE_SHA" ]] || abort "staged index.html sha mismatch" STAGE

python3 - "$CURRENT_ROOT" "$NEW_REL_DIR" <<'PY' || abort "new root differs from live root beyond the overlay" STAGE_DIFF
import os, sys
old, new = sys.argv[1], sys.argv[2]

def walk(base):
    out=set()
    for root, dirs, files in os.walk(base):
        for fn in files:
            out.add(os.path.relpath(os.path.join(root, fn), base))
    return out

old_set, new_set = walk(old), walk(new)
unexpected=[]
for rel in sorted(new_set-old_set):
    if rel == 'rollback.sh':
        continue
    unexpected.append('extra '+rel)
for rel in sorted(old_set-new_set):
    if rel == 'rollback.sh':
        continue
    unexpected.append('missing '+rel)
if unexpected:
    sys.stderr.write('UNEXPECTED:\n'+'\n'.join(unexpected[:20])+'\n')
    sys.exit(1)
sys.exit(0)
PY

I="$NEW_REL_DIR/index.html"
for pat in '<h2>学术进展</h2>' 'id="latestgrid"' 'function cardExcerpt' 'function isAiCaption' 'const excerpt=cardExcerpt(a)' 'assets/fonts/fonts.css' 'assets/ev/px.js?v=20261120a' 'assets/talent/talent_fund.js?v=20261120a' 'id="home-talent"' 'id="home-fund"'; do
  grep -qF "$pat" "$I" || abort "staged homepage missing: $pat" STAGE
done
if grep -qF 'a.card_caption?`<p class="pv-ccap">' "$I"; then
  abort "staged homepage still uses card_caption as the card excerpt" STAGE
fi
grep -qE 'preview-ribbon|此页为未上线预览|勿合并' "$I" && abort "preview text in staged homepage" STAGE
grep -qE 'fonts\.googleapis\.com|fonts\.gstatic\.com' "$I" && abort "staged homepage still references Google Fonts" STAGE
[[ "$(sha "$NEW_REL_DIR/index.html")" == "$NEW_PAGE_SHA" ]] || abort "staged homepage is not the new version" STAGE
[[ "$(sha "$NEW_REL_DIR/therasik/index.html")" == "$THERASIK_SHA" ]] || abort "therasik/index.html changed in staged root" STAGE
[[ "$(sha "$NEW_REL_DIR/theramab/index.html")" == "$THERAMAB_SHA" ]] || abort "theramab/index.html changed in staged root" STAGE
[[ "$(sha "$NEW_REL_DIR/$NEWCO_REL")" == "$NEWCO_SHA" ]] || abort "$NEWCO_REL changed in staged root" STAGE
[[ "$(sha "$NEW_REL_DIR/content/talent/jobs_public.json")" == "$JOBS_SHA" ]] || abort "jobs_public.json changed in staged root" STAGE
[[ "$(sha "$NEW_REL_DIR/$FONTS_CSS_REL")" == "$FONTS_SHA" ]] || abort "fonts.css changed in staged root" STAGE
echo "STAGE_OK" | tee -a "$LOG"

BACKUP_CONF="${VHOST_CONF}.bak.cardexcerpt_v1.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_BASE/inlightbio.cn.conf.bak.cardexcerpt_v1.$TS" || abort "second vhost backup failed" BACKUP
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-25 cardexcerpt_v1 deploy: web root -> $CURRENT_ROOT. Deletes nothing.
set -uo pipefail
TS=\$(date +%Y%m%d_%H%M%S); V="$VHOST_CONF"
cp -a "\$V" "$BACKUP_BASE/inlightbio.cn.conf.before_rollback.\$TS"
sed -i -E "s#^([[:space:]]*root[[:space:]]+)$NEW_REL_DIR;#\\\\1$CURRENT_ROOT;#" "\$V"
grep -qE "^[[:space:]]*root[[:space:]]+$CURRENT_ROOT;" "\$V" && ! grep -qF "$NEW_REL_DIR" "\$V" || { cp -a "$BACKUP_CONF" "\$V"; echo "vhost restored from backup $BACKUP_CONF"; }
NT=\$(nginx -t 2>&1); RC=\$?; echo "\$NT"
if [[ \$RC -ne 0 ]]; then cp -a "$BACKUP_CONF" "\$V"; NT=\$(nginx -t 2>&1); RC=\$?; echo "retry after full backup restore:"; echo "\$NT"; fi
[[ \$RC -eq 0 ]] || { echo ROLLBACK_FAIL_NGINX_T; exit 1; }
nginx -s reload || { echo ROLLBACK_FAIL_NGINX_RELOAD; exit 1; }
echo "ROLLBACK_OK root -> $CURRENT_ROOT"
RB
chmod 700 "$NEW_REL_DIR/rollback.sh"
[[ "$ALLOW_NON_ROOT" == "1" ]] || chown root:root "$NEW_REL_DIR/rollback.sh"
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_cardexcerpt_v1.sh"
echo "BACKUP_OK VHOST_BACKUP=$BACKUP_CONF INDEX_BACKUP=$BACKUP_BASE/index.html.live.$HOME_SHA.$TS ROLLBACK=$NEW_REL_DIR/rollback.sh" | tee -a "$LOG"

web_restore() {
  cp -a "$BACKUP_CONF" "$VHOST_CONF"
  local nt rc; nt=$(nginx -t 2>&1); rc=$?; echo "$nt" | tee -a "$LOG"
  if [[ $rc -eq 0 ]]; then nginx -s reload >>"$LOG" 2>&1; echo "RESTORE_NGINX_T_OK" | tee -a "$LOG"; else echo "RESTORE_NGINX_T_FAIL" | tee -a "$LOG"; fi
}
fail_restored() { echo "ERR: $1" | tee -a "$LOG"; [[ "$WEB_TOUCHED" == "1" ]] && web_restore; summary "FAIL_$2_RESTORED" | tee -a "$LOG"; exit 1; }

WEB_TOUCHED=1
sed -i -E "s#^([[:space:]]*root[[:space:]]+)${CURRENT_ROOT};#\\1${NEW_REL_DIR};#" "$VHOST_CONF"
[[ $(grep -cE "^[[:space:]]*root[[:space:]]+${NEW_REL_DIR};" "$VHOST_CONF") -ge 1 ]] || fail_restored "root switch failed" ROOT_SWITCH
grep -qE "^[[:space:]]*root[[:space:]]+${CURRENT_ROOT};" "$VHOST_CONF" && fail_restored "old root still referenced after switch" ROOT_SWITCH
NT=$(nginx -t 2>&1); NRC=$?; echo "$NT" >>"$LOG"
[[ $NRC -eq 0 ]] || { echo "$NT"; fail_restored "nginx -t failed" NGINX_TEST; }
echo "NGINX_T_OK" | tee -a "$LOG"
nginx -s reload >>"$LOG" 2>&1 || fail_restored "nginx reload failed" NGINX_RELOAD
sleep 1

VT="$TMPD/v.html"; ok=0
for i in 1 2 3 4 5; do
  curl -fsS --retry 3 --retry-delay 2 "${curl_resolve[@]}" "$SITE_ORIGIN/" -o "$VT" >>"$LOG" 2>&1 && [[ "$(sha "$VT")" == "$NEW_PAGE_SHA" ]] && { ok=1; break; }; sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "live homepage sha is not the new page ($(sha "$VT"))" VERIFY_HOME_SHA
grep -qF 'function cardExcerpt' "$VT" || fail_restored "live homepage lacks cardExcerpt" VERIFY_MARKER
grep -qF 'a.card_caption?`<p class="pv-ccap">' "$VT" && fail_restored "live homepage still uses card_caption as the card excerpt" VERIFY_MARKER
grep -qE 'fonts\.googleapis\.com|fonts\.gstatic\.com' "$VT" && fail_restored "live homepage still references Google Fonts" VERIFY_NO_GOOGLE_FONTS
echo "VERIFY_HOME_OK sha=$NEW_PAGE_SHA" | tee -a "$LOG"

verify_canary() {
  local path="$1" exp="$2" tag="$3"
  local C; C=$(curl -s --retry 3 -o "$TMPD/c" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/$path" || true)
  [[ "$C" == "200" && "$(sha "$TMPD/c")" == "$exp" ]] || fail_restored "$path HTTP $C or sha changed" "$tag"
}
verify_canary "therasik/index.html" "$THERASIK_SHA" VERIFY_THERASIK
verify_canary "theramab/index.html" "$THERAMAB_SHA" VERIFY_THERAMAB
verify_canary "$NEWCO_REL" "$NEWCO_SHA" VERIFY_NEWCO
verify_canary "content/talent/jobs_public.json" "$JOBS_SHA" VERIFY_JOBS
verify_canary "$FONTS_CSS_REL" "$FONTS_SHA" VERIFY_FONTS
echo "VERIFY_CANARIES_OK" | tee -a "$LOG"
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
