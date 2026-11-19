#!/usr/bin/env bash
set -uo pipefail
# InLightBio CN deploy v2 - 2026-11-19 启光英才 / 启光资方 + talent API v7.
# v1 failed at `nginx -t`: its location-only include sat in /www/server/panel/vhost/nginx/, which the
# BT nginx.conf includes at http{} level. v2:
#  * puts the CV location include in $SNIPPET_DIR (outside the vhost glob) and inserts the include ONLY
#    inside the 443 server{} block, right after its existing nginx_api_location.conf include;
#  * requires `nginx -t` to pass before any change (moves the v1 stray file out of the vhost dir first);
#  * reuses v1 leftovers after sha verification (new web root, server_v7 dir, talent data dir);
#  * activates v7 with a NEW drop-in numbered after every existing one (no drop-in is deleted);
#  * on failure restores the vhost backup, moves its own include file away, prints `nginx -t`, restores API.
# Deletes nothing. Old roots, server_v6e, drop-ins, caches, 命令助手 records, wx-src pages are kept.
# Env vars override defaults for a sandbox dry run only.
ASSET_PIN="${ASSET_PIN:-72520805063725c98f162bc621a03183e7237d91}"
MIRRORS="${MIRRORS:-cdn.jsdelivr.net fastly.jsdelivr.net gcore.jsdelivr.net testingcf.jsdelivr.net quantil.jsdelivr.net}"
URL_BASE_FMT="${URL_BASE_FMT:-https://%s/gh/jhuang7908/inlightbio-en@%s}"
CACHE_DIR="${CACHE_DIR:-/root/inlight_dl_cache_20261119_talent}"
LIVE_PAGE_SHA="ab4d220f634bdf543965e0b0f4b7831b08396fdb37fdfd0e8b9ca8aa76478a9d"
LIVE_WEEKLY_SHA="bf8b4e8029d913dbe758f1264b2388b424350c7620d0d6da29bbffe592405e4c"
NEW_PAGE_SHA="381aabcd6123bb8e3404f084f8d6e746d6b327e0cddd22c9370a5e630a15a1df"
VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
VHOST_DIR="$(dirname "$VHOST_CONF")"
STRAY="$VHOST_DIR/inlightbio_cn_talent_cv_20261119.conf"
SNIPPET_DIR="${SNIPPET_DIR:-/opt/inlight-newsletter/deploy_v7_talent}"
NGINX_SNIPPET="$SNIPPET_DIR/nginx_talent_cv_location.conf"
TLS_PORT="${TLS_PORT:-443}"
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
LOG="${LOG:-/var/log/inlightbio_cn_deploy_20261119_talent_v2.log}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"; fi
curl_resolve=(); [[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")
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
TS=$(date '+%Y%m%d_%H%M%S')
CURRENT_ROOT=""; BACKUP_CONF=""; DROPIN_BACKUP=""; API_SWITCHED=0; WEB_TOUCHED=0; V6E_EXEC=""; PY=""; NEW_DROPIN=""
CACHED_OK=0; CACHED_SKIP=0; CACHED_GOT=0; REUSED=""
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} API_DIR=$NEW_API_DIR DROPIN=${NEW_DROPIN:-none} VHOST_BACKUP=${BACKUP_CONF:-none} REUSED=${REUSED:-none} LOG=$LOG"; }
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE"; exit 1; }
abort_download() { echo "ERR: $1" | tee -a "$LOG"; echo "FAIL_DOWNLOAD_NOCHANGE LOG=$LOG CACHED=${CACHED_OK}/${N_FILES}" | tee -a "$LOG"; exit 1; }
if ! { : > "$LOG"; } 2>/dev/null; then LOG=/tmp/inlightbio_cn_deploy_20261119_talent_v2.log; : > "$LOG"; fi
TMPD=$(mktemp -d); SMOKE_PID=""
cleanup() { [[ -n "$SMOKE_PID" ]] && kill "$SMOKE_PID" 2>/dev/null; rm -rf "$TMPD"; }
trap cleanup EXIT
IFS=' ' read -r -a MIRROR_ARR <<< "$MIRRORS"
svc_prop() { systemctl show -p "$1" "$UNIT" 2>/dev/null | sed "s/^$1=//"; }
exec_argv() { svc_prop ExecStart | grep -o 'argv\[\]=[^;]*' | head -1 | sed 's/^argv\[\]=//; s/[[:space:]]*$//'; }
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
# next drop-in prefix: one higher than the highest NN- prefix present (so it sorts last)
next_dropin() { local n; n=$(ls -1 "$DROPIN_DIR" | sed -n 's/^\([0-9][0-9]\)-.*\.conf$/\1/p' | sort -n | tail -1); printf '%02d-%s.conf' $((10#${n:-30} + 1)) "$1"; }
park() { # move a file into BACKUP_BASE (never delete); echo the destination
  local src="$1" name="$2" dst; mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
  dst="$BACKUP_BASE/$name"; [[ -e "$dst" ]] && dst="$dst.$TS"; [[ -e "$dst" ]] && dst="$dst.$$"
  mv "$src" "$dst" && echo "$dst"
}
# line number of the nginx_api_location.conf include that sits directly inside the server{} listening on TLS_PORT
target_line() {
  awk -v P="$TLS_PORT" '
    { l=$0; sub(/#.*/,"",l) }
    depth==1 && l ~ /(^|[ \t])listen[ \t]/ { n=split(l,t,/[ \t;]+/); for(i=1;i<=n;i++) if (t[i]==P || t[i] ~ (":" P "$")) tls=1 }
    depth==1 && l ~ /nginx_api_location\.conf/ { api=NR }
    { o=gsub(/\{/,"{",l); c=gsub(/\}/,"}",l); if (depth==0 && o>0) { tls=0; api=0 } depth+=o-c
      if (depth==0 && c>0) { if (tls && api) { print api; found++ } tls=0; api=0 } }
  ' "$1"
}

# ---------------- PRE ----------------
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing" VHOST
if [[ -e "$STRAY" ]]; then
  P=$(park "$STRAY" "inlightbio_cn_talent_cv_20261119.conf.disabled") || abort "cannot move stray $STRAY" PRE_STRAY
  echo "STRAY_MOVED $STRAY -> $P" | tee -a "$LOG"
fi
NT=$(nginx -t 2>&1); NRC=$?
if [[ $NRC -ne 0 ]]; then echo "$NT"; abort "nginx -t fails before any change" PRE_NGINX; fi
echo "PRE_NGINX_T_OK" | tee -a "$LOG"
CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ "$CURRENT_ROOT" == "$EXPECTED_OLD_ROOT" && -d "$CURRENT_ROOT" ]] || abort "live root is not the expected conf57 root ($CURRENT_ROOT)" LIVEROOT
[[ "$(sha "$CURRENT_ROOT/index.html")" == "$LIVE_PAGE_SHA" ]] || abort "live index.html drifted" DRIFT
[[ "$(sha "$CURRENT_ROOT/content/weekly_deals.js")" == "$LIVE_WEEKLY_SHA" ]] || abort "live weekly_deals.js drifted" WEEKLY_DRIFT
grep -qE 'talent_cv|/api/talent' "$VHOST_CONF" && abort "vhost already references the talent CV include" NGINX_EXISTS
TL=$(target_line "$VHOST_CONF")
[[ $(echo "$TL" | grep -c '[0-9]') -eq 1 ]] || abort "need exactly one nginx_api_location.conf include inside a server{} listening on $TLS_PORT (found: ${TL:-none})" NGINX_TARGET
SNIP_BODY='# InLight 2026-11-19: CV upload only (included inside the 443 server{} of inlightbio.cn). Other /api/ paths keep the existing location.
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
}'
case "$SNIPPET_DIR" in "$VHOST_DIR"|"$VHOST_DIR"/*) abort "snippet dir must be outside the vhost dir" NGINX_SNIPPET ;; esac
if [[ -e "$NGINX_SNIPPET" ]]; then
  [[ "$(cat "$NGINX_SNIPPET")" == "$SNIP_BODY" ]] || abort "existing $NGINX_SNIPPET has unexpected content" NGINX_SNIPPET
fi
systemctl is-active --quiet "$UNIT" || abort "$UNIT not active" API_INACTIVE
V6E_EXEC=$(exec_argv)
case "$V6E_EXEC" in *"$OLD_API_DIR/whitepaper_api_v6.py"*) ;; *) abort "effective ExecStart is not v6e ($V6E_EXEC)" API_EXEC ;; esac
PY=$(echo "$V6E_EXEC" | awk '{print $1}')
[[ -x "$PY" ]] || abort "service python not executable ($PY)" API_PY
[[ -d "$DROPIN_DIR" && -f "$DROPIN_DIR/32-v6e.conf" ]] || abort "drop-in dir or 32-v6e.conf missing" API_DROPIN
NEW_DROPIN=$(next_dropin v7-talent-r2)
[[ ! -e "$DROPIN_DIR/$NEW_DROPIN" ]] || abort "drop-in $NEW_DROPIN exists" API_DROPIN
[[ "$(printf '%s\n' "$(ls -1 "$DROPIN_DIR" | grep '\.conf$')" "$NEW_DROPIN" | LC_ALL=C sort | tail -1)" == "$NEW_DROPIN" ]] || abort "$NEW_DROPIN would not sort last" API_DROPIN
[[ -f "$OLD_API_DIR/whitepaper_api_v6.py" ]] || abort "server_v6e dir missing" API_OLD
WP_V3_ENTRY=$(svc_prop Environment | tr ' ' '\n' | sed -n 's/^WP_V3_ENTRY=//p' | head -1)
[[ -n "$WP_V3_ENTRY" && -f "$WP_V3_ENTRY" ]] || abort "WP_V3_ENTRY not found in unit environment" API_ENV
SVC_USER=$(svc_prop User); SVC_GROUP=$(svc_prop Group)
[[ -z "$SVC_USER" ]] && SVC_USER=root
[[ -z "$SVC_GROUP" ]] && SVC_GROUP=$(id -gn "$SVC_USER" 2>/dev/null || echo root)
H=$(curl -s -o /dev/null -w '%{http_code}' "$API_LOCAL/api/whitepaper/download?token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" || true)
[[ "$H" == "404" ]] || abort "live v6e GET probe returned $H (expected 404)" API_PROBE
echo "PRE_OK PY=$PY USER=$SVC_USER DROPIN=$NEW_DROPIN TARGET_LINE=$TL" | tee -a "$LOG"

# ---------------- DOWNLOAD (cache) ----------------
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
  done
  return 1
}
mkdir -p "$CACHE_DIR" || abort_download "cannot create cache dir"
while read -r rel exp; do [[ -z "${exp:-}" ]] && continue; fetch_one "$rel" "$exp" || abort_download "download failed: $rel"; done <<OV
${OVERLAY_FILES}
OV
[[ "$CACHED_OK" -eq "$N_FILES" ]] || abort_download "cache count $CACHED_OK/$N_FILES"
echo "DOWNLOAD_OK CACHED=${CACHED_SKIP}/${N_FILES} GOT=${CACHED_GOT}/${N_FILES}" | tee -a "$LOG"

# ---------------- STAGE web root (reuse v1 copy if it verifies) ----------------
web_rel() { printf '%s\n' "$OVERLAY_FILES" | awk 'NF==2 && $1 !~ /^server\//'; }
if [[ -d "$NEW_REL_DIR" ]]; then
  while read -r rel exp; do [[ "$(sha "$NEW_REL_DIR/$rel")" == "$exp" ]] || abort "existing $NEW_REL_DIR/$rel sha mismatch; not reusing" REUSE_ROOT; done < <(web_rel)
  D=$(diff -rq "$CURRENT_ROOT" "$NEW_REL_DIR" 2>&1 | grep -vE "^Only in $NEW_REL_DIR(/assets|/content)?: (talent|rollback[^ ]*)$|^Files $CURRENT_ROOT/index.html and $NEW_REL_DIR/index.html differ$")
  [[ -z "$D" ]] || abort "existing new root differs from live root beyond the overlay: $(echo "$D" | head -3)" REUSE_ROOT
  REUSED="root"
else
  cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
  while read -r rel exp; do
    [[ "$rel" != "index.html" && -e "$NEW_REL_DIR/$rel" ]] && abort "refusing to overwrite $rel in the copied root" OVERWRITE
    mkdir -p "$(dirname "$NEW_REL_DIR/$rel")"; cp "$CACHE_DIR/$rel" "$NEW_REL_DIR/$rel" || abort "install $rel failed" INSTALL
    chmod 644 "$NEW_REL_DIR/$rel"; [[ "$(sha "$NEW_REL_DIR/$rel")" == "$exp" ]] || abort "staged $rel sha mismatch" STAGE
  done < <(web_rel)
  chmod 755 "$NEW_REL_DIR/assets/talent" "$NEW_REL_DIR/content/talent"
  OWNER=$(stat -c '%U:%G' "$CURRENT_ROOT/index.html")
  chown -R "$OWNER" "$NEW_REL_DIR/assets/talent" "$NEW_REL_DIR/content/talent" "$NEW_REL_DIR/index.html" 2>/dev/null || [[ "$ALLOW_NON_ROOT" == "1" ]] || abort "chown failed" CHOWN
fi
I="$NEW_REL_DIR/index.html"
for pat in 'id="v-talent"' 'id="v-fund"' 'id="home-talent"' 'assets/talent/talent_fund.js' 'name="vc"' 'value="融资"' 'mailto:bd@inlightbio.com' 'id="newco-report-feature"' '2026世界生命科学大会'; do
  grep -qF "$pat" "$I" || abort "staged index missing: $pat" STAGE
done
grep -qE 'preview-ribbon|此页为未上线预览|工作地点为浙江杭州' "$I" && abort "preview text in staged index" STAGE

# ---------------- STAGE API dir (reuse v1 copy if it verifies) ----------------
API_SHA=$(printf '%s\n' "$OVERLAY_FILES" | awk '$1=="server/talent_api_v7.py"{print $2}')
if [[ -d "$NEW_API_DIR" ]]; then
  [[ "$(sha "$NEW_API_DIR/talent_api_v7.py")" == "$API_SHA" ]] || abort "existing talent_api_v7.py sha mismatch" REUSE_API
  REUSED="${REUSED:+$REUSED+}api"
else
  cp -a "$OLD_API_DIR" "$NEW_API_DIR" || abort "copy server_v6e failed" API_COPY
  cp "$CACHE_DIR/server/talent_api_v7.py" "$NEW_API_DIR/talent_api_v7.py" || abort "install api failed" API_COPY
  chown --reference="$NEW_API_DIR/whitepaper_api_v6.py" "$NEW_API_DIR/talent_api_v7.py" 2>/dev/null; chmod --reference="$NEW_API_DIR/whitepaper_api_v6.py" "$NEW_API_DIR/talent_api_v7.py"
  [[ "$(sha "$NEW_API_DIR/talent_api_v7.py")" == "$API_SHA" ]] || abort "staged api sha mismatch" API_STAGE
fi
cmp -s "$OLD_API_DIR/whitepaper_api_v6.py" "$NEW_API_DIR/whitepaper_api_v6.py" || abort "v7 dir v6e module differs from server_v6e" API_STAGE
if [[ -d "$TALENT_DATA" ]]; then
  REUSED="${REUSED:+$REUSED+}data"
  [[ "$ALLOW_NON_ROOT" == "1" ]] || chown "$SVC_USER:$SVC_GROUP" "$TALENT_DATA" || abort "chown $TALENT_DATA failed" API_DATA
  chmod 700 "$TALENT_DATA"
elif [[ "$ALLOW_NON_ROOT" == "1" ]]; then mkdir -m 700 "$TALENT_DATA" || abort "cannot create $TALENT_DATA" API_DATA
else install -d -m 700 -o "$SVC_USER" -g "$SVC_GROUP" "$TALENT_DATA" || abort "cannot create $TALENT_DATA" API_DATA; fi
CHK=$(cd /tmp && env WP_V3_ENTRY="$WP_V3_ENTRY" "$PY" "$NEW_API_DIR/talent_api_v7.py" --check 2>&1)
echo "$CHK" | grep -q 'V7_IMPORT_OK' || abort "v7 --check failed: $(echo "$CHK" | tail -1)" API_CHECK

# offline smoke: spare port, temp DBs, mail as .eml (NL_OUTBOX), no SMTP, live queue untouched
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
C=$(curl -s -o /dev/null -w '%{http_code}' -H 'Origin: https://inlightbio.cn' -H 'Content-Type: application/json' --data '{"kind":"investor","org":"smoke","contact":"smoke","email":"smoke@example.com","note":"smoke","consent":true,"elapsed_ms":5000}' "http://127.0.0.1:$SMOKE_PORT/api/partner-contact")
[[ "$C" == "202" ]] || abort "smoke partner POST $C" API_SMOKE
for i in $(seq 1 40); do [[ $(ls "$SM/outbox" | wc -l) -ge 2 ]] && break; sleep 0.5; done
EML=$(grep -l 'smoke.pdf' "$SM"/outbox/*.eml 2>/dev/null | head -1)
[[ -n "$EML" ]] && grep -q '^Reply-To: smoke@example.com' "$EML" && grep -q '^To: contact@inlightbio.com' "$EML" && grep -qi 'Content-Disposition: attachment' "$EML" || abort "smoke: CV mail wrong or missing" API_SMOKE
kill "$SMOKE_PID" 2>/dev/null; wait "$SMOKE_PID" 2>/dev/null; SMOKE_PID=""
echo "API_SMOKE_OK" | tee -a "$LOG"

# ---------------- backups + rollback.sh (before any live switch) ----------------
mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
BACKUP_CONF="${VHOST_CONF}.bak.v2.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_BASE/inlightbio.cn.conf.bak.v2.$TS"
DROPIN_BACKUP="$BACKUP_BASE/dropin_v2_$TS"; cp -a "$DROPIN_DIR" "$DROPIN_BACKUP" || abort "drop-in backup failed" BACKUP
# v1 rollback scripts would write a drop-in that sorts BEFORE the r2 one: park them, never run them.
for f in "$NEW_REL_DIR/rollback.sh" "$NEW_API_DIR/rollback_v7.sh"; do
  [[ -e "$f" ]] || continue
  P=$(park "$f" "$(basename "$f").superseded.disabled") && chmod 600 "$P" && echo "OLD_ROLLBACK_PARKED $f -> $P" | tee -a "$LOG"
done
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-19 talent deploy v2. Deletes nothing.
# web: root -> $CURRENT_ROOT, drop the talent include line (fallback: vhost backup $BACKUP_CONF),
#      park $NGINX_SNIPPET in $BACKUP_BASE, nginx -t must pass, reload.
# api: new drop-in numbered after all others with the v6e ExecStart.
set -uo pipefail
TS=\$(date +%Y%m%d_%H%M%S); V="$VHOST_CONF"; S="$NGINX_SNIPPET"; DI="$DROPIN_DIR"
cp -a "\$V" "$BACKUP_BASE/inlightbio.cn.conf.before_rollback.\$TS"
sed -i -E "s#^([[:space:]]*root[[:space:]]+)$NEW_REL_DIR;#\\\\1$CURRENT_ROOT;#" "\$V"
sed -i "\\#include \$S;#d" "\$V"
if grep -q "talent_cv" "\$V" || ! grep -qE "^[[:space:]]*root[[:space:]]+$CURRENT_ROOT;" "\$V"; then cp -a "$BACKUP_CONF" "\$V"; echo "vhost restored from backup"; fi
[[ -e "\$S" ]] && mv "\$S" "$BACKUP_BASE/nginx_talent_cv_location.conf.rolledback.\$TS"
NT=\$(nginx -t 2>&1); RC=\$?; echo "\$NT"
if [[ \$RC -ne 0 ]]; then cp -a "$BACKUP_CONF" "\$V"; NT=\$(nginx -t 2>&1); RC=\$?; echo "retry after full backup restore:"; echo "\$NT"; fi
[[ \$RC -eq 0 ]] || { echo ROLLBACK_FAIL_NGINX_T; exit 1; }
nginx -s reload || { echo ROLLBACK_FAIL_NGINX_RELOAD; exit 1; }
n=\$(ls -1 "\$DI" | sed -n 's/^\([0-9][0-9]\)-.*\.conf\$/\1/p' | sort -n | tail -1); RBF="\$DI/\$(printf '%02d' \$((10#\$n + 1)))-v7-r2-rollback.conf"
printf '[Service]\nExecStart=\nExecStart=%s\n' "$V6E_EXEC" > "\$RBF"
systemctl daemon-reload && systemctl restart "$UNIT"
for i in \$(seq 1 30); do systemctl is-active --quiet "$UNIT" && break; sleep 1; done
case "\$(systemctl show -p ExecStart "$UNIT")" in *server_v6e_20261109/whitepaper_api_v6.py*) ;; *) echo ROLLBACK_FAIL_API; exit 1;; esac
systemctl is-active --quiet "$UNIT" || { echo ROLLBACK_FAIL_API_INACTIVE; exit 1; }
echo "ROLLBACK_OK root -> $CURRENT_ROOT api -> v6e (drop-in \$RBF) NGINX_T=ok"
RB
chmod 700 "$NEW_REL_DIR/rollback.sh"; cp -a "$NEW_REL_DIR/rollback.sh" "$NEW_API_DIR/rollback_v7.sh"
[[ "$ALLOW_NON_ROOT" == "1" ]] || chown root:root "$NEW_REL_DIR/rollback.sh" "$NEW_API_DIR/rollback_v7.sh"
echo "STAGE_OK" | tee -a "$LOG"

api_restore() {
  local f="$DROPIN_DIR/$(next_dropin v7-r2-rollback)"
  printf '[Service]\nExecStart=\nExecStart=%s\n' "$V6E_EXEC" > "$f"
  systemctl daemon-reload >>"$LOG" 2>&1; systemctl restart "$UNIT" >>"$LOG" 2>&1
  echo "API_RESTORED v6e via $f" | tee -a "$LOG"
}
web_restore() {
  cp -a "$BACKUP_CONF" "$VHOST_CONF"
  if [[ -e "$NGINX_SNIPPET" ]]; then P=$(park "$NGINX_SNIPPET" "nginx_talent_cv_location.conf.failed"); echo "SNIPPET_PARKED $P" | tee -a "$LOG"; fi
  local nt rc; nt=$(nginx -t 2>&1); rc=$?; echo "$nt" | tee -a "$LOG"
  if [[ $rc -eq 0 ]]; then nginx -s reload >>"$LOG" 2>&1; echo "RESTORE_NGINX_T_OK" | tee -a "$LOG"; else echo "RESTORE_NGINX_T_FAIL" | tee -a "$LOG"; fi
}
fail_restored() {
  echo "ERR: $1" | tee -a "$LOG"
  [[ "$WEB_TOUCHED" == "1" ]] && web_restore
  [[ "$API_SWITCHED" == "1" ]] && api_restore
  summary "FAIL_$2_RESTORED"; exit 1
}

# ---------------- API switch ----------------
printf '[Service]\nExecStart=\nExecStart=%s %s\n' "$PY" "$NEW_API_DIR/talent_api_v7.py" > "$DROPIN_DIR/$NEW_DROPIN" || abort "cannot write drop-in" API_DROPIN
API_SWITCHED=1
systemctl daemon-reload >>"$LOG" 2>&1 || fail_restored "daemon-reload failed" API_RELOAD
systemctl restart "$UNIT" >>"$LOG" 2>&1 || fail_restored "restart failed" API_RESTART
ok=0; for i in $(seq 1 30); do [[ "$(curl -s "$API_LOCAL/api/talent/health")" == *talent-v7* ]] && { ok=1; break; }; sleep 1; done
[[ "$ok" == "1" ]] || fail_restored "v7 health failed" API_HEALTH
case "$(svc_prop ExecStart)" in *"$NEW_API_DIR/talent_api_v7.py"*) ;; *) fail_restored "ExecStart not v7" API_EXEC ;; esac
H=$(curl -s -o /dev/null -w '%{http_code}' "$API_LOCAL/api/whitepaper/download?token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" || true)
[[ "$H" == "404" ]] || fail_restored "whitepaper route after switch returned $H" API_WP
echo "API_OK" | tee -a "$LOG"

# ---------------- NGINX (443 block only) + root switch ----------------
WEB_TOUCHED=1
mkdir -p "$SNIPPET_DIR" && chmod 755 "$SNIPPET_DIR" || fail_restored "cannot create $SNIPPET_DIR" NGINX_SNIPPET
[[ -e "$NGINX_SNIPPET" ]] || printf '%s\n' "$SNIP_BODY" > "$NGINX_SNIPPET" || fail_restored "cannot write snippet" NGINX_SNIPPET
chmod 644 "$NGINX_SNIPPET"
awk -v T="$TL" -v S="$NGINX_SNIPPET" '{ print } NR==T { m=$0; sub(/[^ \t].*/,"",m); print m "include " S ";" }' "$VHOST_CONF" > "$TMPD/vhost.new" || fail_restored "include insert failed" NGINX_INCLUDE
cat "$TMPD/vhost.new" > "$VHOST_CONF"
[[ "$(grep -c "include $NGINX_SNIPPET;" "$VHOST_CONF")" == "1" ]] || fail_restored "include count != 1" NGINX_INCLUDE
sed -i -E "s#^([[:space:]]*root[[:space:]]+)${CURRENT_ROOT};#\\1${NEW_REL_DIR};#" "$VHOST_CONF"
[[ $(grep -cE "^[[:space:]]*root[[:space:]]+${NEW_REL_DIR};" "$VHOST_CONF") -ge 1 ]] || fail_restored "root switch failed" ROOT_SWITCH
NT=$(nginx -t 2>&1); NRC=$?; echo "$NT" >>"$LOG"
[[ $NRC -eq 0 ]] || { echo "$NT"; fail_restored "nginx -t failed" NGINX_TEST; }
nginx -T 2>/dev/null | grep -q 'location = /api/talent/cv' || fail_restored "talent location not in nginx -T" NGINX_TEST
nginx -s reload >>"$LOG" 2>&1 || fail_restored "nginx reload failed" NGINX_RELOAD
sleep 1
VT="$TMPD/v.html"
curl -fsS --retry 5 --retry-delay 2 "${curl_resolve[@]}" "$SITE_ORIGIN/" -o "$VT" >>"$LOG" 2>&1 || fail_restored "homepage fetch failed" VERIFY_HOME
[[ "$(sha "$VT")" == "$NEW_PAGE_SHA" ]] || fail_restored "live index sha is not the new page" VERIFY_HOME_SHA
while read -r rel exp; do
  [[ "$rel" == "index.html" ]] && continue
  C=$(curl -s --retry 3 -o "$TMPD/a" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/$rel" || true)
  [[ "$C" == "200" && "$(sha "$TMPD/a")" == "$exp" ]] || fail_restored "$rel HTTP $C or sha mismatch" VERIFY_ASSET
done < <(web_rel)
[[ "$(curl -s "${curl_resolve[@]}" "$SITE_ORIGIN/api/talent/health")" == *talent-v7* ]] || fail_restored "public talent health failed" VERIFY_API
head -c 2097152 /dev/zero > "$TMPD/big.pdf"   # honeypot upload: reaches app via the 12m location, no mail, no record
C=$(curl -s -o "$TMPD/r3" -w '%{http_code}' "${curl_resolve[@]}" -H "Origin: $SITE_ORIGIN" -F website=deploy-check -F name=x -F email=x@example.com -F consent=1 -F "cv=@$TMPD/big.pdf;filename=x.pdf" "$SITE_ORIGIN/api/talent/cv" || true)
[[ "$C" == "202" ]] && grep -q '"ok": *true' "$TMPD/r3" || fail_restored "2MB CV proxy check returned $C" VERIFY_CV_PROXY
C=$(curl -s -o /dev/null -w '%{http_code}' "${curl_resolve[@]}" -H "Origin: $SITE_ORIGIN" -H 'Content-Type: application/json' --data '{}' "$SITE_ORIGIN/api/partner-contact" || true)
[[ "$C" == "400" ]] || fail_restored "partner-contact invalid probe returned $C" VERIFY_PARTNER
echo "NGINX_OK" | tee -a "$LOG"
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
