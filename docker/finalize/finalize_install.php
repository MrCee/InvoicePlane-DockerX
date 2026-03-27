<?php
declare(strict_types=1);

$stateFile = '/state/status.json';
$defaultState = 'idle';
$defaultMessage = 'Waiting for finalizer request.';

$state = $defaultState;
$message = $defaultMessage;

if (is_file($stateFile)) {
    $raw = @file_get_contents($stateFile);
    if ($raw !== false) {
        $decoded = json_decode($raw, true);
        if (is_array($decoded)) {
            $state = isset($decoded['state']) && is_string($decoded['state']) ? $decoded['state'] : $defaultState;
            $message = isset($decoded['message']) && is_string($decoded['message']) ? $decoded['message'] : $defaultMessage;
        }
    }
}

function h(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>InvoicePlane Finalizer</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    :root {
      --bg: #0b1220;
      --panel: #111a2b;
      --panel-2: #162238;
      --border: #2a3a57;
      --text: #e9eef8;
      --muted: #9db0d0;
      --good: #1f9d55;
      --good-bg: rgba(31, 157, 85, 0.15);
      --warn: #d9a441;
      --warn-bg: rgba(217, 164, 65, 0.14);
      --bad: #d64545;
      --bad-bg: rgba(214, 69, 69, 0.14);
      --info: #4f8cff;
      --info-bg: rgba(79, 140, 255, 0.14);
      --mono-bg: #09111d;
      --mono-border: #20314d;
      --mono-text: #d7e3f7;
      --shadow: 0 20px 45px rgba(0, 0, 0, 0.28);
      --radius: 16px;
      --radius-sm: 12px;
    }

    * { box-sizing: border-box; }

    html, body {
      margin: 0;
      padding: 0;
      background: linear-gradient(180deg, #0a101b 0%, #0e1524 100%);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      min-height: 100%;
    }

    body { padding: 24px; }

    .shell { max-width: 1080px; margin: 0 auto; }

    .card {
      background: linear-gradient(180deg, var(--panel) 0%, var(--panel-2) 100%);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
      overflow: hidden;
    }

    .header {
      padding: 24px 24px 18px 24px;
      border-bottom: 1px solid rgba(255,255,255,0.06);
    }

    .title-row {
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
    }

    .title-wrap h1 {
      margin: 0;
      font-size: 28px;
      line-height: 1.15;
      letter-spacing: -0.02em;
    }

    .title-wrap p {
      margin: 8px 0 0 0;
      color: var(--muted);
      font-size: 14px;
    }

    .pill {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      min-height: 36px;
      padding: 0 14px;
      border-radius: 999px;
      border: 1px solid transparent;
      font-weight: 700;
      font-size: 13px;
      letter-spacing: 0.02em;
      text-transform: uppercase;
      white-space: nowrap;
    }

    .pill::before {
      content: "";
      width: 9px;
      height: 9px;
      border-radius: 50%;
      background: currentColor;
      opacity: 0.95;
      flex: 0 0 auto;
    }

    .pill.idle,
    .pill.requested,
    .pill.updating,
    .pill.recreating,
    .pill.waiting {
      color: var(--info);
      background: var(--info-bg);
      border-color: rgba(79, 140, 255, 0.35);
    }

    .pill.complete {
      color: var(--good);
      background: var(--good-bg);
      border-color: rgba(31, 157, 85, 0.35);
    }

    .pill.error {
      color: var(--bad);
      background: var(--bad-bg);
      border-color: rgba(214, 69, 69, 0.35);
    }

    .content { padding: 24px; display: grid; gap: 18px; }

    .banner {
      display: none;
      padding: 16px 18px;
      border-radius: var(--radius-sm);
      border: 1px solid transparent;
      font-size: 15px;
      line-height: 1.45;
    }

    .banner.show { display: block; }
    .banner.info { color: #cfe0ff; background: var(--info-bg); border-color: rgba(79, 140, 255, 0.35); }
    .banner.success { color: #ddffea; background: var(--good-bg); border-color: rgba(31, 157, 85, 0.35); }
    .banner.error { color: #ffdede; background: var(--bad-bg); border-color: rgba(214, 69, 69, 0.35); }

    .meta-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
    }

    .meta {
      padding: 14px 16px;
      border-radius: var(--radius-sm);
      background: rgba(255,255,255,0.03);
      border: 1px solid rgba(255,255,255,0.06);
    }

    .meta .label {
      display: block;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.06em;
      color: var(--muted);
      margin-bottom: 6px;
    }

    .meta .value {
      display: block;
      font-size: 15px;
      word-break: break-word;
    }

    .terminal-wrap {
      border: 1px solid var(--mono-border);
      border-radius: var(--radius-sm);
      overflow: hidden;
      background: var(--mono-bg);
    }

    .terminal-toolbar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      padding: 12px 14px;
      border-bottom: 1px solid rgba(255,255,255,0.06);
      background: rgba(255,255,255,0.025);
    }

    .terminal-title {
      font-weight: 700;
      font-size: 14px;
      color: #e5eefc;
    }

    .terminal-subtitle {
      font-size: 12px;
      color: var(--muted);
    }

    .terminal {
      margin: 0;
      padding: 16px;
      min-height: 420px;
      max-height: 58vh;
      overflow-y: scroll;
      overflow-x: auto;
      white-space: pre-wrap;
      word-break: break-word;
      font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      color: var(--mono-text);
      scrollbar-width: auto;
      scroll-behavior: auto;
    }

    .actions {
      display: flex;
      gap: 12px;
      flex-wrap: wrap;
      align-items: center;
    }

    .btn {
      appearance: none;
      border: 1px solid rgba(255,255,255,0.08);
      background: rgba(255,255,255,0.06);
      color: var(--text);
      border-radius: 12px;
      padding: 12px 16px;
      font-size: 14px;
      font-weight: 700;
      cursor: pointer;
      text-decoration: none;
    }

    .btn.primary { background: rgba(79, 140, 255, 0.16); border-color: rgba(79, 140, 255, 0.35); }
    .btn.success { background: rgba(31, 157, 85, 0.16); border-color: rgba(31, 157, 85, 0.35); }
    .btn.warn { background: rgba(217, 164, 65, 0.16); border-color: rgba(217, 164, 65, 0.35); }
    .btn[disabled] { opacity: 0.45; cursor: not-allowed; }

    .helper { font-size: 13px; color: var(--muted); }

    .ansi-bold { font-weight: 700; }
    .ansi-dim { opacity: 0.75; }
    .ansi-red { color: #ff7b72; }
    .ansi-green { color: #56d364; }
    .ansi-yellow { color: #e3b341; }
    .ansi-blue { color: #79c0ff; }
    .ansi-magenta { color: #d2a8ff; }
    .ansi-cyan { color: #56d4dd; }
    .ansi-white { color: #f0f6fc; }

    @media (max-width: 820px) {
      body { padding: 16px; }
      .header, .content { padding: 18px; }
      .meta-grid { grid-template-columns: 1fr; }
      .terminal { max-height: 52vh; }
    }
  </style>
</head>
<body>
  <div class="shell">
    <div class="card">
      <div class="header">
        <div class="title-row">
          <div class="title-wrap">
            <h1>InvoicePlane Finalizer</h1>
            <p>Live finalization status, authoritative backend state, and full log snapshot rendering.</p>
          </div>
          <div id="statePill" class="pill <?= h($state) ?>"><?= h($state) ?></div>
        </div>
      </div>

      <div class="content">
        <div id="statusBanner" class="banner info show"><?= h($message) ?></div>

        <div class="meta-grid">
          <div class="meta">
            <span class="label">Finalizer state</span>
            <span id="metaState" class="value"><?= h($state) ?></span>
          </div>
          <div class="meta">
            <span class="label">App reachability</span>
            <span id="metaReachability" class="value">Checking…</span>
          </div>
          <div class="meta">
            <span class="label">Last refresh</span>
            <span id="metaRefresh" class="value">Not yet refreshed</span>
          </div>
        </div>

        <div class="terminal-wrap">
          <div class="terminal-toolbar">
            <div>
              <div class="terminal-title">Finalizer log</div>
              <div class="terminal-subtitle">Full snapshot replaces the terminal contents on every poll. Auto-scroll only happens when you are already near the bottom.</div>
            </div>
            <div class="helper" id="logMeta">Waiting for log data…</div>
          </div>
          <pre id="terminal" class="terminal"></pre>
        </div>

        <div class="actions">
          <button id="continueButton" class="btn success" type="button" disabled>Continue to Login</button>
          <button id="refreshButton" class="btn primary" type="button">Refresh now</button>
          <button id="beginButton" class="btn warn" type="button" style="display:none;">Begin finalization</button>
          <span id="actionHelper" class="helper">Continue becomes available only after finalizer completion, or after an error when the app is already reachable.</span>
        </div>
      </div>
    </div>
  </div>

  <script>
    (() => {
      const statusUrl = '/finalize_status.php';
      const requestUrl = '/custom-complete.php';
      const loginUrl = '/sessions/login';
      const probeUrl = '/sessions/login';

      const pollIntervalMs = 1000;
      const probeIntervalMs = 2500;
      const nearBottomThresholdPx = 36;

      const terminal = document.getElementById('terminal');
      const statePill = document.getElementById('statePill');
      const metaState = document.getElementById('metaState');
      const metaReachability = document.getElementById('metaReachability');
      const metaRefresh = document.getElementById('metaRefresh');
      const statusBanner = document.getElementById('statusBanner');
      const continueButton = document.getElementById('continueButton');
      const refreshButton = document.getElementById('refreshButton');
      const beginButton = document.getElementById('beginButton');
      const actionHelper = document.getElementById('actionHelper');
      const logMeta = document.getElementById('logMeta');

      let lastKnownState = <?= json_encode($state, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>;
      let appReachable = false;

      function nowString() {
        return new Date().toLocaleString();
      }

      function isNearBottom(el) {
        const remaining = el.scrollHeight - el.scrollTop - el.clientHeight;
        return remaining <= nearBottomThresholdPx;
      }

      function scrollToBottom(el) {
        el.scrollTop = el.scrollHeight;
      }

      function escapeHtml(value) {
        return String(value)
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
          .replace(/"/g, '&quot;')
          .replace(/'/g, '&#039;');
      }

      function ansiToHtml(input) {
        const text = String(input || '');
        const pattern = /\x1b\[([0-9;]*)m/g;
        let result = '';
        let lastIndex = 0;
        let openClasses = [];

        function closeAll() {
          if (openClasses.length > 0) {
            result += '</span>';
            openClasses = [];
          }
        }

        function openWithClasses(classes) {
          closeAll();
          if (classes.length > 0) {
            result += '<span class="' + classes.join(' ') + '">';
            openClasses = classes.slice();
          }
        }

        let match;
        while ((match = pattern.exec(text)) !== null) {
          const chunk = text.slice(lastIndex, match.index);
          result += escapeHtml(chunk);
          lastIndex = pattern.lastIndex;

          const rawCodes = match[1] === '' ? ['0'] : match[1].split(';');
          const codes = rawCodes.map(code => parseInt(code, 10)).filter(code => !Number.isNaN(code));

          if (codes.length === 0 || codes.includes(0)) {
            closeAll();
            continue;
          }

          const classes = openClasses.slice();

          for (const code of codes) {
            if (code === 1) { if (!classes.includes('ansi-bold')) classes.push('ansi-bold'); }
            else if (code === 2) { if (!classes.includes('ansi-dim')) classes.push('ansi-dim'); }
            else if (code === 31) { classes.push('ansi-red'); }
            else if (code === 32) { classes.push('ansi-green'); }
            else if (code === 33) { classes.push('ansi-yellow'); }
            else if (code === 34) { classes.push('ansi-blue'); }
            else if (code === 35) { classes.push('ansi-magenta'); }
            else if (code === 36) { classes.push('ansi-cyan'); }
            else if (code === 37) { classes.push('ansi-white'); }
            else if (code === 39) {
              openWithClasses(classes.filter(name => !/^ansi-(red|green|yellow|blue|magenta|cyan|white)$/.test(name)));
              continue;
            } else if (code === 22) {
              openWithClasses(classes.filter(name => name !== 'ansi-bold' && name !== 'ansi-dim'));
              continue;
            }
          }

          openWithClasses([...new Set(classes)]);
        }

        result += escapeHtml(text.slice(lastIndex));
        closeAll();
        return result;
      }

      function updateStatePill(state) {
        const safeState = state || 'idle';
        statePill.className = 'pill ' + safeState;
        statePill.textContent = safeState;
        metaState.textContent = safeState;
      }

      function setBanner(kind, text) {
        statusBanner.className = 'banner ' + kind + ' show';
        statusBanner.textContent = text;
      }

      function updateContinueButton() {
        const allowContinue = (lastKnownState === 'complete') || (lastKnownState === 'error' && appReachable);
        continueButton.disabled = !allowContinue;

        if (lastKnownState === 'complete') {
          actionHelper.textContent = 'Finalizer is complete. You can continue after reviewing and scrolling the log.';
        } else if (lastKnownState === 'error' && appReachable) {
          actionHelper.textContent = 'The finalizer errored, but the app appears reachable. Manual continue is available.';
        } else if (appReachable) {
          actionHelper.textContent = 'The app is reachable, but Continue stays locked until the authoritative finalizer state is complete.';
        } else {
          actionHelper.textContent = 'Waiting for the app and finalizer state to progress.';
        }
      }

      function updateBeginButton(state) {
        beginButton.style.display = (state === 'idle') ? '' : 'none';
      }

      function renderStatus(data) {
        const state = typeof data.state === 'string' && data.state ? data.state : 'idle';
        const message = typeof data.message === 'string' && data.message ? data.message : 'No status message.';
        const log = typeof data.log === 'string' ? data.log : '';
        const timestamp = typeof data.timestamp === 'string' ? data.timestamp : '';
        const logSize = typeof data.log_size !== 'undefined' ? data.log_size : 'unknown';
        const logMtime = typeof data.log_mtime !== 'undefined' ? data.log_mtime : 'unknown';

        lastKnownState = state;
        updateStatePill(state);

        const renderedLog = ansiToHtml(log);
        if (terminal.innerHTML !== renderedLog) {
          const nearBottom = isNearBottom(terminal);
          terminal.innerHTML = renderedLog;
          if (nearBottom) scrollToBottom(terminal);
        }

        logMeta.textContent = 'log_size=' + logSize + ' · log_mtime=' + logMtime;
        metaRefresh.textContent = nowString() + (timestamp ? ' · state timestamp ' + timestamp : '');

        if (state === 'complete') {
          setBanner('success', 'InvoicePlane finalizer completed successfully. Review the log if needed, then continue to login.');
        } else if (state === 'error') {
          setBanner('error', appReachable
            ? 'Finalizer reported an error, but the app appears reachable. Review the log carefully before continuing.'
            : message);
        } else if (appReachable) {
          setBanner('info', 'InvoicePlane is online. Waiting for finalizer log to complete...');
        } else {
          setBanner('info', message);
        }

        updateContinueButton();
        updateBeginButton(state);
      }

      async function fetchStatus() {
        try {
          const response = await fetch(statusUrl + '?_=' + Date.now(), {
            method: 'GET',
            credentials: 'same-origin',
            cache: 'no-store'
          });
          if (!response.ok) throw new Error('HTTP ' + response.status);
          renderStatus(await response.json());
        } catch (error) {
          updateStatePill(lastKnownState || 'error');
          setBanner('error', 'Unable to fetch finalizer status right now. The page will keep retrying.');
          metaRefresh.textContent = nowString() + ' · status fetch failed';
        }
      }

      async function probeApp() {
        try {
          const response = await fetch(probeUrl + '?_probe=' + Date.now(), {
            method: 'GET',
            credentials: 'same-origin',
            cache: 'no-store'
          });
          appReachable = response.ok;
        } catch (error) {
          appReachable = false;
        }

        metaReachability.textContent = appReachable ? 'App reachable' : 'App not reachable yet';
        updateContinueButton();
      }

      async function beginFinalization() {
        beginButton.disabled = true;
        beginButton.textContent = 'Starting…';
        try {
          const response = await fetch(requestUrl, {
            method: 'POST',
            credentials: 'same-origin',
            cache: 'no-store',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' },
            body: 'action=finalize'
          });
          if (!response.ok) throw new Error('HTTP ' + response.status);
          setBanner('info', 'Finalize request sent. Waiting for finalizer sidecar to process it...');
          await fetchStatus();
        } catch (error) {
          setBanner('error', 'Unable to send finalize request. Review custom-complete.php handling and try again.');
        } finally {
          beginButton.disabled = false;
          beginButton.textContent = 'Begin finalization';
        }
      }

      refreshButton.addEventListener('click', () => { void fetchStatus(); void probeApp(); });
      continueButton.addEventListener('click', () => { window.location.href = loginUrl; });
      beginButton.addEventListener('click', () => { void beginFinalization(); });

      void fetchStatus();
      void probeApp();
      window.setInterval(() => { void fetchStatus(); }, pollIntervalMs);
      window.setInterval(() => { void probeApp(); }, probeIntervalMs);

      if (terminal.textContent.trim() === '') {
        terminal.textContent = 'Waiting for finalizer log output...';
      }
      scrollToBottom(terminal);
    })();
  </script>
</body>
</html>
