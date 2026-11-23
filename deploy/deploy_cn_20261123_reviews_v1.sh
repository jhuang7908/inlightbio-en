#!/usr/bin/env bash
# InLightBio CN deploy v1 — reviews 2026-11-23 (PR #149, merge 568227bf3717aa86d15541a4c2aad11fafb44b81)
# Same v3 safety model:
#  - no process-substitution tee of the whole script; every line is written
#    synchronously to stdout and $LOG (log() uses tee -a only)
#  - EXIT trap cannot leave status 0 unless DEPLOY_OK was printed (FINISHED=1)
#  - last visible line is DEPLOY_OK or FAIL_*
#  - already-deployed is detected BEFORE the "expected old root" check (idempotent)
#  - fresh tmp dir name every run
#  - chunks are fetched sequentially (no wait/job-control surprises)
# New root inlightbio_cn_rel_20261123_reviews, abort if live root is not
# inlightbio_cn_rel_20261123_weekly (unless already on the new root and shas
# match). rollback.sh points at the pre-switch weekly root. Never delete or
# overwrite existing roots.
set -euo pipefail
exec </dev/null

TS="$(date '+%Y%m%d_%H%M%S')"
LOG="${LOG:-/root/deploy_cn_20261123_reviews_v1_${TS}.log}"
mkdir -p "$(dirname "$LOG")"
touch "$LOG"

# Synchronous dual write to stdout (paste capture) AND $LOG. No exec/tee/process substitution.
log() { printf '%s\n' "$*" | tee -a "$LOG"; }

VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
EXPECTED_OLD_ROOT="${EXPECTED_OLD_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261123_weekly}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261123_reviews}"
BACKUP_BASE="${BACKUP_BASE:-/www/backup}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
MERGE_SHA="568227bf3717aa86d15541a4c2aad11fafb44b81"
OVERLAY_SHA="5ea499851f385b6ca08b8317e907466c9b4db505d3d30c2d7ab73d15b93d5354"
INDEX_SHA="28afb528408f7447d8af5b9a4b1725bd19c6b03eb8195d8c131502744d897f6d"
CILTA_SHA="337c2de90be02ae949517e314532056288b85169704308b2aa45753d1934956e"
PFIZER_SHA="2b50e0544c80685321c06036e0eb8baffd1150eecae769b82c493993b5dfb672"
FIG_SHA="6908bbfa29b86aacc4a593165a498fe1c3dee4bff1470b011dbae7f7149788f6"
CARD_SHA="8ae73d61ada2351c903fda44554bc5453408faa86a82f8a23282d7ba0185ede9"
DEALS_SHA="6844eec8ef2ababadb89d0d5a14e112e772c5814b99da0f0ecb71d9ac606623a"
CARD_REL="content/weekly/2026-11-23/images/w-20261123-fe93adb730_card_20261123_v2.webp"
FIG_REL="img/w-20261123-fe93adb730_fig_zh_v4_web.webp"
CILTA_REL="pages/article/w-20261123-fe93adb730.html"
PFIZER_REL="pages/article/pfizer-starna-invivo-cart.html"
KUO_REL="pages/article/w-20261123-c5736475d3.html"
EIP_REL="pages/article/w-20261123-d7402cc91c.html"
LU_REL="pages/article/w-20261123-41957df407.html"
KUO_CARD_REL="content/weekly/2026-11-23/images/w-20261123-c5736475d3_card_20261123_v2.webp"
EIP_CARD_REL="content/weekly/2026-11-23/images/w-20261123-d7402cc91c_card_20261123_v2.webp"
LU_CARD_REL="content/weekly/2026-11-23/images/w-20261123-41957df407_card_20261123_v2.webp"
KUO_SHA="8975876c34021a858bef9a73a14830c33df6b528f53f3e43678121ebaf9ffb3c"
EIP_SHA="75fe0deac7938b5b958454d5ecf2bf5a4683331ffee4f2fc3c61341d8e8b6d6e"
LU_SHA="1a86a4053aa339d4f0b51d3a5a8c67f91996b5c853f89981df07daed045de9a1"
KUO_CARD_SHA="34f242289225944673e084214bf19455ab4c146e41480283194514852a97eea6"
EIP_CARD_SHA="3af6d5164a581679d9b225958868f9ed38bb990bf6ce921c01e3b7ae15b693f8"
LU_CARD_SHA="ab7a6f4cacedbba659c5667b4250489c7466243fef7534bc4eb63af9be347ead"

sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
logts() { log "[$(date '+%F %T')] $*"; }
summary() { log "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG MERGE=$MERGE_SHA"; }

FINISHED=0
cleanup() {
  local rc=$?
  if [[ -n "${TMPDIR:-}" && -d "${TMPDIR:-}" ]]; then rm -rf "$TMPDIR"; fi
  if [[ "$FINISHED" != "1" ]]; then
    log "ERR: unexpected exit rc=$rc"
    summary "FAIL_ABORTED_NOCHANGE"
    trap - EXIT
    if [[ $rc -eq 0 ]]; then rc=1; fi
    exit "$rc"
  fi
}
trap cleanup EXIT

abort() {
  log "ERR: $1"
  summary "FAIL_$2_NOCHANGE"
  FINISHED=1
  exit 1
}

if [[ "${ALLOW_NONROOT:-0}" != "1" ]]; then
  [[ $EUID -eq 0 ]] || abort "must run as root (sudo bash $0)" PRE_ROOT
fi
[[ -f "$VHOST_CONF" ]] || abort "vhost config not found: $VHOST_CONF" PRE_VHOST
mkdir -p "$BACKUP_BASE"

NT=$(nginx -t 2>&1) && NRC=0 || NRC=$?
if [[ $NRC -ne 0 ]]; then log "$NT"; abort "nginx -t fails before any change" PRE_NGINX; fi

CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ -n "$CURRENT_ROOT" && -d "$CURRENT_ROOT" ]] || abort "could not determine current live root (got: ${CURRENT_ROOT:-empty})" LIVEROOT
case "$CURRENT_ROOT" in
  */wwwroot/inlightbio_cn_rel_*|/www/wwwroot/inlightbio_cn_rel_*|*/wwwroot_fake/inlightbio_cn_rel_*|/*/inlightbio_cn_rel_*) ;;
  *) abort "live root is not a versioned inlightbio_cn_rel_* dir: $CURRENT_ROOT" LIVEROOT ;;
esac

# Tighten the case after matching: must end with inlightbio_cn_rel_*
[[ "$CURRENT_ROOT" == *"/inlightbio_cn_rel_"* ]] || abort "live root is not a versioned inlightbio_cn_rel_* dir: $CURRENT_ROOT" LIVEROOT

logts "START cn_reviews_20261123_v1 merge=$MERGE_SHA new_root=$NEW_REL_DIR live=$CURRENT_ROOT"
log "START cn_reviews_20261123_v1 $TS merge=$MERGE_SHA new_root=$NEW_REL_DIR live=$CURRENT_ROOT"

files_ok() {
  local root="$1"
  [[ -d "$root" ]] || return 1
  [[ "$(sha "$root/index.html")" == "$INDEX_SHA" ]] || return 1
  [[ "$(sha "$root/$CILTA_REL")" == "$CILTA_SHA" ]] || return 1
  [[ "$(sha "$root/$PFIZER_REL")" == "$PFIZER_SHA" ]] || return 1
  [[ "$(sha "$root/$FIG_REL")" == "$FIG_SHA" ]] || return 1
  [[ "$(sha "$root/$CARD_REL")" == "$CARD_SHA" ]] || return 1
  [[ "$(sha "$root/content/weekly_deals.js")" == "$DEALS_SHA" ]] || return 1
  [[ "$(sha "$root/$KUO_REL")" == "$KUO_SHA" ]] || return 1
  [[ "$(sha "$root/$EIP_REL")" == "$EIP_SHA" ]] || return 1
  [[ "$(sha "$root/$LU_REL")" == "$LU_SHA" ]] || return 1
  [[ "$(sha "$root/$KUO_CARD_REL")" == "$KUO_CARD_SHA" ]] || return 1
  [[ "$(sha "$root/$EIP_CARD_REL")" == "$EIP_CARD_SHA" ]] || return 1
  [[ "$(sha "$root/$LU_CARD_REL")" == "$LU_CARD_SHA" ]] || return 1
  grep -qF "星锐" "$root/index.html" || return 1
  grep -qF "cilta-cel" "$root/index.html" || return 1
  grep -qF "机器学习多目标" "$root/index.html" || return 1
}

already_ok() {
  [[ "$CURRENT_ROOT" == "$NEW_REL_DIR" ]] || return 1
  files_ok "$NEW_REL_DIR"
}

# Idempotent path FIRST — if v2 already switched the vhost, do not demand the old v2c root.
if already_ok; then
  log "IDEMPOTENT already deployed at $NEW_REL_DIR"
  FINISHED=1
  summary "DEPLOY_OK"
  exit 0
fi
if [[ "$CURRENT_ROOT" == "$NEW_REL_DIR" ]]; then
  abort "live root is already $NEW_REL_DIR but files/sha do not fully match; refusing to overwrite" DRIFT
fi
[[ "$CURRENT_ROOT" == "$EXPECTED_OLD_ROOT" ]] \
  || abort "live root is $CURRENT_ROOT, expected $EXPECTED_OLD_ROOT; refusing to switch from an unexpected root" LIVEROOT
log "PRE_ROOT_OK live root=$CURRENT_ROOT (rollback will return here)"

# New root may already exist from a previous attempt. Never reuse/overwrite it.
# If it is complete and we are still on the old root, refuse (needs human check)
# rather than delete or overlay again.
if [[ -e "$NEW_REL_DIR" ]]; then
  abort "new root $NEW_REL_DIR already exists; refusing to reuse/overwrite" NEWROOT_EXISTS
fi
grep -qF "$NEW_REL_DIR" "$VHOST_CONF" && abort "vhost already references the new root" NEWROOT_EXISTS

if [[ "${SKIP_RESOLVE:-0}" == "1" ]]; then
  curl_resolve=()
else
  curl_resolve=(--resolve inlightbio.cn:443:127.0.0.1 --resolve inlightbio.cn:80:127.0.0.1)
fi
code_of() { curl -sS --connect-timeout 8 --max-time 30 "${curl_resolve[@]+"${curl_resolve[@]}"}" -o /dev/null -w '%{http_code}' "$SITE_ORIGIN$1" || echo "000"; }
STATS_PRE=$(code_of "/stats/")
API_PRE=$(code_of "/api/")
THERASIK_PRE=$(code_of "/therasik/")
THERAMAB_PRE=$(code_of "/theramab/")
log "PRE_OK stats=$STATS_PRE api=$API_PRE therasik=$THERASIK_PRE theramab=$THERAMAB_PRE"

# Fresh tmp dir every run so leftover v2 partials are ignored.
TMPDIR=$(mktemp -d "/tmp/cn_reviews_20261123_v1_${TS}_XXXXXX")
BUNDLE_PATH="${TMPDIR}/overlay.tar.gz"
PIN="${P:-${PIN:-}}"
[[ -n "$PIN" ]] || abort "P/PIN (pin commit) is not set; the paste command must export P" PRE_PIN
REPO="jhuang7908/inlightbio-en"
CHUNK_DIR="deploy/reviews_20261123_v1"
CHUNKS=(
  "overlay.part00:13ea33b1b06b55160ce5d6905c715f2fa9ff5021cd81565f1c2d0a66163a8c5c"
  "overlay.part01:3df80d1ed98064303ff577ad70bfdef96cc112c167ba391bdcbe18c0a8f79e91"
  "overlay.part02:363309ed2b302220f41e0868eff923fc285d7300d86b593657358f2a07f7ac81"
  "overlay.part03:02014ac3c489ee4d16512e1183a37fa238d2b10122c7285781a47eab735beb47"
  "overlay.part04:1e94c11022c7312fd56d67deb2292a62a9a1db4d211928e6f8f0a50b43f6bb1f"
  "overlay.part05:35010cb317cce1735819db44a1acdb949c72bcaa8057e1f2578a12c7c9595528"
  "overlay.part06:cc990251d202a7cd501300b769ca77aed60ad53c423832671c5339afeeded8dc"
  "overlay.part07:4b2ff2380c1300d7a2b5fbcb879abcce6d4212224073a3bfa9b60ef69b400ffc"
  "overlay.part08:ae2f1283f5494cb16fbc846666ea60ef277438c8fa5c1b40d0bf6d0da12dba9e"
)

chunk_urls() {
  local file="$1"
  local path="${CHUNK_DIR}/${file}"
  if [[ -n "${LOCAL_CHUNK_BASE:-}" ]]; then
    echo "${LOCAL_CHUNK_BASE}/${file}"
  fi
  echo "https://ghfast.top/https://github.com/${REPO}/raw/${PIN}/${path}"
  echo "https://gh-proxy.com/https://github.com/${REPO}/raw/${PIN}/${path}"
  echo "https://fastly.jsdelivr.net/gh/${REPO}@${PIN}/${path}"
  echo "https://testingcf.jsdelivr.net/gh/${REPO}@${PIN}/${path}"
  echo "https://gcore.jsdelivr.net/gh/${REPO}@${PIN}/${path}"
  echo "https://cdn.jsdelivr.net/gh/${REPO}@${PIN}/${path}"
}

fetch_chunk() {
  local name="$1" exp="$2" dest="${TMPDIR}/$1" part="${TMPDIR}/$1.part" u rc
  if [[ -f "$dest" && "$(sha "$dest")" == "$exp" ]]; then
    log "CHUNK_OK cached $name"
    return 0
  fi
  # Read URLs into an array first (avoid process-sub + set -e surprises).
  local urls=()
  mapfile -t urls < <(chunk_urls "$name")
  for u in "${urls[@]}"; do
    [[ -n "$u" ]] || continue
    log "TRY $name $u"
    rm -f "$part"
    rc=0
    curl --connect-timeout 8 --max-time 30 -fsSL "$u" -o "$part" || rc=$?
    if [[ $rc -eq 0 ]]; then
      if [[ "$(sha "$part")" == "$exp" ]]; then
        mv -f "$part" "$dest"
        log "CHUNK_OK $name"
        return 0
      fi
      log "WARN: sha mismatch $name from $u got=$(sha "$part")"
    else
      log "WARN: curl failed $name $u rc=$rc"
    fi
    rm -f "$part"
  done
  log "ERR: all mirrors failed for $name"
  return 1
}

logts "Fetching overlay in 9 chunks sequentially (pin=$PIN)..."
for item in "${CHUNKS[@]}"; do
  name="${item%%:*}"
  exp="${item#*:}"
  fetch_chunk "$name" "$exp" || abort "overlay chunk failed: $name" DOWNLOAD
done
cat "${TMPDIR}/overlay.part00" "${TMPDIR}/overlay.part01" "${TMPDIR}/overlay.part02" \
    "${TMPDIR}/overlay.part03" "${TMPDIR}/overlay.part04" "${TMPDIR}/overlay.part05" \
    "${TMPDIR}/overlay.part06" "${TMPDIR}/overlay.part07" "${TMPDIR}/overlay.part08" \
    > "$BUNDLE_PATH"
[[ "$(sha "$BUNDLE_PATH")" == "$OVERLAY_SHA" ]] || abort "reassembled overlay sha mismatch expected=$OVERLAY_SHA got=$(sha "$BUNDLE_PATH")" SHA256
log "DOWNLOAD_OK overlay sha=$OVERLAY_SHA"

logts "COPY_START $CURRENT_ROOT -> $NEW_REL_DIR"
cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
log "COPY_OK $CURRENT_ROOT -> $NEW_REL_DIR"

park() {
  local src="$1" name="$2" dest
  mkdir -p "$BACKUP_BASE"
  dest="$BACKUP_BASE/$name"
  if [[ -e "$dest" ]]; then dest="${dest}.$TS"; fi
  mv "$src" "$dest"
  printf '%s\n' "$dest"
}
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then
  P=$(park "$NEW_REL_DIR/rollback.sh" "rollback.sh.inherited_from_$(basename "$CURRENT_ROOT").disabled")
  chmod 600 "$P"
  log "INHERITED_ROLLBACK_PARKED $P"
fi

logts "Extracting overlay..."
tar -xzf "$BUNDLE_PATH" -C "$NEW_REL_DIR" --no-same-owner || abort "overlay extract failed" EXTRACT
if [[ -e "$NEW_REL_DIR/index.html" && -e "$CURRENT_ROOT/index.html" ]]; then
  chown --reference="$CURRENT_ROOT/index.html" -R "$NEW_REL_DIR" 2>/dev/null || true
fi
log "STAGE_EXTRACT_OK"

SUMS="$TMPDIR/overlay_sha256.txt"
tar -xOf "$BUNDLE_PATH" ./overlay_sha256.txt > "$SUMS" 2>/dev/null   || tar -xOf "$BUNDLE_PATH" overlay_sha256.txt > "$SUMS" 2>/dev/null   || true
if [[ -s "$SUMS" ]]; then
  while read -r want f; do
    [[ -n "${f:-}" ]] || continue
    [[ -f "$NEW_REL_DIR/$f" ]] || abort "missing overlay file $f" OVERLAY_MISSING
    got=$(sha "$NEW_REL_DIR/$f")
    [[ "$got" == "$want" ]] || abort "staged sha mismatch $f expected=$want got=$got" STAGE
  done < "$SUMS"
  log "STAGE_SUMS_OK"
fi

[[ "$(sha "$NEW_REL_DIR/index.html")" == "$INDEX_SHA" ]] || abort "staged index.html sha mismatch" STAGE
[[ "$(sha "$NEW_REL_DIR/$CILTA_REL")" == "$CILTA_SHA" ]] || abort "staged cilta article sha mismatch" STAGE
[[ "$(sha "$NEW_REL_DIR/$PFIZER_REL")" == "$PFIZER_SHA" ]] || abort "staged pfizer brief sha mismatch" STAGE
[[ "$(sha "$NEW_REL_DIR/$FIG_REL")" == "$FIG_SHA" ]] || abort "staged cilta fig sha mismatch" STAGE
[[ "$(sha "$NEW_REL_DIR/$CARD_REL")" == "$CARD_SHA" ]] || abort "staged cilta card sha mismatch" STAGE
[[ "$(sha "$NEW_REL_DIR/content/weekly_deals.js")" == "$DEALS_SHA" ]] || abort "staged weekly_deals.js sha mismatch" STAGE
[[ "$(sha "$NEW_REL_DIR/$KUO_REL")" == "$KUO_SHA" ]] || abort "staged kuo article sha mismatch" STAGE
[[ "$(sha "$NEW_REL_DIR/$EIP_REL")" == "$EIP_SHA" ]] || abort "staged eip article sha mismatch" STAGE
[[ "$(sha "$NEW_REL_DIR/$LU_REL")" == "$LU_SHA" ]] || abort "staged lu article sha mismatch" STAGE
[[ "$(sha "$NEW_REL_DIR/$KUO_CARD_REL")" == "$KUO_CARD_SHA" ]] || abort "staged kuo card sha mismatch" STAGE
[[ "$(sha "$NEW_REL_DIR/$EIP_CARD_REL")" == "$EIP_CARD_SHA" ]] || abort "staged eip card sha mismatch" STAGE
[[ "$(sha "$NEW_REL_DIR/$LU_CARD_REL")" == "$LU_CARD_SHA" ]] || abort "staged lu card sha mismatch" STAGE
grep -qF "星锐" "$NEW_REL_DIR/index.html" || abort "staged homepage missing 星锐" STAGE
grep -qF "cilta-cel" "$NEW_REL_DIR/index.html" || abort "staged homepage missing cilta-cel" STAGE
grep -qF "本周头条" "$NEW_REL_DIR/index.html" || abort "staged homepage missing 本周头条" STAGE
grep -qF "plat-rec" "$NEW_REL_DIR/index.html" || abort "staged homepage missing plat-rec" STAGE
grep -qF "/therasik/" "$NEW_REL_DIR/index.html" || abort "staged homepage missing /therasik/" STAGE
grep -qF "AI 赋能的药物研发与设计" "$NEW_REL_DIR/index.html" || abort "staged homepage missing TheraSik blurb" STAGE
grep -qF "tmab-banner" "$NEW_REL_DIR/index.html" || abort "staged homepage missing tmab-banner" STAGE
grep -qF "px.js" "$NEW_REL_DIR/index.html" || abort "staged homepage missing px.js" STAGE
grep -qF "机器学习多目标" "$NEW_REL_DIR/index.html" || abort "staged homepage missing review title" STAGE
grep -qF "EIP 免疫原性" "$NEW_REL_DIR/index.html" || abort "staged homepage missing EIP title" STAGE
grep -qF "转基因抗体小鼠" "$NEW_REL_DIR/index.html" || abort "staged homepage missing Lu title" STAGE
grep -qF "week-feature-science" "$NEW_REL_DIR/index.html" || abort "staged homepage missing science lead" STAGE
grep -qF "fig_zh_v4_web.webp" "$NEW_REL_DIR/$CILTA_REL" || abort "staged cilta article missing v4 figure" STAGE
grep -qF "星锐" "$NEW_REL_DIR/$PFIZER_REL" || abort "staged pfizer brief missing 星锐" STAGE
[[ -s "$NEW_REL_DIR/assets/ev/px.js" ]] || abort "px.js missing after copy" STAGE
[[ "$(sha "$NEW_REL_DIR/assets/ev/px.js")" == "$(sha "$CURRENT_ROOT/assets/ev/px.js")" ]] || abort "px.js changed in staged root" STAGE
[[ -d "$NEW_REL_DIR/therasik" ]] || abort "therasik/ missing after copy" STAGE
[[ -d "$NEW_REL_DIR/theramab" ]] || abort "theramab/ missing after copy" STAGE
if [[ -f "$CURRENT_ROOT/theramab/README.txt" ]]; then
  [[ -f "$NEW_REL_DIR/theramab/README.txt" ]] || abort "theramab/README.txt missing from staged root (must be copied, not deleted)" STAGE
  [[ "$(sha "$NEW_REL_DIR/theramab/README.txt")" == "$(sha "$CURRENT_ROOT/theramab/README.txt")" ]] || abort "theramab/README.txt changed in staged root" STAGE
fi
log "STAGE_OK $NEW_REL_DIR"

cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-23 reviews deploy: web root -> $CURRENT_ROOT. Deletes nothing.
set -uo pipefail
V="${VHOST_CONF}"
TS=\$(date '+%Y%m%d_%H%M%S')
cp -a "\$V" "$BACKUP_BASE/inlightbio.cn.conf.before_rollback.\$TS"
if [[ -s "$BACKUP_BASE/inlightbio.cn.conf.bak.reviews20261123_fixed" ]]; then
  cp -a "$BACKUP_BASE/inlightbio.cn.conf.bak.reviews20261123_fixed" "\$V"
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
chown root:root "$NEW_REL_DIR/rollback.sh" 2>/dev/null || true
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_cn_reviews_20261123.$TS.sh"
log "BACKUP_OK ROLLBACK=$NEW_REL_DIR/rollback.sh (points to $CURRENT_ROOT)"

BACKUP_CONF="${VHOST_CONF}.bak.reviews20261123.$TS"
[[ ! -e "$BACKUP_CONF" ]] || abort "vhost backup name exists: $BACKUP_CONF" BACKUP
cp -a "$VHOST_CONF" "$BACKUP_CONF" || abort "vhost backup failed" BACKUP
VHOST_BAK_FIXED="$BACKUP_BASE/inlightbio.cn.conf.bak.reviews20261123_fixed"
# If a previous (v2) run already wrote this fixed backup, park it rather than overwrite or abort.
if [[ -e "$VHOST_BAK_FIXED" ]]; then
  P2="$BACKUP_BASE/inlightbio.cn.conf.bak.reviews20261123_fixed.parked.$TS"
  mv "$VHOST_BAK_FIXED" "$P2"
  log "WARN: parked pre-existing $VHOST_BAK_FIXED -> $P2"
fi
cp -a "$BACKUP_CONF" "$VHOST_BAK_FIXED" || abort "second vhost backup failed" BACKUP
log "BACKUP_OK VHOST_BACKUP=$BACKUP_CONF ROLLBACK=$NEW_REL_DIR/rollback.sh"

web_restore() {
  log "RESTORING vhost from $BACKUP_CONF"
  cp -a "$BACKUP_CONF" "$VHOST_CONF"
  nginx -t >>"$LOG" 2>&1 && nginx -s reload >>"$LOG" 2>&1 || true
}
fail_restored() {
  log "ERR: $1"
  web_restore
  summary "FAIL_$2_RESTORED"
  FINISHED=1
  exit 1
}

WEB_TOUCHED=1
sed -i -E "s#^([[:space:]]*root[[:space:]]+)${CURRENT_ROOT};#\1${NEW_REL_DIR};#" "$VHOST_CONF"
NNEW=$(grep -cE "^[[:space:]]*root[[:space:]]+${NEW_REL_DIR};" "$VHOST_CONF" || true)
[[ "$NNEW" == "2" ]] || fail_restored "root switch failed (expected exactly 2 root lines pointing at the new dir, got $NNEW)" ROOT_SWITCH
if grep -n 'acme-challenge' -A2 "$VHOST_CONF" | grep -q "$NEW_REL_DIR"; then fail_restored "acme-challenge root changed" ACME; fi
if ! grep -q 'nginx_api_location.conf' "$VHOST_CONF"; then fail_restored "api include missing after root switch" API_INCLUDE; fi
if ! nginx -t 2>&1; then fail_restored "nginx -t failed after root switch" NGINX_TEST; fi
if ! nginx -s reload 2>&1; then fail_restored "nginx reload failed" NGINX_RELOAD; fi
log "NGINX_OK CONF_OK root -> $NEW_REL_DIR"

sleep 1
TMPD=$(mktemp -d "/tmp/cn_reviews_20261123_v1_verify_${TS}_XXXXXX")
verify_curl() {
  curl -sS --retry 2 --retry-delay 1 --connect-timeout 8 --max-time 30 ${curl_resolve[@]+"${curl_resolve[@]}"} \
    -H "Accept-Encoding: identity" \
    -D "$3" -o "$2" -w '%{http_code}' \
    "$SITE_ORIGIN$1" || echo "000"
}

ok=0; C="000"; GOT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/" "$TMPD/home.html" "$TMPD/home.hdr")
  GOT=$(sha "$TMPD/home.html")
  log "VERIFY_HOME_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$INDEX_SHA"
  if [[ "$C" == "200" && "$GOT" == "$INDEX_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "homepage HTTP $C sha_got=${GOT:-empty} sha_expected=$INDEX_SHA" VERIFY_HOME
grep -qF "星锐" "$TMPD/home.html" || fail_restored "live homepage missing 星锐" VERIFY_HOME
grep -qF "cilta-cel" "$TMPD/home.html" || fail_restored "live homepage missing cilta-cel" VERIFY_HOME
grep -qF "本周头条" "$TMPD/home.html" || fail_restored "live homepage missing 本周头条" VERIFY_HOME
grep -qF "plat-rec" "$TMPD/home.html" || fail_restored "live homepage missing plat-rec" VERIFY_HOME
grep -qF "/therasik/" "$TMPD/home.html" || fail_restored "live homepage missing /therasik/" VERIFY_HOME
grep -qF "AI 赋能的药物研发与设计" "$TMPD/home.html" || fail_restored "live homepage missing TheraSik blurb" VERIFY_HOME
grep -qF "tmab-banner" "$TMPD/home.html" || fail_restored "live homepage missing tmab-banner" VERIFY_HOME
grep -qF "px.js" "$TMPD/home.html" || fail_restored "live homepage missing px.js" VERIFY_HOME
grep -qF "机器学习多目标" "$TMPD/home.html" || fail_restored "live homepage missing review title" VERIFY_HOME
log "VERIFY_HOME_OK HTTP=$C sha=$GOT"

ok=0; C="000"; GOT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/$PFIZER_REL" "$TMPD/pfizer.html" "$TMPD/pfizer.hdr")
  GOT=$(sha "$TMPD/pfizer.html")
  log "VERIFY_PFIZER_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$PFIZER_SHA"
  if [[ "$C" == "200" && "$GOT" == "$PFIZER_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "pfizer brief HTTP $C sha_got=${GOT:-empty}" VERIFY_PFIZER
grep -qF "星锐" "$TMPD/pfizer.html" || fail_restored "pfizer brief missing 星锐" VERIFY_PFIZER
log "VERIFY_PFIZER_OK HTTP=$C sha=$GOT"

ok=0; C="000"; GOT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/$CILTA_REL" "$TMPD/cilta.html" "$TMPD/cilta.hdr")
  GOT=$(sha "$TMPD/cilta.html")
  log "VERIFY_CILTA_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$CILTA_SHA"
  if [[ "$C" == "200" && "$GOT" == "$CILTA_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "cilta article HTTP $C sha_got=${GOT:-empty}" VERIFY_CILTA
grep -qF "fig_zh_v4_web.webp" "$TMPD/cilta.html" || fail_restored "cilta article missing v4 figure path" VERIFY_CILTA
grep -qF "3.0%" "$TMPD/cilta.html" || fail_restored "cilta article missing 3.0%" VERIFY_CILTA
log "VERIFY_CILTA_OK HTTP=$C sha=$GOT"

C=$(verify_curl "/$CARD_REL" "$TMPD/card.webp" "$TMPD/card.hdr")
GOT=$(sha "$TMPD/card.webp")
log "VERIFY_CARD HTTP=$C sha_got=${GOT:-empty} sha_expected=$CARD_SHA"
[[ "$C" == "200" && "$GOT" == "$CARD_SHA" ]] || fail_restored "cilta card HTTP $C sha_got=${GOT:-empty}" VERIFY_CARD
log "VERIFY_CARD_OK HTTP=$C sha=$GOT"

C=$(verify_curl "/$FIG_REL" "$TMPD/fig.webp" "$TMPD/fig.hdr")
GOT=$(sha "$TMPD/fig.webp")
log "VERIFY_FIG HTTP=$C sha_got=${GOT:-empty} sha_expected=$FIG_SHA"
[[ "$C" == "200" && "$GOT" == "$FIG_SHA" ]] || fail_restored "cilta fig HTTP $C sha_got=${GOT:-empty}" VERIFY_FIG
log "VERIFY_FIG_OK HTTP=$C sha=$GOT"

# Three new review articles + cards
ok=0; C="000"; GOT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/$KUO_REL" "$TMPD/kuo.html" "$TMPD/kuo.hdr")
  GOT=$(sha "$TMPD/kuo.html")
  log "VERIFY_KUO_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$KUO_SHA"
  if [[ "$C" == "200" && "$GOT" == "$KUO_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "kuo article HTTP $C sha_got=${GOT:-empty}" VERIFY_KUO
grep -qF "机器学习多目标" "$TMPD/kuo.html" || fail_restored "kuo article missing title" VERIFY_KUO
grep -qF "综述" "$TMPD/kuo.html" || fail_restored "kuo article missing 综述" VERIFY_KUO
log "VERIFY_KUO_OK HTTP=$C sha=$GOT"

ok=0; C="000"; GOT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/$EIP_REL" "$TMPD/eip.html" "$TMPD/eip.hdr")
  GOT=$(sha "$TMPD/eip.html")
  log "VERIFY_EIP_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$EIP_SHA"
  if [[ "$C" == "200" && "$GOT" == "$EIP_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "eip article HTTP $C sha_got=${GOT:-empty}" VERIFY_EIP
grep -qF "EIP 免疫原性" "$TMPD/eip.html" || fail_restored "eip article missing title" VERIFY_EIP
log "VERIFY_EIP_OK HTTP=$C sha=$GOT"

ok=0; C="000"; GOT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/$LU_REL" "$TMPD/lu.html" "$TMPD/lu.hdr")
  GOT=$(sha "$TMPD/lu.html")
  log "VERIFY_LU_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$LU_SHA"
  if [[ "$C" == "200" && "$GOT" == "$LU_SHA" ]]; then ok=1; break; fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "lu article HTTP $C sha_got=${GOT:-empty}" VERIFY_LU
grep -qF "人免疫球蛋白位点转基因动物与全人抗" "$TMPD/lu.html" || fail_restored "lu article missing title" VERIFY_LU
log "VERIFY_LU_OK HTTP=$C sha=$GOT"

C=$(verify_curl "/$KUO_CARD_REL" "$TMPD/kuo_card.webp" "$TMPD/kuo_card.hdr")
GOT=$(sha "$TMPD/kuo_card.webp")
log "VERIFY_KUO_CARD HTTP=$C sha_got=${GOT:-empty} sha_expected=$KUO_CARD_SHA"
[[ "$C" == "200" && "$GOT" == "$KUO_CARD_SHA" ]] || fail_restored "kuo card HTTP $C sha_got=${GOT:-empty}" VERIFY_KUO_CARD
log "VERIFY_KUO_CARD_OK HTTP=$C sha=$GOT"

C=$(verify_curl "/$EIP_CARD_REL" "$TMPD/eip_card.webp" "$TMPD/eip_card.hdr")
GOT=$(sha "$TMPD/eip_card.webp")
log "VERIFY_EIP_CARD HTTP=$C sha_got=${GOT:-empty} sha_expected=$EIP_CARD_SHA"
[[ "$C" == "200" && "$GOT" == "$EIP_CARD_SHA" ]] || fail_restored "eip card HTTP $C sha_got=${GOT:-empty}" VERIFY_EIP_CARD
log "VERIFY_EIP_CARD_OK HTTP=$C sha=$GOT"

C=$(verify_curl "/$LU_CARD_REL" "$TMPD/lu_card.webp" "$TMPD/lu_card.hdr")
GOT=$(sha "$TMPD/lu_card.webp")
log "VERIFY_LU_CARD HTTP=$C sha_got=${GOT:-empty} sha_expected=$LU_CARD_SHA"
[[ "$C" == "200" && "$GOT" == "$LU_CARD_SHA" ]] || fail_restored "lu card HTTP $C sha_got=${GOT:-empty}" VERIFY_LU_CARD
log "VERIFY_LU_CARD_OK HTTP=$C sha=$GOT"

C=$(code_of "/therasik/")
log "VERIFY_THERASIK HTTP=$C pre=$THERASIK_PRE"
[[ "$C" == "200" ]] || fail_restored "therasik HTTP $C" VERIFY_THERASIK
log "VERIFY_THERASIK_OK HTTP=$C"

C=$(code_of "/theramab/")
log "VERIFY_THERAMAB HTTP=$C pre=$THERAMAB_PRE"
[[ "$C" == "200" ]] || fail_restored "theramab HTTP $C" VERIFY_THERAMAB
log "VERIFY_THERAMAB_OK HTTP=$C"

STATS_POST=$(code_of "/stats/")
API_POST=$(code_of "/api/")
log "VERIFY_STATS stats_pre=$STATS_PRE stats_post=$STATS_POST api_pre=$API_PRE api_post=$API_POST"
if [[ "$STATS_PRE" =~ ^2 ]]; then [[ "$STATS_POST" == "$STATS_PRE" ]] || fail_restored "stats code changed $STATS_PRE -> $STATS_POST" VERIFY_STATS; fi
if [[ "$API_PRE" =~ ^2 ]]; then [[ "$API_POST" == "$API_PRE" ]] || fail_restored "api code changed $API_PRE -> $API_POST" VERIFY_API; fi

rm -rf "$TMPD"
FINISHED=1
summary "DEPLOY_OK"
exit 0
