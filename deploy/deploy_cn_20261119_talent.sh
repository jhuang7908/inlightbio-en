#!/usr/bin/env bash
set -uo pipefail
# InLightBio CN deploy - 2026-11-19 启光英才 / 启光资方 channels + CV / partner-contact API (v7).
#
# WEB: copies the live root to a NEW release dir, replaces index.html in the copy and
#      adds assets/talent/* and content/talent/* (add-only), switches the vhost root.
# API: copies /opt/inlight-newsletter/server_v6e_20261109 to a NEW dir server_v7_talent_20261119,
#      adds talent_api_v7.py (imports the unchanged v6e module), creates a 0700 data dir,
#      runs an offline smoke test on a spare port (temp DB, NL_OUTBOX -> .eml files, no SMTP),
#      then adds systemd drop-in 34-v7-talent.conf (ExecStart only) and restarts the service.
# NGINX: adds an exact `location = /api/talent/cv` (client_max_body_size 12m) in a NEW include
#      file placed next to the existing nginx_api_location.conf include.
# Never deletes or edits the old web root, server_v6e, old drop-ins, caches, 命令助手 records or
# hidden wx-src pages. Backups: vhost .bak, drop-in dir copy. rollback.sh restores web root,
# nginx and the v6e ExecStart (via an additional higher-numbered drop-in).
# Downloads: jsDelivr mirrors x 3 rounds, sha-verified resumable cache, no raw.githubusercontent.com.
# Pipe-safe. Env vars override defaults for a sandbox dry run only.
ASSET_PIN="${ASSET_PIN:-72520805063725c98f162bc621a03183e7237d91}"
MIRRORS="${MIRRORS:-cdn.jsdelivr.net fastly.jsdelivr.net gcore.jsdelivr.net testingcf.jsdelivr.net quantil.jsdelivr.net}"
URL_BASE_FMT="${URL_BASE_FMT:-https://%s/gh/jhuang7908/inlightbio-en@%s}"
CACHE_DIR="${CACHE_DIR:-/root/inlight_dl_cache_20261119_talent}"
LIVE_PAGE_SHA="ab4d220f634bdf543965e0b0f4b7831b08396fdb37fdfd0e8b9ca8aa76478a9d"
LIVE_WEEKLY_SHA="bf8b4e8029d913dbe758f1264b2388b424350c7620d0d6da29bbffe592405e4c"
NEW_PAGE_SHA="381aabcd6123bb8e3404f084f8d6e746d6b327e0cddd22c9370a5e630a15a1df"
VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
NGINX_SNIPPET="${NGINX_SNIPPET:-/www/server/panel/vhost/nginx/inlightbio_cn_talent_cv_20261119.conf}"
EXPECTED_OLD_ROOT="${EXPECTED_OLD_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261118_2e6815b_conf57}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261119_be38b3b_talent}"
UNIT="${UNIT:-inlight-newsletter-api.service}"
OPT_BASE="${OPT_BASE:-/opt/inlight-newsletter}"
OLD_API_DIR="$OPT_BASE/server_v6e_20261109"
NEW_API_DIR="$OPT_BASE/server_v7_talent_20261119"
TALENT_DATA="$OPT_BASE/talent_data_v7_20261119"
DROPIN_DIR="${DROPIN_DIR:-/etc/systemd/system/${UNIT}.d}"
API_LOCAL="${API_LOCAL:-http://127.0.0.1:8787}"
SMOKE_PORT="${SMOKE_PORT:-18787}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261119_talent}"
LOG="${LOG:-/var/log/inlightbio_cn_deploy_20261119_talent.log}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"; fi
curl_resolve=(); [[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")
# path sha256 (web files go into NEW_REL_DIR/<path>; server/* goes into NEW_API_DIR)
OVERLAY_FILES="
  assets/talent/inlight_channel_logo_green.webp f2480248ff4e4c0130196e559a34912fc6fc0ca3d3793834e34735e6d277f894
  assets/talent/talent_fund.css 7e8637adcaa83b6419fbc7fff48fb095108087a2063b9151688e1b8b401754a3
  assets/talent/talent_fund.js 8c41a15e51e3d9a045a9b5dc0f592f183650f3259e02cf01fde7d2da7661a446
  content/talent/fund_public.json 69827a4cb2fde5c1c6db0bdd20d4b69dcee18f432a7c40763293339380e259e7
  content/talent/jobs_public.json 1f7e1158d44299cf58f85ee57d3763fafd7da4a307bc43ee7c3a97af4020249b
  index.html 381aabcd6123bb8e3404f084f8d6e746d6b327e0cddd22c9370a5e630a15a1df
  server/talent_api_v7.py 34d2d83e2aeb87f1de563595136a77df25d785443d9cc7fcbc47b7249bd35da4
"
N_FILES=$(printf '%s\n' "$OVERLAY_FILES" | awk 'NF==2' | wc -l)
CURRENT_ROOT=""; BACKUP_CONF=""; DROPIN_BACKUP=""; API_SWITCHED=0; V6E_EXEC=""; PY=""
CACHED_OK=0; CACHED_SKIP=0; CACHED_GOT=0
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} API_DIR=$NEW_API_DIR VHOST_BACKUP=${BACKUP_CONF:-none} DROPIN_BACKUP=${DROPIN_BACKUP:-none} LOG=$LOG"; }
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE"; exit 1; }
abort_download() { echo "ERR: $1" | tee -a "$LOG"; echo "FAIL_DOWNLOAD_NOCHANGE NEW_ROOT=$NEW_REL_DIR LOG=$LOG CACHED=${CACHED_OK}/${N_FILES}" | tee -a "$LOG"; exit 1; }
if ! { : > "$LOG"; } 2>/dev/null; then LOG=/tmp/inlightbio_cn_deploy_20261119_talent.log; : > "$LOG"; fi
case "$ASSET_PIN$NEW_PAGE_SHA$OVERLAY_FILES" in *__ASSETS_COMMIT__*|*__NEW_PAGE_SHA__*|*__OVERLAY_FILES__*) abort "placeholders not finalized" PLACEHOLDER ;; esac
case "$NEW_REL_DIR" in *MERGED_SHA*) abort "NEW_REL_DIR placeholder not finalized" PLACEHOLDER ;; esac
TMPD=$(mktemp -d); SMOKE_PID=""
cleanup() { [[ -n "$SMOKE_PID" ]] && kill "$SMOKE_PID" 2>/dev/null; rm -rf "$TMPD"; }
trap cleanup EXIT
IFS=' ' read -r -a MIRROR_ARR <<< "$MIRRORS"
svc_prop() { systemctl show -p "$1" "$UNIT" 2>/dev/null | sed "s/^$1=//"; }
exec_argv() { svc_prop ExecStart | grep -o 'argv\[\]=[^;]*' | head -1 | sed 's/^argv\[\]=//; s/[[:space:]]*$//'; }

# ---------------- PRE (read-only) ----------------
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing" VHOST
CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ -n "$CURRENT_ROOT" && -d "$CURRENT_ROOT" ]] || abort "cannot find live root" LIVEROOT
[[ "$CURRENT_ROOT" == "$EXPECTED_OLD_ROOT" ]] || abort "live root is not the expected conf57 root ($CURRENT_ROOT)" LIVEROOT
[[ ! -e "$NEW_REL_DIR" ]] || abort "new release dir already exists" EXISTS
[[ "$(sha256sum "$CURRENT_ROOT/index.html" | awk '{print $1}')" == "$LIVE_PAGE_SHA" ]] || abort "live index.html drifted" DRIFT
[[ "$(sha256sum "$CURRENT_ROOT/content/weekly_deals.js" | awk '{print $1}')" == "$LIVE_WEEKLY_SHA" ]] || abort "live weekly_deals.js drifted" WEEKLY_DRIFT
[[ ! -e "$CURRENT_ROOT/assets/talent" && ! -e "$CURRENT_ROOT/content/talent" ]] || abort "live root already has talent assets" EXISTS
grep -q 'nginx_api_location.conf' "$VHOST_CONF" || abort "vhost has no nginx_api_location.conf include" API_INCLUDE
grep -q '/api/talent/cv' "$VHOST_CONF" && abort "vhost already mentions /api/talent/cv" NGINX_EXISTS
[[ ! -e "$NGINX_SNIPPET" ]] || abort "nginx snippet already exists: $NGINX_SNIPPET" NGINX_EXISTS
systemctl is-active --quiet "$UNIT" || abort "$UNIT not active" API_INACTIVE
V6E_EXEC=$(exec_argv)
case "$V6E_EXEC" in *"$OLD_API_DIR/whitepaper_api_v6.py"*) ;; *) abort "effective ExecStart is not v6e ($V6E_EXEC)" API_EXEC ;; esac
PY=$(echo "$V6E_EXEC" | awk '{print $1}')
[[ -x "$PY" ]] || abort "service python not executable ($PY)" API_PY
[[ -d "$DROPIN_DIR" && -f "$DROPIN_DIR/32-v6e.conf" ]] || abort "drop-in dir or 32-v6e.conf missing ($DROPIN_DIR)" API_DROPIN
LAST=$(ls -1 "$DROPIN_DIR" | grep '\.conf$' | LC_ALL=C sort | tail -1)
[[ "$LAST" == "32-v6e.conf" ]] || abort "a drop-in sorts after 32-v6e.conf ($LAST)" API_DROPIN
[[ -d "$OLD_API_DIR" && -f "$OLD_API_DIR/whitepaper_api_v6.py" ]] || abort "server_v6e dir missing" API_OLD
[[ ! -e "$NEW_API_DIR" && ! -e "$TALENT_DATA" ]] || abort "v7 server or data dir already exists" API_EXISTS
ENVLINE=$(svc_prop Environment)
WP_V3_ENTRY=$(echo "$ENVLINE" | tr ' ' '\n' | sed -n 's/^WP_V3_ENTRY=//p' | head -1)
[[ -n "$WP_V3_ENTRY" && -f "$WP_V3_ENTRY" ]] || abort "WP_V3_ENTRY not found in unit environment" API_ENV
SVC_USER=$(svc_prop User); SVC_GROUP=$(svc_prop Group)
[[ -z "$SVC_USER" ]] && SVC_USER=root
[[ -z "$SVC_GROUP" ]] && SVC_GROUP=$(id -gn "$SVC_USER" 2>/dev/null || echo root)
H=$(curl -s -o /dev/null -w '%{http_code}' "$API_LOCAL/api/whitepaper/download?token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" || true)
[[ "$H" == "404" ]] || abort "live v6e GET probe returned $H (expected 404)" API_PROBE
echo "PRE_OK PY=$PY USER=$SVC_USER" | tee -a "$LOG"

# ---------------- DOWNLOAD (cache only) ----------------
cache_hit() { [[ -f "$CACHE_DIR/$1" ]] && [[ "$(sha256sum "$CACHE_DIR/$1" | awk '{print $1}')" == "$2" ]]; }
fetch_one() {
  local rel="$1" exp="$2" dest="$CACHE_DIR/$1" part="$CACHE_DIR/$1.part" host url round
  mkdir -p "$(dirname "$dest")"
  if cache_hit "$rel" "$exp"; then echo "CACHED $rel" | tee -a "$LOG"; CACHED_SKIP=$((CACHED_SKIP+1)); CACHED_OK=$((CACHED_OK+1)); return 0; fi
  rm -f "$dest"
  for round in 1 2 3; do
    for host in "${MIRROR_ARR[@]}"; do
      url="$(printf "$URL_BASE_FMT" "$host" "$ASSET_PIN")/$rel"; rm -f "$part"
      if curl --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 180 -fsSL "$url" -o "$part"; then
        if [[ "$(sha256sum "$part" | awk '{print $1}')" == "$exp" ]]; then
          mv -f "$part" "$dest"; echo "GOT $rel mirror=$host" | tee -a "$LOG"; CACHED_GOT=$((CACHED_GOT+1)); CACHED_OK=$((CACHED_OK+1)); return 0
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
mkdir -p "$CACHE_DIR" || abort_download "cannot create cache dir"
while read -r rel exp; do [[ -z "${exp:-}" ]] && continue; fetch_one "$rel" "$exp" || abort_download "download failed: $rel"; done <<OV
${OVERLAY_FILES}
OV
[[ "$CACHED_OK" -eq "$N_FILES" ]] || abort_download "cache count $CACHED_OK/$N_FILES"
echo "DOWNLOAD_OK CACHED=${CACHED_SKIP}/${N_FILES} GOT=${CACHED_GOT}/${N_FILES}" | tee -a "$LOG"

# ---------------- STAGE (new dirs only; live untouched) ----------------
cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
OWNER=$(stat -c '%U:%G' "$CURRENT_ROOT/index.html")
while read -r rel exp; do
  [[ -z "${exp:-}" ]] && continue
  case "$rel" in server/*) continue ;; esac
  if [[ "$rel" != "index.html" && -e "$NEW_REL_DIR/$rel" ]]; then abort "refusing to overwrite $rel in the copied root" OVERWRITE; fi
  mkdir -p "$(dirname "$NEW_REL_DIR/$rel")"
  cp "$CACHE_DIR/$rel" "$NEW_REL_DIR/$rel" || abort "install $rel failed" INSTALL
  chmod 644 "$NEW_REL_DIR/$rel"
  [[ "$(sha256sum "$NEW_REL_DIR/$rel" | awk '{print $1}')" == "$exp" ]] || abort "staged $rel sha mismatch" STAGE
done <<OV
${OVERLAY_FILES}
OV
chmod 755 "$NEW_REL_DIR/assets/talent" "$NEW_REL_DIR/content/talent"
chown -R "$OWNER" "$NEW_REL_DIR/assets/talent" "$NEW_REL_DIR/content/talent" "$NEW_REL_DIR/index.html" 2>/dev/null || [[ "$ALLOW_NON_ROOT" == "1" ]] || abort "chown failed" CHOWN
I="$NEW_REL_DIR/index.html"
[[ "$(sha256sum "$I" | awk '{print $1}')" == "$NEW_PAGE_SHA" ]] || abort "staged index sha" STAGE
for pat in 'id="v-talent"' 'id="v-fund"' 'id="home-talent"' 'id="home-fund"' 'assets/talent/talent_fund.js' 'name="vc"' 'value="融资"' 'mailto:bd@inlightbio.com' 'id="newco-report-feature"' 'content/weekly_deals.js?v=20261118b' '2026世界生命科学大会'; do
  grep -qF "$pat" "$I" || abort "staged index missing: $pat" STAGE
done
grep -qE 'preview-ribbon|此页为未上线预览|工作地点为浙江杭州' "$I" && abort "preview text in staged index" STAGE
[[ "$(sha256sum "$NEW_REL_DIR/content/weekly_deals.js" | awk '{print $1}')" == "$LIVE_WEEKLY_SHA" ]] || abort "weekly_deals.js changed" STAGE

cp -a "$OLD_API_DIR" "$NEW_API_DIR" || abort "copy server_v6e failed" API_COPY
while read -r rel exp; do
  [[ -z "${exp:-}" ]] && continue
  case "$rel" in server/*) ;; *) continue ;; esac
  f="$NEW_API_DIR/${rel#server/}"
  [[ ! -e "$f" ]] || abort "refusing to overwrite $f" API_OVERWRITE
  cp "$CACHE_DIR/$rel" "$f" && chown --reference="$NEW_API_DIR/whitepaper_api_v6.py" "$f" 2>/dev/null; chmod --reference="$NEW_API_DIR/whitepaper_api_v6.py" "$f"
  [[ "$(sha256sum "$f" | awk '{print $1}')" == "$exp" ]] || abort "staged $f sha mismatch" API_STAGE
done <<OV
${OVERLAY_FILES}
OV
cmp -s "$OLD_API_DIR/whitepaper_api_v6.py" "$NEW_API_DIR/whitepaper_api_v6.py" || abort "copied v6e module differs" API_STAGE
if [[ "$ALLOW_NON_ROOT" == "1" ]]; then mkdir -m 700 "$TALENT_DATA" || abort "cannot create $TALENT_DATA" API_DATA
else install -d -m 700 -o "$SVC_USER" -g "$SVC_GROUP" "$TALENT_DATA" || abort "cannot create $TALENT_DATA" API_DATA; fi
CHK=$(cd /tmp && env WP_V3_ENTRY="$WP_V3_ENTRY" "$PY" "$NEW_API_DIR/talent_api_v7.py" --check 2>&1)
echo "$CHK" | grep -q 'V7_IMPORT_OK' || abort "v7 --check failed: $(echo "$CHK" | tail -1)" API_CHECK

# offline smoke on a spare port: temp DBs, mail written as .eml (NL_OUTBOX), no SMTP, live queue untouched
SM="$TMPD/smoke"; mkdir -p "$SM/outbox"
curl -s -o /dev/null "http://127.0.0.1:$SMOKE_PORT/" && abort "smoke port $SMOKE_PORT busy" API_SMOKE
(cd /tmp && exec env -i PATH=/usr/bin:/bin WP_V3_ENTRY="$WP_V3_ENTRY" NL_BIND=127.0.0.1 NL_PORT="$SMOKE_PORT" NL_DB="$SM/subs.db" \
  NL_OUTBOX="$SM/outbox" WP_DATA_DIR="$SM/wp" WP_PDF_PATH="$SM/none.pdf" TALENT_DATA_DIR="$SM/talent" \
  "$PY" "$NEW_API_DIR/talent_api_v7.py" >"$SM/out.log" 2>&1) &
SMOKE_PID=$!
for i in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$SMOKE_PORT/api/talent/health" && break; sleep 0.5; done
[[ "$(curl -s "http://127.0.0.1:$SMOKE_PORT/api/talent/health")" == *talent-v7* ]] || abort "smoke health failed: $(tail -3 "$SM/out.log")" API_SMOKE
printf '%%PDF-1.4\nsmoke\n%%%%EOF\n' > "$SM/s.pdf"
C=$(curl -s -o "$SM/r1" -w '%{http_code}' -H 'Origin: https://inlightbio.cn' -F name=smoke -F email=smoke@example.com -F target=ZJ-005 -F consent=1 -F elapsed_ms=5000 -F "cv=@$SM/s.pdf;filename=smoke.pdf;type=application/pdf" "http://127.0.0.1:$SMOKE_PORT/api/talent/cv")
[[ "$C" == "202" ]] || abort "smoke CV POST $C $(cat "$SM/r1")" API_SMOKE
C=$(curl -s -o "$SM/r2" -w '%{http_code}' -H 'Origin: https://inlightbio.cn' -H 'Content-Type: application/json' --data '{"kind":"investor","org":"smoke","contact":"smoke","email":"smoke@example.com","note":"smoke","consent":true,"elapsed_ms":5000}' "http://127.0.0.1:$SMOKE_PORT/api/partner-contact")
[[ "$C" == "202" ]] || abort "smoke partner POST $C" API_SMOKE
C=$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data '{}' "http://127.0.0.1:$SMOKE_PORT/api/partner-contact")
[[ "$C" == "403" ]] || abort "smoke no-Origin should be 403, got $C" API_SMOKE
for i in $(seq 1 40); do [[ $(ls "$SM/outbox" | wc -l) -ge 2 ]] && break; sleep 0.5; done
EML=$(grep -l 'smoke.pdf' "$SM"/outbox/*.eml 2>/dev/null | head -1)
[[ -n "$EML" ]] || abort "smoke: CV .eml not produced" API_SMOKE
grep -q '^Reply-To: smoke@example.com' "$EML" && grep -q '^To: contact@inlightbio.com' "$EML" && grep -qi 'Content-Disposition: attachment' "$EML" || abort "smoke: CV mail headers/attachment wrong" API_SMOKE
"$PY" -c 'import sys;d=open(sys.argv[1],"rb").read();sys.exit(1 if b"\r\r" in d else 0)' "$EML" || abort "smoke: malformed header line endings" API_SMOKE
kill "$SMOKE_PID" 2>/dev/null; wait "$SMOKE_PID" 2>/dev/null; SMOKE_PID=""
echo "API_SMOKE_OK" | tee -a "$LOG"

# rollback script (written before any live switch)
BACKUP_CONF="${VHOST_CONF}.bak.$(date '+%Y%m%d_%H%M%S')"
[[ -e "$BACKUP_CONF" ]] && BACKUP_CONF="${BACKUP_CONF}_b"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
DROPIN_BACKUP="$BACKUP_BASE/dropin_$(date '+%Y%m%d_%H%M%S')"
cp -a "$DROPIN_DIR" "$DROPIN_BACKUP" || abort "drop-in backup failed" BACKUP
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-19 talent deploy: vhost -> $CURRENT_ROOT (backup $BACKUP_CONF),
# service ExecStart -> v6e via an additional drop-in. Deletes nothing.
set -uo pipefail
cp -a "$BACKUP_CONF" "$VHOST_CONF" && nginx -t && nginx -s reload || { echo ROLLBACK_FAIL_NGINX; exit 1; }
RBF="$DROPIN_DIR/35-v7-rollback.conf"; [[ -e "\$RBF" ]] && RBF="$DROPIN_DIR/36-v7-rollback-\$(date +%Y%m%d%H%M%S).conf"
printf '[Service]\nExecStart=\nExecStart=%s\n' "$V6E_EXEC" > "\$RBF"
systemctl daemon-reload && systemctl restart "$UNIT"
for i in \$(seq 1 30); do systemctl is-active --quiet "$UNIT" && break; sleep 1; done
case "\$(systemctl show -p ExecStart "$UNIT")" in *server_v6e_20261109/whitepaper_api_v6.py*) ;; *) echo ROLLBACK_FAIL_API; exit 1;; esac
systemctl is-active --quiet "$UNIT" || { echo ROLLBACK_FAIL_API_INACTIVE; exit 1; }
echo "ROLLBACK_OK root -> $CURRENT_ROOT api -> v6e (drop-in \$RBF)"
RB
chmod 700 "$NEW_REL_DIR/rollback.sh"; cp -a "$NEW_REL_DIR/rollback.sh" "$NEW_API_DIR/rollback_v7.sh"
[[ "$ALLOW_NON_ROOT" == "1" ]] || chown root:root "$NEW_REL_DIR/rollback.sh" "$NEW_API_DIR/rollback_v7.sh"
chmod 700 "$NEW_API_DIR/rollback_v7.sh"
echo "STAGE_OK" | tee -a "$LOG"

api_restore() {
  local f="$DROPIN_DIR/35-v7-rollback.conf"
  [[ -e "$f" ]] && f="$DROPIN_DIR/36-v7-rollback-$(date +%Y%m%d%H%M%S).conf"
  printf '[Service]\nExecStart=\nExecStart=%s\n' "$V6E_EXEC" > "$f"
  systemctl daemon-reload >>"$LOG" 2>&1; systemctl restart "$UNIT" >>"$LOG" 2>&1
  echo "api restored to v6e via $f" | tee -a "$LOG"
}
fail_restored() {
  echo "ERR: $1" | tee -a "$LOG"
  if [[ "$3" == "web" ]]; then cp -a "$BACKUP_CONF" "$VHOST_CONF"; nginx -t >>"$LOG" 2>&1 && nginx -s reload >>"$LOG" 2>&1; fi
  [[ "$API_SWITCHED" == "1" ]] && api_restore
  summary "FAIL_$2_RESTORED"; exit 1
}

# ---------------- API switch ----------------
printf '[Service]\nExecStart=\nExecStart=%s %s\n' "$PY" "$NEW_API_DIR/talent_api_v7.py" > "$DROPIN_DIR/34-v7-talent.conf" || abort "cannot write drop-in" API_DROPIN
API_SWITCHED=1
systemctl daemon-reload >>"$LOG" 2>&1 || fail_restored "daemon-reload failed" API_RELOAD api
systemctl restart "$UNIT" >>"$LOG" 2>&1 || fail_restored "restart failed" API_RESTART api
ok=0; for i in $(seq 1 30); do [[ "$(curl -s "$API_LOCAL/api/talent/health")" == *talent-v7* ]] && { ok=1; break; }; sleep 1; done
[[ "$ok" == "1" ]] || fail_restored "v7 health failed" API_HEALTH api
case "$(svc_prop ExecStart)" in *"$NEW_API_DIR/talent_api_v7.py"*) ;; *) fail_restored "ExecStart not v7" API_EXEC api ;; esac
H=$(curl -s -o /dev/null -w '%{http_code}' "$API_LOCAL/api/whitepaper/download?token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" || true)
[[ "$H" == "404" ]] || fail_restored "whitepaper route after switch returned $H" API_WP api
echo "API_OK" | tee -a "$LOG"

# ---------------- NGINX + web root switch ----------------
cat > "$NGINX_SNIPPET" <<'NG'
# InLight 2026-11-19: CV upload only. Other /api/ paths keep the existing location and limits.
location = /api/talent/cv {
    client_max_body_size 12m;
    client_body_timeout 60s;
    proxy_pass http://127.0.0.1:8787;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
NG
N_API=$(grep -c 'nginx_api_location.conf' "$VHOST_CONF")
sed -i "/nginx_api_location\.conf/a\\    include $NGINX_SNIPPET;" "$VHOST_CONF"
[[ "$(grep -c "include $NGINX_SNIPPET;" "$VHOST_CONF")" == "$N_API" ]] || fail_restored "include insert failed" NGINX_INCLUDE web
sed -i -E "s#^([[:space:]]*root[[:space:]]+)${CURRENT_ROOT};#\\1${NEW_REL_DIR};#" "$VHOST_CONF"
[[ $(grep -cE "^[[:space:]]*root[[:space:]]+${NEW_REL_DIR};" "$VHOST_CONF") -ge 1 ]] || fail_restored "root switch failed" ROOT_SWITCH web
nginx -t >>"$LOG" 2>&1 || fail_restored "nginx -t failed (see $LOG)" NGINX_TEST web
nginx -s reload >>"$LOG" 2>&1 || fail_restored "nginx reload failed" NGINX_RELOAD web
sleep 1
VT="$TMPD/v.html"
curl -fsS --retry 5 --retry-delay 2 "${curl_resolve[@]}" "$SITE_ORIGIN/" -o "$VT" >>"$LOG" 2>&1 || fail_restored "homepage fetch failed" VERIFY_HOME web
[[ "$(sha256sum "$VT" | awk '{print $1}')" == "$NEW_PAGE_SHA" ]] || fail_restored "live index sha is not the new page" VERIFY_HOME_SHA web
while read -r rel exp; do
  [[ -z "${exp:-}" ]] && continue; case "$rel" in server/*|index.html) continue ;; esac
  C=$(curl -s --retry 3 -o "$TMPD/a" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/$rel" || true)
  [[ "$C" == "200" && "$(sha256sum "$TMPD/a" | awk '{print $1}')" == "$exp" ]] || fail_restored "$rel HTTP $C or sha mismatch" VERIFY_ASSET web
done <<OV
${OVERLAY_FILES}
OV
[[ "$(curl -s "${curl_resolve[@]}" "$SITE_ORIGIN/api/talent/health")" == *talent-v7* ]] || fail_restored "public talent health failed" VERIFY_API web
# 2MB honeypot upload through nginx: proves the 12m location reaches the app; honeypot => no mail, no record
head -c 2097152 /dev/zero > "$TMPD/big.pdf"
C=$(curl -s -o "$TMPD/r3" -w '%{http_code}' "${curl_resolve[@]}" -H "Origin: $SITE_ORIGIN" -F website=deploy-check -F name=x -F email=x@example.com -F consent=1 -F "cv=@$TMPD/big.pdf;filename=x.pdf" "$SITE_ORIGIN/api/talent/cv" || true)
[[ "$C" == "202" ]] && grep -q '"ok": *true' "$TMPD/r3" || fail_restored "2MB CV proxy check returned $C" VERIFY_CV_PROXY web
C=$(curl -s -o /dev/null -w '%{http_code}' "${curl_resolve[@]}" -H "Origin: $SITE_ORIGIN" -H 'Content-Type: application/json' --data '{}' "$SITE_ORIGIN/api/partner-contact" || true)
[[ "$C" == "400" ]] || fail_restored "partner-contact invalid probe returned $C" VERIFY_PARTNER web
echo "NGINX_OK" | tee -a "$LOG"
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
