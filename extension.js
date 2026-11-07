const vscode = require("vscode");
const path = require("path");
const cp = require("child_process");
const fs = require("fs");
const os = require("os");
const net = require("net");
const readline = require("readline");

const WHISPER_PORT = 18971;

let whisperServerProc = null;
let ownsWhisperServer = false;
let daemonProc = null;
let daemonRl = null;

let isManualRecording = false;
let isBusyProcessing = false;
let autoMode = false;
let ttsState = "Stopped";

// Pure-RAM conversation & attachment state (zero temporary files on disk)
let ramSession = {
  turns: [],           // [{ role: "user" | "assistant", text: string }]
  detectedLang: "pl",  // ISO 2-letter code detected by OpenAI Whisper Turbo
  hasAttachment: false // Set true on Canvas [C] copy, PrintScreen image, or voice attachment paste
};

let pendingCaptureCallbacks = new Map();
let lastSeenSignatures = {
  assistant: "",
  user: "",
  initialized: false
};
let lastSpokenTextNorm = "";

function normalizeForCompare(str) {
  return (str || "").replace(/\s+/g, " ").trim().slice(0, 240).toLowerCase();
}

function sendDaemonCmd(payload) {
  if (daemonProc && daemonProc.stdin && !daemonProc.stdin.destroyed) {
    try {
      daemonProc.stdin.write(JSON.stringify(payload) + "\n", "utf8");
    } catch (e) {}
  }
}

function checkPortOpen(port, host = "127.0.0.1", timeoutMs = 450) {
  return new Promise((resolve) => {
    const sock = new net.Socket();
    let settled = false;
    const finish = (ok) => {
      if (!settled) {
        settled = true;
        try { sock.destroy(); } catch (e) {}
        resolve(ok);
      }
    };
    sock.setTimeout(timeoutMs);
    sock.once("connect", () => finish(true));
    sock.once("timeout", () => finish(false));
    sock.once("error", () => finish(false));
    sock.connect(port, host);
  });
}

// Dynamically locate latest CLI binaries so extension updates never break whisper_saver
function resolvePluginBinaries() {
  const home = os.homedir();
  const extRoot = path.join(home, ".vscode", "extensions");

  const agyExe = path.join(home, ".gemini", "bin", "agy.exe");
  let claudeExe = "";
  let codexExe = "";

  try {
    if (fs.existsSync(extRoot)) {
      const dirs = fs.readdirSync(extRoot);
      const claudeDirs = dirs.filter(d => d.startsWith("anthropic.claude-code-")).sort().reverse();
      for (const d of claudeDirs) {
        const candidate = path.join(extRoot, d, "resources", "native-binary", "claude.exe");
        if (fs.existsSync(candidate)) { claudeExe = candidate; break; }
      }
      const codexDirs = dirs.filter(d => d.startsWith("openai.chatgpt-")).sort().reverse();
      for (const d of codexDirs) {
        const candidate = path.join(extRoot, d, "bin", "windows-x86_64", "codex.exe");
        if (fs.existsSync(candidate)) { codexExe = candidate; break; }
      }
    }
  } catch (e) {}

  return {
    agyExe: fs.existsSync(agyExe) ? agyExe : "agy",
    claudeExe: claudeExe || "claude",
    codexExe: codexExe || "codex"
  };
}

function detectActivePlugin() {
  const cfg = vscode.workspace.getConfiguration("whisperSaver");
  const forced = cfg.get("targetPlugin", "auto");
  if (forced && forced !== "auto") return forced;

  try {
    for (const group of vscode.window.tabGroups.all) {
      const activeTab = group.activeTab;
      if (activeTab && activeTab.input && activeTab.input.viewType) {
        const vt = String(activeTab.input.viewType).toLowerCase();
        if (vt.includes("claude")) return "claude";
        if (vt.includes("chatgpt") || vt.includes("codex")) return "codex";
        if (vt.includes("grok") || vt.includes("xai")) return "grok";
        if (vt.includes("antigravity")) return "antigravity";
      }
    }
  } catch (e) {}

  const home = os.homedir();
  const candidates = [];

  const latestMtimeIn = (dirPath, filterFn, depth = 2) => {
    let best = 0;
    const walk = (curr, d) => {
      if (d < 0 || !fs.existsSync(curr)) return;
      let entries = [];
      try { entries = fs.readdirSync(curr, { withFileTypes: true }); } catch (e) { return; }
      for (const ent of entries) {
        const full = path.join(curr, ent.name);
        if (ent.isDirectory()) {
          walk(full, d - 1);
        } else if (!filterFn || filterFn(full, ent.name)) {
          try {
            const m = fs.statSync(full).mtimeMs;
            if (m > best) best = m;
          } catch (e) {}
        }
      }
    };
    walk(dirPath, depth);
    return best;
  };

  try {
    const brainRoot = path.join(home, ".gemini", "antigravity", "brain");
    if (fs.existsSync(brainRoot)) {
      let bestAgy = 0;
      for (const d of fs.readdirSync(brainRoot)) {
        const tf = path.join(brainRoot, d, ".system_generated", "logs", "transcript.jsonl");
        if (fs.existsSync(tf)) {
          const m = fs.statSync(tf).mtimeMs;
          if (m > bestAgy) bestAgy = m;
        }
      }
      if (bestAgy > 0) candidates.push({ plugin: "antigravity", mtime: bestAgy });
    }
  } catch (e) {}

  const bestClaude = latestMtimeIn(path.join(home, ".claude", "projects"), (_, n) => n.endsWith(".jsonl"), 2);
  if (bestClaude > 0) candidates.push({ plugin: "claude", mtime: bestClaude });

  const bestCodex = latestMtimeIn(path.join(home, ".codex", "sessions"), (_, n) => n.endsWith(".jsonl"), 4);
  if (bestCodex > 0) candidates.push({ plugin: "codex", mtime: bestCodex });

  try {
    const hasGrok = vscode.extensions.all.some(ext => /grok|xai/i.test(ext.id));
    if (hasGrok && candidates.length === 0) return "grok";
  } catch (e) {}

  if (candidates.length > 0) {
    candidates.sort((a, b) => b.mtime - a.mtime);
    return candidates[0].plugin;
  }

  return "antigravity";
}

function getCompactCommandForPlugin(plugin) {
  const cfg = vscode.workspace.getConfiguration("whisperSaver");
  const map = cfg.get("compactCommands") || {};
  const defaults = {
    antigravity: "/compact",
    claude: "/compact",
    codex: "/compact",
    grok: "/summarize"
  };
  return (map[plugin] || defaults[plugin] || "/compact").trim();
}

async function focusActivePluginChatInput(plugin) {
  const focusMap = {
    antigravity: ["antigravity.panel.focus"],
    claude: ["claude-vscode.focus", "claude-vscode.sidebar.open"],
    codex: ["chatgpt.openSidebar"],
    grok: ["grok.focus", "workbench.panel.chat.view.copilot.focus"]
  };
  const cmds = focusMap[plugin] || focusMap.antigravity;
  for (const c of cmds) {
    try {
      await vscode.commands.executeCommand(c);
      break;
    } catch (e) {}
  }
}

function readTailUtf8InRam(filePath, maxBytes = 65536) {
  try {
    if (!fs.existsSync(filePath)) return "";
    const stat = fs.statSync(filePath);
    if (stat.size === 0) return "";
    const readLen = Math.min(stat.size, maxBytes);
    const startPos = Math.max(0, stat.size - readLen);
    const buf = Buffer.alloc(readLen);
    const fd = fs.openSync(filePath, "r");
    try {
      fs.readSync(fd, buf, 0, readLen, startPos);
    } finally {
      fs.closeSync(fd);
    }
    let str = buf.toString("utf8");
    if (startPos > 0) {
      const nl = str.indexOf("\n");
      if (nl !== -1) str = str.slice(nl + 1);
    }
    return str;
  } catch (e) {
    return "";
  }
}

function readActiveTopicDataInRam(preferredPlugin) {
  const home = os.homedir();
  const sources = [];

  try {
    const brainRoot = path.join(home, ".gemini", "antigravity", "brain");
    if (fs.existsSync(brainRoot)) {
      let bestFile = "";
      let bestMtime = 0;
      for (const d of fs.readdirSync(brainRoot)) {
        const tf = path.join(brainRoot, d, ".system_generated", "logs", "transcript.jsonl");
        if (fs.existsSync(tf)) {
          const st = fs.statSync(tf);
          if (st.mtimeMs > bestMtime) { bestMtime = st.mtimeMs; bestFile = tf; }
        }
      }
      if (bestFile) sources.push({ plugin: "antigravity", file: bestFile, mtime: bestMtime });
    }
  } catch (e) {}

  try {
    const claudeRoot = path.join(home, ".claude", "projects");
    if (fs.existsSync(claudeRoot)) {
      let bestFile = "";
      let bestMtime = 0;
      for (const proj of fs.readdirSync(claudeRoot)) {
        const pDir = path.join(claudeRoot, proj);
        if (!fs.statSync(pDir).isDirectory()) continue;
        for (const f of fs.readdirSync(pDir)) {
          if (f.endsWith(".jsonl")) {
            const full = path.join(pDir, f);
            const st = fs.statSync(full);
            if (st.mtimeMs > bestMtime) { bestMtime = st.mtimeMs; bestFile = full; }
          }
        }
      }
      if (bestFile) sources.push({ plugin: "claude", file: bestFile, mtime: bestMtime });
    }
  } catch (e) {}

  try {
    const codexRoot = path.join(home, ".codex", "sessions");
    const walkCodex = (dir, depth) => {
      if (depth < 0 || !fs.existsSync(dir)) return;
      for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, ent.name);
        if (ent.isDirectory()) walkCodex(full, depth - 1);
        else if (ent.name.endsWith(".jsonl")) {
          const st = fs.statSync(full);
          sources.push({ plugin: "codex", file: full, mtime: st.mtimeMs });
        }
      }
    };
    walkCodex(codexRoot, 4);
  } catch (e) {}

  if (sources.length === 0) {
    return { contextSummary: "", lastAssistant: "", lastUser: "", mtime: 0 };
  }

  sources.sort((a, b) => {
    if (preferredPlugin && a.plugin === preferredPlugin && b.plugin !== preferredPlugin) {
      if (Math.abs(a.mtime - b.mtime) < 3600000) return -1;
    }
    if (preferredPlugin && b.plugin === preferredPlugin && a.plugin !== preferredPlugin) {
      if (Math.abs(a.mtime - b.mtime) < 3600000) return 1;
    }
    return b.mtime - a.mtime;
  });

  const chosen = sources[0];
  const tail = readTailUtf8InRam(chosen.file, 98304);
  const lines = tail.split("\n").filter(Boolean);

  const messages = [];
  let lastAssistantFinal = "";
  let lastUserFinal = "";

  for (const ln of lines) {
    try {
      const obj = JSON.parse(ln);
      if (chosen.plugin === "antigravity") {
        if (obj.type === "USER_INPUT" && obj.content) {
          const cleanU = String(obj.content).replace(/<\/?USER_REQUEST>/g, "").trim();
          if (cleanU) {
            messages.push({ role: "USER", text: cleanU });
            lastUserFinal = cleanU;
          }
        } else if (obj.source === "MODEL" && obj.type === "PLANNER_RESPONSE" && obj.content && String(obj.content).trim()) {
          const txt = String(obj.content).trim();
          messages.push({ role: "ASSISTANT", text: txt });
          if (!Array.isArray(obj.tool_calls) || obj.tool_calls.length === 0) {
            lastAssistantFinal = txt;
          }
        }
      } else if (chosen.plugin === "claude") {
        const m = obj.message || obj;
        if (m && (m.role === "user" || m.role === "assistant")) {
          let txt = "";
          if (typeof m.content === "string") txt = m.content;
          else if (Array.isArray(m.content)) {
            txt = m.content.filter(b => b && b.type === "text" && b.text).map(b => b.text).join("\n");
          }
          txt = txt.trim();
          if (txt) {
            const r = m.role === "user" ? "USER" : "ASSISTANT";
            messages.push({ role: r, text: txt });
            if (r === "ASSISTANT") lastAssistantFinal = txt;
            else lastUserFinal = txt;
          }
        }
      } else if (chosen.plugin === "codex") {
        const role = obj.role || (obj.payload && obj.payload.role);
        const content = obj.content || (obj.payload && obj.payload.content);
        let txt = "";
        if (typeof content === "string") txt = content;
        else if (Array.isArray(content)) {
          txt = content.map(c => c.text || c.output_text || c.input_text || "").join("\n");
        }
        txt = txt.trim();
        if (txt && (role === "user" || role === "assistant")) {
          const r = role === "user" ? "USER" : "ASSISTANT";
          messages.push({ role: r, text: txt });
          if (r === "ASSISTANT") lastAssistantFinal = txt;
          else lastUserFinal = txt;
        }
      }
    } catch (e) {}
  }

  const recent = messages.slice(-10).map(m => `${m.role}: ${m.text.slice(0, 900)}`).join("\n\n");
  return {
    plugin: chosen.plugin,
    contextSummary: recent.slice(-7500),
    lastAssistant: lastAssistantFinal,
    lastUser: lastUserFinal,
    mtime: chosen.mtime
  };
}

function runCheapModelInRam(plugin, systemPrompt, timeoutMs = 28000) {
  return new Promise((resolve) => {
    const bins = resolvePluginBinaries();
    let exe = bins.agyExe;
    let args = [];
    let useStdin = false;

    if (plugin === "claude" && bins.claudeExe) {
      exe = bins.claudeExe;
      args = ["-p", "--model", "sonnet", "--tools", ""];
      useStdin = true;
    } else if (plugin === "codex" && bins.codexExe) {
      exe = bins.codexExe;
      args = ["exec", "-c", 'model="gpt-6.1-sol"', "-c", 'model_reasoning_effort="low"', "--skip-git-repo-check", "-"];
      useStdin = true;
    } else {
      exe = bins.agyExe;
      args = ["--model", "Gemini 3.8 Flash (Low)", "--disable-slash-commands", "-p", systemPrompt];
      useStdin = false;
    }

    let done = false;
    const finish = (out) => {
      if (!done) {
        done = true;
        resolve((out || "").trim());
      }
    };

    try {
      const proc = cp.spawn(exe, args, {
        cwd: os.tmpdir(),
        windowsHide: true,
        stdio: ["pipe", "pipe", "pipe"]
      });

      const chunks = [];
      proc.stdout.on("data", d => chunks.push(d));

      const timer = setTimeout(() => {
        try { proc.kill(); } catch (e) {}
        finish(Buffer.concat(chunks).toString("utf8"));
      }, timeoutMs);

      proc.on("close", () => {
        clearTimeout(timer);
        finish(Buffer.concat(chunks).toString("utf8"));
      });

      proc.on("error", () => {
        clearTimeout(timer);
        if (exe !== bins.agyExe && fs.existsSync(bins.agyExe)) {
          cp.execFile(
            bins.agyExe,
            ["--model", "Gemini 3.8 Flash (Low)", "--disable-slash-commands", "-p", systemPrompt],
            { cwd: os.tmpdir(), timeout: timeoutMs, windowsHide: true },
            (_err, stdout) => finish(stdout || "")
          );
        } else {
          finish("");
        }
      });

      if (useStdin) {
        proc.stdin.write(systemPrompt, "utf8");
        proc.stdin.end();
      } else {
        proc.stdin.end();
      }
    } catch (e) {
      finish("");
    }
  });
}

function speakNaturalTts(text, langIso = "", requestId = "") {
  if (!text || !text.trim()) return;
  lastSpokenTextNorm = normalizeForCompare(text);
  sendDaemonCmd({
    cmd: "ttsSpeak",
    text: text.trim(),
    lang: langIso,
    requestId
  });
}

async function activate(context) {
  // Auto-remove legacy locked 'antigravity_mod' folder once VS Code opens 'whisper_saver'
  try {
    const activeFolders = (vscode.workspace.workspaceFolders || []).map(f => f.uri.fsPath.toLowerCase());
    const legacyFolder = path.join(os.homedir(), "projects", "antigravity_mod");
    if (!activeFolders.includes(legacyFolder.toLowerCase()) && fs.existsSync(legacyFolder)) {
      fs.rmSync(legacyFolder, { recursive: true, force: true });
    }
  } catch (e) {}

  const binDir = path.join(context.extensionPath, "bin");
  const scriptsDir = path.join(context.extensionPath, "src");

  const canvasScript = path.join(scriptsDir, "CanvasOverlay.ps1");
  const daemonScript = path.join(scriptsDir, "WhisperDaemon.ps1");
  const whisperServerExe = path.join(binDir, "whisper-server.exe");

  const turboModel = path.join(binDir, "ggml-large-v3-turbo-q5_0.bin");
  const fallbackModel = path.join(binDir, "ggml-base.bin");
  const activeWhisperModel = fs.existsSync(turboModel) ? turboModel : fallbackModel;

  // =========================================================================
  // 1. Status Bar Icons (Bottom Bar of VS Code)
  // =========================================================================
  const canvasBtn = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 104);
  canvasBtn.command = "whisperSaver.canvas";
  canvasBtn.text = "$(device-camera) C";
  canvasBtn.tooltip = "whisper_saver [C]: Wycinek ekranu + Rysowanie -> Ctrl+C kompresuje do 768px w RAM (Alt+C)";
  canvasBtn.show();

  const micBtn = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 103);
  micBtn.command = "whisperSaver.voiceMic";
  micBtn.text = "$(mic)";
  micBtn.tooltip = "whisper_saver [Mic]: Stacjonarny Array/USB + OpenAI Whisper Turbo ('whisper over' / 'whisper enter', Alt+M)";
  micBtn.show();

  const ttsBtn = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 102);
  ttsBtn.command = "whisperSaver.ttsPlay";
  ttsBtn.text = "$(play) ▶";
  ttsBtn.tooltip = "whisper_saver [Play/Pause]: Słuchawki Bluetooth Stereo 48kHz 16-bit / AUX (głośniki zablokowane, Alt+P)";
  ttsBtn.show();

  const autoBtn = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 101);
  autoBtn.command = "whisperSaver.toggleAuto";
  autoBtn.text = "$(radio-tower) A";
  autoBtn.tooltip = "whisper_saver [A]: Tryb Auto (Auto TTS przy pisaniu w input + Auto nasłuchiwanie mikrofonu Array/USB ON, Alt+A)";
  autoBtn.show();

  const refreshMicUi = (status = "idle") => {
    if (status === "recording") {
      micBtn.text = "$(record) REC";
      micBtn.color = "#ff5555";
    } else if (status === "processing") {
      micBtn.text = "$(sync~spin) AI";
      micBtn.color = "#fbbf24";
    } else if (autoMode) {
      micBtn.text = "$(mic) AUTO";
      micBtn.color = "#4ade80";
    } else {
      micBtn.text = "$(mic)";
      micBtn.color = undefined;
    }
  };

  // =========================================================================
  // 2. Start Persistent In-RAM OpenAI Whisper Turbo Server & Audio/TTS Daemon
  // =========================================================================
  const alreadyRunning = await checkPortOpen(WHISPER_PORT);
  if (!alreadyRunning && fs.existsSync(whisperServerExe) && fs.existsSync(activeWhisperModel)) {
    const cpuThreads = Math.max(4, Math.min(12, os.cpus().length - 2));
    whisperServerProc = cp.spawn(
      whisperServerExe,
      [
        "-m", activeWhisperModel,
        "--host", "127.0.0.1",
        "--port", String(WHISPER_PORT),
        "-l", "auto",
        "-nt",
        "-sns",
        "-t", String(cpuThreads)
      ],
      { cwd: binDir, windowsHide: true, stdio: "ignore" }
    );
    ownsWhisperServer = true;
    whisperServerProc.on("error", () => { whisperServerProc = null; });
  }

  if (fs.existsSync(daemonScript)) {
    daemonProc = cp.spawn(
      "powershell.exe",
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", daemonScript, "-WhisperPort", String(WHISPER_PORT)],
      { windowsHide: true, stdio: ["pipe", "pipe", "ignore"] }
    );

    daemonRl = readline.createInterface({ input: daemonProc.stdout });
    daemonRl.on("line", async (line) => {
      let evt = null;
      try { evt = JSON.parse(line); } catch (e) { return; }
      if (!evt || !evt.event) return;

      switch (evt.event) {
        case "ttsState": {
          ttsState = evt.state || "Stopped";
          if (ttsState === "Playing") {
            ttsBtn.text = "$(debug-pause) ❚❚";
            ttsBtn.color = "#60a5fa";
            ttsBtn.tooltip = `whisper_saver: Odtwarzanie 48kHz 16-bit Stereo (${evt.voice || "Natural TTS"} -> ${evt.device || "Słuchawki"})`;
          } else if (ttsState === "Paused") {
            ttsBtn.text = "$(play) ▶";
            ttsBtn.color = "#fbbf24";
            ttsBtn.tooltip = "whisper_saver: Spauzowano — kliknij lub użyj przycisku na słuchawce Bluetooth, aby wznowić";
          } else {
            ttsBtn.text = "$(play) ▶";
            ttsBtn.color = undefined;
            ttsBtn.tooltip = "whisper_saver [Play/Pause]: Słuchawki Bluetooth Stereo 48kHz 16-bit / AUX (głośniki zablokowane, Alt+P)";
          }
          break;
        }

        case "ttsBlockedNoHeadphones": {
          vscode.window.setStatusBarMessage("$(mute) whisper_saver: Głośniki są zablokowane — podłącz słuchawki Bluetooth Stereo lub AUX!", 5000);
          break;
        }

        case "vadSpeechStart": {
          if (autoMode && !isManualRecording) {
            refreshMicUi("recording");
            vscode.window.setStatusBarMessage("$(record) whisper_saver [Auto]: Słucham (Array/USB)...", 8000);
          }
          break;
        }

        case "vadProcessing": {
          refreshMicUi("processing");
          vscode.window.setStatusBarMessage("$(sync~spin) whisper_saver: Whisper Turbo rozpoznaje mowę w RAM...", 10000);
          break;
        }

        case "micIdle": {
          isManualRecording = false;
          refreshMicUi("idle");
          break;
        }

        case "clipboardImageDetected": {
          ramSession.hasAttachment = true;
          vscode.window.setStatusBarMessage("$(clippy) whisper_saver: Wykryto obraz w schowku RAM (dodam /compact przy wysyłce)", 4500);
          break;
        }

        case "inputCaptured": {
          const cb = pendingCaptureCallbacks.get(evt.requestId);
          if (cb) {
            pendingCaptureCallbacks.delete(evt.requestId);
            cb(evt.text || "");
          }
          break;
        }

        case "transcription": {
          await handleWhisperTranscription(evt.text || "", evt.lang || "pl");
          break;
        }
      }
    });
  }

  // =========================================================================
  // 3. Core Voice Co-Pilot Logic ("whisper over", "whisper enter" & attachments)
  // =========================================================================
  async function finalizeGrammarSpeakAndSend(rawDraftText, langIso, plugin, includeDialogueTurns) {
    isBusyProcessing = true;
    refreshMicUi("processing");

    try {
      const langLabel = langIso === "pl" ? "Polish" : langIso === "en" ? "English" : `ISO language '${langIso}'`;
      let combinedSource = rawDraftText;

      if (includeDialogueTurns && ramSession.turns.length > 0) {
        const historyLines = ramSession.turns.map(t => `${t.role === "user" ? "User" : "Assistant"}: ${t.text}`).join("\n");
        combinedSource = `${historyLines}\nUser final input: ${rawDraftText}`;
      }

      const polishPrompt =
        `You are an expert technical editor and prompt polisher.\n` +
        `Target language: ${langLabel} (keep 100% the user's spoken language, do NOT translate to another language).\n` +
        `Tasks:\n` +
        `1. Synthesize the user's intent into a single, grammatically flawless message with rich, precise vocabulary.\n` +
        `2. Strictly preserve 100% of the core meaning and intent. Do NOT start a discussion, do NOT ask questions, and do NOT answer the prompt yourself.\n` +
        `3. Output ONLY the improved message text ready to be sent to the chat. No quotes, no markdown wrappers, no explanations.\n\n` +
        `--- INPUT ---\n${combinedSource}`;

      vscode.window.setStatusBarMessage(`$(sync~spin) whisper_saver (${plugin}): Poprawiam gramatykę i słownictwo w RAM...`, 12000);
      let improved = await runCheapModelInRam(plugin, polishPrompt);
      if (!improved) improved = rawDraftText.trim();

      improved = improved.replace(/^["«„]+|["»”]+$/g, "").trim();

      let payloadForChat = improved;
      if (ramSession.hasAttachment) {
        const compactCmd = getCompactCommandForPlugin(plugin);
        if (!payloadForChat.includes(compactCmd)) {
          payloadForChat = `${payloadForChat}\n${compactCmd} `;
        }
      }

      speakNaturalTts(improved, langIso, "post_grammar_send");

      await focusActivePluginChatInput(plugin);
      sendDaemonCmd({
        cmd: "injectChat",
        text: payloadForChat,
        replace: true,
        submit: true
      });

      ramSession.turns = [];
      ramSession.hasAttachment = false;

      vscode.window.setStatusBarMessage("$(check) whisper_saver: Odczytano TTS i wysłano na czat!", 5000);
    } finally {
      isBusyProcessing = false;
      refreshMicUi("idle");
    }
  }

  async function handleWhisperOverDiscussion(cleanUserSpeech, langIso, plugin) {
    isBusyProcessing = true;
    refreshMicUi("processing");

    try {
      if (cleanUserSpeech) {
        ramSession.turns.push({ role: "user", text: cleanUserSpeech });
      }
      if (ramSession.turns.length === 0) return;

      const topicData = readActiveTopicDataInRam(plugin);
      const langLabel = langIso === "pl" ? "Polish" : langIso === "en" ? "English" : `ISO language '${langIso}'`;
      const dialogueBlock = ramSession.turns
        .map((t, idx) => `[${idx + 1}] ${t.role === "user" ? "USER" : "CO-PILOT"}: ${t.text}`)
        .join("\n");

      const overPrompt =
        `You are an intelligent voice co-pilot helping the user craft a complete prompt before sending it to the main expensive AI model.\n` +
        `Language rule: Respond EXCLUSIVELY in ${langLabel} (matching the user's spoken language).\n\n` +
        `=== CURRENT MAIN CHAT TOPIC CONTEXT (READ-ONLY RAM) ===\n` +
        `${topicData.contextSummary || "(New topic)"}\n\n` +
        `=== CURRENT LIVE VOICE DISCUSSION IN RAM ===\n` +
        `${dialogueBlock}\n\n` +
        `Instructions:\n` +
        `1. Check if the user forgot an important detail, skipped an edge case, or left ambiguity relative to the topic context, OR if the user is still discussing options with you.\n` +
        `2. If something important is missing or worth clarifying:\n` +
        `   Output prefix "ASK:" followed by a concise, grammatically polished question (1-2 short sentences) in ${langLabel}.\n` +
        `3. ONLY if the user has already answered your previous question(s) and everything is now 100% clear, complete, and ready to execute on the main chat:\n` +
        `   Output prefix "SEND:" followed by the final grammatically corrected, vocabulary-enriched prompt combining all user requirements in ${langLabel} (preserving exact meaning, no extra commentary).\n` +
        `Output ONLY "ASK: <text>" or "SEND: <text>".`;

      vscode.window.setStatusBarMessage(`$(sync~spin) whisper_saver (${plugin}): Konsultacja 'whisper over' w RAM...`, 15000);
      const rawReply = await runCheapModelInRam(plugin, overPrompt);

      if (!rawReply) {
        vscode.window.showWarningMessage("whisper_saver: Brak odpowiedzi modelu pomocniczego.");
        return;
      }

      if (/^SEND\s*:/i.test(rawReply)) {
        const finalPrompt = rawReply.replace(/^SEND\s*:\s*/i, "").trim();
        let payloadForChat = finalPrompt;
        if (ramSession.hasAttachment) {
          const compactCmd = getCompactCommandForPlugin(plugin);
          if (!payloadForChat.includes(compactCmd)) {
            payloadForChat = `${payloadForChat}\n${compactCmd} `;
          }
        }

        speakNaturalTts(finalPrompt, langIso, "over_final_send");
        await focusActivePluginChatInput(plugin);
        sendDaemonCmd({
          cmd: "injectChat",
          text: payloadForChat,
          replace: true,
          submit: true
        });

        ramSession.turns = [];
        ramSession.hasAttachment = false;
        vscode.window.setStatusBarMessage("$(check) whisper_saver: Kontekst kompletny — odczytano TTS i wysłano na czat!", 5000);
      } else {
        const questionText = rawReply.replace(/^ASK\s*:\s*/i, "").trim();
        ramSession.turns.push({ role: "assistant", text: questionText });

        await focusActivePluginChatInput(plugin);
        sendDaemonCmd({
          cmd: "injectChat",
          text: questionText,
          replace: true,
          submit: false
        });
        speakNaturalTts(questionText, langIso, "over_question");
        vscode.window.setStatusBarMessage(`$(comment-discussion) whisper_saver: Odpowiedz i powiedz "whisper over" lub "whisper enter"`, 10000);
      }
    } finally {
      isBusyProcessing = false;
      refreshMicUi("idle");
    }
  }

  async function handleWhisperTranscription(rawText, detectedLang) {
    refreshMicUi("idle");
    const trimmed = (rawText || "").trim();
    if (!trimmed) {
      vscode.window.setStatusBarMessage("$(info) whisper_saver: Nie wykryto mowy.", 3000);
      return;
    }

    ramSession.detectedLang = detectedLang || "pl";
    const plugin = detectActivePlugin();

    const attachRegex = /\b(?:wklej\s+(?:screen\w*|zrzut\w*|obraz\w*|załącznik\w*)|dodaj\s+(?:screen\w*|obraz\w*|załącznik\w*)|załącz\s+(?:screen\w*|obraz\w*)|(?:whisper|łisper|wisper)\s+(?:paste|screen|screenshot|image|załącznik|obrazek)|paste\s+(?:screen\w*|image)|attach\s+(?:screen\w*|image))\b[,.!?]*/gi;
    let workingText = trimmed;
    if (attachRegex.test(workingText)) {
      workingText = workingText.replace(attachRegex, "").trim();
      ramSession.hasAttachment = true;
      await focusActivePluginChatInput(plugin);
      sendDaemonCmd({ cmd: "pasteImage" });
      await new Promise(r => setTimeout(r, 180));
    }

    const overRegex = /[,\s]*(?:whisper|łisper|wisper)[,\s]+(?:over|ower|odbiór)[\s.!?]*$/i;
    const enterRegex = /[,\s]*(?:whisper|łisper|wisper)[,\s]+(?:enter|wyślij)[\s.!?]*$/i;

    if (enterRegex.test(workingText)) {
      const cleanBody = workingText.replace(enterRegex, "").trim();
      await finalizeGrammarSpeakAndSend(cleanBody, ramSession.detectedLang, plugin, true);
      return;
    }

    if (overRegex.test(workingText)) {
      const cleanBody = workingText.replace(overRegex, "").trim();
      await handleWhisperOverDiscussion(cleanBody, ramSession.detectedLang, plugin);
      return;
    }

    if (workingText) {
      ramSession.turns.push({ role: "user", text: workingText });
      await focusActivePluginChatInput(plugin);
      sendDaemonCmd({
        cmd: "injectChat",
        text: workingText,
        replace: false,
        submit: false
      });
      if (autoMode) {
        speakNaturalTts(workingText, ramSession.detectedLang, "auto_dictation");
      }
      vscode.window.setStatusBarMessage(`$(check) whisper_saver [${ramSession.detectedLang.toUpperCase()}]: "${workingText.slice(0, 60)}"`, 5000);
    }
  }

  // =========================================================================
  // 4. Background RAM Watcher for Main Chat Model Responses & Auto [A] Mode
  // =========================================================================
  const initializeSignatures = () => {
    const data = readActiveTopicDataInRam(detectActivePlugin());
    lastSeenSignatures.assistant = normalizeForCompare(data.lastAssistant);
    lastSeenSignatures.user = normalizeForCompare(data.lastUser);
    lastSeenSignatures.initialized = true;
  };
  initializeSignatures();

  const chatPollTimer = setInterval(() => {
    try {
      if (isBusyProcessing) return;
      const cfg = vscode.workspace.getConfiguration("whisperSaver");
      const autoReadMain = cfg.get("autoReadResponses", true);
      if (!autoReadMain && !autoMode) return;

      const plugin = detectActivePlugin();
      const data = readActiveTopicDataInRam(plugin);
      if (!data.mtime) return;

      if (Date.now() - data.mtime < 1400) return;

      if (autoMode && data.lastUser) {
        const uNorm = normalizeForCompare(data.lastUser);
        if (uNorm && uNorm !== lastSeenSignatures.user) {
          lastSeenSignatures.user = uNorm;
          if (uNorm !== lastSpokenTextNorm && ttsState === "Stopped") {
            speakNaturalTts(data.lastUser, "", "auto_user_input");
          }
        }
      } else if (data.lastUser) {
        lastSeenSignatures.user = normalizeForCompare(data.lastUser);
      }

      if ((autoReadMain || autoMode) && data.lastAssistant) {
        const aNorm = normalizeForCompare(data.lastAssistant);
        if (aNorm && aNorm !== lastSeenSignatures.assistant) {
          lastSeenSignatures.assistant = aNorm;
          if (aNorm !== lastSpokenTextNorm) {
            speakNaturalTts(data.lastAssistant, "", "main_chat_response");
          }
        }
      }
    } catch (e) {}
  }, 1300);
  context.subscriptions.push({ dispose: () => clearInterval(chatPollTimer) });

  // =========================================================================
  // 5. Automatic Git Commit & Push Watcher on Workspace File Changes
  // =========================================================================
  let gitDebounceTimer = null;
  let gitSyncRunning = false;

  const triggerAutoGitSync = (folderPath) => {
    const cfg = vscode.workspace.getConfiguration("whisperSaver");
    if (!cfg.get("autoGitCommitPush", true)) return;
    if (!folderPath || !fs.existsSync(path.join(folderPath, ".git"))) return;

    if (gitDebounceTimer) clearTimeout(gitDebounceTimer);
    gitDebounceTimer = setTimeout(() => {
      if (gitSyncRunning) return;
      gitSyncRunning = true;

      cp.exec("git status --porcelain", { cwd: folderPath, windowsHide: true }, (err, stdout) => {
        if (err || !(stdout || "").trim()) {
          gitSyncRunning = false;
          return;
        }
        const changedFiles = (stdout || "")
          .trim()
          .split("\n")
          .map(l => l.trim().replace(/^[A-Z?]+\s+/, ""))
          .slice(0, 4)
          .join(", ");
        const msg = `chore(auto): update ${changedFiles || "workspace files"}`;

        cp.exec(
          `git add -A && git commit -m "${msg.replace(/"/g, "'")}" && git push`,
          { cwd: folderPath, windowsHide: true, timeout: 45000 },
          (pushErr) => {
            gitSyncRunning = false;
            if (!pushErr) {
              vscode.window.setStatusBarMessage("$(cloud-upload) whisper_saver: Auto commit & push wykonany!", 4000);
            }
          }
        );
      });
    }, 8000);
  };

  const fsWatcher = vscode.workspace.createFileSystemWatcher("**/*", false, false, false);
  const onFsChange = (uri) => {
    if (!uri || !uri.fsPath) return;
    if (/[\\/]\.git([\\/]|$)|[\\/]node_modules([\\/]|$)|\.bin$|\.log$/i.test(uri.fsPath)) return;
    const wf = vscode.workspace.getWorkspaceFolder(uri);
    if (wf && wf.uri && wf.uri.fsPath) {
      triggerAutoGitSync(wf.uri.fsPath);
    }
  };
  fsWatcher.onDidChange(onFsChange);
  fsWatcher.onDidCreate(onFsChange);
  fsWatcher.onDidDelete(onFsChange);
  context.subscriptions.push(fsWatcher);

  // =========================================================================
  // 6. Registered Commands
  // =========================================================================
  const canvasCmd = vscode.commands.registerCommand("whisperSaver.canvas", () => {
    if (!fs.existsSync(canvasScript)) {
      vscode.window.showErrorMessage("whisper_saver: Brak pliku src/CanvasOverlay.ps1");
      return;
    }
    vscode.window.setStatusBarMessage("$(device-camera) whisper_saver Canvas: Zaznacz obszar, narysuj poprawki i naciśnij Ctrl+C (768px w RAM)...", 8000);
    cp.execFile(
      "powershell.exe",
      ["-STA", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", canvasScript],
      { windowsHide: true },
      (_err, stdout) => {
        if ((stdout || "").includes("CANVAS_COPIED_768")) {
          ramSession.hasAttachment = true;
          vscode.window.setStatusBarMessage("$(check) whisper_saver: Wycinek z rysunkiem (768px w RAM) skopiowany do schowka! Wklej Ctrl+V (auto /compact aktywny).", 6000);
        }
      }
    );
  });

  const micCmd = vscode.commands.registerCommand("whisperSaver.voiceMic", () => {
    if (!isManualRecording) {
      isManualRecording = true;
      refreshMicUi("recording");
      sendDaemonCmd({ cmd: "startMic" });
      vscode.window.setStatusBarMessage("$(record) whisper_saver: Nagrywam w RAM (Array/USB)... Zakończ 'whisper over' lub 'whisper enter' i wciśnij Alt+M.", 30000);
    } else {
      isManualRecording = false;
      refreshMicUi("processing");
      vscode.window.setStatusBarMessage("$(sync~spin) whisper_saver: Rozpoznawanie mowy i języka przez OpenAI Whisper Turbo...", 15000);
      sendDaemonCmd({ cmd: "stopMic" });
    }
  });

  const ttsCmd = vscode.commands.registerCommand("whisperSaver.ttsPlay", async () => {
    if (ttsState === "Playing" || ttsState === "Paused") {
      sendDaemonCmd({ cmd: "ttsToggle" });
      return;
    }

    let textToSpeak = "";
    const editor = vscode.window.activeTextEditor;
    if (editor && !editor.selection.isEmpty) {
      textToSpeak = editor.document.getText(editor.selection).trim();
    }
    if (!textToSpeak) {
      const topicData = readActiveTopicDataInRam(detectActivePlugin());
      textToSpeak = topicData.lastAssistant || "";
    }
    if (!textToSpeak) {
      textToSpeak = (await vscode.env.clipboard.readText()).trim();
    }

    if (!textToSpeak) {
      vscode.window.showInformationMessage("whisper_saver: Brak wiadomości odpowiedzi do odczytania.");
      return;
    }

    speakNaturalTts(textToSpeak, "", "manual_play");
  });

  const autoCmd = vscode.commands.registerCommand("whisperSaver.toggleAuto", () => {
    autoMode = !autoMode;
    sendDaemonCmd({ cmd: "setAutoVad", enabled: autoMode });

    if (autoMode) {
      autoBtn.text = "$(radio-tower) A [ON]";
      autoBtn.color = "#4ade80";
      refreshMicUi("idle");
      vscode.window.setStatusBarMessage("$(radio-tower) whisper_saver [A] ON: Automatyczny TTS i automatyczne nasłuchiwanie mikrofonu Array/USB aktywne!", 5000);
    } else {
      autoBtn.text = "$(radio-tower) A";
      autoBtn.color = undefined;
      refreshMicUi("idle");
      vscode.window.setStatusBarMessage("$(radio-tower) whisper_saver [A] OFF: Tryb ręczny mikrofonu.", 4000);
    }
  });

  const enhanceCmd = vscode.commands.registerCommand("whisperSaver.enhanceAndSend", async () => {
    const plugin = detectActivePlugin();
    let draft = "";

    const editor = vscode.window.activeTextEditor;
    if (editor && !editor.selection.isEmpty) {
      draft = editor.document.getText(editor.selection).trim();
    } else {
      const reqId = "cap_" + Date.now();
      draft = await new Promise((resolve) => {
        const timeout = setTimeout(() => {
          pendingCaptureCallbacks.delete(reqId);
          resolve("");
        }, 2200);
        pendingCaptureCallbacks.set(reqId, (txt) => {
          clearTimeout(timeout);
          resolve((txt || "").trim());
        });
        sendDaemonCmd({ cmd: "captureInput", requestId: reqId });
      });
    }

    if (!draft) {
      vscode.window.showWarningMessage("whisper_saver: Wpisz wiadomość w polu inputu czatu przed użyciem Ctrl+Alt+Enter.");
      return;
    }

    const isPl = /[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]|\b(jest|nie|dla|się|czy|tak|jak|oraz|kod|teraz)\b/i.test(draft);
    await finalizeGrammarSpeakAndSend(draft, isPl ? "pl" : "en", plugin, false);
  });

  const pasteAttachCmd = vscode.commands.registerCommand("whisperSaver.pasteAttachment", async () => {
    const plugin = detectActivePlugin();
    ramSession.hasAttachment = true;
    await focusActivePluginChatInput(plugin);
    sendDaemonCmd({ cmd: "pasteImage" });
    vscode.window.setStatusBarMessage(`$(clippy) whisper_saver: Załącznik wklejony — po wysłaniu automatycznie dodam ${getCompactCommandForPlugin(plugin)}`, 5000);
  });

  const selectPluginCmd = vscode.commands.registerCommand("whisperSaver.selectPlugin", async () => {
    const picked = await vscode.window.showQuickPick(
      [
        { label: "auto", description: "Automatyczne wykrywanie aktywnego czatu (Zalecane)" },
        { label: "antigravity", description: "Antigravity (Gemini 3.8 Flash + /compact)" },
        { label: "claude", description: "Claude Code (Claude Sonnet + /compact)" },
        { label: "codex", description: "OpenAI Codex (GPT-6.1 Sol Low + /compact)" },
        { label: "grok", description: "Grok / Cursor (/summarize)" }
      ],
      { placeHolder: "Wybierz docelowy plugin czatu dla whisper_saver" }
    );
    if (picked) {
      await vscode.workspace.getConfiguration("whisperSaver").update("targetPlugin", picked.label, vscode.ConfigurationTarget.Global);
      vscode.window.setStatusBarMessage(`$(check) whisper_saver: Ustawiono tryb pluginu -> ${picked.label}`, 4000);
    }
  });

  context.subscriptions.push(
    canvasBtn,
    micBtn,
    ttsBtn,
    autoBtn,
    canvasCmd,
    micCmd,
    ttsCmd,
    autoCmd,
    enhanceCmd,
    pasteAttachCmd,
    selectPluginCmd
  );
}

function deactivate() {
  try {
    sendDaemonCmd({ cmd: "shutdown" });
  } catch (e) {}
  if (daemonRl) {
    try { daemonRl.close(); } catch (e) {}
    daemonRl = null;
  }
  if (daemonProc) {
    try { daemonProc.kill(); } catch (e) {}
    daemonProc = null;
  }
  if (ownsWhisperServer && whisperServerProc) {
    try { whisperServerProc.kill(); } catch (e) {}
    whisperServerProc = null;
  }
}

module.exports = {
  activate,
  deactivate
};
