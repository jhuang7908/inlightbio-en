#!/usr/bin/env bash
set -uo pipefail
# InLightBio CN Deploy - 2026-11-17 NewCo 第3期 series item + body teaser (p03b)
# Overlay: pages/newco-report.html only.
# Copies the live root to a NEW release dir; never deletes or edits the old root.
# Does not delete Aliyun 命令助手 commands or hidden wx-src pages.
# Writes rollback.sh in the new release dir.
# Pipe-safe: the overlay bundle is a quoted heredoc (not read from $0 or BASH_SOURCE),
# so this script behaves the same when run as a file or piped to bash.
EXPECTED_SHA256="5f3b9b7b217e63c9c6ea29933dc2c1cd2f51174abb2f9ba45831fe0a7b793c8b"
PRE_PAGE_SHA="6f5af8bd48461ca9bf9e96d6ac632b91a6045b56b5c42263a8d91704b26fdb5f"
VHOST_CONF="/www/server/panel/vhost/nginx/inlightbio.cn.conf"
NEW_REL_DIR="/www/wwwroot/inlightbio_cn_rel_20261117_b036d0a"
LOG="/var/log/inlightbio_cn_deploy_20261117_p03b.log"
WECHAT='https://mp.weixin.qq.com/s/_0pRIuCZaiB_HEskO3sGGg'
TEASER='第 3 期已发布'
TITLE='25份协议分析，便利终止全归买方'
CURRENT_ROOT=""; BACKUP_CONF=""
summary() { echo "$1 NEW_ROOT=$NEW_REL_DIR OLD_ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE"; exit 1; }
restore() { echo "ERR: $1" | tee -a "$LOG"; cp -a "$BACKUP_CONF" "$VHOST_CONF"; nginx -t >>"$LOG" 2>&1 && nginx -s reload >>"$LOG" 2>&1; summary "FAIL_$2_RESTORED"; exit 1; }
if ! { : > "$LOG"; } 2>/dev/null; then LOG=/tmp/inlightbio_cn_deploy_20261117_p03b.log; : > "$LOG"; fi
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
# Decode the embedded bundle from this heredoc (works when the script is a file or stdin).
base64 -d > "$TMPD/o.tgz" <<'__BUNDLE_BASE64__' || abort "bundle base64 decode failed" B64
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
EpKQhCQkIQlJ+H+E3wBebDv6AMgAAA==
__BUNDLE_BASE64__
[[ "$(sha256sum "$TMPD/o.tgz" | awk '{print $1}')" == "$EXPECTED_SHA256" ]] || abort "bundle sha256 mismatch" SHA256
[[ $EUID -eq 0 ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing" VHOST
CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ -n "$CURRENT_ROOT" && -d "$CURRENT_ROOT" ]] || abort "cannot find live root" LIVEROOT
[[ ! -e "$NEW_REL_DIR" ]] || abort "new release dir already exists" EXISTS
have=$(sha256sum "$CURRENT_ROOT/pages/newco-report.html" | awk '{print $1}')
[[ "$have" == "$PRE_PAGE_SHA" ]] || abort "live pages/newco-report.html differs from expected pre-P3 file ($have)" DRIFT
echo "PRE_OK"
BACKUP_CONF="${VHOST_CONF}.bak.$(date '+%Y%m%d_%H%M%S')"
[[ -e "$BACKUP_CONF" ]] && BACKUP_CONF="${BACKUP_CONF}_b"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
cp -a "$CURRENT_ROOT" "$NEW_REL_DIR" || abort "copy failed" COPY
tar -xzf "$TMPD/o.tgz" -C "$NEW_REL_DIR" --no-same-owner || abort "extract failed" EXTRACT
chown "$(stat -c '%U:%G' "$CURRENT_ROOT/pages/newco-report.html")" "$NEW_REL_DIR/pages/newco-report.html"
grep -qF "$TEASER" "$NEW_REL_DIR/pages/newco-report.html" || abort "teaser missing in staged page" STAGE
grep -qF "$TITLE" "$NEW_REL_DIR/pages/newco-report.html" || abort "P3 title missing in staged page" STAGE
grep -qF "$WECHAT" "$NEW_REL_DIR/pages/newco-report.html" || abort "公众号 URL missing in staged page" STAGE
grep -qF '连载第 1 期' "$NEW_REL_DIR/pages/newco-report.html" || abort "关于本连载 line lost" STAGE
grep -qF '交易库 v10' "$NEW_REL_DIR/pages/newco-report.html" || abort "P1 v10 reference lost" STAGE
cat > "$NEW_REL_DIR/rollback.sh" <<RB
#!/usr/bin/env bash
# Roll back the 2026-11-17 NewCo P3 report-page overlay: restore vhost backup (root -> $CURRENT_ROOT), reload nginx.
set -euo pipefail
cp -a "$BACKUP_CONF" "$VHOST_CONF"
nginx -t
nginx -s reload
echo "ROLLBACK_OK root -> $CURRENT_ROOT"
RB
chmod 700 "$NEW_REL_DIR/rollback.sh"; chown root:root "$NEW_REL_DIR/rollback.sh"
echo "STAGE_OK"
sed -i -E "s#^([[:space:]]*root[[:space:]]+)${CURRENT_ROOT};#\\1${NEW_REL_DIR};#" "$VHOST_CONF"
[[ $(grep -cE "^[[:space:]]*root[[:space:]]+${NEW_REL_DIR};" "$VHOST_CONF") -ge 1 ]] || restore "root switch failed" ROOT_SWITCH
grep -q 'nginx_api_location.conf' "$VHOST_CONF" || restore "api include missing" API_INCLUDE
nginx -t >>"$LOG" 2>&1 || restore "nginx -t failed (see $LOG)" NGINX_TEST
nginx -s reload >>"$LOG" 2>&1 || restore "nginx reload failed" NGINX_RELOAD
sleep 1
VT="$TMPD/v.html"
curl -fsS --resolve inlightbio.cn:443:127.0.0.1 "https://inlightbio.cn/" -o "$VT" >>"$LOG" 2>&1 || true
grep -qF 'msvalidate.01' "$VT" || restore "homepage Bing tag lost" VERIFY_TAG
grep -q '"@type": "Organization"' "$VT" || restore "homepage JSON-LD lost" VERIFY_JSONLD
grep -q 'id="ivonescimab-crl-feature"' "$VT" || restore "homepage CRL feature lost" VERIFY_CRL
C=$(curl -s -o /dev/null -w '%{http_code}' --resolve inlightbio.cn:443:127.0.0.1 "https://inlightbio.cn/pages/article/c1-org-1.html" || true)
[[ "$C" == "200" ]] || restore "article page HTTP $C" VERIFY_ARTICLE
RP="$TMPD/r.html"
curl -fsS --resolve inlightbio.cn:443:127.0.0.1 "https://inlightbio.cn/pages/newco-report.html" -o "$RP" >>"$LOG" 2>&1 || restore "report page fetch failed" VERIFY_REPORT
grep -qF "$TEASER" "$RP" || restore "live report lacks 第 3 期已发布 teaser" VERIFY_TEASER
grep -qF "$TITLE" "$RP" || restore "live report lacks P3 title" VERIFY_TITLE
grep -qF "$WECHAT" "$RP" || restore "live report lacks 公众号 URL" VERIFY_URL
grep -qF '第 2 期已发布' "$RP" && restore "old 第 2 期 teaser still present" VERIFY_OLD_TEASER
echo "NGINX_OK"
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
