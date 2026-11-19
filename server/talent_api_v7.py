#!/usr/bin/env python3
"""v7 talent/partner intake on top of the unchanged v6e whitepaper extension.

Adds, in the same inlight-newsletter-api process (127.0.0.1:8787):
  POST /api/talent/cv        multipart/form-data, PDF/DOC/DOCX <= 10MB, mailed as attachment to TALENT_CV_TO
  POST /api/partner-contact  JSON <= 8KB (employer / investor contact), mailed to PARTNER_CONTACT_TO
  GET  /api/talent/health    liveness (no personal data)
Everything else is delegated to the v6e handler (whitepaper + newsletter v3 routes).
Python 3.6+ / stdlib only. Mail is sent through v3 common_v2.Mailer() (Aliyun DirectMail, same SMTP/password config);
MIME is built locally with the same headers as common_v2.build_message() plus attachment and Reply-To.
"""
import contextlib, hashlib, hmac, html, json, os, re, secrets, sqlite3, sys, threading, time, zipfile, io
from urllib.parse import urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import whitepaper_api_v6 as wp  # noqa: E402  (copied, unmodified v6e module in this directory)

DATA_DIR = os.environ.get('TALENT_DATA_DIR', '/opt/inlight-newsletter/talent_data_v7_20261119')
CV_TO = os.environ.get('TALENT_CV_TO', 'contact@inlightbio.com')
PARTNER_TO = os.environ.get('PARTNER_CONTACT_TO', 'contact@inlightbio.com')
MAX_FILE = 10 * 1024 * 1024
MAX_BODY = MAX_FILE + 256 * 1024
MAX_JSON = 8192
DRAIN_MAX = 13 * 1024 * 1024
MAX_ATTEMPTS = 8
AUDIT_DAYS = 30
EMAIL_RE = wp.EMAIL_RE
CODE_RE = re.compile(r'^[A-Z]{2}-\d{3}$')
CTRL_RE = re.compile(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]')
BOUNDARY_RE = re.compile(r"^[0-9A-Za-z'()+_,\-./:=? ]{1,70}$")
OLE = b'\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1'
MIME = {'.pdf': ('application', 'pdf'), '.doc': ('application', 'msword'),
        '.docx': ('application', 'vnd.openxmlformats-officedocument.wordprocessingml.document')}


def _int_env(name, default):
    try: return int(os.environ.get(name, default))
    except ValueError: return default

LIMITS = {  # (per ip per hour, per email per day, global per hour)
    'cv': (_int_env('TALENT_CV_IP_HOUR', 3), _int_env('TALENT_CV_EMAIL_DAY', 2), _int_env('TALENT_CV_GLOBAL_HOUR', 30)),
    'partner': (_int_env('PARTNER_IP_HOUR', 5), _int_env('PARTNER_EMAIL_DAY', 3), _int_env('PARTNER_GLOBAL_HOUR', 40)),
}


class Bad(ValueError):
    pass


def clean(v, n, required=False, label='', multiline=False):
    v = ('' if v is None else str(v)).strip()
    if multiline: v = v.replace('\r\n', '\n')
    if CTRL_RE.search(v) or (not multiline and ('\n' in v or '\r' in v)): raise Bad('{}含有不支持的字符'.format(label))
    if required and not v: raise Bad('请填写{}'.format(label))
    if len(v) > n: raise Bad('{}过长'.format(label))
    return v


def check_email(v):
    v = clean(v, 120, True, '邮箱')
    if not EMAIL_RE.match(v): raise Bad('邮箱格式不正确')
    return v


def truthy(v):
    return v is True or str(v).strip().lower() in ('1', 'true', 'on', 'yes')


def file_kind(filename, data):
    ext = os.path.splitext(filename or '')[1].lower()
    if ext not in MIME: raise Bad('仅支持 PDF、DOC、DOCX 格式')
    if not data: raise Bad('文件为空')
    if len(data) > MAX_FILE: raise Bad('文件超过 10MB')
    if ext == '.pdf' and data[:5] == b'%PDF-': return ext
    if ext == '.doc' and data[:8] == OLE: return ext
    if ext == '.docx' and data[:4] == b'PK\x03\x04':
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as z:
                names = set(z.namelist())
        except (zipfile.BadZipFile, ValueError, OSError):
            raise Bad('文件内容与格式不符')
        if 'word/document.xml' in names and '[Content_Types].xml' in names and 'word/vbaProject.bin' not in names:
            return ext
    raise Bad('文件内容与格式不符')


def safe_filename(name, ext):
    base = os.path.basename((name or '').replace('\\', '/'))
    base = CTRL_RE.sub('', base).replace('"', '').replace('\r', '').replace('\n', '').strip() or 'resume'
    stem = os.path.splitext(base)[0][:80].strip() or 'resume'
    return stem + ext


def parse_multipart(ctype, body):
    m = re.search(r'boundary=(?:"([^"]+)"|([^;\s]+))', ctype or '', re.I)
    if not m: raise Bad('请求格式错误')
    boundary = (m.group(1) or m.group(2))
    if not BOUNDARY_RE.match(boundary): raise Bad('请求格式错误')
    delim = b'--' + boundary.encode('ascii')
    pos = body.find(delim)
    if pos < 0: raise Bad('请求格式错误')
    pos += len(delim)
    fields, files, count = {}, {}, 0
    while True:
        if body[pos:pos + 2] == b'--': break
        if body[pos:pos + 2] != b'\r\n': raise Bad('请求格式错误')
        pos += 2
        nxt = body.find(b'\r\n' + delim, pos)
        if nxt < 0: raise Bad('请求格式错误')
        part = body[pos:nxt]; pos = nxt + 2 + len(delim)
        count += 1
        if count > 20: raise Bad('请求格式错误')
        hend = part.find(b'\r\n\r\n')
        if hend < 0 or hend > 8192: raise Bad('请求格式错误')
        head = part[:hend].decode('utf-8', 'replace'); content = part[hend + 4:]
        disp = ''
        for line in head.split('\r\n'):
            if line.lower().startswith('content-disposition:'): disp = line.split(':', 1)[1]
        nm = re.search(r'(?:^|;)\s*name="([^"]*)"', disp)
        if not nm: continue
        fn = re.search(r'(?:^|;)\s*filename="([^"]*)"', disp)
        if fn is not None:
            files[nm.group(1)] = (fn.group(1), content)
        else:
            if len(content) > 4096: raise Bad('字段过长')
            fields[nm.group(1)] = content.decode('utf-8', 'replace')
    return fields, files


class TalentStore:
    def __init__(self, directory, now=time.time):
        self.directory, self.now = directory, now
        os.makedirs(directory, mode=0o700, exist_ok=True)
        self.spool = os.path.join(directory, 'spool')
        os.makedirs(self.spool, mode=0o700, exist_ok=True)
        os.chmod(directory, 0o700); os.chmod(self.spool, 0o700)
        self.database = os.path.join(directory, 'talent.sqlite3')
        self.lock = threading.Lock()
        keyf = os.path.join(directory, 'hash.key')
        if not os.path.exists(keyf):
            fd = os.open(keyf, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, 'w') as f: f.write(secrets.token_hex(32))
        with open(keyf) as f: self.key = f.read().strip().encode()
        with self.db() as c:
            c.executescript('''
            CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, kind TEXT NOT NULL, created REAL NOT NULL,
                ip_hash TEXT NOT NULL, email_hash TEXT NOT NULL, target TEXT, file_sha256 TEXT, file_size INTEGER);
            CREATE INDEX IF NOT EXISTS ev_ip ON events(kind, ip_hash, created);
            CREATE INDEX IF NOT EXISTS ev_email ON events(kind, email_hash, created);
            CREATE TABLE IF NOT EXISTS outbox (id INTEGER PRIMARY KEY, event_id TEXT, kind TEXT NOT NULL,
                recipient TEXT NOT NULL, reply_to TEXT, subject TEXT NOT NULL, text TEXT NOT NULL, html TEXT NOT NULL,
                attach_path TEXT, attach_name TEXT, attach_ext TEXT,
                status TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
                next_at REAL NOT NULL, last_error TEXT, created REAL NOT NULL);
            ''')
        os.chmod(self.database, 0o600)

    @contextlib.contextmanager
    def db(self):
        c = sqlite3.connect(self.database, timeout=10)
        c.row_factory = sqlite3.Row
        try:
            yield c
            c.commit()
        except BaseException:
            c.rollback(); raise
        finally:
            c.close()

    def h(self, v):
        return hmac.new(self.key, v.strip().lower().encode('utf-8'), hashlib.sha256).hexdigest()

    def write_spool(self, data):
        p = os.path.join(self.spool, secrets.token_hex(16) + '.bin')
        fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'wb') as f: f.write(data)
        return p

    def enqueue(self, kind, ip, email, mail, target=None, data=None, ext=None, attach_name=None):
        """Rate-limit + record + queue. Returns event id or None when limited."""
        now = self.now(); per_ip, per_email, glob = LIMITS[kind]
        iph, emh = self.h(ip), self.h(email)
        with self.lock:
            with self.db() as c:
                c.execute('DELETE FROM events WHERE created<?', (now - AUDIT_DAYS * 86400,))
                n_ip = c.execute('SELECT COUNT(*) FROM events WHERE kind=? AND ip_hash=? AND created>?', (kind, iph, now - 3600)).fetchone()[0]
                n_em = c.execute('SELECT COUNT(*) FROM events WHERE kind=? AND email_hash=? AND created>?', (kind, emh, now - 86400)).fetchone()[0]
                n_gl = c.execute('SELECT COUNT(*) FROM events WHERE kind=? AND created>?', (kind, now - 3600)).fetchone()[0]
                if n_ip >= per_ip or n_em >= per_email or n_gl >= glob:
                    return None
                path = self.write_spool(data) if data is not None else None
                eid = secrets.token_hex(12)
                try:
                    c.execute('INSERT INTO events VALUES (?,?,?,?,?,?,?,?)', (eid, kind, now, iph, emh, target or '',
                              hashlib.sha256(data).hexdigest() if data is not None else None, len(data) if data is not None else None))
                    c.execute('INSERT INTO outbox (event_id,kind,recipient,reply_to,subject,text,html,attach_path,attach_name,attach_ext,next_at,created) '
                              'VALUES (?,?,?,?,?,?,?,?,?,?,?,?)', (eid, kind, mail['to'], mail['reply_to'], mail['subject'], mail['text'],
                              mail['html'], path, attach_name, ext, now, now))
                except BaseException:
                    if path and os.path.exists(path): os.remove(path)
                    raise
                return eid


def mail_parts(title, rows, extra=''):
    text = title + '\n\n' + '\n'.join('{}：{}'.format(k, v) for k, v in rows) + ('\n\n' + extra if extra else '')
    body = ''.join('<tr><td style="padding:4px 12px 4px 0;color:#555;white-space:nowrap">{}</td><td style="padding:4px 0">{}</td></tr>'.format(
        html.escape(k), html.escape(v).replace('\n', '<br>')) for k, v in rows)
    htm = ('<div style="font-family:Arial,sans-serif;line-height:1.7"><p style="color:#2E6B4F;font-weight:bold">{}</p>'
           '<table style="border-collapse:collapse">{}</table>{}</div>').format(html.escape(title), body,
           '<p style="color:#666">{}</p>'.format(html.escape(extra)) if extra else '')
    return text, htm


class TalentService:
    def __init__(self, store, common):
        self.store, self.common = store, common
        self.wakeup = threading.Event()
        self.delivery_lock = threading.Lock()

    def stamp(self):
        return time.strftime('%Y-%m-%d %H:%M', time.localtime(self.store.now()))

    def submit_cv(self, fields, files, ip):
        try:
            if fields.get('website', '').strip(): return 202, {'ok': True, 'status': 'queued'}  # honeypot: silently drop
            try:
                if int(fields.get('elapsed_ms', '99999')) < 1500: return 202, {'ok': True, 'status': 'queued'}
            except ValueError:
                pass
            name = clean(fields.get('name'), 40, True, '姓名')
            email = check_email(fields.get('email'))
            wechat = clean(fields.get('wechat'), 40, False, '微信号')
            target = clean(fields.get('target'), 10, False, '目标职位')
            if target and not CODE_RE.match(target): raise Bad('目标职位编号无效')
            if not truthy(fields.get('consent')): raise Bad('请勾选同意项')
            if 'cv' not in files: raise Bad('请上传简历文件')
            fname, data = files['cv']
            ext = file_kind(fname, data)
        except Bad as e:
            return 400, {'ok': False, 'error': str(e)}
        att = safe_filename(fname, ext)
        rows = [('提交时间', self.stamp() + '（北京时间）'), ('目标职位', target or '暂无具体职位（仅登记简历）'), ('姓名', name), ('邮箱', email),
                ('微信号', wechat or '未填写'), ('同意项', '已勾选：同意 InLight 保存并用于职位推荐'),
                ('附件', '{}（{:.1f} KB）'.format(att, len(data) / 1024.0)), ('来源', '启光英才 inlightbio.cn/#talent')]
        text, htm = mail_parts('新的启光英才简历投递', rows, '直接回复本邮件即可联系投递者。')
        mail = {'to': CV_TO, 'reply_to': email, 'subject': 'InLight｜启光英才简历：{} · {}'.format(name, target or '仅登记简历'), 'text': text, 'html': htm}
        try:
            eid = self.store.enqueue('cv', ip, email, mail, target, data, ext, att)
        except (OSError, sqlite3.Error):
            return 503, {'ok': False, 'error': '服务暂时不可用，请稍后重试。'}
        if eid is None: return 429, {'ok': False, 'error': '提交过于频繁，请稍后再试。'}
        self.wakeup.set()
        return 202, {'ok': True, 'status': 'queued', 'message': '已提交，启光专人将尽快联系您。'}

    def submit_partner(self, d, ip):
        try:
            if not isinstance(d, dict): raise Bad('请求格式错误')
            if str(d.get('website') or '').strip(): return 202, {'ok': True, 'status': 'queued'}
            try:
                if int(d.get('elapsed_ms', 99999)) < 1500: return 202, {'ok': True, 'status': 'queued'}
            except (ValueError, TypeError):
                pass
            kind = d.get('kind')
            if kind not in ('employer', 'investor'): raise Bad('请求格式错误')
            org = clean(d.get('org'), 80, True, '机构名称')
            contact = clean(d.get('contact'), 40, True, '联系人')
            email = check_email(d.get('email'))
            wechat = clean(d.get('wechat'), 40, False, '微信号')
            note = clean(d.get('note'), 500, True, '简短说明', multiline=True)
            if not truthy(d.get('consent')): raise Bad('请勾选同意项')
        except Bad as e:
            return 400, {'ok': False, 'error': str(e)}
        label = '启光英才 · 用人单位发布职位' if kind == 'employer' else '启光资方 · 投资机构联系'
        rows = [('提交时间', self.stamp() + '（北京时间）'), ('类型', label), ('机构名称', org), ('联系人', contact), ('邮箱', email),
                ('微信号', wechat or '未填写'), ('简短说明', note), ('来源', 'inlightbio.cn/#' + ('talent' if kind == 'employer' else 'fund'))]
        text, htm = mail_parts('新的' + label + '留言', rows, '直接回复本邮件即可联系对方。')
        mail = {'to': PARTNER_TO, 'reply_to': email, 'subject': 'InLight｜{}：{}'.format(label, org), 'text': text, 'html': htm}
        try:
            eid = self.store.enqueue('partner', ip, email, mail, kind)
        except (OSError, sqlite3.Error):
            return 503, {'ok': False, 'error': '服务暂时不可用，请稍后重试。'}
        if eid is None: return 429, {'ok': False, 'error': '提交过于频繁，请稍后再试。'}
        self.wakeup.set()
        return 202, {'ok': True, 'status': 'queued', 'message': '已提交，启光专人将尽快与您联系。'}

    def _drop_file(self, path):
        if path:
            try: os.remove(path)
            except OSError: pass

    def deliver_due(self):
        st = self.store
        with self.delivery_lock:
            with st.db() as c:
                rows = c.execute("SELECT * FROM outbox WHERE status='pending' AND next_at<=? ORDER BY id LIMIT 30", (st.now(),)).fetchall()
            for row in rows:
                try:
                    att = None
                    if row['attach_path']:
                        with open(row['attach_path'], 'rb') as f: att = (f.read(), row['attach_ext'], row['attach_name'])
                    msg = build_mail(self.common, row['recipient'], row['subject'], row['html'], row['text'], row['reply_to'], att)
                    with self.common.Mailer() as mailer:
                        mailer.send(msg)
                except (Exception, SystemExit) as error:
                    attempts = row['attempts'] + 1
                    final = attempts >= MAX_ATTEMPTS or isinstance(error, FileNotFoundError)
                    delay = min(3600, 60 * (2 ** min(attempts - 1, 6)))
                    with st.db() as c:
                        c.execute("UPDATE outbox SET attempts=?, next_at=?, last_error=?, status=? WHERE id=?",
                                  (attempts, st.now() + delay, type(error).__name__, 'failed' if final else 'pending', row['id']))
                    print('talent mail retry; outbox_id={} attempts={}{}'.format(row['id'], attempts, ' FINAL' if final else ''), file=sys.stderr, flush=True)
                    if final:
                        self._drop_file(row['attach_path'])
                        if row['kind'] != 'alert':
                            self._alert(row)
                else:
                    self._drop_file(row['attach_path'])
                    with st.db() as c:  # keep only minimal audit; scrub personal data from the queue row
                        c.execute("UPDATE outbox SET status='sent', last_error=NULL, text='', html='', reply_to=NULL, "
                                  "subject='[sent]', attach_path=NULL, attach_name=NULL WHERE id=?", (row['id'],))

    def _alert(self, row):
        text = ('一封「{}」通知邮件多次发送失败，服务器上的临时附件已删除。\n请求编号：{}\n投递者邮箱：{}\n请直接联系对方补发。').format(
            '简历' if row['kind'] == 'cv' else '联系留言', row['event_id'], row['reply_to'] or '未知')
        now = self.store.now()
        with self.store.db() as c:
            c.execute('INSERT INTO outbox (event_id,kind,recipient,reply_to,subject,text,html,next_at,created) VALUES (?,?,?,?,?,?,?,?,?)',
                      (row['event_id'], 'alert', row['recipient'], None, 'InLight｜站内投递发送失败提醒', text,
                       '<pre style="font-family:Arial,sans-serif">' + html.escape(text) + '</pre>', now, now))

    def worker(self):
        while True:
            try:
                self.deliver_due()
            except Exception:
                print('talent worker storage error; retrying', file=sys.stderr, flush=True)
            self.wakeup.wait(5)
            self.wakeup.clear()


def build_mail(common, to, subject, html_body, text, reply_to=None, attachment=None):
    """Same headers as v3 common_v2.build_message(), built with the compat32 MIME classes.
    (On Python 3.6 the EmailMessage/policy.SMTP path folds a non-ASCII From display name with stray CRs.)"""
    from email.mime.multipart import MIMEMultipart
    from email.mime.text import MIMEText
    from email.mime.application import MIMEApplication
    from email.header import Header
    from email.utils import formatdate, make_msgid, formataddr
    sender = getattr(common, 'SMTP_USER', 'contact@inlightbio.com')
    name = getattr(common, 'FROM_NAME', {}).get('cn', '启光生物资讯')
    alt = MIMEMultipart('alternative')
    alt.attach(MIMEText(text or '', 'plain', 'utf-8'))
    alt.attach(MIMEText(html_body, 'html', 'utf-8'))
    if attachment:
        msg = MIMEMultipart('mixed'); msg.attach(alt)
        data, ext, filename = attachment
        part = MIMEApplication(data, _subtype=MIME[ext][1])
        part.add_header('Content-Disposition', 'attachment', filename=('utf-8', '', filename))
        msg.attach(part)
    else:
        msg = alt
    msg['From'] = formataddr((str(Header(name, 'utf-8')), sender))
    msg['To'] = to
    msg['Subject'] = Header(subject, 'utf-8')
    msg['Date'] = formatdate(localtime=False)
    msg['Message-ID'] = make_msgid(domain='inlightbio.com')
    msg['Reply-To'] = reply_to or getattr(common, 'REPLY_TO', 'contact@inlightbio.com')
    return msg


PATHS = ('/api/talent/cv', '/api/partner-contact')


def make_handler(base, wp_service, talent):
    Parent = wp.make_handler(base, wp_service)

    class H(Parent):
        def log_message(self, fmt, *args):
            p = urlparse(self.path).path
            if p.startswith('/api/talent') or p == '/api/partner-contact':
                print('talent HTTP {}'.format(p), file=sys.stderr, flush=True)
            else:
                super().log_message(fmt, *args)

        def client_ip(self):
            peer = self.client_address[0]
            ip = (self.headers.get('X-Real-IP') or peer) if peer in ('127.0.0.1', '::1') else peer
            return ip[:100]

        def read_body(self, limit):
            try:
                length = int(self.headers.get('Content-Length', '0'))
            except ValueError:
                return 400, None
            if self.headers.get('Transfer-Encoding') or length < 1: return 400, None
            if length > limit:
                self.close_connection = True
                if length <= DRAIN_MAX:  # drain so nginx gets a clean JSON 413 instead of a broken pipe
                    self.connection.settimeout(30)
                    left = length
                    try:
                        while left > 0:
                            b = self.rfile.read(min(65536, left))
                            if not b: break
                            left -= len(b)
                    except OSError:
                        pass
                return 413, None
            self.connection.settimeout(30)
            chunks, got = [], 0
            try:
                while got < length:
                    b = self.rfile.read(min(65536, length - got))
                    if not b: break
                    chunks.append(b); got += len(b)
            except OSError:
                return 400, None
            if got != length: return 400, None
            return 200, b''.join(chunks)

        def do_GET(self):
            if urlparse(self.path).path == '/api/talent/health':
                return self.out(200, {'ok': True, 'service': 'talent-v7'})
            return super().do_GET()

        def do_POST(self):
            p = urlparse(self.path).path
            if p not in PATHS:
                return super().do_POST()
            origin = self.headers.get('Origin')
            if not origin or origin not in base.ALLOWED_ORIGINS:
                return self.out(403, {'ok': False, 'error': '来源不被允许。'})
            ctype = self.headers.get('Content-Type', '')
            main = ctype.split(';')[0].strip().lower()
            if p == '/api/talent/cv':
                if main != 'multipart/form-data': return self.out(415, {'ok': False, 'error': '请求格式错误。'})
                code, raw = self.read_body(MAX_BODY)
                if code == 413: return self.out(413, {'ok': False, 'error': '文件超过 10MB，请压缩后重试。'})
                if code != 200: return self.out(400, {'ok': False, 'error': '请求格式错误。'})
                try:
                    fields, files = parse_multipart(ctype, raw)
                except Bad as e:
                    return self.out(400, {'ok': False, 'error': str(e)})
                code, res = talent.submit_cv(fields, files, self.client_ip())
                return self.out(code, res)
            if main != 'application/json': return self.out(415, {'ok': False, 'error': '请求格式错误。'})
            code, raw = self.read_body(MAX_JSON)
            if code == 413: return self.out(413, {'ok': False, 'error': '内容过长。'})
            if code != 200: return self.out(400, {'ok': False, 'error': '请求格式错误。'})
            try:
                d = json.loads(raw.decode('utf-8'))
            except ValueError:
                return self.out(400, {'ok': False, 'error': '请求格式错误。'})
            code, res = talent.submit_partner(d, self.client_ip())
            return self.out(code, res)
    return H


def main():
    base = wp.load_base()
    if '--check' in sys.argv:
        print('V7_IMPORT_OK; v6e whitepaper + v3 newsletter handlers retained; talent routes added')
        return
    os.umask(0o077)
    store = wp.Store(os.environ.get('WP_DATA_DIR', '/opt/inlight-newsletter/whitepaper_data_v5_20261109'),
                     os.environ.get('WP_PDF_PATH', '/opt/inlight-newsletter/whitepaper_files/InLight_whitepaper_zh_2026_v5.pdf'),
                     pdf_path_en=wp.configured_english_pdf())
    service = wp.Service(store, base.common)
    talent = TalentService(TalentStore(DATA_DIR), base.common)
    base.common.db().close()
    threading.Thread(target=service.worker, daemon=True).start()
    threading.Thread(target=talent.worker, daemon=True).start()
    if hasattr(base, 'ThreadingHTTPServer'):
        server_class = base.ThreadingHTTPServer
    else:
        from http.server import HTTPServer
        from socketserver import ThreadingMixIn
        class Server(ThreadingMixIn, HTTPServer):
            daemon_threads = True
        server_class = Server
    server_class((base.HOST, base.PORT), make_handler(base, service, talent)).serve_forever()


if __name__ == '__main__':
    main()
