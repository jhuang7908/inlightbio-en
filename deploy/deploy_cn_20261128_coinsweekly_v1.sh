#!/usr/bin/env bash
# InLightBio CN deploy coinsweekly_v1 - 2026-11-28
# Publishes the COINS lead + weekly deal roundup (CN) and the homepage lead slot.
# Web-only: stages a FRESH release root = copy of the live root + 4 replaced files + 6 new files.
# Does not change nginx locations, SSL, ACME, or APIs. The only nginx edit is the existing
# one-line `root` switch used by prior CN deploys. Deletes nothing.
# Approved by Jing (via parent): publish 2026-11-28. CN PR #155 merged as 62edbe6.
set -euo pipefail

ASSET_PIN="${ASSET_PIN:-684f46afe36493f50e70b643a8e7b417a4d65ed2}"
MIRRORS="${MIRRORS:-cdn.jsdelivr.net fastly.jsdelivr.net gcore.jsdelivr.net testingcf.jsdelivr.net quantil.jsdelivr.net}"
URL_BASE_FMT="${URL_BASE_FMT:-https://%s/gh/jhuang7908/inlightbio-en@%s}"
OVL="deploy/overlays/coinsweekly_v1"
CACHE_DIR="${CACHE_DIR:-/root/inlight_dl_cache_20261128_coinsweekly_v1}"
# kind|dest_rel_in_site_root|new_sha256|live_sha256_or_-|src_name_in_overlay
FILES=(
"R|index.html|a28dbe1f77decbc3027d8f7f09b0ec82c93a5e5063b25d3f14d40c6de0769d26|3f615b9c6ba38a3104bfba4ca62044ceba84617113eb7d5a031a1e84473d7540|index.html"
"R|content/weekly_deals.js|2e76ec96376ae45862057b8f5e66943e987580a257bc0ed57318275a3b5c5557|6844eec8ef2ababadb89d0d5a14e112e772c5814b99da0f0ecb71d9ac606623a|weekly_deals.js"
"R|feed.xml|a9ed23e1d035cf0a516cde094420f82687d35cfbb9d5d37896598ad72fc05be0|c52a4648bb40df3b42973df94f093b4fe01060354547e1152e2c816b454cd347|feed.xml"
"R|sitemap.xml|da8f0b54e0f915cc13c642fe95d07da154e266b0e883d6fd23d36469a83e39bb|200ee8614bec8f7a3bf4dca0caa188df95b526e5a6c6746657323347c7d54999|sitemap.xml"
"N|pages/article/us-coins-biotech-outbound-rule.html|02b6d6c87ab4b47d3176b36ed888041932a69aaaaf65b4671caaae7deb606078|-|us-coins-biotech-outbound-rule.html"
"N|pages/article/deals-weekly-20261128.html|d5cf7b1c3cf1c26b8ae88c920ac7813d77d1264f0ce60060cfecb836a50a1d69|-|deals-weekly-20261128.html"
"N|img/pal/deals/v11/deal_73_20261128_v1.png|961997796c3bd1a486a6239d805a98b4559cc2e0aa0c2f10c299e08e435d99c6|-|deal_73_20261128_v1.png"
"N|img/pal/deals/v11/deal_73_20261128_v1_web.webp|8280fc50e9898a3122ab88107235fcf2c7b62633b20bd481d243543ec33f3dbf|-|deal_73_20261128_v1_web.webp"
"N|img/pal/deals/v11/deal_74_20261128_v1.png|bea491d2497024cad4d09d2c1ea17d98aa60171c944769847e1d82d207442310|-|deal_74_20261128_v1.png"
"N|img/pal/deals/v11/deal_74_20261128_v1_web.webp|079d44106f7426242d84925eb4e7ab490ce0061d80bbb0d6cded3c9306d0a228|-|deal_74_20261128_v1_web.webp"
)
NFILES=${#FILES[@]}
# canaries that must stay byte-identical: path|sha256
CANARIES=(
"therasik/index.html|2b03ddb6ea506eb183b65ff6f4a2908bbc3b495e58766b80c9d77e20cf8216c4"
"theramab/index.html|a0429e99a722adce23637e7574ff89eb79c1a355b2f6d9ad144c2daf120f1199"
"pages/newco-report.html|46dba787b054d4d04e54d884ff07dc7722b50bc70e60f413b853f48f0f2c0204"
"content/talent/jobs_public.json|1f7e1158d44299cf58f85ee57d3763fafd7da4a307bc43ee7c3a97af4020249b"
"assets/fonts/fonts.css|8228afd6527ba54591634f39ca6bfe8cb867ad88882da7a95d5da917d85aec60"
)
VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261128_62edbe6_coinsweekly_v1}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261128_coinsweekly_v1}"
LOG="${LOG:-/var/log/inlightbio_cn_deploy_20261128_coinsweekly_v1.log}"
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

echo "START coinsweekly_v1 $TS pin=$ASSET_PIN (4 replaced + 6 new files; nginx locations untouched)" | tee -a "$LOG"
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing" VHOST
[[ -n "$ASSET_PIN" ]] || abort "ASSET_PIN is not set" PIN
NT=$(nginx -t 2>&1); NRC=$?
if [[ $NRC -ne 0 ]]; then echo "$NT"; abort "nginx -t fails before any change" PRE_NGINX; fi
echo "PRE_NGINX_T_OK" | tee -a "$LOG"

CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ -n "$CURRENT_ROOT" && -d "$CURRENT_ROOT" ]] || abort "cannot detect live root from $VHOST_CONF ($CURRENT_ROOT)" LIVEROOT
NROOTS=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | awk '{print $2}' | tr -d ';' | sort -u | wc -l)
[[ "$NROOTS" == "1" ]] || abort "vhost has $NROOTS distinct root values; expected 1" LIVEROOT
for e in "${FILES[@]}"; do
  IFS='|' read -r kind dest nsha lsha src <<< "$e"
  if [[ "$kind" == "R" ]]; then
    [[ "$(sha "$CURRENT_ROOT/$dest")" == "$lsha" ]] || abort "live $dest is not the expected $lsha" DRIFT
  else
    [[ ! -e "$CURRENT_ROOT/$dest" ]] || abort "live already has $dest; refusing to overwrite" DRIFT
  fi
done
for c in "${CANARIES[@]}"; do IFS='|' read -r p s <<< "$c"; [[ "$(sha "$CURRENT_ROOT/$p")" == "$s" ]] || abort "live $p drifted" DRIFT; done
[[ ! -e "$NEW_REL_DIR" ]] || abort "new root $NEW_REL_DIR already exists; refusing to reuse/overwrite (set NEW_REL_DIR to a new name)" NEWROOT_EXISTS
grep -qF "$NEW_REL_DIR" "$VHOST_CONF" && abort "vhost already references the new root" NEWROOT_EXISTS
mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
for e in "${FILES[@]}"; do
  IFS='|' read -r kind dest nsha lsha src <<< "$e"
  [[ "$kind" == "R" ]] && { cp -a "$CURRENT_ROOT/$dest" "$BACKUP_BASE/$(echo "$dest" | tr '/' '_').live.$lsha.$TS" || abort "backup of live $dest failed" BACKUP; }
done
echo "PRE_OK OLD_ROOT=$CURRENT_ROOT BACKUP_BASE=$BACKUP_BASE" | tee -a "$LOG"

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
for e in "${FILES[@]}"; do
  IFS='|' read -r kind dest nsha lsha src <<< "$e"
  fetch_one "$OVL/$src" "$nsha" "$src" || abort "download failed: $OVL/$src" DOWNLOAD
done
[[ "$CACHED_OK" -eq "$NFILES" ]] || abort "cache count $CACHED_OK/$NFILES" DOWNLOAD
echo "DOWNLOAD_OK CACHED=${CACHED_SKIP}/$NFILES GOT=${CACHED_GOT}/$NFILES" | tee -a "$LOG"

cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then P=$(park "$NEW_REL_DIR/rollback.sh" "rollback.sh.inherited_from_$(basename "$CURRENT_ROOT").disabled") && chmod 600 "$P" && echo "INHERITED_ROLLBACK_PARKED $P" | tee -a "$LOG"; fi
for e in "${FILES[@]}"; do
  IFS='|' read -r kind dest nsha lsha src <<< "$e"
  T="$NEW_REL_DIR/$dest"
  if [[ "$kind" == "R" ]]; then
    [[ "$(sha "$T")" == "$lsha" ]] || abort "copied $dest is not the known live version" STAGE
    ref="$CURRENT_ROOT/$dest"
  else
    mkdir -p "$(dirname "$T")"
    ref="$CURRENT_ROOT/$(dirname "$dest")/$(ls "$CURRENT_ROOT/$(dirname "$dest")" | head -1)"
    [[ -e "$ref" ]] || ref="$CURRENT_ROOT/index.html"
  fi
  cp "$CACHE_DIR/$src" "$TMPD/f" && chown --reference="$ref" "$TMPD/f" 2>/dev/null; chmod --reference="$ref" "$TMPD/f" 2>/dev/null || chmod 644 "$TMPD/f"
  cat "$TMPD/f" > "$T" || abort "install $dest failed" INSTALL
  [[ "$(sha "$T")" == "$nsha" ]] || abort "staged $dest sha mismatch" STAGE
done

EXPECT_NEW=$(for e in "${FILES[@]}"; do IFS='|' read -r kind dest _ _ _ <<< "$e"; [[ "$kind" == "N" ]] && echo "$dest"; done | sort | tr '\n' ',')
python3 - "$CURRENT_ROOT" "$NEW_REL_DIR" "$EXPECT_NEW" <<'PY' || abort "new root differs from live root beyond the overlay" STAGE_DIFF
import os, sys
old, new, exp = sys.argv[1], sys.argv[2], set(x for x in sys.argv[3].split(',') if x)
def walk(base):
    out=set()
    for root, dirs, files in os.walk(base):
        for fn in files:
            out.add(os.path.relpath(os.path.join(root, fn), base))
    return out
old_set, new_set = walk(old), walk(new)
unexpected=[]
for rel in sorted(new_set-old_set):
    if rel == 'rollback.sh' or rel in exp: continue
    unexpected.append('extra '+rel)
for rel in sorted(exp-(new_set-old_set)): unexpected.append('absent '+rel)
for rel in sorted(old_set-new_set):
    if rel == 'rollback.sh': continue
    unexpected.append('missing '+rel)
if unexpected:
    sys.stderr.write('UNEXPECTED:\n'+'\n'.join(unexpected[:20])+'\n'); sys.exit(1)
sys.exit(0)
PY

I="$NEW_REL_DIR/index.html"
for pat in 'id="week-feature-deals"' 'us-coins-biotech-outbound-rule.html' 'deal_73_20261128_v1_web.webp' 'deal_74_20261128_v1_web.webp' 'id="homefeed"' 'assets/fonts/fonts.css' 'id="home-talent"' 'id="home-fund"'; do
  grep -qF "$pat" "$I" || abort "staged homepage missing: $pat" STAGE
done
grep -qE 'preview-ribbon|此页为未上线预览|勿合并' "$I" && abort "preview text in staged homepage" STAGE
grep -qE 'fonts\.googleapis\.com|fonts\.gstatic\.com' "$I" && abort "staged homepage still references Google Fonts" STAGE
for pg in us-coins-biotech-outbound-rule deals-weekly-20261128; do
  grep -qF '黄菁 (Rocky Huang)' "$NEW_REL_DIR/pages/article/$pg.html" || abort "page $pg lacks byline" STAGE
  grep -qF '待Jing定调' "$NEW_REL_DIR/pages/article/$pg.html" && abort "page $pg still has placeholder" STAGE
done
for c in "${CANARIES[@]}"; do IFS='|' read -r p s <<< "$c"; [[ "$(sha "$NEW_REL_DIR/$p")" == "$s" ]] || abort "$p changed in staged root" STAGE; done
echo "STAGE_OK" | tee -a "$LOG"

BACKUP_CONF="${VHOST_CONF}.bak.coinsweekly_v1.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_BASE/inlightbio.cn.conf.bak.coinsweekly_v1.$TS" || abort "second vhost backup failed" BACKUP
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-28 coinsweekly_v1 deploy: web root -> $CURRENT_ROOT. Deletes nothing.
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
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_coinsweekly_v1.sh"
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

VT="$TMPD/v.bin"
for e in "${FILES[@]}"; do
  IFS='|' read -r kind dest nsha lsha src <<< "$e"
  path="$dest"; [[ "$dest" == "index.html" ]] && path=""
  ok=0
  for i in 1 2 3 4 5; do
    C=$(curl -s --retry 3 --retry-delay 2 "${curl_resolve[@]}" -o "$VT" -w '%{http_code}' "$SITE_ORIGIN/$path" || true)
    [[ "$C" == "200" && "$(sha "$VT")" == "$nsha" ]] && { ok=1; break; }; sleep 2
  done
  [[ "$ok" == "1" ]] || fail_restored "live /$path HTTP $C sha $(sha "$VT") is not the new file" VERIFY_FILE
done
echo "VERIFY_FILES_OK n=$NFILES" | tee -a "$LOG"
grep -qE 'fonts\.googleapis\.com|fonts\.gstatic\.com' "$I" && fail_restored "homepage references Google Fonts" VERIFY_NO_GOOGLE_FONTS
for c in "${CANARIES[@]}"; do
  IFS='|' read -r p s <<< "$c"
  C=$(curl -s --retry 3 -o "$TMPD/c" -w '%{http_code}' "${curl_resolve[@]}" "$SITE_ORIGIN/$p" || true)
  [[ "$C" == "200" && "$(sha "$TMPD/c")" == "$s" ]] || fail_restored "$p HTTP $C or sha changed" VERIFY_CANARY
done
echo "VERIFY_CANARIES_OK" | tee -a "$LOG"
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
