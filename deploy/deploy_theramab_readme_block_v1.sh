#!/usr/bin/env bash
# InLightBio CN deploy — block public /theramab/README.txt, v1 (2026-11-22)
# Jing approved 屏蔽readme (do NOT delete or move the file on disk).
#
# v34e is LIVE: root /www/wwwroot/inlightbio_cn_rel_20261122_d61afa4_theramab_v34e,
# homepage sha 93af7661…, /theramab/ sha 41e6eb5e…, PR #139 merged as f475daa9.
# https://inlightbio.cn/theramab/README.txt is still HTTP 200 and contains
# internal v3.4 deploy notes (mp4 paths, nginx alias, static dir).
#
# This script is vhost-only:
#  * never deletes, moves, or overwrites theramab/README.txt (or any site file);
#  * never changes nginx `root` paths, never overlays a new release dir;
#  * backs up /www/server/panel/vhost/nginx/inlightbio.cn.conf;
#  * inserts, inside the 443 server block and the 80 server block (it serves
#    content via a site root — it is not HTTPS-only), the two one-line
#    locations:
#      location = /theramab/README.txt { return 404; }  # theramab_readme_block_v1
#      location ~* ^/theramab/(?:.*/)?(?:README[^/]*\.(?:txt|md)|.*\.md)$ { return 404; }
#  * does NOT insert after every `root` line (that was the v34c layout bug
#    that moved `listen 443` and broke ACME adjacency);
#  * logs `diff -u` (backup vs new);
#  * nginx -t && reload; sleep 1; verify with curl --resolve
#    inlightbio.cn:443:127.0.0.1, logging HTTP / sha_got / sha_expected;
#  * auto-restore the vhost on any post-edit failure (FAIL_*_RESTORED).
#  * Idempotent if the locations are already present and live README is 404
#    and the homepage sha still matches.
#
# Adding two lines to the port-80 block will move `listen 443 ssl http2`
# down from line 10 (expected; this is a deliberate location insert, not a
# root-only sed). ACME and both `root` lines stay unchanged.
#
# Run as root on the Aliyun 轻量 instance. Log: /root/deploy_theramab_readme_block_v1_<ts>.log
# Never delete/overwrite earlier release roots or their backup dirs:
#   /www/wwwroot/inlightbio_cn_rel_20261122_24d381a_theramab_v34
#   /www/wwwroot/inlightbio_cn_rel_20261122_24d381a_theramab_v34b
#   /www/wwwroot/inlightbio_cn_rel_20261122_24d381a_theramab_v34c
#   /www/wwwroot/inlightbio_cn_rel_20261122_24d381a_theramab_v34d
#   /www/wwwroot/inlightbio_cn_rel_20261122_d61afa4_theramab_v34e
#   /root/inlight_backups_20261122_theramab_v34{,b,c,d,e}/
set -uo pipefail

EXPECTED_HOME_SHA="${EXPECTED_HOME_SHA:-93af766116fc0a4c58c8aba79e6c7c184669b6ae9a8d035c89d765147a620a2a}"
EXPECTED_TM_SHA="${EXPECTED_TM_SHA:-41e6eb5e8767297ca3ceaf94cf6e917c861303954a169e725cfc1d9caeb07326}"
VHOST_CONF="${VHOST_CONF:-/www/server/panel/vhost/nginx/inlightbio.cn.conf}"
EXPECTED_ROOT="${EXPECTED_ROOT:-/www/wwwroot/inlightbio_cn_rel_20261122_d61afa4_theramab_v34e}"
BACKUP_BASE="${BACKUP_BASE:-/root/inlight_backups_20261122_theramab_readme_block_v1}"
SITE_ORIGIN="${SITE_ORIGIN:-https://inlightbio.cn}"
ALLOW_NON_ROOT="${ALLOW_NON_ROOT:-}"
PUB_TAG="${PUB_TAG:-cn-deploy-2026-11-22-theramab-readme-block-v1}"
if [[ "${CURL_RESOLVE-__unset__}" == "__unset__" ]]; then CURL_RESOLVE="inlightbio.cn:443:127.0.0.1"; fi
curl_resolve=(); [[ -n "$CURL_RESOLVE" ]] && curl_resolve=(--resolve "$CURL_RESOLVE")

TS=$(date '+%Y%m%d_%H%M%S')
LOG="${LOG:-/root/deploy_theramab_readme_block_v1_${TS}.log}"
CURRENT_ROOT=""; BACKUP_CONF=""; WEB_TOUCHED=0
README_DISK=""; README_DISK_SHA=""
summary() { echo "$1 ROOT=${CURRENT_ROOT:-?} VHOST_BACKUP=${BACKUP_CONF:-none} LOG=$LOG"; }
FINISHED=0
abort() { echo "ERR: $1" | tee -a "$LOG"; summary "FAIL_$2_NOCHANGE" | tee -a "$LOG"; FINISHED=1; exit 1; }
if ! { : >> "$LOG"; } 2>/dev/null; then LOG="/tmp/deploy_theramab_readme_block_v1_${TS}.log"; : >> "$LOG"; fi
TMPD=$(mktemp -d)
cleanup() {
  local ec=$?
  rm -rf "$TMPD"
  if [[ "$FINISHED" != "1" && "$ec" -ne 0 ]]; then
    echo "ERR: unexpected exit status $ec" | tee -a "$LOG"
    summary "FAIL_UNEXPECTED_NOCHANGE" | tee -a "$LOG"
  fi
}
trap cleanup EXIT
sha() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

echo "START theramab_readme_block_v1 $TS expected_root=$EXPECTED_ROOT" | tee -a "$LOG"
[[ $EUID -eq 0 || "$ALLOW_NON_ROOT" == "1" ]] || abort "must run as root" ROOT
[[ -f "$VHOST_CONF" ]] || abort "vhost missing: $VHOST_CONF" VHOST
NT=$(nginx -t 2>&1); NRC=$?
if [[ $NRC -ne 0 ]]; then echo "$NT" | tee -a "$LOG"; abort "nginx -t fails before any change" PRE_NGINX; fi
echo "PRE_NGINX_T_OK" | tee -a "$LOG"

CURRENT_ROOT=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | head -1 | awk '{print $2}' | tr -d ';')
[[ -n "$CURRENT_ROOT" && -d "$CURRENT_ROOT" ]] || abort "could not detect live root from $VHOST_CONF ($CURRENT_ROOT)" LIVEROOT
case "$(basename "$(dirname "$CURRENT_ROOT")")/$(basename "$CURRENT_ROOT")" in
  wwwroot/inlightbio_cn_rel_*) ;;
  *) abort "live root is not a versioned wwwroot/inlightbio_cn_rel_* dir: $CURRENT_ROOT" LIVEROOT ;;
esac
NROOTS=$(grep -E '^\s*root\s+' "$VHOST_CONF" | grep -v '#' | awk '{print $2}' | tr -d ';' | sort -u | wc -l)
[[ "$NROOTS" == "1" ]] || abort "vhost has $NROOTS distinct root values; expected 1" LIVEROOT
LIVE_INDEX_SHA=$(sha "$CURRENT_ROOT/index.html")
[[ -n "$LIVE_INDEX_SHA" ]] || abort "live index.html unreadable" LIVEROOT
[[ "$LIVE_INDEX_SHA" == "$EXPECTED_HOME_SHA" ]] || abort "live $CURRENT_ROOT/index.html sha=$LIVE_INDEX_SHA != expected v34e homepage $EXPECTED_HOME_SHA; refusing to edit vhost" DRIFT
if [[ "$CURRENT_ROOT" != "$EXPECTED_ROOT" ]]; then
  echo "WARN: live root is $CURRENT_ROOT (expected $EXPECTED_ROOT); homepage sha matches v34e, continuing" | tee -a "$LOG"
fi

# Layout notes (do not abort on shifted line numbers if the server was already
# edited once; still require the structural pieces).
L2=$(sed -n '2p' "$VHOST_CONF" || true)
L6=$(sed -n '6p' "$VHOST_CONF" || true)
L10=$(sed -n '10p' "$VHOST_CONF" || true)
echo "PRE_LAYOUT L2=$(printf %s "$L2" | tr -d '\r')" | tee -a "$LOG"
echo "PRE_LAYOUT L6=$(printf %s "$L6" | tr -d '\r')" | tee -a "$LOG"
echo "PRE_LAYOUT L10=$(printf %s "$L10" | tr -d '\r')" | tee -a "$LOG"
grep -qE '^[[:space:]]*listen[[:space:]]+80\b' "$VHOST_CONF" || abort "vhost has no listen 80" VHOST
grep -qE '^[[:space:]]*listen[[:space:]]+443\b' "$VHOST_CONF" || abort "vhost has no listen 443" VHOST
grep -qE 'location[[:space:]]+\^~[[:space:]]+/\.well-known/acme-challenge/' "$VHOST_CONF" || abort "vhost missing ACME location" VHOST
if grep -nE '^[[:space:]]*listen[[:space:]]+443' "$VHOST_CONF" | head -1 | grep -q '^10:'; then
  echo "PRE_LAYOUT_OK listen 443 is on line 10" | tee -a "$LOG"
else
  echo "WARN: listen 443 is not on line 10 (already edited?); structural checks still apply" | tee -a "$LOG"
fi

README_DISK="$CURRENT_ROOT/theramab/README.txt"
[[ -f "$README_DISK" ]] || abort "README.txt missing on disk at $README_DISK (refusing to continue; we do not create or move it)" README_DISK
README_DISK_SHA=$(sha "$README_DISK")
[[ -n "$README_DISK_SHA" ]] || abort "cannot sha README on disk" README_DISK
echo "PRE_README_DISK $README_DISK sha=$README_DISK_SHA bytes=$(wc -c < "$README_DISK" | tr -d ' ')" | tee -a "$LOG"

# Extract the inserter next to the guard (do not use `python3 -` with a stdin
# program — that is what v34b ran on the server).
INSERT_PY="$TMPD/insert_readme_block.py"
cat > "$INSERT_PY" <<'INSERT_PY_EOF'
# -*- coding: utf-8 -*-
"""Insert README-block locations into inlightbio.cn nginx vhost.

Adds, inside each content-serving server block (listen 443, and listen 80
if it has a site root), the two one-line locations:

  location = /theramab/README.txt { return 404; }  # theramab_readme_block_v1
  location ~* <README*.txt or *.md under /theramab/> { return 404; }  # theramab_readme_block_v1

Does not insert after every `root` line (that was the v34c layout bug).
Does not modify ACME, root, listen, ssl, or `location /` lines.
Idempotent: exits 0 with "ALREADY" on stdout if both blocks already have
the exact pair. Exits 2 on unexpected layout. Prints the new text on stdout
and "CHANGED" on stderr when an edit is needed.

Usage: python3 insert_readme_block.py <vhost.conf>
Writes in place when --in-place is given; otherwise prints the new file.
"""
from __future__ import print_function

import re
import sys

MARKER = "theramab_readme_block_v1"
EXACT = "  location = /theramab/README.txt { return 404; }  # theramab_readme_block_v1"
REGEX = (
    "  location ~* ^/theramab/(?:.*/)?(?:README[^/]*\\.(?:txt|md)|.*\\.md)$ "
    "{ return 404; }  # theramab_readme_block_v1"
)
BLOCK_LINES = [EXACT, REGEX]
EXACT_RE = re.compile(r"location\s+=\s+/theramab/README\.txt\s*\{")
REGEX_RE = re.compile(r"location\s+~\*?\s+\^/theramab/")
ACME_RE = re.compile(
    r"^(\s*)location\s+\^~\s+/\.well-known/acme-challenge/"
)
ROOT_BOL_RE = re.compile(r"^(\s*)root\s+\S+;")
LOCATION_SLASH_RE = re.compile(r"^(\s*)location\s+/\s*\{")
LISTEN_RE = re.compile(r"listen\s+(\S+)")


def _strip_comment(line):
    # nginx comments: unquoted #
    if "#" not in line:
        return line
    out = []
    in_s = in_d = False
    for ch in line:
        if ch == "'" and not in_d:
            in_s = not in_s
        elif ch == '"' and not in_s:
            in_d = not in_d
        elif ch == "#" and not in_s and not in_d:
            break
        out.append(ch)
    return "".join(out)


def split_server_blocks(text):
    """Return list of (start, end, block_text) for top-level server { } blocks.
    start/end are string indices into text; end is exclusive."""
    blocks = []
    i = 0
    n = len(text)
    while i < n:
        m = re.search(r"(?m)^(\s*)server\s*\{", text[i:])
        if not m:
            break
        start = i + m.start()
        brace_at = i + m.end() - 1
        depth = 1
        j = brace_at + 1
        while j < n and depth > 0:
            ch = text[j]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
            j += 1
        if depth != 0:
            raise ValueError("unbalanced braces in server block starting at %d" % start)
        blocks.append((start, j, text[start:j]))
        i = j
    return blocks


def listen_ports(block):
    ports = []
    for raw in block.splitlines():
        line = _strip_comment(raw)
        m = re.search(r"listen\s+([0-9]+)", line)
        if m:
            ports.append(int(m.group(1)))
    return ports


def has_site_root(block):
    """True if the block has a directive-at-bol root (not the ACME inline root)."""
    for raw in block.splitlines():
        if ROOT_BOL_RE.match(raw.strip() and raw or "") or ROOT_BOL_RE.match(raw):
            # ROOT_BOL_RE is ^\s*root
            if re.match(r"^\s*root\s+\S+;", raw):
                return True
    return False


def block_has_pair(block):
    return bool(EXACT_RE.search(block)) and bool(REGEX_RE.search(block) and MARKER in block)


def block_has_partial(block):
    has_e = bool(EXACT_RE.search(block))
    has_r = bool(REGEX_RE.search(block) and MARKER in block)
    return has_e != has_r or ((has_e or has_r) and not block_has_pair(block))


def needs_locations(block):
    ports = listen_ports(block)
    if 443 in ports:
        return True
    if 80 in ports and has_site_root(block):
        return True
    return False


def insert_into_block(block):
    if block_has_pair(block):
        return block, False
    if block_has_partial(block):
        raise ValueError("server block has a partial theramab_readme_block_v1 location set")
    if not block.endswith("}") and not block.rstrip().endswith("}"):
        raise ValueError("server block does not end with }")

    lines = block.splitlines(True)  # keepends
    # Work on a list of lines (with newlines). The last non-empty line should be '}'.
    # Find insertion index (into `lines`).
    acme_idx = None
    loc_slash_idx = None
    last_root_idx = None
    close_idx = None
    for i, raw in enumerate(lines):
        if ACME_RE.match(raw):
            acme_idx = i
        if LOCATION_SLASH_RE.match(raw):
            loc_slash_idx = i
        if re.match(r"^\s*root\s+\S+;", raw):
            last_root_idx = i
        stripped = raw.strip()
        if stripped == "}":
            close_idx = i
    if close_idx is None:
        raise ValueError("could not find closing } of server block")

    ports = listen_ports(block)
    if 80 in ports and 443 not in ports and acme_idx is not None:
        insert_at = acme_idx + 1
    elif loc_slash_idx is not None:
        insert_at = loc_slash_idx
    elif last_root_idx is not None:
        insert_at = last_root_idx + 1
    else:
        insert_at = close_idx

    nl = "\n"
    # preserve the file's line ending of nearby lines
    for cand in lines:
        if cand.endswith("\r\n"):
            nl = "\r\n"
            break
    new = [ln + ("" if ln.endswith(("\n", "\r\n")) else nl) for ln in BLOCK_LINES]
    out = lines[:insert_at] + new + lines[insert_at:]
    return "".join(out), True


def bol_roots(text):
    return [ln.rstrip("\r") for ln in text.splitlines() if re.match(r"^\s*root\s+\S+;", ln)]


def acme_lines(text):
    return [ln.rstrip("\r") for ln in text.splitlines() if ACME_RE.match(ln)]


def apply(text):
    if not text.endswith("\n"):
        # keep stable: nginx files usually end with newline
        pass
    blocks = split_server_blocks(text)
    if len(blocks) < 1:
        raise ValueError("no server blocks found")
    targets = [(s, e, b) for s, e, b in blocks if needs_locations(b)]
    if not targets:
        raise ValueError("no content-serving server blocks (expected listen 443 and/or listen 80 with a site root)")

    already = all(block_has_pair(b) for _, _, b in targets)
    if already:
        return text, False

    # rebuild from the end so earlier indices stay valid
    new_text = text
    changed_any = False
    for s, e, b in reversed(targets):
        nb, ch = insert_into_block(b)
        if ch:
            new_text = new_text[:s] + nb + new_text[e:]
            changed_any = True

    # post-checks
    old_roots = bol_roots(text)
    new_roots = bol_roots(new_text)
    if old_roots != new_roots:
        raise ValueError("root lines changed: %s -> %s" % (old_roots, new_roots))
    if acme_lines(text) != acme_lines(new_text):
        raise ValueError("ACME location line(s) changed")
    new_blocks = split_server_blocks(new_text)
    new_targets = [b for _, _, b in new_blocks if needs_locations(b)]
    if not new_targets or not all(block_has_pair(b) for b in new_targets):
        raise ValueError("edit did not leave the location pair in every content-serving block")
    # Must not have slipped a video alias in.
    if re.search(r"location\s+(\^~\s+)?/theramab/assets/video/", new_text) and not re.search(
        r"location\s+(\^~\s+)?/theramab/assets/video/", text
    ):
        raise ValueError("edit unexpectedly added a /theramab/assets/video/ location")
    return new_text, changed_any


def main(argv):
    in_place = False
    args = []
    for a in argv[1:]:
        if a == "--in-place":
            in_place = True
        else:
            args.append(a)
    if len(args) != 1:
        print("usage: insert_readme_block.py [--in-place] <vhost.conf>", file=sys.stderr)
        return 2
    path = args[0]
    text = open(path, "r", encoding="utf-8", errors="replace").read()
    try:
        new_text, changed = apply(text)
    except ValueError as e:
        print("ERR: %s" % e, file=sys.stderr)
        return 2
    if not changed:
        print("ALREADY", file=sys.stderr)
        if not in_place:
            sys.stdout.write(new_text)
        return 0
    if in_place:
        tmp = path + ".readme_block_v1.tmp"
        with open(tmp, "w", encoding="utf-8", newline="") as f:
            f.write(new_text)
        import os
        os.replace(tmp, path)
        print("CHANGED", file=sys.stderr)
        return 0
    sys.stdout.write(new_text)
    print("CHANGED", file=sys.stderr)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(2)

INSERT_PY_EOF
# syntax check the extracted inserter before any vhost edit
python3 -m py_compile "$INSERT_PY" || abort "embedded insert_readme_block.py failed to compile" PRE

vhost_already() {
  python3 "$INSERT_PY" "$VHOST_CONF" >/dev/null 2>"$TMPD/insert_already.err"
  local rc=$?
  if [[ $rc -eq 0 ]] && grep -q ALREADY "$TMPD/insert_already.err"; then
    return 0
  fi
  return 1
}

# ---------- live helpers (used by idempotent + post-reload verify) ----------
verify_curl() {
  curl -sS --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 \
    "${curl_resolve[@]}" \
    -H "Accept-Encoding: identity" \
    -D "$3" -o "$2" -w '%{http_code}' \
    "$SITE_ORIGIN$1" || echo "000"
}
log_hdr() {
  echo "----- response headers ($1) -----" | tee -a "$LOG"
  head -n 25 "$2" | tr -d '\r' | tee -a "$LOG" || true
}

# Probe current live README (best-effort, before any change).
C_PRE=$(verify_curl "/theramab/README.txt" "$TMPD/readme_pre.txt" "$TMPD/readme_pre.hdr")
echo "PRE_README HTTP=$C_PRE disk_sha=$README_DISK_SHA" | tee -a "$LOG"

if vhost_already && [[ "$C_PRE" == "404" && "$LIVE_INDEX_SHA" == "$EXPECTED_HOME_SHA" && -f "$README_DISK" && "$(sha "$README_DISK")" == "$README_DISK_SHA" ]]; then
  echo "IDEMPOTENT already blocked (vhost has theramab_readme_block_v1, README HTTP 404, file still on disk)" | tee -a "$LOG"
  echo "BACKUP_OK (no change; already live)" | tee -a "$LOG"
  FINISHED=1
  summary "DEPLOY_OK" | tee -a "$LOG"
  exit 0
fi
if vhost_already && [[ "$C_PRE" != "404" ]]; then
  abort "vhost already has theramab_readme_block_v1 locations but live README HTTP=$C_PRE (expected 404); refusing to guess" DRIFT
fi

echo "PRE_OK ROOT=$CURRENT_ROOT LIVE_INDEX_SHA=$LIVE_INDEX_SHA README_HTTP=$C_PRE" | tee -a "$LOG"

# staged edit in a copy first (so a failed insert cannot half-write the live vhost)
cp -a "$VHOST_CONF" "$TMPD/vhost.staged"
python3 "$INSERT_PY" --in-place "$TMPD/vhost.staged" >"$TMPD/insert_out.txt" 2>"$TMPD/insert_err.txt" || {
  echo "----- inserter stdout -----" | tee -a "$LOG"
  cat "$TMPD/insert_out.txt" 2>/dev/null | tee -a "$LOG" || true
  echo "----- inserter stderr -----" | tee -a "$LOG"
  cat "$TMPD/insert_err.txt" 2>/dev/null | tee -a "$LOG" || true
  abort "vhost insert failed: $(head -n 1 "$TMPD/insert_err.txt" 2>/dev/null | tr -d '\r')" INSERT
}
if ! grep -q CHANGED "$TMPD/insert_err.txt"; then
  echo "----- inserter stderr -----" | tee -a "$LOG"
  cat "$TMPD/insert_err.txt" | tee -a "$LOG"
  abort "inserter did not report CHANGED (and idempotent path did not fire)" INSERT
fi
# Confirm the staged file differs only by the new location lines.
if diff -q "$VHOST_CONF" "$TMPD/vhost.staged" >/dev/null; then
  abort "staged vhost is identical to live after a CHANGED insert" INSERT
fi
grep -qF 'location = /theramab/README.txt' "$TMPD/vhost.staged" || abort "staged vhost missing exact README location" INSERT
grep -qF 'theramab_readme_block_v1' "$TMPD/vhost.staged" || abort "staged vhost missing marker" INSERT
# Each content-serving block should have the pair (count exact-match locations: 2)
NEXACT=$(grep -cE '^[[:space:]]*location[[:space:]]+=[[:space:]]+/theramab/README\.txt' "$TMPD/vhost.staged" || true)
[[ "$NEXACT" == "2" ]] || abort "staged vhost has $NEXACT exact README locations, expected 2 (port 80 + port 443)" INSERT

mkdir -p "$BACKUP_BASE" && chmod 700 "$BACKUP_BASE"
VHOST_BAK_FIXED="$BACKUP_BASE/inlightbio.cn.conf.bak.theramab_readme_block_v1.$TS"
cat > "$BACKUP_BASE/rollback_theramab_readme_block_v1.$TS.sh" <<RB
#!/usr/bin/env bash
# Roll back 2026-11-22 theramab_readme_block_v1: restore vhost. Deletes nothing. Does not touch site files.
set -euo pipefail
V="${VHOST_CONF}"
TS=\$(date '+%Y%m%d_%H%M%S')
cp -a "\$V" "$BACKUP_BASE/inlightbio.cn.conf.before_rollback.\$TS"
if [[ -s "$VHOST_BAK_FIXED" ]]; then
  cp -a "$VHOST_BAK_FIXED" "\$V"
else
  echo "backup $VHOST_BAK_FIXED missing"
  exit 1
fi
NT=\$(nginx -t 2>&1); RC=\$?
echo "\$NT"
if [[ \$RC -ne 0 ]]; then
  echo "nginx -t failed after rollback edit"
  exit 1
fi
nginx -s reload || exit 1
echo "ROLLBACK_OK vhost restored; README.txt on disk was not moved"
RB
chmod 700 "$BACKUP_BASE/rollback_theramab_readme_block_v1.$TS.sh"
[[ "$ALLOW_NON_ROOT" == "1" ]] || chown root:root "$BACKUP_BASE/rollback_theramab_readme_block_v1.$TS.sh" 2>/dev/null || true
echo "STAGE_OK staged vhost insert (file on disk untouched)" | tee -a "$LOG"

# ---------- vhost backup + install staged edit ----------
BACKUP_CONF="${VHOST_CONF}.bak.theramab_readme_block_v1.$TS"
[[ -e "$BACKUP_CONF" ]] && { BACKUP_CONF=""; abort "vhost backup name exists" BACKUP; }
cp -a "$VHOST_CONF" "$BACKUP_CONF" || { BACKUP_CONF=""; abort "vhost backup failed" BACKUP; }
[[ ! -e "$VHOST_BAK_FIXED" ]] || abort "backup $VHOST_BAK_FIXED already exists" BACKUP
cp -a "$BACKUP_CONF" "$VHOST_BAK_FIXED" || abort "second vhost backup failed" BACKUP
echo "BACKUP_OK VHOST_BACKUP=$BACKUP_CONF ROLLBACK=$BACKUP_BASE/rollback_theramab_readme_block_v1.$TS.sh" | tee -a "$LOG"

web_restore() {
  echo "RESTORING vhost from $BACKUP_CONF" | tee -a "$LOG"
  cp -a "$BACKUP_CONF" "$VHOST_CONF"
  nginx -t >>"$LOG" 2>&1 && nginx -s reload >>"$LOG" 2>&1
}
fail_restored() { echo "ERR: $1" | tee -a "$LOG"; [[ "$WEB_TOUCHED" == "1" ]] && web_restore; summary "FAIL_$2_RESTORED" | tee -a "$LOG"; FINISHED=1; exit 1; }

WEB_TOUCHED=1
cp -a "$TMPD/vhost.staged" "$VHOST_CONF" || fail_restored "installing staged vhost failed" VHOST_INSTALL

echo "===== VHOST_DIFF (old vs new) =====" | tee -a "$LOG"
if diff -u "$BACKUP_CONF" "$VHOST_CONF" >"$TMPD/vhost.diff"; then
  fail_restored "vhost diff is empty after insert" VHOST_EDIT
fi
cat "$TMPD/vhost.diff" | tee -a "$LOG"
echo "===== VHOST_LINES after edit =====" | tee -a "$LOG"
nl -ba "$VHOST_CONF" | tee -a "$LOG"

# Structural guards (roots + ACME unchanged; no unexpected video-alias).
if ! diff -q <(grep -E '^[[:space:]]*root[[:space:]]+' "$BACKUP_CONF" | grep -v '#') \
             <(grep -E '^[[:space:]]*root[[:space:]]+' "$VHOST_CONF" | grep -v '#') >/dev/null; then
  fail_restored "root directive line(s) changed" VHOST_LAYOUT
fi
if grep -qE 'location[[:space:]]+\^~[[:space:]]+/\.well-known/acme-challenge/' "$BACKUP_CONF"; then
  if ! diff -q <(grep -E 'location[[:space:]]+\^~[[:space:]]+/\.well-known/acme-challenge/' "$BACKUP_CONF") \
               <(grep -E 'location[[:space:]]+\^~[[:space:]]+/\.well-known/acme-challenge/' "$VHOST_CONF") >/dev/null; then
    fail_restored "ACME location line changed" VHOST_LAYOUT
  fi
fi
if ! grep -qE 'location[[:space:]]+(\^~[[:space:]]+)?/theramab/assets/video/' "$BACKUP_CONF"; then
  if grep -qE 'location[[:space:]]+(\^~[[:space:]]+)?/theramab/assets/video/' "$VHOST_CONF"; then
    fail_restored "vhost unexpectedly gained a /theramab/assets/video/ location" VHOST_LAYOUT
  fi
fi
# Added lines should be only the README-block locations (and we added 2 per
# content-serving server = 4 lines on the standard 80+443 vhost).
NOLD=$(wc -l < "$BACKUP_CONF" | tr -d "[:space:]")
NNOW=$(wc -l < "$VHOST_CONF" | tr -d "[:space:]")
NADDED=$((NNOW - NOLD))
echo "VHOST_LINE_DELTA $NOLD -> $NNOW (added $NADDED)" | tee -a "$LOG"
[[ "$NADDED" == "4" ]] || fail_restored "expected to add exactly 4 lines (2 locations × 2 server blocks), added $NADDED" VHOST_LAYOUT
# listen 443 may move down by 2 (the two lines inserted in the port-80 block).
L_BEFORE=$(grep -nE '^[[:space:]]*listen[[:space:]]+443' "$BACKUP_CONF" | head -1 | cut -d: -f1)
L_AFTER=$(grep -nE '^[[:space:]]*listen[[:space:]]+443' "$VHOST_CONF" | head -1 | cut -d: -f1)
[[ -n "$L_BEFORE" && -n "$L_AFTER" ]] || fail_restored "listen 443 line missing after edit" VHOST_LAYOUT
echo "LISTEN_443_LINE $L_BEFORE -> $L_AFTER" | tee -a "$LOG"
# File on disk must still be in place with the same sha (we never touch it).
[[ -f "$README_DISK" && "$(sha "$README_DISK")" == "$README_DISK_SHA" ]] || fail_restored "README.txt on disk was changed or removed; this script must not touch it" README_DISK

NT=$(nginx -t 2>&1); NRC=$?
echo "$NT" | tee -a "$LOG"
[[ $NRC -eq 0 ]] || fail_restored "nginx -t failed" NGINX_TEST
echo "NGINX_T_OK" | tee -a "$LOG"
nginx -s reload >>"$LOG" 2>&1 || fail_restored "nginx reload failed" NGINX_RELOAD
echo "NGINX_RELOAD_OK" | tee -a "$LOG"

# ---------- live verify ----------
sleep 1

ok=0
C="000"; GOT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/" "$TMPD/home.html" "$TMPD/home.hdr")
  GOT=$(sha "$TMPD/home.html")
  CE=$(grep -i '^content-encoding:' "$TMPD/home.hdr" 2>/dev/null | tr -d '\r' | head -1 || true)
  echo "VERIFY_HOME_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$EXPECTED_HOME_SHA ${CE:-Content-Encoding: (none)}" | tee -a "$LOG"
  log_hdr "GET / try $try" "$TMPD/home.hdr"
  if [[ "$C" == "200" && "$GOT" == "$EXPECTED_HOME_SHA" ]]; then
    ok=1
    break
  fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "homepage HTTP $C sha_got=${GOT:-empty} sha_expected=$EXPECTED_HOME_SHA" VERIFY_HOME
echo "VERIFY_HOME_OK HTTP=$C sha=$GOT expected=$EXPECTED_HOME_SHA" | tee -a "$LOG"

ok=0
C="000"; GOT=""
for try in 1 2 3 4 5; do
  C=$(verify_curl "/theramab/" "$TMPD/tm.html" "$TMPD/tm.hdr")
  GOT=$(sha "$TMPD/tm.html")
  CE=$(grep -i '^content-encoding:' "$TMPD/tm.hdr" 2>/dev/null | tr -d '\r' | head -1 || true)
  echo "VERIFY_THERAMAB_TRY $try HTTP=$C sha_got=${GOT:-empty} sha_expected=$EXPECTED_TM_SHA ${CE:-Content-Encoding: (none)}" | tee -a "$LOG"
  log_hdr "GET /theramab/ try $try" "$TMPD/tm.hdr"
  if [[ "$C" == "200" && "$GOT" == "$EXPECTED_TM_SHA" ]]; then
    ok=1
    break
  fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "/theramab/ HTTP $C sha_got=${GOT:-empty} sha_expected=$EXPECTED_TM_SHA" VERIFY_THERAMAB
echo "VERIFY_THERAMAB_OK HTTP=$C sha=$GOT expected=$EXPECTED_TM_SHA" | tee -a "$LOG"

ok=0
C="000"
for try in 1 2 3 4 5; do
  C=$(verify_curl "/theramab/README.txt" "$TMPD/readme.txt" "$TMPD/readme.hdr")
  echo "VERIFY_README_TRY $try HTTP=$C sha_got=$(sha "$TMPD/readme.txt" || echo empty) (expect HTTP 404; file on disk sha=$README_DISK_SHA)" | tee -a "$LOG"
  log_hdr "GET /theramab/README.txt try $try" "$TMPD/readme.hdr"
  if [[ "$C" == "404" ]]; then
    # Body must not be the on-disk README.
    if [[ -s "$TMPD/readme.txt" && "$(sha "$TMPD/readme.txt")" == "$README_DISK_SHA" ]]; then
      echo "ERR: 404 body is still the on-disk README" | tee -a "$LOG"
    else
      ok=1
      break
    fi
  fi
  sleep 2
done
[[ "$ok" == "1" ]] || fail_restored "README HTTP $C (expected 404); file still on disk sha=$README_DISK_SHA" VERIFY_README
echo "VERIFY_README_OK HTTP=$C (blocked); disk unchanged sha=$README_DISK_SHA" | tee -a "$LOG"

# Broader deny: a not-present .md under /theramab/ should also 404 (not 200).
C=$(verify_curl "/theramab/README.md" "$TMPD/readme.md" "$TMPD/readme_md.hdr")
echo "VERIFY_README_MD HTTP=$C" | tee -a "$LOG"
[[ "$C" == "404" ]] || fail_restored "/theramab/README.md HTTP $C (expected 404)" VERIFY_README
echo "VERIFY_README_MD_OK HTTP=$C" | tee -a "$LOG"

# File still on disk after verify.
[[ -f "$README_DISK" && "$(sha "$README_DISK")" == "$README_DISK_SHA" ]] || fail_restored "README.txt on disk changed during verify" README_DISK
echo "VERIFY_README_DISK_OK $README_DISK sha=$README_DISK_SHA" | tee -a "$LOG"

FINISHED=1
summary "DEPLOY_OK" | tee -a "$LOG"
exit 0
