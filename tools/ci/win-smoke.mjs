import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, openSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const exe = process.argv[2];
const outDir = process.argv[3] ?? 'screens';
const port = 9222 + Math.floor(Math.random() * 500);

if (!exe) {
  console.error('usage: node win-smoke.mjs <app.exe> [out-dir]');
  process.exit(2);
}

mkdirSync(outDir, { recursive: true });

const work = mkdtempSync(join(tmpdir(), 'nsm-smoke-'));
const dataDir = join(work, 'data');
const profileDir = join(work, 'webview');
const inputDir = join(work, 'inputs');
mkdirSync(inputDir, { recursive: true });

const results = [];
let failed = false;

function log(message) {
  console.log(`[${new Date().toISOString().slice(11, 19)}] ${message}`);
}

function check(name, ok, detail = '') {
  results.push({ name, ok });
  if (!ok) failed = true;
  log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ` | ${detail}` : ''}`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function wav(path, seconds, frequency) {
  const rate = 44100;
  const frames = Math.round(rate * seconds);
  const data = Buffer.alloc(44 + frames * 2);
  data.write('RIFF', 0);
  data.writeUInt32LE(36 + frames * 2, 4);
  data.write('WAVEfmt ', 8);
  data.writeUInt32LE(16, 16);
  data.writeUInt16LE(1, 20);
  data.writeUInt16LE(1, 22);
  data.writeUInt32LE(rate, 24);
  data.writeUInt32LE(rate * 2, 28);
  data.writeUInt16LE(2, 32);
  data.writeUInt16LE(16, 34);
  data.write('data', 36);
  data.writeUInt32LE(frames * 2, 40);
  for (let index = 0; index < frames; index += 1) {
    data.writeInt16LE(Math.round(9000 * Math.sin((2 * Math.PI * frequency * index) / rate)), 44 + index * 2);
  }
  writeFileSync(path, data);
}

const names = ['09 - 2pac - Ratha Be Ya Nigga.wav', '01 - Test Band - First Song.wav', '02 - Test Band - Second Song.wav'];
const files = names.map((name, index) => {
  const path = join(inputDir, name);
  wav(path, 6 + index, 330 + index * 110);
  return path;
});

log(`launching ${exe}`);
const appOutput = openSync(join(outDir, 'app.log'), 'a');
const child = spawn(exe, [], {
  env: {
    ...process.env,
    NSM_MUTE: '1',
    NSM_OFFLINE: '1',
    NSM_DATA_DIR: dataDir,
    WEBVIEW2_USER_DATA_FOLDER: profileDir,
    NSM_DEBUG_PORT: String(port)
  },
  stdio: ['ignore', appOutput, appOutput]
});
child.on('exit', (code) => log(`app exited with ${code}`));

function killApp() {
  try {
    spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore' });
  } catch {
    child.kill();
  }
}

function diagnose() {
  const script = [
    "Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'nodeshift|msedgewebview2' } | Select-Object ProcessId,Name,CommandLine | Format-List | Out-String -Width 400",
    "Get-NetTCPConnection -State Listen | Where-Object { $_.LocalAddress -eq '127.0.0.1' } | Select-Object LocalPort,OwningProcess | Format-Table | Out-String"
  ].join('; ');
  const result = spawnSync('powershell', ['-NoProfile', '-Command', script], { encoding: 'utf8' });
  log(`diagnostics:
${result.stdout}${result.stderr}`);
  const panic = join(tmpdir(), 'nodeshift-music-panic.log');
  if (existsSync(panic)) log(`panic log:
${readFileSync(panic, 'utf8')}`);
  const output = join(outDir, 'app.log');
  if (existsSync(output)) log(`app output:
${readFileSync(output, 'utf8').slice(-3000)}`);
  log(`data dir: ${existsSync(dataDir) ? readdirSync(dataDir).join(', ') : 'missing'}`);
  log(`webview profile: ${existsSync(profileDir) ? readdirSync(profileDir).join(', ') : 'missing'}`);
}

async function findTarget() {
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json`);
      const targets = await response.json();
      const page = targets.find((target) => target.type === 'page' && /tauri\.localhost|localhost/.test(target.url)) ?? targets.find((target) => target.type === 'page');
      if (page) return page;
    } catch {
      await sleep(500);
    }
    await sleep(500);
  }
  diagnose();
  throw new Error('no webview target on the debugging port');
}

async function connect(target) {
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', () => reject(new Error('websocket error')), { once: true });
  });
  let counter = 0;
  const pending = new Map();
  const problems = [];
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message));
      else resolve(message.result);
      return;
    }
    if (message.method === 'Runtime.exceptionThrown') {
      problems.push(message.params.exceptionDetails.exception?.description ?? message.params.exceptionDetails.text);
    }
    if (message.method === 'Runtime.consoleAPICalled' && message.params.type === 'error') {
      problems.push(message.params.args.map((arg) => arg.value ?? arg.description ?? '').join(' '));
    }
  });
  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      counter += 1;
      pending.set(counter, { resolve, reject });
      socket.send(JSON.stringify({ id: counter, method, params }));
    });
  await send('Runtime.enable');
  await send('Page.enable');
  const evaluate = async (expression) => {
    const result = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text);
    return result.result.value;
  };
  const shot = async (name) => {
    const result = await send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(join(outDir, `${name}.png`), Buffer.from(result.data, 'base64'));
    log(`screenshot ${name}`);
  };
  return { send, evaluate, shot, problems, close: () => socket.close() };
}

async function until(label, probe, timeoutMs = 30_000, stepMs = 400) {
  const deadline = Date.now() + timeoutMs;
  let last;
  while (Date.now() < deadline) {
    try {
      last = await probe();
      if (last) return last;
    } catch {
      last = null;
    }
    await sleep(stepMs);
  }
  throw new Error(`timeout waiting for ${label}`);
}

let page = null;

try {
  const target = await findTarget();
  log(`target ${target.url}`);
  page = await connect(target);
  const call = (command, args = {}) => page.evaluate(`window.__TAURI_INTERNALS__.invoke(${JSON.stringify(command)}, ${JSON.stringify(args)})`);

  await until('sidebar', () => page.evaluate("Boolean(document.querySelector('.sidebar'))"), 60_000);
  check('ui renders', true);
  await sleep(1500);
  await page.shot('01-empty');

  const info = await call('app_info');
  check('app info', Boolean(info.version) && String(info.mediaBase).startsWith('http://127.0.0.1:'), JSON.stringify(info));
  check('forced mute', info.muted === true);
  check('empty library at start', (await call('library_all')).length === 0);

  await call('import_start', { paths: files });
  await until('import finished', async () => {
    const snapshot = await call('import_snapshot');
    return !snapshot.running && snapshot.items.length === files.length;
  }, 180_000, 1000);
  const snapshot = await call('import_snapshot');
  check('imported three files', snapshot.summary.added === 3, JSON.stringify(snapshot.summary));

  const library = await call('library_all');
  const parsed = library.find((track) => track.title === 'Ratha Be Ya Nigga');
  check('title parsed from file name', Boolean(parsed), library.map((track) => track.title).join(' | '));
  check('artist parsed from file name', Boolean(parsed) && parsed.artist.toLowerCase().includes('2pac'), parsed?.artist);
  check('track number parsed', Boolean(parsed) && parsed.trackNumber === 9, String(parsed?.trackNumber));
  check('duration read from file', library.every((track) => track.durationMs > 4000), library.map((track) => track.durationMs).join(','));

  await call('import_start', { paths: [files[0]] });
  await until('second import finished', async () => {
    const next = await call('import_snapshot');
    return !next.running && next.items.length === files.length + 1;
  }, 60_000, 500);
  const again = await call('import_snapshot');
  check('same file is flagged as duplicate', again.summary.duplicates >= 1, JSON.stringify(again.summary));
  check('library still has three tracks', (await call('library_all')).length === 3);
  await call('import_clear');

  await page.evaluate("location.hash = '#/'");
  await until('cards', () => page.evaluate("document.querySelectorAll('.track-grid .group').length >= 3"), 30_000);
  await sleep(1200);
  await page.shot('02-library');

  await page.evaluate("document.querySelector('.track-grid button[aria-label=\"Играть\"]').click()");
  const played = await until(
    'audio playing',
    () =>
      page.evaluate(`(() => { const a = document.querySelector('audio'); return a && !a.error && a.currentTime > 0.8 ? { t: a.currentTime, muted: a.muted, src: a.currentSrc } : null; })()`),
    30_000
  );
  check('audio element plays from the local media server', Boolean(played), JSON.stringify(played));
  check('audio element stays muted', played?.muted === true);
  const session = await page.evaluate("navigator.mediaSession && navigator.mediaSession.metadata ? navigator.mediaSession.metadata.title : null");
  check('media session has the title', Boolean(session), String(session));

  await page.evaluate("document.querySelector('[aria-label=\"Развернуть плеер\"]').click()");
  await until('full player', () => page.evaluate("Boolean(document.querySelector('.np'))"), 15_000);
  await sleep(4500);
  await page.shot('03-player');
  const lyricsState = await page.evaluate("document.querySelectorAll('.lyric-line').length + ':' + (document.querySelector('.np-lyrics')?.innerText ?? '').slice(0, 60)");
  log(`lyrics panel: ${lyricsState}`);

  await page.evaluate("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))");
  await sleep(800);
  await page.evaluate("location.hash = '#/import'");
  await sleep(1500);
  await page.shot('04-import');
  await page.evaluate("location.hash = '#/site'");
  await sleep(1500);
  await page.shot('05-site');

  const remote = await call('catalog_page', { search: '', sort: 'new', format: null, limit: 12, offset: 0 });
  check('site catalog loads', remote.tracks.length > 0 && remote.count > 0, `${remote.tracks.length} of ${remote.count}`);
  check('catalog tracks stream over https', remote.tracks.every((track) => String(track.streamUrl).startsWith('https://')));
  const found = await call('catalog_page', { search: remote.tracks[0].title.slice(0, 3), sort: 'popular', format: null, limit: 5, offset: 0 });
  check('catalog search answers', found.tracks.length > 0, String(found.tracks.length));

  await page.evaluate("localStorage.setItem('nsm_library_mode', 'catalog'); location.hash = '#/'; location.reload()");
  await sleep(1500);
  await until('catalog cards', () => page.evaluate("document.querySelectorAll('.track-grid .group').length >= 6"), 40_000);
  await sleep(1500);
  await page.shot('06-catalog');
  const clicked = await page.evaluate(
    "(() => { const card = [...document.querySelectorAll('.track-grid .group')].find((item) => item.innerText.toLowerCase().includes('mp3')); const button = card && card.querySelector('button[aria-label=\"Играть\"]'); if (button) button.click(); return Boolean(button); })()"
  );
  check('an mp3 card is available in the catalog', clicked === true);
  const streamed = await until(
    'catalog audio playing',
    () => page.evaluate(`(() => { const a = document.querySelector('audio'); return a && !a.error && a.currentTime > 1 ? { t: a.currentTime, src: a.currentSrc.slice(0, 40), muted: a.muted } : null; })()`),
    60_000
  );
  check('catalog track plays through the local decrypting server', Boolean(streamed) && String(streamed.src).startsWith('http://127.0.0.1:'), JSON.stringify(streamed));
  check('streamed audio stays muted', streamed?.muted === true);
  await page.evaluate("document.querySelector('[aria-label=\"Развернуть плеер\"]').click()");
  await until('full player for the streamed track', () => page.evaluate("Boolean(document.querySelector('.np'))"), 15_000);
  await sleep(4000);
  await page.shot('07-catalog-player');

  const problems = page.problems.filter((text) => !/ResizeObserver|favicon/i.test(text));
  check('no uncaught page errors', problems.length === 0, problems.slice(0, 3).join(' || '));
} catch (error) {
  check('smoke run', false, error instanceof Error ? error.message : String(error));
  try {
    await page?.shot('99-failure');
  } catch {
    log('could not capture the failure screenshot');
  }
} finally {
  page?.close();
  killApp();
  writeFileSync(join(outDir, 'results.json'), JSON.stringify(results, null, 2));
}

const passed = results.filter((item) => item.ok).length;
log(`${passed}/${results.length} checks passed`);
process.exit(failed ? 1 : 0);
