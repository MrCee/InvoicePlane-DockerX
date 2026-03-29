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
      --glow-good: 0 0 0 1px rgba(31,157,85,0.25), 0 0 22px rgba(31,157,85,0.12);
      --glow-warn: 0 0 0 1px rgba(217,164,65,0.22), 0 0 22px rgba(217,164,65,0.10);
      --glow-bad: 0 0 0 1px rgba(214,69,69,0.22), 0 0 22px rgba(214,69,69,0.10);
      --glow-info: 0 0 0 1px rgba(79,140,255,0.22), 0 0 22px rgba(79,140,255,0.10);
    }

    * { box-sizing: border-box; }

    html, body {
      margin: 0;
      padding: 0;
      background: radial-gradient(circle at top, #13203a 0%, #0b1220 46%, #08101c 100%);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      min-height: 100%;
    }

    body { padding: 24px; }

    .shell { max-width: 1180px; margin: 0 auto; }

    .card {
      background: linear-gradient(180deg, rgba(17,26,43,0.96) 0%, rgba(22,34,56,0.96) 100%);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
      overflow: hidden;
      backdrop-filter: blur(8px);
    }

    .header {
      padding: 26px 26px 18px 26px;
      border-bottom: 1px solid rgba(255,255,255,0.06);
      background: linear-gradient(180deg, rgba(255,255,255,0.02) 0%, rgba(255,255,255,0) 100%);
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
      font-size: 30px;
      line-height: 1.1;
      letter-spacing: -0.03em;
    }

    .title-wrap p {
      margin: 9px 0 0 0;
      color: var(--muted);
      font-size: 14px;
    }

    .pill {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      min-height: 38px;
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
      box-shadow: 0 0 14px currentColor;
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

    .content {
      padding: 24px;
      display: grid;
      gap: 18px;
    }

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

    .status-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 14px;
    }

    .status-card {
      position: relative;
      overflow: hidden;
      padding: 16px 18px;
      border-radius: var(--radius-sm);
      border: 1px solid rgba(255,255,255,0.08);
      background: rgba(255,255,255,0.03);
      min-height: 122px;
      transition: border-color 0.18s ease, box-shadow 0.18s ease;
    }

    .status-card::after {
      content: "";
      position: absolute;
      inset: 0 auto 0 0;
      width: 4px;
      background: rgba(255,255,255,0.14);
    }

    .status-card .status-label {
      display: flex;
      align-items: center;
      gap: 10px;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--muted);
    }

    .status-card .status-dot {
      width: 10px;
      height: 10px;
      border-radius: 50%;
      background: currentColor;
      box-shadow: 0 0 18px currentColor;
      flex: 0 0 auto;
    }

    .status-card .status-value {
      display: block;
      margin-top: 12px;
      font-size: 22px;
      font-weight: 800;
      letter-spacing: -0.02em;
    }

    .status-card .status-detail {
      display: block;
      margin-top: 8px;
      color: var(--muted);
      font-size: 13px;
      line-height: 1.45;
    }

    .status-card.tone-green {
      color: var(--good);
      box-shadow: var(--glow-good);
    }

    .status-card.tone-green::after {
      background: linear-gradient(180deg, rgba(31,157,85,0.95) 0%, rgba(31,157,85,0.35) 100%);
    }

    .status-card.tone-amber {
      color: var(--warn);
      box-shadow: var(--glow-warn);
    }

    .status-card.tone-amber::after {
      background: linear-gradient(180deg, rgba(217,164,65,0.95) 0%, rgba(217,164,65,0.35) 100%);
    }

    .status-card.tone-red {
      color: var(--bad);
      box-shadow: var(--glow-bad);
    }

    .status-card.tone-red::after {
      background: linear-gradient(180deg, rgba(214,69,69,0.95) 0%, rgba(214,69,69,0.35) 100%);
    }

    .status-card.tone-blue {
      color: var(--info);
      box-shadow: var(--glow-info);
    }

    .status-card.tone-blue::after {
      background: linear-gradient(180deg, rgba(79,140,255,0.95) 0%, rgba(79,140,255,0.35) 100%);
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
      display: flex;
      align-items: center;
      gap: 10px;
      font-weight: 700;
      font-size: 14px;
      color: #e5eefc;
    }

    .live-dot {
      width: 9px;
      height: 9px;
      border-radius: 50%;
      background: var(--info);
      box-shadow: 0 0 16px var(--info);
      animation: pulse 1.6s ease-in-out infinite;
      flex: 0 0 auto;
    }

    @keyframes pulse {
      0% { transform: scale(1); opacity: 0.75; }
      50% { transform: scale(1.25); opacity: 1; }
      100% { transform: scale(1); opacity: 0.75; }
    }

    .terminal-subtitle {
      font-size: 12px;
      color: var(--muted);
      margin-top: 2px;
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

    @media (max-width: 980px) {
      .status-grid { grid-template-columns: 1fr; }
    }

    @media (max-width: 820px) {
      body { padding: 16px; }
      .header, .content { padding: 18px; }
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
            <p>Preparing your system for first login.</p>
          </div>
          <div id="statePill" class="pill <?= h($state) ?>"><?= h($state) ?></div>
        </div>
      </div>

      <div class="content">
        <div id="statusBanner" class="banner info show"><?= h($message) ?></div>

        <div class="status-grid">
          <div id="appCard" class="status-card tone-blue">
            <div class="status-label"><span class="status-dot"></span><span>App</span></div>
            <span id="appValue" class="status-value">Checking…</span>
            <span id="appDetail" class="status-detail">Waiting for reachability signal.</span>
          </div>

          <div id="templateCard" class="status-card tone-red">
            <div class="status-label"><span class="status-dot"></span><span>Templates</span></div>
            <span id="templateValue" class="status-value">Pending</span>
            <span id="templateDetail" class="status-detail">Compact template defaults not yet confirmed.</span>
          </div>

          <div id="readyCard" class="status-card tone-blue">
            <div class="status-label"><span class="status-dot"></span><span>Ready</span></div>
            <span id="readyValue" class="status-value">Not yet</span>
            <span id="readyDetail" class="status-detail">Waiting for finalization to complete.</span>
          </div>
        </div>

        <div class="terminal-wrap">
          <div class="terminal-toolbar">
            <div>
              <div class="terminal-title"><span class="live-dot"></span><span>Live backend log</span></div>
              <div class="terminal-subtitle">Always visible. Scroll freely while finalization continues.</div>
            </div>
            <div class="helper" id="logMeta">Waiting for log data…</div>
          </div>
          <pre id="terminal" class="terminal"></pre>
        </div>

        <div class="actions">
          <button id="continueButton" class="btn success" type="button" disabled>Continue to Login</button>
          <button id="refreshButton" class="btn primary" type="button">Refresh now</button>
          <button id="beginButton" class="btn warn" type="button" style="display:none;">Begin finalization</button>
          <span id="actionHelper" class="helper">Continue unlocks when finalization completes, or when the app is reachable after an error.</span>
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
      const statusBanner = document.getElementById('statusBanner');
      const continueButton = document.getElementById('continueButton');
      const refreshButton = document.getElementById('refreshButton');
      const beginButton = document.getElementById('beginButton');
      const actionHelper = document.getElementById('actionHelper');
      const logMeta = document.getElementById('logMeta');

      const appCard = document.getElementById('appCard');
      const appValue = document.getElementById('appValue');
      const appDetail = document.getElementById('appDetail');

      const templateCard = document.getElementById('templateCard');
      const templateValue = document.getElementById('templateValue');
      const templateDetail = document.getElementById('templateDetail');

      const readyCard = document.getElementById('readyCard');
      const readyValue = document.getElementById('readyValue');
      const readyDetail = document.getElementById('readyDetail');

      let lastKnownState = <?= json_encode($state, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?>;
      let appReachable = false;
      let lastTemplateStatus = 'pending';
      let lastTemplateMessage = 'Waiting for compact template defaults.';

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
      }

      function setBanner(kind, text) {
        statusBanner.className = 'banner ' + kind + ' show';
        statusBanner.textContent = text;
      }

      function setStatusCard(card, valueNode, detailNode, tone, valueText, detailText) {
        card.className = 'status-card ' + tone;
        valueNode.textContent = valueText;
        detailNode.textContent = detailText;
      }

      function updateBeginButton(state) {
        beginButton.style.display = (state === 'idle') ? '' : 'none';
      }

      function updateContinueButton() {
        const allowContinue = (lastKnownState === 'complete') || (lastKnownState === 'error' && appReachable);
        continueButton.disabled = !allowContinue;

        if (lastKnownState === 'complete') {
          actionHelper.textContent = 'Finalization complete. Continue when you are ready.';
        } else if (lastKnownState === 'error' && appReachable) {
          actionHelper.textContent = 'The app is reachable, but the finalizer reported an error. Review the log before continuing.';
        } else if (appReachable) {
          actionHelper.textContent = 'InvoicePlane is reachable. Waiting for finalizer completion.';
        } else {
          actionHelper.textContent = 'Waiting for app readiness and finalizer progress.';
        }
      }

      function renderCompositeState() {
        const inProgressStates = ['requested', 'updating', 'recreating', 'waiting'];

        if (appReachable) {
          setStatusCard(appCard, appValue, appDetail, 'tone-green', 'Reachable', 'InvoicePlane is responding.');
        } else if (inProgressStates.includes(lastKnownState)) {
          setStatusCard(appCard, appValue, appDetail, 'tone-amber', 'Starting up', 'Waiting for application response.');
        } else {
          setStatusCard(appCard, appValue, appDetail, 'tone-red', 'Offline', 'App not reachable yet.');
        }

        if (lastTemplateStatus === 'applied') {
          setStatusCard(templateCard, templateValue, templateDetail, 'tone-green', '2026 Compact Ready', lastTemplateMessage || 'Bundled compact templates confirmed.');
        } else if (lastTemplateStatus === 'error') {
          setStatusCard(templateCard, templateValue, templateDetail, 'tone-red', 'Needs attention', lastTemplateMessage || 'Unable to confirm compact template defaults.');
        } else if (inProgressStates.includes(lastKnownState)) {
          setStatusCard(templateCard, templateValue, templateDetail, 'tone-amber', 'Applying defaults', 'Waiting for compact template confirmation.');
        } else {
          setStatusCard(templateCard, templateValue, templateDetail, 'tone-red', 'Pending', lastTemplateMessage || 'Compact template defaults not yet applied.');
        }

        if (lastKnownState === 'complete') {
          setStatusCard(readyCard, readyValue, readyDetail, 'tone-green', 'Ready to Login', 'Finalizer completed successfully.');
        } else if (lastKnownState === 'error' && appReachable) {
          setStatusCard(readyCard, readyValue, readyDetail, 'tone-amber', 'Manual review', 'App reachable, but finalizer reported an error.');
        } else if (inProgressStates.includes(lastKnownState)) {
          setStatusCard(readyCard, readyValue, readyDetail, 'tone-blue', 'Finalizing', 'Working through post-install steps.');
        } else {
          setStatusCard(readyCard, readyValue, readyDetail, 'tone-red', 'Not ready', 'Waiting for finalization to begin.');
        }

        if (lastKnownState === 'complete') {
          setBanner('success', 'InvoicePlane finalizer completed successfully. Review the live log if you want, then continue to login.');
        } else if (lastKnownState === 'error') {
          setBanner('error', appReachable
            ? 'Finalizer reported an error, but the app appears reachable. Review the live log carefully before continuing.'
            : 'Finalizer reported an error. Review the live log before retrying.');
        } else if (appReachable) {
          setBanner('info', 'InvoicePlane is online. Waiting for finalizer completion...');
        } else {
          setBanner('info', 'Preparing your install. Live backend activity appears below.');
        }

        updateContinueButton();
        updateBeginButton(lastKnownState);
      }

      function renderStatus(data) {
        const state = typeof data.state === 'string' && data.state ? data.state : 'idle';
        const message = typeof data.message === 'string' && data.message ? data.message : 'No status message.';
        const templateStatus = typeof data.template_status === 'string' && data.template_status ? data.template_status : 'pending';
        const templateMessage = typeof data.template_message === 'string' && data.template_message ? data.template_message : 'Waiting for compact template defaults.';
        const log = typeof data.log === 'string' ? data.log : '';
        const timestamp = typeof data.timestamp === 'string' ? data.timestamp : '';
        const logSize = typeof data.log_size !== 'undefined' ? data.log_size : 'unknown';
        const logMtime = typeof data.log_mtime !== 'undefined' ? data.log_mtime : 'unknown';

        lastKnownState = state;
        lastTemplateStatus = templateStatus;
        lastTemplateMessage = templateMessage;

        updateStatePill(state);

        const renderedLog = ansiToHtml(log);
        if (terminal.innerHTML !== renderedLog) {
          const nearBottom = isNearBottom(terminal);
          terminal.innerHTML = renderedLog;
          if (nearBottom) scrollToBottom(terminal);
        }

        const refreshBits = [];
        if (timestamp) refreshBits.push('State ' + timestamp);
        if (logMtime) refreshBits.push('Log ' + logMtime);
        refreshBits.push('Size ' + logSize);
        logMeta.textContent = refreshBits.join(' · ');

        renderCompositeState();
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
          logMeta.textContent = 'Status fetch failed · ' + nowString();
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

        renderCompositeState();
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
          setBanner('info', 'Finalize request sent. Waiting for the finalizer sidecar to process it...');
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

