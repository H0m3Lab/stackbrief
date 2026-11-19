// Stackbrief gateway: POST /ask {job, input} -> runs `claude -p` with jobs/<job>.md + input, returns text.
// Claude gets no shell, no docker, no host access: only Read/Write/Edit/Glob/Grep inside /data/workspace.
// One job at a time. Every call is logged to /data/history/<job>/.
const http = require('http'), fs = require('fs'), path = require('path'), crypto = require('crypto');
const { spawn } = require('child_process');
const PORT = 8765, JOBS = '/app/jobs', SEED = '/app/seed', WS = '/data/workspace', HIST = '/data/history';
const TOOLS = 'Read,Write,Edit,Glob,Grep';
const KEY = process.env.GATEWAY_KEY || '';
const TIMEOUT_MS = (+process.env.JOB_TIMEOUT_SEC || 900) * 1000;
const KEEP_HISTORY = +process.env.KEEP_HISTORY || 200;
let chain = Promise.resolve(), busy = 0;

const log = (...a) => console.log(new Date().toISOString(), ...a);
const keyOk = (h) => {
  const got = Buffer.from((h || '').replace(/^Bearer /, '')), want = Buffer.from(KEY);
  return KEY.length >= 32 && got.length === want.length && crypto.timingSafeEqual(got, want);
};
const jobs = () => fs.readdirSync(JOBS).filter(f => f.endsWith('.md')).map(f => f.slice(0, -3));
const auth = () => process.env.ANTHROPIC_API_KEY ? 'api-key' : process.env.CLAUDE_CODE_OAUTH_TOKEN ? 'oauth-token' : 'none';

function runClaude(job, input) {
  return new Promise((resolve) => {
    const prompt = fs.readFileSync(path.join(JOBS, job + '.md'), 'utf8') +
      '\n\n<input>\n' + input + '\n</input>\n';
    const args = ['-p', '--output-format', 'json', '--tools', TOOLS, '--allowedTools', TOOLS,
      '--permission-mode', 'acceptEdits'];
    if (process.env.CLAUDE_MODEL) args.push('--model', process.env.CLAUDE_MODEL);
    const p = spawn('claude', args, { cwd: WS, env: process.env });
    let out = '', err = '';
    const t = setTimeout(() => { err += '\n[gateway] timeout, killed'; p.kill('SIGTERM'); }, TIMEOUT_MS);
    p.stdout.on('data', d => out += d); p.stderr.on('data', d => err += d);
    p.on('error', e => { err += String(e); });
    p.on('close', (code) => {
      clearTimeout(t);
      let r = { ok: false, error: (err || out).slice(-2000) };
      try {
        const j = JSON.parse(out);
        r = { ok: code === 0 && !j.is_error, text: j.result || '', duration_ms: j.duration_ms,
              turns: j.num_turns, cost_usd: j.total_cost_usd };
        if (!r.ok) r.error = (j.result || err).slice(-2000);
      } catch (_) {}
      resolve(r);
    });
    p.stdin.end(prompt);
  });
}

function saveHistory(job, input, result) {
  const dir = path.join(HIST, job);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, new Date().toISOString().replace(/[:.]/g, '-') + '.json'),
    JSON.stringify({ job, input, result }, null, 1));
  const files = fs.readdirSync(dir).sort();
  files.slice(0, Math.max(0, files.length - KEEP_HISTORY)).forEach(f => fs.unlinkSync(path.join(dir, f)));
}

const send = (res, code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };

http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') return send(res, 200, { ok: true, busy, jobs: jobs(), auth: auth() });
  if (req.method !== 'POST' || req.url !== '/ask') return send(res, 404, { ok: false, error: 'not found' });
  if (!keyOk(req.headers.authorization)) return send(res, 401, { ok: false, error: 'bad key' });
  let body = '';
  req.on('data', d => { body += d; if (body.length > 2e6) req.destroy(); });
  req.on('end', () => {
    let job, input;
    try { ({ job, input } = JSON.parse(body)); } catch (_) { return send(res, 400, { ok: false, error: 'bad json' }); }
    if (!/^[a-z0-9-]{1,40}$/.test(job || '') || !jobs().includes(job))
      return send(res, 400, { ok: false, error: 'unknown job', jobs: jobs() });
    busy++;
    chain = chain.then(async () => {
      log('start', job, (input || '').length, 'chars');
      const r = await runClaude(job, String(input || ''));
      log('done', job, r.ok ? 'ok' : 'FAIL', r.duration_ms || '', r.ok ? '' : r.error);
      try { saveHistory(job, input, r); } catch (e) { log('history write failed', e.message); }
      busy--; send(res, r.ok ? 200 : 502, r);
    });
  });
}).listen(PORT, () => {
  if (KEY.length < 32) log('WARNING: GATEWAY_KEY missing or shorter than 32 chars - every /ask will be refused');
  for (const d of [WS, path.join(WS, 'memory'), HIST, process.env.HOME]) fs.mkdirSync(d, { recursive: true });
  for (const f of fs.readdirSync(SEED)) {             // first start: copy the workspace instructions
    const dst = path.join(WS, f);
    if (!fs.existsSync(dst)) fs.copyFileSync(path.join(SEED, f), dst);
  }
  log('stackbrief gateway listening on', PORT, 'auth:', auth(), 'jobs:', jobs().join(','));
});
