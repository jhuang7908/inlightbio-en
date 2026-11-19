#!/usr/bin/env bash
set -uo pipefail
# InLightBio CN deploy multi v6 - 2026-11-19 目标职位多选（不跳转）+ talent API v8
# (therasik-inlight PR #131, commit a1aa381). Front end + API, v7 kept intact.
#  * stages a FRESH web root (aborts if it already exists; never reuses or overwrites a root);
#  * copies the current live root (…_70f4ecf_cardadd_v5) and overlays 3 changed files, each sha256-verified;
#  * copies live v7 API dir to a NEW /opt/inlight-newsletter/server_v8_talent_multi_20261119 (v7 untouched)
#    and overlays talent_api_v8.py + jobs_titles.json;
#  * writes rollback.sh (web -> cardadd_v5, API -> v7 via a new drop-in);
#  * backs up nginx vhost and drop-in dir; switches API then web; nginx -t; health talent-v8;
#  * on any failure after a switch, restores vhost and/or API to v7.
# Deletes nothing. Old roots, v7 API, backups and caches are kept. Env vars override defaults for a sandbox dry run only.
ASSET_PIN="${ASSET_PIN:-6c4db948acb3f09e9ef07da0e22c619dcfed43f6}"
MIRRORS="${MIRRORS:-cdn.jsdelivr.net fastly.jsdelivr.net gcore.jsdelivr.net testingcf.jsdelivr.net quantil.jsdelivr.net}"
URL_BASE_FMT="${URL_BASE_FMT:-https://%s/gh/jhuang7908/inlightbio-en@%s}"
CACHE_DIR="${CACHE_DIR:-/root/inlight_dl_cache_20261119_multi_v6}"
LIVE_PAGE_SHA="d8447cbc5873b3cb1bcf095ae4acc820b2602261272b04d2b8c0c44f72edfe5d"
NEW_PAGE_SHA="7d0f878d0c69731f97df70ee12248c0b1400316c1b042d78198f7c51b2a3104c"
JOBS_SHA="1f7e1158d44299cf58f85ee57d3763fafd7da4a307bc43ee7c3a97af4020249b"
VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
EXPECTED_OLD_ROOT="${EXPECTED_OLD_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261119_70f4ecf_cardadd_v5}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261119_a1aa381_multi_v6}"
UNIT="${UNIT:-inlight-newsletter-api.service}"
OPT_BASE="${OPT_BASE:-/opt/inlight-newsletter}"
OLD_API_DIR="$OPT_BASE/server_v7_talent_20261119"
NEW_API_DIR="$OPT_BASE/server_v8_talent_multi_20261119"
TALENT_DATA="$OPT_BASE/talent_data_v7_20261119"
DROPIN_DIR="${DROPIN_DIR:-/etc/systemd/system/${UNIT}.d}"
API_LOCAL="${API_LOCAL:-http://127.0.0.1:8787}"
SMOKE_PORT="${SMOKE_PORT:-18788}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261119_multi_v6}"
LOG="${LOG:-/var/log/inlightbio_cn_deploy_20261119_multi_v6.log}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"; fi
curl_resolve=(); [[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")
# path  new_sha  live_sha (web files only)
OVERLAY_FILES="
  index.html 7d0f878d0c69731f97df70ee12248c0b1400316c1b042d78198f7c51b2a3104c d8447cbc5873b3cb1bcf095ae4acc820b2602261272b04d2b8c0c44f72edfe5d
  assets/talent/talent_fund.css a965932539d0709f38516e11b23b688ea990f6ba968fbd70f28df641df772c1e 4b5c2aaa93c945f7b55ab89dd6c277e63b3240e1151bc697d6b265005ae82b54
  assets/talent/talent_fund.js 3999cbce4cdb2f4f7f4a6f953f1dd3cdf9abc3421e670e3431a0667c42102b2b c3d8375694028b3a61fd1ba3cfb67e56c2e3b59171380d5a03c279448314497d
"
API_FILES="
  server/talent_api_v8.py 25b41f113b608648c42663a5cf243125934e692a6ae6f3f527ecef2279f7eaae
  server/jobs_titles.json 0e2a0a6fb6f7a2e8bf75df93060d4dc901afbc79469a1c7e5a56740e43a65d60
"
ov() { printf '%s\n' "$OVERLAY_FILES" | awk 'NF==3'; }
ap() { printf '%s\n' "$API_FILES" | awk 'NF==2'; }
N_FILES=$(( $(ov | wc -l) + $(ap | wc -l) ))
TS=$(date '+%Y%m%d_%H%M%S')
CURRENT_ROOT=""; BACKUP_CONF=""; WEB_TOUCHED=0; API_SWITCHED=0; CACHED_OK=0; CACHED_SKIP=0; CACHED_GOT=0
V7_EXEC=""; PY=""; NEW_DROPIN=""; DROPIN_BACKUP=""; SMOKE_PID=""
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} API_DIR=$NEW_API_DIR DROPIN=${NEW_DROPIN:-none} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE" | tee -a "$LOG"; exit 1; }
if ! { : > "$LOG"; } 2>/dev/null; then LOG=/tmp/inlightbio_cn_deploy_20261119_multi_v6.log; : > "$LOG"; fi
TMPD=$(mktemp -d)
cleanup() { [[ -n "$SMOKE_PID" ]] && kill "$SMOKE_PID" 2>/dev/null; rm -rf "$TMPD"; }
trap cleanup EXIT
IFS=' ' read -r -a MIRROR_ARR <<< "$MIRRORS"
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
park() { local src="$1" name="$2" dst; mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"; dst="$BACKUP_BASE/$name"; [[ -e "$dst" ]] && dst="$dst.$TS"; [[ -e "$dst" ]] && dst="$dst.$$"; mv "$src" "$dst" && echo "$dst"; }
svc_prop() { systemctl show -p "$1" "$UNIT" 2>/dev/null | sed "s/^$1=//"; }
exec_argv() { svc_prop ExecStart | grep -o 'argv\[\]=[^;]*' | head -1 | sed 's/^argv\[\]=//; s/[[:space:]]*$//'; }
next_dropin() { local n; n=$(ls -1 "$DROPIN_DIR" | sed -n 's/^\([0-9][0-9]\)-.*\.conf$/\1/p' | sort -n | tail -1); printf '%02d-%s.conf' $((10#${n:-30} + 1)) "$1"; }

# ---------------- PRE (read-only) ----------------
echo "START multi_v6 $TS pin=$ASSET_PIN" | tee -a "$LOG"
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing" VHOST
NT=$(nginx -t 2>&1); NRC=$?
if [[ $NRC -ne 0 ]]; then echo "$NT"; abort "nginx -t fails before any change" PRE_NGINX; fi
echo "PRE_NGINX_T_OK" | tee -a "$LOG"
CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ "$CURRENT_ROOT" == "$EXPECTED_OLD_ROOT" && -d "$CURRENT_ROOT" ]] || abort "live root is not the expected 70f4ecf_cardadd_v5 root ($CURRENT_ROOT)" LIVEROOT
NROOTS=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | awk '{print $2}' | tr -d ';' | sort -u | wc -l)
[[ "$NROOTS" == "1" ]] || abort "vhost has $NROOTS distinct root values; expected 1" LIVEROOT
while read -r rel new old; do [[ "$(sha "$CURRENT_ROOT/$rel")" == "$old" ]] || abort "live $rel drifted from the known 70f4ecf_cardadd_v5 version" DRIFT; done < <(ov)
[[ "$(sha "$CURRENT_ROOT/index.html")" == "$LIVE_PAGE_SHA" ]] || abort "live homepage sha drifted" DRIFT
[[ "$(sha "$CURRENT_ROOT/content/talent/jobs_public.json")" == "$JOBS_SHA" ]] || abort "live jobs_public.json drifted" DRIFT
[[ ! -e "$NEW_REL_DIR" ]] || abort "new root $NEW_REL_DIR already exists; refusing to reuse/overwrite (set NEW_REL_DIR to a new name)" NEWROOT_EXISTS
grep -qF "$NEW_REL_DIR" "$VHOST_CONF" && abort "vhost already references the new root" NEWROOT_EXISTS
[[ ! -e "$NEW_API_DIR" ]] || abort "new API dir $NEW_API_DIR already exists; refusing to reuse/overwrite" NEWAPI_EXISTS
systemctl is-active --quiet "$UNIT" || abort "$UNIT not active" API_INACTIVE
V7_EXEC=$(exec_argv)
case "$V7_EXEC" in *"$OLD_API_DIR/talent_api_v7.py"*) ;; *) abort "effective ExecStart is not v7 ($V7_EXEC)" API_EXEC ;; esac
PY=$(echo "$V7_EXEC" | awk '{print $1}')
[[ -x "$PY" ]] || abort "service python not executable ($PY)" API_PY
[[ -d "$DROPIN_DIR" ]] || abort "drop-in dir missing" API_DROPIN
[[ -f "$OLD_API_DIR/talent_api_v7.py" && -f "$OLD_API_DIR/whitepaper_api_v6.py" ]] || abort "v7 API dir incomplete" API_OLD
NEW_DROPIN=$(next_dropin v8-talent-multi)
[[ ! -e "$DROPIN_DIR/$NEW_DROPIN" ]] || abort "drop-in $NEW_DROPIN exists" API_DROPIN
[[ "$(printf '%s\n' "$(ls -1 "$DROPIN_DIR" | grep '\.conf$')" "$NEW_DROPIN" | LC_ALL=C sort | tail -1)" == "$NEW_DROPIN" ]] || abort "$NEW_DROPIN would not sort last" API_DROPIN
WP_V3_ENTRY=$(svc_prop Environment | tr ' ' '\n' | sed -n 's/^WP_V3_ENTRY=//p' | head -1)
[[ -n "$WP_V3_ENTRY" && -f "$WP_V3_ENTRY" ]] || abort "WP_V3_ENTRY not found in unit environment" API_ENV
SVC_USER=$(svc_prop User); SVC_GROUP=$(svc_prop Group)
[[ -z "$SVC_USER" ]] && SVC_USER=root
[[ -z "$SVC_GROUP" ]] && SVC_GROUP=$(id -gn "$SVC_USER" 2>/dev/null || echo root)
H=$(curl -s "$API_LOCAL/api/talent/health" || true)
[[ "$H" == *talent-v7* ]] || abort "live talent health is not talent-v7 ($H)" API_HEALTH
echo "PRE_OK OLD_ROOT=$CURRENT_ROOT PY=$PY DROPIN=$NEW_DROPIN" | tee -a "$LOG"

# ---------------- DOWNLOAD ----------------
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
while read -r rel new old; do fetch_one "$rel" "$new" || abort "download failed: $rel" DOWNLOAD; done < <(ov)
while read -r rel exp; do fetch_one "$rel" "$exp" || abort "download failed: $rel" DOWNLOAD; done < <(ap)
[[ "$CACHED_OK" -eq "$N_FILES" ]] || abort "cache count $CACHED_OK/$N_FILES" DOWNLOAD
echo "DOWNLOAD_OK CACHED=${CACHED_SKIP}/${N_FILES} GOT=${CACHED_GOT}/${N_FILES}" | tee -a "$LOG"

# ---------------- STAGE web root ----------------
cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then P=$(park "$NEW_REL_DIR/rollback.sh" "rollback.sh.inherited_from_70f4ecf_cardadd_v5.disabled") && chmod 600 "$P" && echo "INHERITED_ROLLBACK_PARKED $P" | tee -a "$LOG"; fi
while read -r rel new old; do
  T="$NEW_REL_DIR/$rel"
  [[ "$(sha "$T")" == "$old" ]] || abort "copied $rel is not the known live version" STAGE
  cp "$CACHE_DIR/$rel" "$TMPD/f" && chown --reference="$CURRENT_ROOT/$rel" "$TMPD/f" 2>/dev/null; chmod --reference="$CURRENT_ROOT/$rel" "$TMPD/f"
  cat "$TMPD/f" > "$T" || abort "install $rel failed" INSTALL
  [[ "$(sha "$T")" == "$new" ]] || abort "staged $rel sha mismatch" STAGE
done < <(ov)
D=$(diff -rq "$CURRENT_ROOT" "$NEW_REL_DIR" 2>&1 | grep -vE "^Files $CURRENT_ROOT/(index\.html|assets/talent/talent_fund\\.(css|js)) and $NEW_REL_DIR/[^ ]+ differ$|^Only in $CURRENT_ROOT: rollback\.sh$")
[[ -z "$D" ]] || abort "new root differs from live root beyond the overlay: $(echo "$D" | head -3)" STAGE_DIFF
I="$NEW_REL_DIR/index.html"
for pat in 'id="v-talent"' 'id="v-fund"' 'id="home-talent"' 'id="home-fund"' 'assets/talent/talent_fund.js' '投资机构' '启光英才' 'fund-disclaimer' 'mailto:bd@inlightbio.com' 'id="newco-report-feature"' 'id="talent-cv-target"' 'IX.e(this)' 'inlightbio-en@"+PIN' 'bed52835e24b24d47e547350512bb40122fc0b8e' 'data-ixs=' 'talent_fund.css?v=20261119h' 'talent_fund.js?v=20261119h' 'class="talent-add"' 'class="cvt-chips"' 'class="cvt-pill"' 'id="talent-cv-target-input"' 'data-target="MT-000"' '根据简历智能/人工匹配' '仅登记简历' '去投递'; do
  grep -qF "$pat" "$I" || abort "staged index missing: $pat" STAGE
done
grep -qE 'preview-ribbon|此页为未上线预览|勿合并' "$I" && abort "preview text in staged index" STAGE
grep -qF 'class="sec-logo"' "$I" && abort "withdrawn column-logo markup found in staged index" STAGE
grep -qF 'class="cvt-btn"' "$I" && abort "removed dropdown markup still in staged index: cvt-btn" STAGE
grep -qF 'id="cvt-panel"' "$I" && abort "removed dropdown markup still in staged index: cvt-panel" STAGE
[[ "$(sha "$NEW_REL_DIR/content/talent/jobs_public.json")" == "$JOBS_SHA" ]] || abort "jobs_public.json changed in staged root" STAGE
echo "STAGE_WEB_OK" | tee -a "$LOG"

# ---------------- STAGE API dir (copy of v7, v7 left untouched) ----------------
cp -a "$OLD_API_DIR" "$NEW_API_DIR" || abort "copy v7 API dir failed" API_COPY
cmp -s "$OLD_API_DIR/whitepaper_api_v6.py" "$NEW_API_DIR/whitepaper_api_v6.py" || abort "v8 dir v6e module differs from v7" API_STAGE
cmp -s "$OLD_API_DIR/talent_api_v7.py" "$NEW_API_DIR/talent_api_v7.py" || abort "copied talent_api_v7.py drifted" API_STAGE
install -m 644 "$CACHE_DIR/server/talent_api_v8.py" "$NEW_API_DIR/talent_api_v8.py" || abort "install talent_api_v8.py failed" API_COPY
install -m 644 "$CACHE_DIR/server/jobs_titles.json" "$NEW_API_DIR/jobs_titles.json" || abort "install jobs_titles.json failed" API_COPY
chown --reference="$NEW_API_DIR/whitepaper_api_v6.py" "$NEW_API_DIR/talent_api_v8.py" "$NEW_API_DIR/jobs_titles.json" 2>/dev/null
[[ "$(sha "$NEW_API_DIR/talent_api_v8.py")" == "$(ap | awk '$1=="server/talent_api_v8.py"{print $2}')" ]] || abort "staged talent_api_v8.py sha mismatch" API_STAGE
[[ "$(sha "$NEW_API_DIR/jobs_titles.json")" == "$(ap | awk '$1=="server/jobs_titles.json"{print $2}')" ]] || abort "staged jobs_titles.json sha mismatch" API_STAGE
# v7 original still intact
[[ "$(sha "$OLD_API_DIR/talent_api_v7.py")" == "$(sha "$NEW_API_DIR/talent_api_v7.py")" ]] || abort "v7 file changed while staging v8" API_STAGE
if [[ -d "$TALENT_DATA" ]]; then
  [[ "$ALLOW_NON_ROOT" == "1" ]] || chown "$SVC_USER:$SVC_GROUP" "$TALENT_DATA" || abort "chown $TALENT_DATA failed" API_DATA
  chmod 700 "$TALENT_DATA"
fi
CHK=$(cd /tmp && env WP_V3_ENTRY="$WP_V3_ENTRY" TALENT_JOBS_JSON="$NEW_API_DIR/jobs_titles.json" "$PY" "$NEW_API_DIR/talent_api_v8.py" --check 2>&1)
echo "$CHK" | grep -q 'V8_IMPORT_OK' || abort "v8 --check failed: $(echo "$CHK" | tail -1)" API_CHECK
# offline smoke: spare port, temp DBs, mail as .eml, live queue untouched
SM="$TMPD/smoke"; mkdir -p "$SM/outbox"
curl -s -o /dev/null "http://127.0.0.1:$SMOKE_PORT/" && abort "smoke port $SMOKE_PORT busy" API_SMOKE
(cd /tmp && exec env -i PATH=/usr/bin:/bin WP_V3_ENTRY="$WP_V3_ENTRY" NL_BIND=127.0.0.1 NL_PORT="$SMOKE_PORT" NL_DB="$SM/subs.db" \
  NL_OUTBOX="$SM/outbox" WP_DATA_DIR="$SM/wp" WP_PDF_PATH="$SM/none.pdf" TALENT_DATA_DIR="$SM/talent" \
  TALENT_JOBS_JSON="$NEW_API_DIR/jobs_titles.json" \
  "$PY" "$NEW_API_DIR/talent_api_v8.py" >"$SM/out.log" 2>&1) &
SMOKE_PID=$!
for i in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$SMOKE_PORT/api/talent/health" && break; sleep 0.5; done
[[ "$(curl -s "http://127.0.0.1:$SMOKE_PORT/api/talent/health")" == *talent-v8* ]] || abort "smoke health failed: $(tail -3 "$SM/out.log")" API_SMOKE
printf '%%PDF-1.4\nsmoke\n%%%%EOF\n' > "$SM/s.pdf"
C=$(curl -s -o "$SM/r1" -w '%{http_code}' -H 'Origin: https://inlightbio.cn' -F name=smoke -F email=smoke@example.com -F target=SH-003,GD-001,MT-000 -F consent=1 -F elapsed_ms=5000 -F "cv=@$SM/s.pdf;filename=smoke.pdf;type=application/pdf" "http://127.0.0.1:$SMOKE_PORT/api/talent/cv")
[[ "$C" == "202" ]] || abort "smoke CV POST $C $(cat "$SM/r1")" API_SMOKE
for i in $(seq 1 40); do [[ $(ls "$SM/outbox" | wc -l) -ge 1 ]] && break; sleep 0.5; done
EML=$(grep -l 'smoke.pdf' "$SM"/outbox/*.eml 2>/dev/null | head -1)
[[ -n "$EML" ]] && grep -q '临床药理副总监' "$EML" && grep -q '根据简历智能/人工匹配' "$EML" && grep -q '药物研究情报' "$EML" || abort "smoke: CV mail missing job titles" API_SMOKE
kill "$SMOKE_PID" 2>/dev/null; wait "$SMOKE_PID" 2>/dev/null; SMOKE_PID=""
echo "API_SMOKE_OK" | tee -a "$LOG"

# ---------------- backups + rollback.sh (before any live switch) ----------------
mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
BACKUP_CONF="${VHOST_CONF}.bak.multi_v6.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_BASE/inlightbio.cn.conf.bak.multi_v6.$TS" || abort "second vhost backup failed" BACKUP
DROPIN_BACKUP="$BACKUP_BASE/dropin_multi_v6_$TS"
cp -a "$DROPIN_DIR" "$DROPIN_BACKUP" || abort "drop-in backup failed" BACKUP
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-19 multi v6: web root -> $CURRENT_ROOT, API -> v7. Deletes nothing.
set -uo pipefail
TS=\$(date +%Y%m%d_%H%M%S); V="$VHOST_CONF"; DI="$DROPIN_DIR"
cp -a "\$V" "$BACKUP_BASE/inlightbio.cn.conf.before_rollback.\$TS"
sed -i -E "s#^([[:space:]]*root[[:space:]]+)$NEW_REL_DIR;#\\\\1$CURRENT_ROOT;#" "\$V"
grep -qE "^[[:space:]]*root[[:space:]]+$CURRENT_ROOT;" "\$V" && ! grep -qF "$NEW_REL_DIR" "\$V" || { cp -a "$BACKUP_CONF" "\$V"; echo "vhost restored from backup $BACKUP_CONF"; }
NT=\$(nginx -t 2>&1); RC=\$?; echo "\$NT"
if [[ \$RC -ne 0 ]]; then cp -a "$BACKUP_CONF" "\$V"; NT=\$(nginx -t 2>&1); RC=\$?; echo "retry after full backup restore:"; echo "\$NT"; fi
[[ \$RC -eq 0 ]] || { echo ROLLBACK_FAIL_NGINX_T; exit 1; }
nginx -s reload || { echo ROLLBACK_FAIL_NGINX_RELOAD; exit 1; }
n=\$(ls -1 "\$DI" | sed -n 's/^\([0-9][0-9]\)-.*\.conf\$/\1/p' | sort -n | tail -1); RBF="\$DI/\$(printf '%02d' \$((10#\$n + 1)))-v8-multi-rollback.conf"
printf '[Service]\nExecStart=\nExecStart=%s\n' "$V7_EXEC" > "\$RBF"
systemctl daemon-reload && systemctl restart "$UNIT"
for i in \$(seq 1 30); do systemctl is-active --quiet "$UNIT" && curl -s "$API_LOCAL/api/talent/health" | grep -q talent-v7 && break; sleep 1; done
case "\$(systemctl show -p ExecStart "$UNIT")" in *server_v7_talent_20261119/talent_api_v7.py*) ;; *) echo ROLLBACK_FAIL_API; exit 1;; esac
systemctl is-active --quiet "$UNIT" || { echo ROLLBACK_FAIL_API_INACTIVE; exit 1; }
H=\$(curl -s "$API_LOCAL/api/talent/health" || true)
[[ "\$H" == *talent-v7* ]] || { echo "ROLLBACK_FAIL_API_HEALTH \$H"; exit 1; }
echo "ROLLBACK_OK root -> $CURRENT_ROOT api -> v7 (drop-in \$RBF) NGINX_T=ok"
RB
chmod 700 "$NEW_REL_DIR/rollback.sh"
[[ "$ALLOW_NON_ROOT" == "1" ]] || chown root:root "$NEW_REL_DIR/rollback.sh"
cp -a "$NEW_REL_DIR/rollback.sh" "$NEW_API_DIR/rollback_v8.sh"
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_multi_v6.sh"
echo "BACKUP_OK VHOST_BACKUP=$BACKUP_CONF ROLLBACK=$NEW_REL_DIR/rollback.sh DROPIN_BACKUP=$DROPIN_BACKUP" | tee -a "$LOG"
echo "STAGE_OK" | tee -a "$LOG"

api_restore() {
  local f="$DROPIN_DIR/$(next_dropin v8-multi-rollback)"
  printf '[Service]\nExecStart=\nExecStart=%s\n' "$V7_EXEC" > "$f"
  systemctl daemon-reload >>"$LOG" 2>&1; systemctl restart "$UNIT" >>"$LOG" 2>&1
  echo "API_RESTORED v7 via $f" | tee -a "$LOG"
}
web_restore() {
  cp -a "$BACKUP_CONF" "$VHOST_CONF"
  local nt rc; nt=$(nginx -t 2>&1); rc=$?; echo "$nt" | tee -a "$LOG"
  if [[ $rc -eq 0 ]]; then nginx -s reload >>"$LOG" 2>&1; echo "RESTORE_NGINX_T_OK" | tee -a "$LOG"; else echo "RESTORE_NGINX_T_FAIL" | tee -a "$LOG"; fi
}
fail_restored() {
  echo "ERR: $1" | tee -a "$LOG"
  [[ "$WEB_TOUCHED" == "1" ]] && web_restore
  [[ "$API_SWITCHED" == "1" ]] && api_restore
  summary "FAIL_$2_RESTORED" | tee -a "$LOG"
  exit 1
}

# ---------------- API switch ----------------
printf '[Service]\nExecStart=\nExecStart=%s %s\n' "$PY" "$NEW_API_DIR/talent_api_v8.py" > "$DROPIN_DIR/$NEW_DROPIN" || abort "cannot write drop-in" API_DROPIN
API_SWITCHED=1
systemctl daemon-reload >>"$LOG" 2>&1 || fail_restored "daemon-reload failed" API_RELOAD
systemctl restart "$UNIT" >>"$LOG" 2>&1 || fail_restored "restart failed" API_RESTART
ok=0; for i in $(seq 1 30); do [[ "$(curl -s "$API_LOCAL/api/talent/health")" == *talent-v8* ]] && { ok=1; break; }; sleep 1; done
[[ "$ok" == "1" ]] || fail_restored "v8 health failed" API_HEALTH
case "$(svc_prop ExecStart)" in *"$NEW_API_DIR/talent_api_v8.py"*) ;; *) fail_restored "ExecStart not v8" API_EXEC ;; esac
# v7 still on disk
[[ -f "$OLD_API_DIR/talent_api_v7.py" ]] || fail_restored "v7 API file missing after switch" API_V7
echo "API_OK" | tee -a "$LOG"

# ---------------- switch web root ----------------
WEB_TOUCHED=1
sed -i -E "s#^([[:space:]]*root[[:space:]]+)${CURRENT_ROOT};#\\1${NEW_REL_DIR};#" "$VHOST_CONF"
[[ $(grep -cE "^[[:space:]]*root[[:space:]]+${NEW_REL_DIR};" "$VHOST_CONF") -ge 1 ]] || fail_restored "root switch failed" ROOT_SWITCH
grep -qE "^[[:space:]]*root[[:space:]]+${CURRENT_ROOT};" "$VHOST_CONF" && fail_restored "old root still referenced after switch" ROOT_SWITCH
NT=$(nginx -t 2>&1); NRC=$?; echo "$NT" >>"$LOG"
[[ $NRC -eq 0 ]] || { echo "$NT"; fail_restored "nginx -t failed" NGINX_TEST; }
echo "NGINX_T_OK" | tee -a "$LOG"
nginx -s reload >>"$LOG" 2>&1 || fail_restored "nginx reload failed" NGINX_RELOAD
sleep 1

# ---------------- verify ----------------
VT="$TMPD/v.html"; ok=0
for i in 1 2 3 4 5; do
  curl -fsS --retry 3 --retry-delay 2 "${curl_resolve[@]}" "$SITE_ORIGIN/" -o "$VT" >>"$LOG" 2>&1 && [[ "$(sha "$VT")" == "$NEW_PAGE_SHA" ]] && { ok=1; break; }; sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "live homepage sha is not the new page ($(sha "$VT"))" VERIFY_HOME_SHA
echo "VERIFY_HOME_OK sha=$NEW_PAGE_SHA" | tee -a "$LOG"
while read -r rel new old; do
  [[ "$rel" == "index.html" ]] && continue
  C=$(curl -s --retry 3 -o "$TMPD/a" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/$rel" || true)
  [[ "$C" == "200" && "$(sha "$TMPD/a")" == "$new" ]] || fail_restored "$rel HTTP $C or sha mismatch" VERIFY_ASSET
done < <(ov)
C=$(curl -s --retry 3 -o "$TMPD/j" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/content/talent/jobs_public.json" || true)
[[ "$C" == "200" && "$(sha "$TMPD/j")" == "$JOBS_SHA" ]] || fail_restored "jobs_public.json HTTP $C or sha changed" VERIFY_JOBS
echo "VERIFY_ASSETS_OK" | tee -a "$LOG"
H=$(curl -s -m 10 "${curl_resolve[@]}" "$SITE_ORIGIN/api/talent/health" || true)
[[ "$H" == *talent-v8* ]] && echo "TALENT_API_OK service=talent-v8" | tee -a "$LOG" || fail_restored "public talent health is not talent-v8 ($H)" VERIFY_API
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
