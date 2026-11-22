#!/usr/bin/env bash
# InLightBio CN deploy — TheraMab v3.4 partner placement (2026-11-22)
# Pin: therasik-inlight commit 24d381a (PR #138, branch feat/theramab-v34-cn-preview).
#
# Safe pattern (same as clickstats_v1 / scicards / p03b):
#  * detect the live nginx root; copy it to a FRESH release dir (abort if that dir exists);
#  * overlay the 84 web files from commit 24d381a (tarball sha-verified); never edit/delete the old root;
#  * download 1080p + 720p MP4s (+ poster) into /www/wwwroot/inlight_static/theramab/ (never overwrite a
#    different sha; identical sha is ok / idempotent);
#  * write rollback.sh; back up the vhost; add `location ^~ /theramab/assets/video/` alias; switch root;
#  * nginx -t && reload; verify homepage / theramab page / Range 206; print DEPLOY_OK.
#  * On any failure after the vhost is touched, restore the backup and reload (FAIL_*_RESTORED).
#  * Idempotent: if the live root is already the new dir, files match, alias is correct → DEPLOY_OK.
#  * Does NOT merge the PR, does not delete old roots, does not run anything except on this host.
#
# Run as root on the Aliyun 轻量 instance. Log: /root/deploy_theramab_v34_<ts>.log
set -uo pipefail

OVERLAY_TAR_SHA="${OVERLAY_TAR_SHA:-e825cd831b592f9ea6208b48d38abe891c345369d4830634d014e443ca6a96bd}"
NEW_INDEX_SHA="${NEW_INDEX_SHA:-bb07f9b68b4fc979afefe54ad45f83e9f30e1e996751ca1e867035310c34b981}"
OLD_INDEX_SHA="${OLD_INDEX_SHA:-90f6945929297483e62e645c6134c7fec711129dec9c522fd2d6d3be813e89eb}"
NEW_SITE_CSS_SHA="${NEW_SITE_CSS_SHA:-8e7a78c31cc09243fc7e6fcc0e8e8827b6bf9ec10266b71c08d6ec407d88ba59}"
NEW_THERAMAB_INDEX_SHA="${NEW_THERAMAB_INDEX_SHA:-41e6eb5e8767297ca3ceaf94cf6e917c861303954a169e725cfc1d9caeb07326}"
NEW_NEWCO_SHA="${NEW_NEWCO_SHA:-048df5468f58575899d87e67ac7d9a80167c1dac107b51634e77fa0684e860c5}"
POSTER_SHA="${POSTER_SHA:-fb2e21702862f900aed2785f732f2652839649d9d06b0e5a80f84d3b587a90bd}"
MP4_1080_SHA="${MP4_1080_SHA:-1ee6af4a09cdaa7a40ee22370d3fc071416a5fdaffc184c5a6390e82a953e0ee}"
MP4_720_SHA="${MP4_720_SHA:-806afc6172a55e01f4019f4e32cae8aa299393da7ead647b1fe58e859c9cb445}"
# ffmpeg -vn -acodec copy -f md5  (same on both renditions)
AUDIO_MD5_COPY="e86cc6214c834dba0238356f45f926ad"
OVERLAY_NFILES=84
SRC_COMMIT="24d381a"

VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
EXPECTED_OLD_ROOT="${EXPECTED_OLD_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261120_e239fe7_clickstats_v1}"
NEW_REL_DIR="${NEW_REL_DIR:-/www/wwwroot/inlightbio_cn_rel_20261122_24d381a_theramab_v34}"
STATIC_DIR="${STATIC_DIR:-/www/wwwroot/inlight_static/theramab}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261122_theramab_v34}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
PUB_TAG="${PUB_TAG:-cn-deploy-2026-11-22-theramab-v34}"
PRIV_TAG="${PRIV_TAG:-theramab-v34-video-20261122}"
PUB_REPO="${PUB_REPO:-jhuang7908/inlightbio-en}"
PRIV_REPO="${PRIV_REPO:-jhuang7908/therasik-inlight}"
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"; fi
curl_resolve=(); [[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")

TS=$(date '+%Y%m%d_%H%M%S')
LOG="${LOG:-/root/deploy_theramab_v34_${TS}.log}"
CURRENT_ROOT=""; BACKUP_CONF=""; WEB_TOUCHED=0
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE" | tee -a "$LOG"; exit 1; }
if ! { : >> "$LOG"; } 2>/dev/null; then LOG="/tmp/deploy_theramab_v34_${TS}.log"; : >> "$LOG"; fi
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
park() { local src="$1" name="$2" dst; mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"; dst="$BACKUP_BASE/$name"; [[ -e "$dst" ]] && dst="$dst.$TS"; [[ -e "$dst" ]] && dst="$dst.$$"; mv "$src" "$dst" && echo "$dst"; }

echo "START theramab_v34 $TS src=$SRC_COMMIT new_root=$NEW_REL_DIR" | tee -a "$LOG"
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing: $VHOST_CONF" VHOST
NT=$(nginx -t 2>&1); NRC=$?
if [[ $NRC -ne 0 ]]; then echo "$NT" | tee -a "$LOG"; abort "nginx -t fails before any change" PRE_NGINX; fi
echo "PRE_NGINX_T_OK" | tee -a "$LOG"

CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ -n "$CURRENT_ROOT" && -d "$CURRENT_ROOT" ]] || abort "could not detect live root from $VHOST_CONF ($CURRENT_ROOT)" LIVEROOT
case "$CURRENT_ROOT" in
  /www/wwwroot/inlightbio_cn_rel_*) ;;
  *) abort "live root is not a versioned inlightbio_cn_rel_* dir: $CURRENT_ROOT" LIVEROOT ;;
esac
NROOTS=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | awk '{print $2}' | tr -d ';' | sort -u | wc -l)
[[ "$NROOTS" == "1" ]] || abort "vhost has $NROOTS distinct root values; expected 1" LIVEROOT
LIVE_INDEX_SHA=$(sha "$CURRENT_ROOT/index.html")
[[ -n "$LIVE_INDEX_SHA" ]] || abort "live index.html unreadable" LIVEROOT

alias_ok() {
  python3 - "$VHOST_CONF" "$STATIC_DIR" <<'PY'
import re, sys, os
conf, static = open(sys.argv[1], encoding="utf-8", errors="replace").read(), os.path.abspath(sys.argv[2])
want = static if static.endswith("/") else static + "/"
pats = [
    r"location\s+\^~\s+/theramab/assets/video/\s*\{([^}]+)\}",
    r"location\s+/theramab/assets/video/\s*\{([^}]+)\}",
]
blocks = []
for p in pats:
    blocks.extend(re.findall(p, conf, re.S))
if not blocks:
    sys.exit(1)
for b in blocks:
    m = re.search(r"alias\s+(\S+);", b)
    if not m:
        sys.exit(2)
    got = m.group(1)
    if os.path.abspath(got if got.endswith("/") else got + "/") + "/" != os.path.abspath(want) + "/":
        sys.exit(3)
sys.exit(0)
PY
}

static_ok() {
  [[ "$(sha "$STATIC_DIR/theramab_demo_1080p.mp4")" == "$MP4_1080_SHA" ]] || return 1
  [[ "$(sha "$STATIC_DIR/theramab_demo_720p.mp4")"  == "$MP4_720_SHA"  ]] || return 1
  [[ "$(sha "$STATIC_DIR/theramab_demo_poster.jpg")" == "$POSTER_SHA"  ]] || return 1
  return 0
}

staged_ok() {
  [[ -d "$NEW_REL_DIR" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/index.html")" == "$NEW_INDEX_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/site.css")" == "$NEW_SITE_CSS_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/theramab/index.html")" == "$NEW_THERAMAB_INDEX_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/theramab/assets/video/theramab_demo_poster.jpg")" == "$POSTER_SHA" ]] || return 1
  [[ "$(sha "$NEW_REL_DIR/pages/newco-report.html")" == "$NEW_NEWCO_SHA" ]] || return 1
  return 0
}

already_live() {
  [[ "$CURRENT_ROOT" == "$NEW_REL_DIR" ]] || return 1
  [[ "$LIVE_INDEX_SHA" == "$NEW_INDEX_SHA" ]] || return 1
  staged_ok || return 1
  static_ok || return 1
  alias_ok || return 1
  return 0
}

if already_live; then
  echo "IDEMPOTENT already deployed at $NEW_REL_DIR" | tee -a "$LOG"
  echo "BACKUP_OK (no change; already live)" | tee -a "$LOG"
  echo "STAGE_OK (no change; already live)" | tee -a "$LOG"
  summary "DEPLOY_OK" | tee -a "$LOG"
  exit 0
fi

if [[ "$CURRENT_ROOT" == "$NEW_REL_DIR" ]]; then
  abort "live root is already $NEW_REL_DIR but files/alias/sha do not fully match; refusing to overwrite" DRIFT
fi

if [[ "$LIVE_INDEX_SHA" == "$NEW_INDEX_SHA" ]]; then
  abort "live homepage is already the 24d381a page but root is $CURRENT_ROOT (not $NEW_REL_DIR); refusing to guess" DRIFT
fi
if [[ "$LIVE_INDEX_SHA" != "$OLD_INDEX_SHA" ]]; then
  abort "live $CURRENT_ROOT/index.html sha=$LIVE_INDEX_SHA is neither the expected clickstats page ($OLD_INDEX_SHA) nor the new page; refusing to overlay (would risk losing live edits)" DRIFT
fi
if [[ "$CURRENT_ROOT" != "$EXPECTED_OLD_ROOT" ]]; then
  echo "WARN: live root is $CURRENT_ROOT (expected $EXPECTED_OLD_ROOT); homepage sha matches clickstats, continuing" | tee -a "$LOG"
fi
[[ ! -e "$NEW_REL_DIR" ]] || abort "new root $NEW_REL_DIR already exists; refusing to reuse/overwrite" NEWROOT_EXISTS
grep -qF "$NEW_REL_DIR" "$VHOST_CONF" && abort "vhost already references the new root" NEWROOT_EXISTS
echo "PRE_OK OLD_ROOT=$CURRENT_ROOT LIVE_INDEX_SHA=$LIVE_INDEX_SHA" | tee -a "$LOG"

# Public inlightbio-en release is the fetch source (therasik-inlight is private;
# unauthenticated pulls from the CN server would fail). ghfast / ghproxy first.
asset_urls() {
  local file="$1"
  echo "https://ghfast.top/https://github.com/${PUB_REPO}/releases/download/${PUB_TAG}/${file}"
  echo "https://gh-proxy.com/https://github.com/${PUB_REPO}/releases/download/${PUB_TAG}/${file}"
  echo "https://mirror.ghproxy.com/https://github.com/${PUB_REPO}/releases/download/${PUB_TAG}/${file}"
  echo "https://github.com/${PUB_REPO}/releases/download/${PUB_TAG}/${file}"
  echo "https://ghfast.top/https://github.com/${PRIV_REPO}/releases/download/${PRIV_TAG}/${file}"
  echo "https://github.com/${PRIV_REPO}/releases/download/${PRIV_TAG}/${file}"
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

CACHE_DIR="${CACHE_DIR:-/root/inlight_cache_theramab_v34}"
mkdir -p "$CACHE_DIR" || abort "cannot create cache dir" DOWNLOAD

fetch_sha "$CACHE_DIR/overlay_24d381a_theramab_v34.tar.gz" "$OVERLAY_TAR_SHA" "overlay_24d381a_theramab_v34.tar.gz" \
  || abort "failed to download overlay tarball (commit $SRC_COMMIT)" DOWNLOAD
fetch_sha "$CACHE_DIR/theramab_demo_1080p.mp4" "$MP4_1080_SHA" "theramab_demo_1080p.mp4" \
  || abort "failed to download 1080p mp4" DOWNLOAD
fetch_sha "$CACHE_DIR/theramab_demo_720p.mp4" "$MP4_720_SHA" "theramab_demo_720p.mp4" \
  || abort "failed to download 720p mp4" DOWNLOAD
fetch_sha "$CACHE_DIR/theramab_demo_poster.jpg" "$POSTER_SHA" "theramab_demo_poster.jpg" \
  || abort "failed to download poster" DOWNLOAD
echo "DOWNLOAD_OK" | tee -a "$LOG"

# Place static MP4s + poster (never overwrite a different sha)
install_static() {
  local src="$1" dest="$2" exp="$3"
  if [[ -e "$dest" ]]; then
    if [[ "$(sha "$dest")" == "$exp" ]]; then
      echo "STATIC_EXISTS_OK $dest" | tee -a "$LOG"
      return 0
    fi
    abort "existing $dest sha=$(sha "$dest") != $exp; refusing to overwrite" STATIC
  fi
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest" || abort "copy $dest failed" STATIC
  chmod 644 "$dest"
  [[ "$(sha "$dest")" == "$exp" ]] || abort "installed $dest sha mismatch" STATIC
  echo "STATIC_INSTALLED $dest" | tee -a "$LOG"
}
install_static "$CACHE_DIR/theramab_demo_1080p.mp4" "$STATIC_DIR/theramab_demo_1080p.mp4" "$MP4_1080_SHA"
install_static "$CACHE_DIR/theramab_demo_720p.mp4"  "$STATIC_DIR/theramab_demo_720p.mp4"  "$MP4_720_SHA"
install_static "$CACHE_DIR/theramab_demo_poster.jpg" "$STATIC_DIR/theramab_demo_poster.jpg" "$POSTER_SHA"
if [[ ! -e "$STATIC_DIR/SHA256SUMS.txt" ]]; then
  cat > "$STATIC_DIR/SHA256SUMS.txt" <<SUMS
$MP4_1080_SHA  theramab_demo_1080p.mp4
$MP4_720_SHA  theramab_demo_720p.mp4
$POSTER_SHA  theramab_demo_poster.jpg
SUMS
  chmod 644 "$STATIC_DIR/SHA256SUMS.txt"
fi
echo "STATIC_OK $STATIC_DIR" | tee -a "$LOG"

# ---------- stage new root ----------
echo "COPY_START $CURRENT_ROOT -> $NEW_REL_DIR" | tee -a "$LOG"
cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy web root failed" COPY
if [[ -e "$NEW_REL_DIR/rollback.sh" ]]; then
  P=$(park "$NEW_REL_DIR/rollback.sh" "rollback.sh.inherited_from_$(basename "$CURRENT_ROOT").disabled") && chmod 600 "$P" && echo "INHERITED_ROLLBACK_PARKED $P" | tee -a "$LOG"
fi

mkdir -p "$TMPD/overlay"
tar -xzf "$CACHE_DIR/overlay_24d381a_theramab_v34.tar.gz" -C "$TMPD/overlay" --no-same-owner || abort "overlay extract failed" EXTRACT
NFOUND=$(find "$TMPD/overlay" -type f | wc -l)
[[ "$NFOUND" -eq "$OVERLAY_NFILES" ]] || abort "overlay has $NFOUND files, expected $OVERLAY_NFILES" EXTRACT
[[ "$(sha "$TMPD/overlay/index.html")" == "$NEW_INDEX_SHA" ]] || abort "overlay index.html sha mismatch" EXTRACT
[[ "$(sha "$TMPD/overlay/theramab/index.html")" == "$NEW_THERAMAB_INDEX_SHA" ]] || abort "overlay theramab/index.html sha mismatch" EXTRACT
[[ "$(sha "$TMPD/overlay/theramab/assets/video/theramab_demo_poster.jpg")" == "$POSTER_SHA" ]] || abort "overlay poster sha mismatch" EXTRACT
if find "$TMPD/overlay" -iname '*.mp4' | grep -q .; then abort "overlay tarball unexpectedly contains mp4s" EXTRACT; fi

while IFS= read -r -d '' f; do
  rel="${f#./}"
  dest="$NEW_REL_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" ]]; then
    cat "$TMPD/overlay/$rel" > "$dest" || abort "install $rel failed" INSTALL
  else
    cp "$TMPD/overlay/$rel" "$dest" || abort "install new $rel failed" INSTALL
    if [[ -e "$NEW_REL_DIR/index.html" ]]; then
      chown --reference="$NEW_REL_DIR/index.html" "$dest" 2>/dev/null || true
      chmod --reference="$NEW_REL_DIR/index.html" "$dest" 2>/dev/null || true
    fi
  fi
  [[ "$(sha "$dest")" == "$(sha "$TMPD/overlay/$rel")" ]] || abort "staged $rel sha mismatch" STAGE
done < <(cd "$TMPD/overlay" && find . -type f -print0)

if [[ -d "$NEW_REL_DIR/theramab" && -e "$NEW_REL_DIR/index.html" ]]; then
  chown -R --reference="$NEW_REL_DIR/index.html" "$NEW_REL_DIR/theramab" 2>/dev/null || true
fi

staged_ok || abort "staged key file sha check failed" STAGE

I="$NEW_REL_DIR/index.html"
for pat in 'TheraMab' 'tmab-art' '<h2>学术进展</h2>' 'id="latestgrid"' 'assets/ev/px.js?v=20261120a' 'assets/talent/talent_fund.js?v=20261120a' 'assets/fonts/fonts.css' 'id="bp-home"' 'id="home-talent"' '看演示视频'; do
  grep -qF "$pat" "$I" || abort "staged homepage missing: $pat" STAGE
done
grep -qE 'preview-ribbon|此页为未上线预览|勿合并' "$I" && abort "preview text in staged homepage" STAGE
grep -qE 'fonts\.googleapis\.com|fonts\.gstatic\.com' "$I" && abort "staged homepage still references Google Fonts" STAGE
grep -qE '11 月 24|11月24|Tuesday' "$I" && abort "staged homepage still has 11/24 availability wording" STAGE
TI="$NEW_REL_DIR/theramab/index.html"
grep -qF 'assets/video/theramab_demo_1080p.mp4' "$TI" || abort "theramab page missing 1080p source" STAGE
grep -qF 'assets/video/theramab_demo_720p.mp4' "$TI" || abort "theramab page missing 720p source" STAGE
[[ ! -e "$NEW_REL_DIR/theramab/assets/video/theramab_demo_1080p.mp4" ]] || abort "1080p mp4 must not be in the release root" STAGE
[[ ! -e "$NEW_REL_DIR/theramab/assets/video/theramab_demo_720p.mp4" ]] || abort "720p mp4 must not be in the release root" STAGE
[[ -s "$CURRENT_ROOT/assets/ev/px.js" && -s "$NEW_REL_DIR/assets/ev/px.js" ]] || abort "clickstats px.js missing after copy" STAGE
[[ "$(sha "$NEW_REL_DIR/assets/ev/px.js")" == "$(sha "$CURRENT_ROOT/assets/ev/px.js")" ]] || abort "px.js changed in staged root" STAGE
if [[ -s "$CURRENT_ROOT/content/talent/jobs_public.json" ]]; then
  [[ "$(sha "$NEW_REL_DIR/content/talent/jobs_public.json")" == "$(sha "$CURRENT_ROOT/content/talent/jobs_public.json")" ]] || abort "jobs_public.json changed in staged root" STAGE
fi

mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
VHOST_BAK_FIXED="$BACKUP_BASE/inlightbio.cn.conf.bak.theramab_v34.$TS"
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-22 theramab_v34 deploy: web root -> $CURRENT_ROOT. Deletes nothing.
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
cp -a "$NEW_REL_DIR/rollback.sh" "$BACKUP_BASE/rollback_theramab_v34.$TS.sh"
echo "STAGE_OK" | tee -a "$LOG"

# ---------- vhost backup + alias + root switch ----------
BACKUP_CONF="${VHOST_CONF}.bak.theramab_v34.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
[[ ! -e "$VHOST_BAK_FIXED" ]] || abort "backup $VHOST_BAK_FIXED already exists" BACKUP
cp -a "$BACKUP_CONF" "$VHOST_BAK_FIXED" || abort "second vhost backup failed" BACKUP
echo "BACKUP_OK VHOST_BACKUP=$BACKUP_CONF ROLLBACK=$NEW_REL_DIR/rollback.sh" | tee -a "$LOG"

web_restore() {
  echo "RESTORING vhost from $BACKUP_CONF" | tee -a "$LOG"
  cp -a "$BACKUP_CONF" "$VHOST_CONF"
  nginx -t >>"$LOG" 2>&1 && nginx -s reload >>"$LOG" 2>&1
}
fail_restored() { echo "ERR: $1" | tee -a "$LOG"; [[ "$WEB_TOUCHED" == "1" ]] && web_restore; summary "FAIL_$2_RESTORED" | tee -a "$LOG"; exit 1; }

WEB_TOUCHED=1
python3 - "$VHOST_CONF" "$CURRENT_ROOT" "$NEW_REL_DIR" "$STATIC_DIR" <<'PY' || fail_restored "failed to insert nginx video alias" ALIAS
import os, re, sys
path, old_root, new_root, static = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
alias = static if static.endswith("/") else static + "/"
text = open(path, encoding="utf-8", errors="replace").read()
loc_re = re.compile(r"location\s+(?:\^~\s+)?/theramab/assets/video/\s*\{([^}]*)\}", re.S)
found = list(loc_re.finditer(text))
if found:
    for m in found:
        am = re.search(r"alias\s+(\S+);", m.group(1))
        if not am:
            sys.stderr.write("existing /theramab/assets/video/ location has no alias\n")
            sys.exit(1)
        got = am.group(1)
        got_n = os.path.abspath(got if got.endswith("/") else got + "/") + "/"
        want_n = os.path.abspath(alias) + "/"
        if got_n != want_n:
            sys.stderr.write("existing alias %s != %s\n" % (got, alias))
            sys.exit(1)
    open(path, "w", encoding="utf-8").write(text)
    sys.exit(0)

root_re = re.compile(r"^([ \t]*root[ \t]+)(" + re.escape(old_root) + r"|" + re.escape(new_root) + r");[ \t]*$", re.M)
hits = list(root_re.finditer(text))
if not hits:
    sys.stderr.write("no root directives for the live/new release dir\n")
    sys.exit(1)

def indent_of(line):
    m = re.match(r"([ \t]*)", line)
    return m.group(1) if m else "    "

out = []
last = 0
for m in hits:
    out.append(text[last:m.end()])
    ind = indent_of(m.group(0))
    lines = [
        "",
        ind + "location ^~ /theramab/assets/video/ {",
        ind + "    alias %s;" % alias,
        ind + "    add_header Accept-Ranges bytes;",
        ind + "}",
    ]
    out.append("\n".join(lines))
    last = m.end()
out.append(text[last:])
new = "".join(out)
if not re.search(r"location\s+\^~\s+/theramab/assets/video/", new):
    sys.stderr.write("alias insert produced no location\n")
    sys.exit(1)
open(path, "w", encoding="utf-8").write(new)
sys.exit(0)
PY

sed -i -E "s#^([[:space:]]*root[[:space:]]+)${CURRENT_ROOT};#\\1${NEW_REL_DIR};#" "$VHOST_CONF"
[[ $(grep -cE "^[[:space:]]*root[[:space:]]+${NEW_REL_DIR};" "$VHOST_CONF") -ge 1 ]] || fail_restored "root switch failed" ROOT_SWITCH
grep -qE "^[[:space:]]*root[[:space:]]+${CURRENT_ROOT};" "$VHOST_CONF" && fail_restored "old root still referenced after switch" ROOT_SWITCH
alias_ok || fail_restored "alias missing or wrong after edit" ALIAS

NT=$(nginx -t 2>&1); NRC=$?
echo "$NT" | tee -a "$LOG"
[[ $NRC -eq 0 ]] || fail_restored "nginx -t failed" NGINX_TEST
echo "NGINX_T_OK" | tee -a "$LOG"
nginx -s reload >>"$LOG" 2>&1 || fail_restored "nginx reload failed" NGINX_RELOAD
echo "NGINX_RELOAD_OK" | tee -a "$LOG"

# ---------- live verify ----------
http_get() {
  local path="$1" dest="$2"
  curl -sS --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 "${curl_resolve[@]}" -o "$dest" -w '%{http_code}' "$SITE_ORIGIN$path" || echo "000"
}

C=$(http_get "/" "$TMPD/home.html")
[[ "$C" == "200" && "$(sha "$TMPD/home.html")" == "$NEW_INDEX_SHA" ]] || fail_restored "homepage HTTP $C or sha mismatch" VERIFY_HOME
grep -qF 'TheraMab' "$TMPD/home.html" || fail_restored "live homepage lacks TheraMab nav/banner" VERIFY_HOME
grep -qF 'tmab-art' "$TMPD/home.html" || fail_restored "live homepage lacks compact banner" VERIFY_HOME
grep -qE 'fonts\.googleapis\.com|fonts\.gstatic\.com' "$TMPD/home.html" && fail_restored "live homepage still references Google Fonts" VERIFY_HOME
echo "VERIFY_HOME_OK" | tee -a "$LOG"

C=$(http_get "/theramab/" "$TMPD/tm.html")
[[ "$C" == "200" && "$(sha "$TMPD/tm.html")" == "$NEW_THERAMAB_INDEX_SHA" ]] || fail_restored "/theramab/ HTTP $C or sha mismatch" VERIFY_THERAMAB
grep -qF 'theramab_demo_1080p.mp4' "$TMPD/tm.html" || fail_restored "live /theramab/ missing 1080p source" VERIFY_THERAMAB
echo "VERIFY_THERAMAB_OK" | tee -a "$LOG"

C=$(http_get "/theramab/assets/video/theramab_demo_poster.jpg" "$TMPD/poster.jpg")
[[ "$C" == "200" && "$(sha "$TMPD/poster.jpg")" == "$POSTER_SHA" ]] || fail_restored "poster HTTP $C or sha mismatch" VERIFY_POSTER
echo "VERIFY_POSTER_OK" | tee -a "$LOG"

verify_range() {
  local path="$1"
  local hdr="$TMPD/hdr" body="$TMPD/range.body"
  local code
  code=$(curl -sS --retry 2 --connect-timeout 10 --max-time 60 "${curl_resolve[@]}" -D "$hdr" -o "$body" -w '%{http_code}' -H "Range: bytes=0-1023" "$SITE_ORIGIN$path" || echo "000")
  if [[ "$code" != "206" ]]; then
    echo "ERR: $path Range expected 206 got $code" | tee -a "$LOG"
    head -n 20 "$hdr" | tee -a "$LOG"
    return 1
  fi
  local n
  n=$(wc -c < "$body")
  [[ "$n" -eq 1024 ]] || { echo "ERR: $path Range body $n bytes, expected 1024" | tee -a "$LOG"; return 1; }
  echo "VERIFY_RANGE_OK $path HTTP 206 (1024 bytes)" | tee -a "$LOG"
  return 0
}
verify_range "/theramab/assets/video/theramab_demo_1080p.mp4" || fail_restored "1080p Range/206 failed" VERIFY_RANGE
verify_range "/theramab/assets/video/theramab_demo_720p.mp4"  || fail_restored "720p Range/206 failed" VERIFY_RANGE

H=$(curl -s -m 10 "${curl_resolve[@]}" "$SITE_ORIGIN/api/talent/health" || true)
[[ "$H" == *talent-v* ]] && echo "TALENT_API_OK (unchanged) $(printf %s "${H:0:60}" | tr -d '\r\n')" | tee -a "$LOG" || echo "WARN: talent API health did not answer (API untouched by this deploy): $(printf %s "${H:0:80}" | tr -d '\r\n')" | tee -a "$LOG"

summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
