#!/usr/bin/env bash
set -uo pipefail
# InLightBio CN deploy homefix v1 - 2026-11-19 homepage/column logos, 目标职位 grid, full-width notes
# (therasik-inlight PR #126, commit b644ce5). Web-only: no API / systemd / nginx-location change.
#  * stages a FRESH release root (aborts if it already exists; never reuses or overwrites a root);
#  * copies the current live root (…_9f63548_fund) and overlays 3 changed files, each sha256-verified
#    (and each replaced file must first match its known live sha);
#  * writes rollback.sh into the new root (points back to the 9f63548_fund root);
#  * backs up the nginx vhost, switches `root`, `nginx -t`, reload, verifies homepage + asset shas;
#  * on any failure after the switch, restores the vhost backup and reloads.
# Deletes nothing. Old roots, backups and caches are kept. Env vars override defaults for a sandbox dry run only.
ASSET_PIN="${ASSET_PIN:-92005bbc81b7fbf2b1ca806f8c2936d4af307682}"
MIRRORS="${MIRRORS:-cdn.jsdelivr.net fastly.jsdelivr.net gcore.jsdelivr.net testingcf.jsdelivr.net quantil.jsdelivr.net}"
URL_BASE_FMT="${URL_BASE_FMT:-https://%s/gh/jhuang7908/inlightbio-en@%s}"
CACHE_DIR="${CACHE_DIR:-/root/inlight_dl_cache_20261119_homefix}"
LIVE_PAGE_SHA="6a4ad61280c6145cbee5321080524a50d4e4673b8e34280212c8552715508d7e"
NEW_PAGE_SHA="75af910ab5731946ea25701ef7ff7c47989d8e2b9c3ff24c611508484cb4cb3e"
JOBS_SHA="1f7e1158d44299cf58f85ee57d3763fafd7da4a307bc43ee7c3a97af4020249b"   # 启光英才 jobs: must stay unchanged
VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
EXPECTED_OLD_ROOT="${EXPECTED_OLD_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261119_9f63548_fund}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261119_b644ce5_homefix}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261119_homefix}"
LOG="${LOG:-/var/log/inlightbio_cn_deploy_20261119_homefix_v1.log}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"; fi
curl_resolve=(); [[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")
# path  new_sha  live_sha(expected in the 9f63548_fund root)
OVERLAY_FILES="
  index.html 75af910ab5731946ea25701ef7ff7c47989d8e2b9c3ff24c611508484cb4cb3e 6a4ad61280c6145cbee5321080524a50d4e4673b8e34280212c8552715508d7e
  assets/talent/talent_fund.css f3086f96aa3074ee59d1692d5f4a47cbb2a96c82ce6af9c9feed185f4a243e33 3a3aa8eac31aa7817b7c3e11a9f9b809453f1a54fe692fb78a5e8bb0abb45fdc
  assets/talent/talent_fund.js 7cfa272ea944b7af392d28448a52cc233fd5e8a806578e85e507ccc4326fe6c5 df784814d4cea9618ea7588f6ec9530a90bd49457fc56712a2146526595e396a
"
ov() { printf '%s\n' "$OVERLAY_FILES" | awk 'NF==3'; }
N_FILES=$(ov | wc -l)
TS=$(date '+%Y%m%d_%H%M%S')
CURRENT_ROOT=""; BACKUP_CONF=""; WEB_TOUCHED=0; CACHED_OK=0; CACHED_SKIP=0; CACHED_GOT=0
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE" | tee -a "$LOG"; exit 1; }
if ! { : > "$LOG"; } 2>/dev/null; then LOG=/tmp/inlightbio_cn_deploy_20261119_homefix_v1.log; : > "$LOG"; fi
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
IFS=' ' read -r -a MIRROR_ARR <<< "$MIRRORS"
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
park() { local src="$1" name="$2" dst; mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"; dst="$BACKUP_BASE/$name"; [[ -e "$dst" ]] && dst="$dst.$TS"; [[ -e "$dst" ]] && dst="$dst.$$"; mv "$src" "$dst" && echo "$dst"; }

# ---------------- PRE (read-only) ----------------
echo "START homefix_v1 $TS pin=$ASSET_PIN" | tee -a "$LOG"
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing" VHOST
NT=$(nginx -t 2>&1); NRC=$?
if [[ $NRC -ne 0 ]]; then echo "$NT"; abort "nginx -t fails before any change" PRE_NGINX; fi
echo "PRE_NGINX_T_OK" | tee -a "$LOG"
CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ "$CURRENT_ROOT" == "$EXPECTED_OLD_ROOT" && -d "$CURRENT_ROOT" ]] || abort "live root is not the expected 9f63548_fund root ($CURRENT_ROOT)" LIVEROOT
NROOTS=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | awk '{print $2}' | tr -d ';' | sort -u | wc -l)
[[ "$NROOTS" == "1" ]] || abort "vhost has $NROOTS distinct root values; expected 1" LIVEROOT
while read -r rel new old; do [[ "$(sha "$CURRENT_ROOT/$rel")" == "$old" ]] || abort "live $rel drifted from the known 9f63548_fund version" DRIFT; done < <(ov)
[[ "$(sha "$CURRENT_ROOT/content/talent/jobs_public.json")" == "$JOBS_SHA" ]] || abort "live jobs_public.json drifted" DRIFT
[[ ! -e "$NEW_REL_DIR" ]] || abort "new root $NEW_REL_DIR already exists; refusing to reuse/overwrite (set NEW_REL_DIR to a new name)" NEWROOT_EXISTS
grep -qF "$NEW_REL_DIR" "$VHOST_CONF" && abort "vhost already references the new root" NEWROOT_EXISTS
echo "PRE_OK OLD_ROOT=$CURRENT_ROOT" | tee -a "$LOG"

# ---------------- DOWNLOAD (jsDelivr pin, mirror rotation, sha256) ----------------
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
[[ "$CACHED_OK" -eq "$N_FILES" ]] || abort "cache count $CACHED_OK/$N_FILES" DOWNLOAD
echo "DOWNLOAD_OK CACHED=${CACHED_SKIP}/${N_FILES} GOT=${CACHED_GOT}/${N_FILES}" | tee -a "$LOG"

# ---------------- STAGE fresh root ----------------
cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
# a rollback.sh inherited from the 9f63548_fund root points to an older root: move the COPY out of the new root (original untouched)
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then P=$(park "$NEW_REL_DIR/rollback.sh" "rollback.sh.inherited_from_9f63548_fund.disabled") && chmod 600 "$P" && echo "INHERITED_ROLLBACK_PARKED $P" | tee -a "$LOG"; fi
while read -r rel new old; do
  T="$NEW_REL_DIR/$rel"
  [[ "$(sha "$T")" == "$old" ]] || abort "copied $rel is not the known live version" STAGE
  cp "$CACHE_DIR/$rel" "$TMPD/f" && chown --reference="$CURRENT_ROOT/$rel" "$TMPD/f" 2>/dev/null; chmod --reference="$CURRENT_ROOT/$rel" "$TMPD/f"
  cat "$TMPD/f" > "$T" || abort "install $rel failed" INSTALL
  [[ "$(sha "$T")" == "$new" ]] || abort "staged $rel sha mismatch" STAGE
done < <(ov)
D=$(diff -rq "$CURRENT_ROOT" "$NEW_REL_DIR" 2>&1 | grep -vE "^Files $CURRENT_ROOT/(index\.html|assets/talent/talent_fund\.(css|js)) and $NEW_REL_DIR/[^ ]+ differ$|^Only in $CURRENT_ROOT: rollback\.sh$")
[[ -z "$D" ]] || abort "new root differs from live root beyond the overlay: $(echo "$D" | head -3)" STAGE_DIFF
I="$NEW_REL_DIR/index.html"
for pat in 'id="v-talent"' 'id="v-fund"' 'id="home-talent"' 'id="home-fund"' 'assets/talent/talent_fund.js' '投资机构' '启光英才' 'fund-disclaimer' 'mailto:bd@inlightbio.com' 'id="newco-report-feature"' 'id="talent-cv-target"' 'class="cvt-grid"' 'class="sec-logo"' 'talent_fund.css?v=20261119c' 'talent_fund.js?v=20261119c'; do
  grep -qF "$pat" "$I" || abort "staged index missing: $pat" STAGE
done
grep -qE 'preview-ribbon|此页为未上线预览|勿合并' "$I" && abort "preview text in staged index" STAGE
[[ "$(sha "$NEW_REL_DIR/content/talent/jobs_public.json")" == "$JOBS_SHA" ]] || abort "jobs_public.json changed in staged root" STAGE
echo "STAGE_OK" | tee -a "$LOG"

# ---------------- backups + rollback.sh (before the switch) ----------------
mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
BACKUP_CONF="${VHOST_CONF}.bak.homefix_v1.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_BASE/inlightbio.cn.conf.bak.homefix_v1.$TS" || abort "second vhost backup failed" BACKUP
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-19 homefix v1 deploy: web root -> $CURRENT_ROOT. Deletes nothing.
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
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_homefix_v1.sh"
echo "BACKUP_OK VHOST_BACKUP=$BACKUP_CONF ROLLBACK=$NEW_REL_DIR/rollback.sh" | tee -a "$LOG"

web_restore() {
  cp -a "$BACKUP_CONF" "$VHOST_CONF"
  local nt rc; nt=$(nginx -t 2>&1); rc=$?; echo "$nt" | tee -a "$LOG"
  if [[ $rc -eq 0 ]]; then nginx -s reload >>"$LOG" 2>&1; echo "RESTORE_NGINX_T_OK" | tee -a "$LOG"; else echo "RESTORE_NGINX_T_FAIL" | tee -a "$LOG"; fi
}
fail_restored() { echo "ERR: $1" | tee -a "$LOG"; [[ "$WEB_TOUCHED" == "1" ]] && web_restore; summary "FAIL_$2_RESTORED" | tee -a "$LOG"; exit 1; }

# ---------------- switch root ----------------
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
[[ "$H" == *talent-v7* ]] && echo "TALENT_API_OK (unchanged)" | tee -a "$LOG" || echo "WARN: talent API health did not answer talent-v7 (API untouched by this deploy): $(printf %s "${H:0:80}" | tr -d '\r\n')" | tee -a "$LOG"
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
