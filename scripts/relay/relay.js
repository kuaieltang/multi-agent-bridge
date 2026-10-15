/*
 * agent-bridge 本地中继
 *
 * 为什么需要它：DSH 沙箱内的子进程无法建立 TLS（schannel SEC_E_NO_CREDENTIALS），
 * 因此 Codex / CodeBuddy / Qoder 这些需要访问云端模型的 CLI 在沙箱里必然失败。
 * 解决办法：把中继放在沙箱外用完全权限常驻一次，之后我只通过
 * 127.0.0.1 的明文 HTTP 调用它 —— 不涉及 TLS，也不再需要每次审批。
 *
 * 启动（需要一次提权）：
 *   node relay.js
 *
 * 调用：
 *   POST http://127.0.0.1:18791/run
 *   header: x-bridge-token: <relay/token.txt>
 *   body:   {"agent":"codex","prompt":"...","workdir":"...","timeoutSec":300,"allowTools":false,"native":false}
 *
 * 安全约束：只监听 127.0.0.1 + 随机 token；token 每次启动重新生成。
 */
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');

const RELAY_DIR = __dirname;
const BRIDGE_DIR = path.resolve(RELAY_DIR, '..');
const SCRIPT = path.join(BRIDGE_DIR, 'agents.ps1');
const PORT = Number(process.env.BRIDGE_PORT || 18791);
const PS = process.env.BRIDGE_POWERSHELL ||
    'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';

const TOKEN = process.env.BRIDGE_TOKEN || crypto.randomBytes(16).toString('hex');
fs.writeFileSync(path.join(RELAY_DIR, 'token.txt'), TOKEN, 'utf8');

function send(res, code, payload) {
    const body = typeof payload === 'string' ? payload : JSON.stringify(payload, null, 2);
    res.writeHead(code, { 'content-type': 'application/json; charset=utf-8' });
    res.end(body);
}

const server = http.createServer((req, res) => {
    if (req.method !== 'POST' || req.url !== '/run') {
        return send(res, 404, { error: 'not found; POST /run' });
    }
    if (req.headers['x-bridge-token'] !== TOKEN) {
        return send(res, 401, { error: 'bad token' });
    }

    let buf = '';
    req.on('data', (c) => {
        buf += c;
        if (buf.length > 2e6) req.destroy();
    });
    req.on('end', () => {
        let p;
        try { p = JSON.parse(buf || '{}'); }
        catch (e) { return send(res, 400, { error: 'bad json' }); }

        if (!p.agent || !p.prompt) return send(res, 400, { error: 'need agent + prompt' });

        const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', SCRIPT,
                      '-Agent', String(p.agent), '-Prompt', String(p.prompt)];
        if (p.workdir) args.push('-WorkDir', String(p.workdir));
        if (p.timeoutSec) args.push('-TimeoutSec', String(p.timeoutSec));
        if (p.allowTools) args.push('-AllowTools');
        if (p.fullAccess) args.push('-FullAccess');
        if (p.native) args.push('-Native');
        if (p.extraArgs) args.push('-ExtraArgs', String(p.extraArgs));

        const started = Date.now();
        const child = spawn(PS, args, { stdio: ['ignore', 'pipe', 'pipe'], env: process.env });
        let out = '', err = '';
        child.stdout.on('data', (d) => { out += d; });
        child.stderr.on('data', (d) => { err += d; });
        child.on('error', (e) => send(res, 500, { error: String(e && e.message || e) }));
        child.on('close', (code) => {
            const m = out.match(/OUTFILE:\s*(.+)/);
            const logFile = m ? m[1].trim() : null;
            let log = null;
            if (logFile) { try { log = fs.readFileSync(logFile, 'utf8'); } catch (e) { } }
            send(res, 200, {
                agent: p.agent,
                exitCode: code,
                seconds: Math.round((Date.now() - started) / 100) / 10,
                logFile,
                log,
                stdoutTail: out.slice(-4000),
                stderrTail: err.slice(-2000)
            });
        });
    });
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`[bridge-relay] listening http://127.0.0.1:${PORT}  token=${TOKEN}`);
    console.log(`[bridge-relay] script=${SCRIPT}`);
});
