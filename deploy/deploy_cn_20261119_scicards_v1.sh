#!/usr/bin/env bash
set -uo pipefail
# InLightBio CN deploy scicards_v1 - 2026-11-19 首页科研动态卡片配图：连接停滞时自动换备用来源，加载中显示浅色底
# (therasik-inlight fix/sci-cards-img-stall-20261119, commit 934e137, on live main 81b5960). Web-only, ONE file: index.html. Adds 1 CSS line + 18 JS lines; removes nothing.
# No API / systemd / nginx-location change. Does NOT re-download or touch assets/fonts/ or any image.
#  * stages a FRESH release root (aborts if it already exists; never reuses or overwrites a root);
#  * copies the current live root (inlightbio_cn_rel_20261119_81b5960_fonts_headline_v1) and overlays only index.html, sha256-verified
#    (live index must first match b30a8afb…; new sha af373c97…);
#  * checks the new index.html differs from the live one ONLY by added lines (19), containing the fix markers;
#  * pages/newco-report.html, content/talent/jobs_public.json, and assets/fonts/ must stay unchanged;
#  * writes rollback.sh into the new root (points back to inlightbio_cn_rel_20261119_81b5960_fonts_headline_v1);
#  * backs up the nginx vhost, switches `root`, `nginx -t`, reload, verifies homepage sha,
#    and checks newco / jobs / fonts.css shas unchanged;
#  * on any failure after the switch, restores the vhost backup and reloads.
# Deletes nothing. Old roots, backups and caches are kept. Env vars override defaults (sandbox dry run only).
# DO NOT RUN until Jing says 上.
export LANG=C.UTF-8 LC_ALL=C.UTF-8
ASSET_PIN="${ASSET_PIN:-9c875bea8aa042041e137d24be1c5dbdf9b4d186}"
MIRRORS="${MIRRORS:-cdn.jsdelivr.net fastly.jsdelivr.net gcore.jsdelivr.net testingcf.jsdelivr.net quantil.jsdelivr.net}"
URL_BASE_FMT="${URL_BASE_FMT:-https://%s/gh/jhuang7908/inlightbio-en@%s}"
CACHE_DIR="${CACHE_DIR:-/root/inlight_dl_cache_20261119_scicards_v1}"
HOME_SHA="${HOME_SHA:-b30a8afbdd6108adf6277f5b7f0f998a220d4638a005728ef7304a851e2a5b11}"   # live homepage before this deploy
NEW_PAGE_SHA="af373c97d52a879815fd18dcd11671522633b4d693d7380f0805650e09872d6e"   # homepage after (science-card image stall fix)
LIVE_PAGE_SHA="$HOME_SHA"
NEWCO_REL="pages/newco-report.html"
NEWCO_SHA="75ddb1c0c024e243f8d01f1a0c2325ceb7232b3de5f17424de69db46d1b9d4cf"   # NewCo report page: must stay unchanged
JOBS_SHA="1f7e1158d44299cf58f85ee57d3763fafd7da4a307bc43ee7c3a97af4020249b"   # 启光英才 jobs: must stay unchanged
FONTS_CSS_REL="assets/fonts/fonts.css"
VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
EXPECTED_OLD_ROOT="${EXPECTED_OLD_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261119_81b5960_fonts_headline_v1}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261119_934e137_scicards_v1}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261119_scicards_v1}"
LOG="${LOG:-/var/log/inlightbio_cn_deploy_20261119_scicards_v1.log}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"; fi
curl_resolve=(); [[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")
# path  new_sha  live_sha — index.html only; fonts already in the live root, not re-downloaded
OVERLAY_REPLACE="
  index.html af373c97d52a879815fd18dcd11671522633b4d693d7380f0805650e09872d6e b30a8afbdd6108adf6277f5b7f0f998a220d4638a005728ef7304a851e2a5b11
"
ov_rep() { printf '%s\n' "$OVERLAY_REPLACE" | awk 'NF==3'; }
N_FILES=$(ov_rep | wc -l)
TS=$(date '+%Y%m%d_%H%M%S')
CURRENT_ROOT=""; BACKUP_CONF=""; WEB_TOUCHED=0; CACHED_OK=0; CACHED_SKIP=0; CACHED_GOT=0
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE" | tee -a "$LOG"; exit 1; }
if ! { : > "$LOG"; } 2>/dev/null; then LOG=/tmp/inlightbio_cn_deploy_20261119_scicards_v1.log; : > "$LOG"; fi
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
IFS=' ' read -r -a MIRROR_ARR <<< "$MIRRORS"
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
park() { local src="$1" name="$2" dst; mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"; dst="$BACKUP_BASE/$name"; [[ -e "$dst" ]] && dst="$dst.$TS"; [[ -e "$dst" ]] && dst="$dst.$$"; mv "$src" "$dst" && echo "$dst"; }

echo "START scicards_v1 $TS pin=$ASSET_PIN files=$N_FILES (index.html only; fonts not re-downloaded)" | tee -a "$LOG"
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing" VHOST
[[ "$ASSET_PIN" != "__ASSET_PIN__" && -n "$ASSET_PIN" ]] || abort "ASSET_PIN is not set (pin the files on inlightbio-en first)" PIN
NT=$(nginx -t 2>&1); NRC=$?
if [[ $NRC -ne 0 ]]; then echo "$NT"; abort "nginx -t fails before any change" PRE_NGINX; fi
echo "PRE_NGINX_T_OK" | tee -a "$LOG"
CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ "$CURRENT_ROOT" == "$EXPECTED_OLD_ROOT" && -d "$CURRENT_ROOT" ]] || abort "live root is not the expected root $EXPECTED_OLD_ROOT ($CURRENT_ROOT)" LIVEROOT
NROOTS=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | awk '{print $2}' | tr -d ';' | sort -u | wc -l)
[[ "$NROOTS" == "1" ]] || abort "vhost has $NROOTS distinct root values; expected 1" LIVEROOT
while read -r rel new old; do [[ "$(sha "$CURRENT_ROOT/$rel")" == "$old" ]] || abort "live $rel drifted from the known version" DRIFT; done < <(ov_rep)
[[ "$(sha "$CURRENT_ROOT/index.html")" == "$HOME_SHA" ]] || abort "live homepage index.html is not the expected $HOME_SHA" DRIFT
[[ "$(sha "$CURRENT_ROOT/content/talent/jobs_public.json")" == "$JOBS_SHA" ]] || abort "live jobs_public.json drifted" DRIFT
[[ "$(sha "$CURRENT_ROOT/$NEWCO_REL")" == "$NEWCO_SHA" ]] || abort "live $NEWCO_REL drifted" DRIFT
[[ -s "$CURRENT_ROOT/$FONTS_CSS_REL" ]] || abort "live root lacks $FONTS_CSS_REL (fonts must already be present; this deploy does not download them)" ASSET_MISSING
FONTS_CSS_SHA=$(sha "$CURRENT_ROOT/$FONTS_CSS_REL")
[[ ! -e "$NEW_REL_DIR" ]] || abort "new root $NEW_REL_DIR already exists; refusing to reuse/overwrite (set NEW_REL_DIR to a new name)" NEWROOT_EXISTS
grep -qF "$NEW_REL_DIR" "$VHOST_CONF" && abort "vhost already references the new root" NEWROOT_EXISTS
echo "PRE_OK OLD_ROOT=$CURRENT_ROOT FONTS_CSS_SHA=$FONTS_CSS_SHA" | tee -a "$LOG"

fetch_one() {
  local rel="$1" exp="$2" dest="$CACHE_DIR/$1" part="$CACHE_DIR/$1.part" host url round
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
while read -r rel new old; do fetch_one "$rel" "$new" || abort "download failed: $rel" DOWNLOAD; done < <(ov_rep)
[[ "$CACHED_OK" -eq "$N_FILES" ]] || abort "cache count $CACHED_OK/$N_FILES" DOWNLOAD
echo "DOWNLOAD_OK CACHED=${CACHED_SKIP}/${N_FILES} GOT=${CACHED_GOT}/${N_FILES}" | tee -a "$LOG"

cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then P=$(park "$NEW_REL_DIR/rollback.sh" "rollback.sh.inherited_from_$(basename "$CURRENT_ROOT").disabled") && chmod 600 "$P" && echo "INHERITED_ROLLBACK_PARKED $P" | tee -a "$LOG"; fi
while read -r rel new old; do
  T="$NEW_REL_DIR/$rel"
  [[ "$(sha "$T")" == "$old" ]] || abort "copied $rel is not the known live version" STAGE
  cp "$CACHE_DIR/$rel" "$TMPD/f" && chown --reference="$CURRENT_ROOT/$rel" "$TMPD/f" 2>/dev/null; chmod --reference="$CURRENT_ROOT/$rel" "$TMPD/f"
  cat "$TMPD/f" > "$T" || abort "install $rel failed" INSTALL
  [[ "$(sha "$T")" == "$new" ]] || abort "staged $rel sha mismatch" STAGE
done < <(ov_rep)
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
for pat in '<h2>学术进展</h2>' 'id="latestgrid"' '卡住保护' 'data-ixok' '.pgrid .item .cover .coverimg:not([data-ixok])' 'assets/fonts/fonts.css' 'id="bp-home"' 'id="home-talent"' 'id="home-fund"'; do
  grep -qF "$pat" "$I" || abort "staged homepage missing: $pat" STAGE
done
python3 - "$CURRENT_ROOT/index.html" "$I" <<'PY' || abort "staged homepage differs from live by more than the 19 added lines" STAGE
import sys, difflib
a=open(sys.argv[1],encoding='utf-8').read().splitlines()
b=open(sys.argv[2],encoding='utf-8').read().splitlines()
d=[l for l in difflib.unified_diff(a,b,lineterm='',n=0) if not l.startswith(('---','+++','@@'))]
rem=[l for l in d if l.startswith('-')]; add=[l for l in d if l.startswith('+')]
sys.exit(0 if (not rem and len(add)==19) else 1)
PY
grep -qE 'preview-ribbon|此页为未上线预览|勿合并' "$I" && abort "preview text in staged homepage" STAGE
grep -qE 'fonts\.googleapis\.com|fonts\.gstatic\.com' "$I" && abort "staged homepage still references Google Fonts" STAGE
[[ "$(sha "$NEW_REL_DIR/index.html")" == "$NEW_PAGE_SHA" ]] || abort "staged homepage is not the new version" STAGE
[[ "$(sha "$NEW_REL_DIR/$NEWCO_REL")" == "$NEWCO_SHA" ]] || abort "$NEWCO_REL changed in staged root" STAGE
[[ "$(sha "$NEW_REL_DIR/content/talent/jobs_public.json")" == "$JOBS_SHA" ]] || abort "jobs_public.json changed in staged root" STAGE
[[ "$(sha "$NEW_REL_DIR/$FONTS_CSS_REL")" == "$FONTS_CSS_SHA" ]] || abort "fonts.css changed in staged root" STAGE
echo "STAGE_OK" | tee -a "$LOG"

mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
BACKUP_CONF="${VHOST_CONF}.bak.scicards_v1.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_BASE/inlightbio.cn.conf.bak.scicards_v1.$TS" || abort "second vhost backup failed" BACKUP
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-19 scicards_v1 deploy: web root -> $CURRENT_ROOT. Deletes nothing.
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
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_scicards_v1.sh"
echo "BACKUP_OK VHOST_BACKUP=$BACKUP_CONF ROLLBACK=$NEW_REL_DIR/rollback.sh" | tee -a "$LOG"

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
grep -qE 'fonts\.googleapis\.com|fonts\.gstatic\.com' "$VT" && fail_restored "live homepage still references Google Fonts" VERIFY_NO_GOOGLE_FONTS
grep -qF '卡住保护' "$VT" || fail_restored "live homepage lacks the fix marker" VERIFY_MARKER
echo "VERIFY_HOME_OK sha=$NEW_PAGE_SHA" | tee -a "$LOG"
C=$(curl -s --retry 3 -o "$TMPD/css" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/$FONTS_CSS_REL" || true)
[[ "$C" == "200" && "$(sha "$TMPD/css")" == "$FONTS_CSS_SHA" ]] || fail_restored "fonts.css HTTP $C or sha changed" VERIFY_FONTS
C=$(curl -s --retry 3 -o "$TMPD/n" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/$NEWCO_REL" || true)
[[ "$C" == "200" && "$(sha "$TMPD/n")" == "$NEWCO_SHA" ]] || fail_restored "$NEWCO_REL HTTP $C or sha mismatch" VERIFY_NEWCO
C=$(curl -s --retry 3 -o "$TMPD/j" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/content/talent/jobs_public.json" || true)
[[ "$C" == "200" && "$(sha "$TMPD/j")" == "$JOBS_SHA" ]] || fail_restored "jobs_public.json HTTP $C or sha changed" VERIFY_JOBS
echo "VERIFY_ASSETS_OK" | tee -a "$LOG"
H=$(curl -s -m 10 "${curl_resolve[@]}" "$SITE_ORIGIN/api/talent/health" || true)
[[ "$H" == *talent-v* ]] && echo "TALENT_API_OK (unchanged) $(printf %s "${H:0:60}" | tr -d '\r\n')" | tee -a "$LOG" || echo "WARN: talent API health did not answer (API untouched by this deploy): $(printf %s "${H:0:80}" | tr -d '\r\n')" | tee -a "$LOG"
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
