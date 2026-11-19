#!/usr/bin/env bash
set -uo pipefail
# InLightBio CN deploy homeorder v8 - 2026-11-19 首页按菜单顺序重排 + 简历横条 + 重点推荐大会 + 赞助合作位
# (therasik-inlight PR #133, merge commit 0477511). Web-only, ONE file: index.html. No API / systemd / nginx-location change.
#  * stages a FRESH release root (aborts if it already exists; never reuses or overwrites a root);
#  * copies the current live root (…_7ab60a1_p4list_v7m, homepage must be 7d0f878d…) and overlays index.html,
#    sha256-verified (the replaced file must first match its known live sha 7d0f878d…; new sha ee19fb63… = main 0477511);
#  * pages/newco-report.html (7db54ec2…) and content/talent/jobs_public.json (1f7e1158…) must stay unchanged;
#  * writes rollback.sh into the new root (points back to the 7ab60a1_p4list_v7m root);
#  * backs up the nginx vhost, switches `root`, `nginx -t`, reload, verifies homepage + newco page + jobs shas;
#  * on any failure after the switch, restores the vhost backup and reloads.
# Deletes nothing. Old roots, backups and caches are kept. Env vars override defaults (sandbox dry run only).
export LANG=C.UTF-8 LC_ALL=C.UTF-8
ASSET_PIN="${ASSET_PIN:-058595420c2e63dc6d5a76df244b6292c5c8806a}"
MIRRORS="${MIRRORS:-cdn.jsdelivr.net fastly.jsdelivr.net gcore.jsdelivr.net testingcf.jsdelivr.net quantil.jsdelivr.net}"
URL_BASE_FMT="${URL_BASE_FMT:-https://%s/gh/jhuang7908/inlightbio-en@%s}"
CACHE_DIR="${CACHE_DIR:-/root/inlight_dl_cache_20261119_homeorder_v8}"
HOME_SHA="${HOME_SHA:-7d0f878d0c69731f97df70ee12248c0b1400316c1b042d78198f7c51b2a3104c}"   # live homepage before this deploy (p4list_v7m)
NEW_PAGE_SHA="ee19fb63e2c48cc1722e8715016d028976d7d0c3cb00e00b064e1707438d11a5"   # homepage after (therasik-inlight main 0477511)
LIVE_PAGE_SHA="$HOME_SHA"
NEWCO_REL="pages/newco-report.html"
NEWCO_SHA="7db54ec2e9c5b79ba029da4932f847b164e486febc22a77486419515d658e0e1"   # NewCo report page: must stay unchanged
JOBS_SHA="1f7e1158d44299cf58f85ee57d3763fafd7da4a307bc43ee7c3a97af4020249b"   # 启光英才 jobs: must stay unchanged
VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
EXPECTED_OLD_ROOT="${EXPECTED_OLD_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261119_7ab60a1_p4list_v7m}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261119_0477511_homeorder_v8}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261119_homeorder_v8}"
LOG="${LOG:-/var/log/inlightbio_cn_deploy_20261119_homeorder_v8.log}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"; fi
curl_resolve=(); [[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")
# path  new_sha  live_sha(expected in the old root 7ab60a1_p4list_v7m)
OVERLAY_FILES="
  index.html ee19fb63e2c48cc1722e8715016d028976d7d0c3cb00e00b064e1707438d11a5 7d0f878d0c69731f97df70ee12248c0b1400316c1b042d78198f7c51b2a3104c
"
ov() { printf '%s\n' "$OVERLAY_FILES" | awk 'NF==3'; }
N_FILES=$(ov | wc -l)
TS=$(date '+%Y%m%d_%H%M%S')
CURRENT_ROOT=""; BACKUP_CONF=""; WEB_TOUCHED=0; CACHED_OK=0; CACHED_SKIP=0; CACHED_GOT=0
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE" | tee -a "$LOG"; exit 1; }
if ! { : > "$LOG"; } 2>/dev/null; then LOG=/tmp/inlightbio_cn_deploy_20261119_homeorder_v8.log; : > "$LOG"; fi
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
IFS=' ' read -r -a MIRROR_ARR <<< "$MIRRORS"
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
park() { local src="$1" name="$2" dst; mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"; dst="$BACKUP_BASE/$name"; [[ -e "$dst" ]] && dst="$dst.$TS"; [[ -e "$dst" ]] && dst="$dst.$$"; mv "$src" "$dst" && echo "$dst"; }

# ---------------- PRE (read-only) ----------------
echo "START homeorder_v8 $TS pin=$ASSET_PIN" | tee -a "$LOG"
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing" VHOST
NT=$(nginx -t 2>&1); NRC=$?
if [[ $NRC -ne 0 ]]; then echo "$NT"; abort "nginx -t fails before any change" PRE_NGINX; fi
echo "PRE_NGINX_T_OK" | tee -a "$LOG"
CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ "$CURRENT_ROOT" == "$EXPECTED_OLD_ROOT" && -d "$CURRENT_ROOT" ]] || abort "live root is not the expected root $EXPECTED_OLD_ROOT ($CURRENT_ROOT)" LIVEROOT
NROOTS=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | awk '{print $2}' | tr -d ';' | sort -u | wc -l)
[[ "$NROOTS" == "1" ]] || abort "vhost has $NROOTS distinct root values; expected 1" LIVEROOT
while read -r rel new old; do [[ "$(sha "$CURRENT_ROOT/$rel")" == "$old" ]] || abort "live $rel drifted from the known version" DRIFT; done < <(ov)
[[ "$(sha "$CURRENT_ROOT/index.html")" == "$HOME_SHA" ]] || abort "live homepage index.html is not the expected $HOME_SHA" DRIFT
[[ "$(sha "$CURRENT_ROOT/content/talent/jobs_public.json")" == "$JOBS_SHA" ]] || abort "live jobs_public.json drifted" DRIFT
[[ "$(sha "$CURRENT_ROOT/$NEWCO_REL")" == "$NEWCO_SHA" ]] || abort "live $NEWCO_REL drifted" DRIFT
# logos used by the new 重点推荐大会 block must already exist in the live root (this deploy adds no images)
for f in img/conf/logos/t/conf_14.png img/conf/logos/t/conf_57.png img/conf/logos/t/conf_51_off.png img/conf/logos/t/conf_36.png img/conf/logos/t/conf_16.png img/conf/logos/t/conf_17.png; do [[ -s "$CURRENT_ROOT/$f" ]] || abort "live root lacks $f" ASSET_MISSING; done
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
# a rollback.sh inherited from the old root points to an older root: move the COPY out of the new root (original untouched)
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then P=$(park "$NEW_REL_DIR/rollback.sh" "rollback.sh.inherited_from_$(basename "$CURRENT_ROOT").disabled") && chmod 600 "$P" && echo "INHERITED_ROLLBACK_PARKED $P" | tee -a "$LOG"; fi
while read -r rel new old; do
  T="$NEW_REL_DIR/$rel"
  [[ "$(sha "$T")" == "$old" ]] || abort "copied $rel is not the known live version" STAGE
  cp "$CACHE_DIR/$rel" "$TMPD/f" && chown --reference="$CURRENT_ROOT/$rel" "$TMPD/f" 2>/dev/null; chmod --reference="$CURRENT_ROOT/$rel" "$TMPD/f"
  cat "$TMPD/f" > "$T" || abort "install $rel failed" INSTALL
  [[ "$(sha "$T")" == "$new" ]] || abort "staged $rel sha mismatch" STAGE
done < <(ov)
D=$(diff -rq "$CURRENT_ROOT" "$NEW_REL_DIR" 2>&1 | grep -vE "^Files $CURRENT_ROOT/index\.html and $NEW_REL_DIR/index\.html differ$|^Only in $CURRENT_ROOT: rollback\.sh$")
[[ -z "$D" ]] || abort "new root differs from live root beyond the overlay: $(echo "$D" | head -3)" STAGE_DIFF
I="$NEW_REL_DIR/index.html"
for pat in '<h2>学术进展</h2>' 'id="cv-home"' '简历投递 / 智能匹配' 'id="home-confpick"' 'CONF_PICK' '赞助合作位招募中' 'sponsorad-r' 'sponsorad-m' 'bd@inlightbio.com?subject=%E8%B5%9E%E5%8A%A9%E5%90%88%E4%BD%9C%E5%92%A8%E8%AF%A2' 'id="bp-home"' 'id="home-talent"' 'id="home-fund"' 'id="homecomp"'; do
  grep -qF "$pat" "$I" || abort "staged homepage missing: $pat" STAGE
done
grep -qE 'preview-ribbon|此页为未上线预览|勿合并' "$I" && abort "preview text in staged homepage" STAGE
[[ "$(sha "$NEW_REL_DIR/index.html")" == "$NEW_PAGE_SHA" ]] || abort "staged homepage is not the new version" STAGE
[[ "$(sha "$NEW_REL_DIR/$NEWCO_REL")" == "$NEWCO_SHA" ]] || abort "$NEWCO_REL changed in staged root" STAGE
[[ "$(sha "$NEW_REL_DIR/content/talent/jobs_public.json")" == "$JOBS_SHA" ]] || abort "jobs_public.json changed in staged root" STAGE
echo "STAGE_OK" | tee -a "$LOG"

# ---------------- backups + rollback.sh (before the switch) ----------------
mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
BACKUP_CONF="${VHOST_CONF}.bak.homeorder_v8.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_BASE/inlightbio.cn.conf.bak.homeorder_v8.$TS" || abort "second vhost backup failed" BACKUP
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-19 homeorder v8 deploy: web root -> $CURRENT_ROOT. Deletes nothing.
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
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_homeorder_v8.sh"
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
C=$(curl -s --retry 3 -o "$TMPD/n" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/$NEWCO_REL" || true)
[[ "$C" == "200" && "$(sha "$TMPD/n")" == "$NEWCO_SHA" ]] || fail_restored "$NEWCO_REL HTTP $C or sha changed" VERIFY_NEWCO
C=$(curl -s --retry 3 -o "$TMPD/j" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/content/talent/jobs_public.json" || true)
[[ "$C" == "200" && "$(sha "$TMPD/j")" == "$JOBS_SHA" ]] || fail_restored "jobs_public.json HTTP $C or sha changed" VERIFY_JOBS
echo "VERIFY_ASSETS_OK" | tee -a "$LOG"
H=$(curl -s -m 10 "${curl_resolve[@]}" "$SITE_ORIGIN/api/talent/health" || true)
[[ "$H" == *talent-v* ]] && echo "TALENT_API_OK (unchanged) $(printf %s "${H:0:60}" | tr -d '\r\n')" | tee -a "$LOG" || echo "WARN: talent API health did not answer (API untouched by this deploy): $(printf %s "${H:0:80}" | tr -d '\r\n')" | tee -a "$LOG"
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
