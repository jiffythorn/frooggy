#!/usr/bin/env bash
# ================================================
# MrT AI Hub PRO - Auto Installer v3.2
# Multi-AI Support | Dynamic Model Selection | Smart Port Handling
# File Attachments | Project Save | Auto Model-Restart
# Updated: March 2026
# ================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting MrT AI Hub PRO v3.2 Installation...${NC}"

CURRENT_DIR="$(pwd)"
if [[ "$CURRENT_DIR" == "$HOME/Downloads"* ]]; then
    echo -e "${YELLOW}⚠️  Detected running from Downloads folder.${NC}"
    mkdir -p "$HOME/mrt-ai-hub-pro"
    cp "$0" "$HOME/mrt-ai-hub-pro/install-mrt-pro-v3.2.sh"
    cd "$HOME/mrt-ai-hub-pro"
    chmod +x install-mrt-pro-v3.2.sh
    echo -e "${GREEN}✅ Moving to clean folder and restarting...${NC}"
    exec "$HOME/mrt-ai-hub-pro/install-mrt-pro-v3.2.sh"
fi

INSTALL_DIR="$(pwd)"
echo -e "${BLUE}📍 Installing in: $INSTALL_DIR${NC}"

if [ -f "$INSTALL_DIR/server/app.js" ]; then
    echo ""
    echo -e "${YELLOW}⚠️  Existing installation detected!${NC}"
    read -p "Continue and update? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}❌ Cancelled.${NC}"
        exit 1
    fi
fi

mkdir -p "$INSTALL_DIR"/{server,frontend,data}

# ===================================================================
# API Provider Selection
# ===================================================================
echo ""
echo -e "${BLUE}🔑 AI API Provider Setup${NC}"
echo ""
echo "Choose your AI provider:"
echo "  1) Google Gemini    (Free tier available)"
echo "  2) Anthropic Claude (API key required)"
echo "  3) OpenAI ChatGPT   (API key required)"
echo ""
read -p "Enter choice (1-3) [default: 1]: " PROVIDER_CHOICE
PROVIDER_CHOICE="${PROVIDER_CHOICE:-1}"

case "$PROVIDER_CHOICE" in
  2)
    PROVIDER="claude"
    PROVIDER_URL="https://console.anthropic.com"
    echo -e "${BLUE}Claude selected - visit: ${GREEN}$PROVIDER_URL${NC}"
    read -p "Paste your Claude API key: " API_KEY
    ;;
  3)
    PROVIDER="openai"
    PROVIDER_URL="https://platform.openai.com/api-keys"
    echo -e "${BLUE}ChatGPT selected - visit: ${GREEN}$PROVIDER_URL${NC}"
    read -p "Paste your OpenAI API key: " API_KEY
    ;;
  *)
    PROVIDER="gemini"
    PROVIDER_URL="https://aistudio.google.com/app/apikey"
    echo -e "${BLUE}Gemini selected - visit: ${GREEN}$PROVIDER_URL${NC}"
    read -p "Paste your Gemini API key: " API_KEY
    ;;
esac

EXISTING_KEY=""
if [ -f "$INSTALL_DIR/server/.env" ]; then
    EXISTING_KEY=$(grep -oP "(?<=$(echo "$PROVIDER" | tr '[:lower:]' '[:upper:]')_KEY=).*" "$INSTALL_DIR/server/.env" 2>/dev/null || true)
fi

if [ -n "$EXISTING_KEY" ]; then
    echo ""
    echo -e "${BLUE}Found existing ${PROVIDER} key: ${GREEN}${EXISTING_KEY:0:8}...${NC}"
    read -p "Press ENTER to keep it, or paste a new key: " NEW_KEY
    API_KEY="${NEW_KEY:-$EXISTING_KEY}"
fi

if [ -z "$API_KEY" ]; then
    echo -e "${RED}❌ An API key is required.${NC}"
    echo "   Get one free at: $PROVIDER_URL"
    exit 1
fi

if [ "${#API_KEY}" -lt 10 ]; then
    echo -e "${RED}❌ API key appears too short. Please verify.${NC}"
    exit 1
fi

# ===================================================================
# Model Selection
# ===================================================================
echo ""
echo -e "${BLUE}🤖 Model Configuration${NC}"

case "$PROVIDER" in
    claude) DEFAULT_MODEL="claude-3-5-sonnet-20241022" ;;
    openai) DEFAULT_MODEL="gpt-4o-mini" ;;
    *)      DEFAULT_MODEL="gemini-1.5-flash" ;;
esac

EXISTING_MODEL=""
if [ -f "$INSTALL_DIR/server/.env" ]; then
    EXISTING_MODEL=$(grep -oP "(?<=MODEL_NAME=).*" "$INSTALL_DIR/server/.env" 2>/dev/null || true)
fi

if [ -n "$EXISTING_MODEL" ]; then
    echo -e "  Current model: ${GREEN}$EXISTING_MODEL${NC}"
    read -p "  Press ENTER to keep it, or enter a new model name [default: $DEFAULT_MODEL]: " CUSTOM_MODEL
    MODEL_NAME="${CUSTOM_MODEL:-$EXISTING_MODEL}"
else
    echo -e "  Default model for ${PROVIDER}: ${GREEN}$DEFAULT_MODEL${NC}"
    read -p "  Press ENTER to use default, or enter a custom model name: " CUSTOM_MODEL
    MODEL_NAME="${CUSTOM_MODEL:-$DEFAULT_MODEL}"
fi

echo -e "${GREEN}  ✅ Model: $MODEL_NAME${NC}"

# ===================================================================
# Custom API Endpoint (optional)
# ===================================================================
echo ""
echo -e "${BLUE}🔗 Custom API Endpoint (optional)${NC}"
echo -e "  ${YELLOW}Leave blank to use the standard provider endpoint.${NC}"

EXISTING_URL=""
if [ -f "$INSTALL_DIR/server/.env" ]; then
    EXISTING_URL=$(grep -oP "(?<=API_BASE_URL=).*" "$INSTALL_DIR/server/.env" 2>/dev/null || true)
fi

if [ -n "$EXISTING_URL" ]; then
    echo -e "  Current endpoint: ${GREEN}$EXISTING_URL${NC}"
    read -p "  Press ENTER to keep it, or enter a new URL (type 'clear' to remove): " NEW_URL
    if [[ "${NEW_URL:-}" == "clear" ]]; then
        API_BASE_URL=""
    else
        API_BASE_URL="${NEW_URL:-$EXISTING_URL}"
    fi
else
    read -p "  Custom API base URL (or press ENTER to skip): " API_BASE_URL
fi

# ===================================================================
# Port Configuration
# ===================================================================
echo ""
echo -e "${BLUE}🌐 Port Configuration${NC}"

DEFAULT_PORT=8080
APP_PORT=$DEFAULT_PORT

port_in_use() {
    local p="$1"
    if command -v lsof >/dev/null 2>&1; then
        lsof -ti:"$p" >/dev/null 2>&1
    elif command -v ss >/dev/null 2>&1; then
        ss -tlnp 2>/dev/null | grep -q ":${p} "
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tlnp 2>/dev/null | grep -q ":${p} "
    else
        return 1
    fi
}

kill_port() {
    local p="$1"
    if command -v lsof >/dev/null 2>&1; then
        lsof -ti:"$p" | xargs kill -9 2>/dev/null || true
    elif command -v fuser >/dev/null 2>&1; then
        fuser -k "${p}/tcp" 2>/dev/null || true
    fi
}

if port_in_use "$DEFAULT_PORT"; then
    EXISTING_PID=""
    EXISTING_CMD="unknown"
    if command -v lsof >/dev/null 2>&1; then
        EXISTING_PID=$(lsof -ti:"$DEFAULT_PORT" 2>/dev/null | head -1 || true)
    fi
    if [ -n "$EXISTING_PID" ]; then
        EXISTING_CMD=$(ps -p "$EXISTING_PID" -o comm= 2>/dev/null || echo "unknown")
    fi

    echo -e "${YELLOW}  ⚠️  Port $DEFAULT_PORT is already in use!${NC}"
    [ -n "$EXISTING_PID" ] && echo -e "      Process: ${RED}PID $EXISTING_PID ($EXISTING_CMD)${NC}"
    echo ""
    echo "  Options:"
    echo "    1) Try to kill the existing process and use port $DEFAULT_PORT"
    echo "    2) Use a different port"
    echo ""
    read -p "  Enter choice (1-2) [default: 2]: " PORT_CHOICE
    PORT_CHOICE="${PORT_CHOICE:-2}"

    if [[ "$PORT_CHOICE" == "1" ]]; then
        echo -e "${YELLOW}  Attempting to free port $DEFAULT_PORT...${NC}"
        kill_port "$DEFAULT_PORT"
        sleep 2
        if port_in_use "$DEFAULT_PORT"; then
            echo -e "${RED}  ❌ Could not free port $DEFAULT_PORT.${NC}"
            read -p "  Enter a different port [default: 8081]: " ALT_PORT
            APP_PORT="${ALT_PORT:-8081}"
        else
            echo -e "${GREEN}  ✅ Port $DEFAULT_PORT is now free.${NC}"
            APP_PORT=$DEFAULT_PORT
        fi
    else
        read -p "  Enter port number [default: 8081]: " ALT_PORT
        APP_PORT="${ALT_PORT:-8081}"
    fi
else
    echo -e "${GREEN}  ✅ Port $DEFAULT_PORT is available.${NC}"
fi

# Validate port number
if ! [[ "$APP_PORT" =~ ^[0-9]+$ ]] || [ "$APP_PORT" -lt 1 ] || [ "$APP_PORT" -gt 65535 ]; then
    echo -e "${YELLOW}  ⚠️  Invalid port number, defaulting to 8080.${NC}"
    APP_PORT=8080
fi

echo -e "${GREEN}  Port: $APP_PORT${NC}"

# ===================================================================
# Write .env
# ===================================================================
{
    echo "PROVIDER=${PROVIDER}"
    echo "$(echo "$PROVIDER" | tr '[:lower:]' '[:upper:]')_KEY=${API_KEY}"
    echo "PORT=${APP_PORT}"
    echo "MODEL_NAME=${MODEL_NAME}"
    if [ -n "${API_BASE_URL:-}" ]; then
        echo "API_BASE_URL=${API_BASE_URL}"
    else
        echo "# API_BASE_URL="
    fi
    echo "NODE_ENV=production"
    echo "DEBUG=false"
} > "$INSTALL_DIR/server/.env"

chmod 600 "$INSTALL_DIR/server/.env"
echo -e "${GREEN}✅ Config saved to server/.env (permissions: 600)${NC}"

# ===================================================================
# Backend server/app.js
# ===================================================================
cat > "$INSTALL_DIR/server/app.js" << 'APPEOF'
'use strict';
const dotenv = require('dotenv');
dotenv.config({ path: __dirname + '/.env' });

// On any unexpected error or unhandled promise rejection, log and exit so
// that the restart loop in start.sh brings the server back up.
// Exit code 2 signals an abnormal crash (distinct from 0 = clean restart,
// 1 = config error, 130+ = signal); start.sh restarts on any exit other than
// 1 or ≥ 130.
process.on('uncaughtException', (err) => {
  console.error('⚠️  Uncaught exception — restarting:', err.stack || err.message);
  process.exit(2);
});
process.on('unhandledRejection', (reason) => {
  console.error('⚠️  Unhandled rejection — restarting:', reason);
  process.exit(2);
});

const express = require('express');
const path = require('path');
const fs = require('fs');
const https = require('https');
const os = require('os');

const PORT = parseInt(process.env.PORT, 10) || 8080;
const PROVIDER = (process.env.PROVIDER || 'gemini').toLowerCase();
const API_BASE_URL = (process.env.API_BASE_URL || '').trim();

const PROVIDER_DEFAULTS = {
  gemini: 'gemini-1.5-flash',
  claude: 'claude-3-5-sonnet-20241022',
  openai: 'gpt-4o-mini'
};

let API_KEY = '';
let MODEL_NAME = (process.env.MODEL_NAME || '').trim() || PROVIDER_DEFAULTS[PROVIDER] || 'gemini-1.5-flash';
let AI_SERVICE = null;
let genAI = null;

switch (PROVIDER) {
  case 'claude':
    API_KEY = (process.env.CLAUDE_KEY || '').trim();
    if (!API_KEY) {
      console.error('❌  CLAUDE_KEY is missing from server/.env');
      console.error('    Visit: https://console.anthropic.com/api_keys');
      process.exit(1);
    }
    try {
      const Anthropic = require('@anthropic-ai/sdk');
      const opts = { apiKey: API_KEY };
      if (API_BASE_URL) opts.baseURL = API_BASE_URL;
      AI_SERVICE = new Anthropic(opts);
    } catch (e) {
      console.error('❌  Anthropic SDK not installed. Run: npm install @anthropic-ai/sdk');
      process.exit(1);
    }
    break;

  case 'openai':
    API_KEY = (process.env.OPENAI_KEY || '').trim();
    if (!API_KEY) {
      console.error('❌  OPENAI_KEY is missing from server/.env');
      console.error('    Visit: https://platform.openai.com/api-keys');
      process.exit(1);
    }
    try {
      const OpenAI = require('openai');
      const opts = { apiKey: API_KEY };
      if (API_BASE_URL) opts.baseURL = API_BASE_URL;
      AI_SERVICE = new OpenAI(opts);
    } catch (e) {
      console.error('❌  OpenAI SDK not installed. Run: npm install openai');
      process.exit(1);
    }
    break;

  case 'gemini':
  default:
    API_KEY = (process.env.GEMINI_KEY || '').trim();
    if (!API_KEY) {
      console.error('❌  GEMINI_KEY is missing from server/.env');
      console.error('    Visit: https://aistudio.google.com/app/apikey');
      process.exit(1);
    }
    try {
      const { GoogleGenerativeAI } = require('@google/generative-ai');
      genAI = new GoogleGenerativeAI(API_KEY);
      AI_SERVICE = genAI.getGenerativeModel({ model: MODEL_NAME });
    } catch (e) {
      console.error('❌  Google SDK not installed. Run: npm install @google/generative-ai');
      process.exit(1);
    }
    break;
}

console.log(`✅ Initialized ${PROVIDER.toUpperCase()} — model: ${MODEL_NAME}`);
if (API_BASE_URL) console.log(`   Custom endpoint: ${API_BASE_URL}`);

// OS detection
(function detectOS() {
  const platform = os.platform();
  const release = os.release();
  console.log(`💻 OS: ${platform} ${release}`);
  if (platform === 'linux') {
    try {
      const info = fs.readFileSync('/etc/os-release', 'utf8');
      const pretty = (info.match(/PRETTY_NAME="([^"]+)"/) || [])[1] || 'Linux';
      console.log(`   Distro: ${pretty}`);
    } catch (_) {}
  }
})();

// ---------------------------------------------------------------
// File-based JSON storage (replaces SQLite)
// ---------------------------------------------------------------
const app = express();
const dataDir = path.join(__dirname, '../data');
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

const HISTORY_FILE  = path.join(dataDir, 'history.json');
const PROJECTS_FILE = path.join(dataDir, 'projects.json');

function readJSON(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) {
    if (e.code !== 'ENOENT') console.error(`⚠️  Could not read ${file}:`, e.message);
    return [];
  }
}
function writeJSON(file, rows) {
  fs.writeFileSync(file, JSON.stringify(rows, null, 2));
}
function nextId(rows) {
  return rows.length > 0 ? Math.max(...rows.map(r => r.id), 0) + 1 : 1;
}

function readHistory()  { return readJSON(HISTORY_FILE); }
function writeHistory(rows) { writeJSON(HISTORY_FILE, rows); }

function readProjects()  { return readJSON(PROJECTS_FILE); }
function writeProjects(rows) { writeJSON(PROJECTS_FILE, rows); }

function insertHistory(tab, prompt, response, provider) {
  const rows = readHistory();
  rows.push({ id: nextId(rows), tab, prompt, response, provider, date: new Date().toISOString() });
  writeHistory(rows);
}

app.use(express.json({ limit: '10mb' }));
app.use(express.static(path.join(__dirname, '../frontend')));

// ---------------------------------------------------------------
// Helper: HTTPS GET returning parsed JSON (works on all Node versions)
// ---------------------------------------------------------------
function httpsGet(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error('Invalid JSON from: ' + url)); }
      });
    }).on('error', reject);
  });
}

// ---------------------------------------------------------------
// Rate limiting
// ---------------------------------------------------------------
let lastCall = 0;
const RATE_MS = 1500;

// ---------------------------------------------------------------
// Routes
// ---------------------------------------------------------------

app.get('/api/status', (_req, res) => {
  res.json({
    ok: true,
    provider: PROVIDER,
    model: MODEL_NAME,
    customEndpoint: API_BASE_URL || null
  });
});

// GET /api/models — list available models for the current provider
app.get('/api/models', async (_req, res) => {
  try {
    if (PROVIDER === 'gemini') {
      const baseUrl = API_BASE_URL || 'https://generativelanguage.googleapis.com';
      const data = await httpsGet(`${baseUrl}/v1beta/models?key=${API_KEY}`);
      const models = (data.models || [])
        .filter((m) => (m.supportedGenerationMethods || []).includes('generateContent'))
        .map((m) => ({
          id: m.name.replace('models/', ''),
          displayName: m.displayName || m.name.replace('models/', ''),
          description: m.description || ''
        }));
      return res.json({ provider: PROVIDER, models, current: MODEL_NAME });

    } else if (PROVIDER === 'openai') {
      const page = await AI_SERVICE.models.list();
      const models = (page.data || [])
        // Keep GPT and o-series (reasoning) models; excludes embedding/moderation/audio models
        .filter((m) => m.id.startsWith('gpt') || m.id.startsWith('o'))
        .sort((a, b) => a.id.localeCompare(b.id))
        .map((m) => ({ id: m.id, displayName: m.id }));
      return res.json({ provider: PROVIDER, models, current: MODEL_NAME });

    } else if (PROVIDER === 'claude') {
      // Anthropic does not expose a public model-listing API; return a curated static list.
      const staticModels = [
        { id: 'claude-opus-4-5',             displayName: 'Claude Opus 4.5' },
        { id: 'claude-sonnet-4-5',           displayName: 'Claude Sonnet 4.5' },
        { id: 'claude-3-5-sonnet-20241022',  displayName: 'Claude 3.5 Sonnet' },
        { id: 'claude-3-5-haiku-20241022',   displayName: 'Claude 3.5 Haiku' },
        { id: 'claude-3-opus-20240229',      displayName: 'Claude 3 Opus' },
        { id: 'claude-3-haiku-20240307',     displayName: 'Claude 3 Haiku' }
      ];
      return res.json({
        provider: PROVIDER,
        models: staticModels,
        current: MODEL_NAME,
        warning: 'Claude model list is static. Check https://docs.anthropic.com for the latest models.'
      });
    }

    res.json({ provider: PROVIDER, models: [], warning: 'Model listing is not available for this provider.' });
  } catch (err) {
    console.error('Models error:', err.message);
    res.status(500).json({ error: 'Failed to fetch models.', detail: err.message });
  }
});

// POST /api/setmodel — persist a new model name to .env and restart
app.post('/api/setmodel', (req, res) => {
  const { model } = req.body || {};
  if (!model || model.trim().length < 2) {
    return res.status(400).json({ ok: false, error: 'Invalid model name.' });
  }
  const envPath = path.join(__dirname, '.env');
  try {
    let content = fs.existsSync(envPath) ? fs.readFileSync(envPath, 'utf8') : '';
    if (/MODEL_NAME=/.test(content)) {
      content = content.replace(/MODEL_NAME=.*/, `MODEL_NAME=${model.trim()}`);
    } else {
      content += `\nMODEL_NAME=${model.trim()}`;
    }
    fs.writeFileSync(envPath, content);
    fs.chmodSync(envPath, 0o600);
    res.json({ ok: true, model: model.trim(), message: 'Model updated. Server is restarting…' });
    // Short delay lets the HTTP response finish before the process restarts
    setTimeout(() => process.exit(0), 400);
  } catch (e) {
    res.status(500).json({ ok: false, error: 'Could not write .env' });
  }
});

// POST /api/generate — send a prompt to the configured AI provider
app.post('/api/generate', async (req, res) => {
  const now = Date.now();
  if (now - lastCall < RATE_MS) {
    return res.status(429).json({ error: 'Please wait a moment before sending again.' });
  }
  lastCall = now;

  const { prompt, system, tab } = req.body;
  if (!prompt || prompt.trim().length < 3) {
    return res.status(400).json({ error: 'Prompt too short.' });
  }

  const fullPrompt = system ? `${system}\n\nUser request: ${prompt.trim()}` : prompt.trim();

  try {
    let text = '';
    if (PROVIDER === 'claude') {
      const message = await AI_SERVICE.messages.create({
        model: MODEL_NAME,
        max_tokens: 2048,
        messages: [{ role: 'user', content: fullPrompt }]
      });
      text = message.content[0].text;
    } else if (PROVIDER === 'openai') {
      const message = await AI_SERVICE.chat.completions.create({
        model: MODEL_NAME,
        messages: [{ role: 'user', content: fullPrompt }]
      });
      text = message.choices[0].message.content;
    } else {
      const result = await AI_SERVICE.generateContent(fullPrompt);
      text = result.response.text();
    }

    insertHistory(tab || 'chat', prompt.trim(), text, PROVIDER);
    res.json({ result: text });
  } catch (err) {
    console.error(`${PROVIDER.toUpperCase()} error:`, err.message);
    const isModelErr = /model/i.test(err.message) || /not found/i.test(err.message) || /invalid/i.test(err.message);
    if (isModelErr) {
      return res.status(500).json({
        error: `Model "${MODEL_NAME}" may not be supported by ${PROVIDER}. ` +
               `Check /api/models or update MODEL_NAME in server/.env.`,
        detail: err.message
      });
    }
    res.status(500).json({ error: 'AI error. Check your API key in server/.env', detail: err.message });
  }
});

// POST /api/setkey — update an API key and restart
app.post('/api/setkey', (req, res) => {
  const { key, provider } = req.body || {};
  if (!key || key.trim().length < 10) {
    return res.status(400).json({ ok: false, error: 'Invalid key' });
  }
  // Sanitise to alphanumeric only before using in a RegExp to prevent ReDoS
  const p = (provider || PROVIDER).toLowerCase().replace(/[^a-z0-9]/g, '');
  const envPath = path.join(__dirname, '.env');
  try {
    let content = fs.existsSync(envPath) ? fs.readFileSync(envPath, 'utf8') : '';
    const keyVar = `${p.toUpperCase()}_KEY`;
    if (content.match(new RegExp(`${keyVar}=`))) {
      content = content.replace(new RegExp(`${keyVar}=.*`), `${keyVar}=${key.trim()}`);
    } else {
      content += `\n${keyVar}=${key.trim()}`;
    }
    fs.writeFileSync(envPath, content);
    fs.chmodSync(envPath, 0o600);
    res.json({ ok: true });
    // Short delay lets the HTTP response finish before the process restarts
    setTimeout(() => process.exit(0), 400);
  } catch (e) {
    res.status(500).json({ ok: false, error: 'Could not write .env' });
  }
});

app.get('/api/history', (_req, res) => {
  res.json(readHistory().slice().reverse().slice(0, 25));
});

app.delete('/api/history/:id', (req, res) => {
  const id = parseInt(req.params.id, 10);
  writeHistory(readHistory().filter(r => r.id !== id));
  res.json({ ok: true });
});

// ---------------------------------------------------------------
// Projects
// ---------------------------------------------------------------
app.get('/api/projects', (_req, res) => {
  res.json(readProjects().slice().reverse());
});

app.get('/api/projects/:id', (req, res) => {
  const id = parseInt(req.params.id, 10);
  const row = readProjects().find(r => r.id === id);
  if (!row) return res.status(404).json({ error: 'Project not found' });
  res.json(row);
});

app.post('/api/projects', (req, res) => {
  const { name, tab, prompt, output } = req.body || {};
  if (!name || !name.trim()) {
    return res.status(400).json({ ok: false, error: 'Project name is required.' });
  }
  const rows = readProjects();
  const id = nextId(rows);
  rows.push({ id, name: name.trim(), tab: tab || 'chat', prompt: prompt || '', output: output || '', date: new Date().toISOString() });
  writeProjects(rows);
  res.json({ ok: true, id });
});

app.delete('/api/projects/:id', (req, res) => {
  const id = parseInt(req.params.id, 10);
  writeProjects(readProjects().filter(r => r.id !== id));
  res.json({ ok: true });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n✅ MrT AI Hub PRO v3.2 → http://localhost:${PORT}`);
  console.log(`   Provider: ${PROVIDER.toUpperCase()} | Model: ${MODEL_NAME}`);
  console.log(`   Change model:   POST /api/setmodel  { "model": "..." }`);
  console.log(`   List models:    GET  /api/models\n`);
});
APPEOF

# ===================================================================
# npm setup
# ===================================================================
echo ""
echo -e "${BLUE}📦 Installing Node.js dependencies...${NC}"
cd "$INSTALL_DIR"
npm init -y >/dev/null 2>&1
npm install express dotenv --save >/dev/null 2>&1

case "$PROVIDER" in
    gemini) npm install @google/generative-ai --save >/dev/null 2>&1 ;;
    claude) npm install @anthropic-ai/sdk --save >/dev/null 2>&1 ;;
    openai) npm install openai --save >/dev/null 2>&1 ;;
esac

echo -e "${GREEN}✅ Dependencies installed.${NC}"

# ===================================================================
# Frontend dashboard
# ===================================================================
cat > "$INSTALL_DIR/frontend/index.html" << 'FRONTEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>MrT AI Hub PRO</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: #0f172a;
    color: #e2e8f0;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
  }
  header {
    background: #1e293b;
    border-bottom: 1px solid #334155;
    padding: 14px 20px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 8px;
  }
  header h1 { font-size: 1.2rem; font-weight: 700; color: #38bdf8; }
  #status-bar {
    font-size: 0.8rem;
    background: #0f172a;
    border: 1px solid #334155;
    border-radius: 6px;
    padding: 4px 10px;
    color: #94a3b8;
  }
  #status-bar span { color: #4ade80; font-weight: 600; }
  nav.tabs {
    display: flex;
    background: #1e293b;
    border-bottom: 1px solid #334155;
    padding: 0 20px;
  }
  nav.tabs button {
    background: none;
    border: none;
    color: #94a3b8;
    padding: 12px 18px;
    cursor: pointer;
    font-size: 0.9rem;
    border-bottom: 2px solid transparent;
    transition: color 0.15s, border-color 0.15s;
  }
  nav.tabs button:hover { color: #e2e8f0; }
  nav.tabs button.active { color: #38bdf8; border-bottom-color: #38bdf8; }
  main { flex: 1; padding: 24px 20px; max-width: 860px; width: 100%; margin: 0 auto; }
  .tab { display: none; }
  .tab.active { display: block; }

  /* Chat */
  #chat-output {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 10px;
    padding: 16px;
    min-height: 260px;
    max-height: 440px;
    overflow-y: auto;
    margin-bottom: 14px;
    font-size: 0.9rem;
    line-height: 1.6;
    white-space: pre-wrap;
  }
  .msg-user { color: #38bdf8; margin-bottom: 8px; }
  .msg-ai   { color: #e2e8f0; margin-bottom: 16px; border-left: 3px solid #38bdf8; padding-left: 10px; position: relative; }
  .msg-err  { color: #f87171; margin-bottom: 16px; }
  textarea {
    width: 100%;
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 8px;
    color: #e2e8f0;
    padding: 10px 14px;
    font-size: 0.9rem;
    resize: vertical;
    outline: none;
    transition: border-color 0.15s;
  }
  textarea:focus { border-color: #38bdf8; }
  .btn-row { display: flex; gap: 10px; margin-top: 10px; flex-wrap: wrap; }
  button.btn {
    background: #38bdf8;
    color: #0f172a;
    border: none;
    border-radius: 8px;
    padding: 9px 20px;
    font-size: 0.9rem;
    font-weight: 600;
    cursor: pointer;
    transition: background 0.15s;
  }
  button.btn:hover { background: #7dd3fc; }
  button.btn:disabled { background: #334155; color: #64748b; cursor: not-allowed; }
  button.btn-sec {
    background: #334155;
    color: #e2e8f0;
    border: none;
    border-radius: 8px;
    padding: 9px 20px;
    font-size: 0.9rem;
    font-weight: 600;
    cursor: pointer;
    transition: background 0.15s;
  }
  button.btn-sec:hover { background: #475569; }
  button.btn-danger {
    background: #ef4444;
    color: #fff;
    border: none;
    border-radius: 8px;
    padding: 9px 20px;
    font-size: 0.9rem;
    font-weight: 600;
    cursor: pointer;
    transition: background 0.15s;
  }
  button.btn-danger:hover { background: #dc2626; }

  /* Setup */
  .setup-card {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 10px;
    padding: 20px;
    margin-bottom: 18px;
  }
  .setup-card h3 { color: #38bdf8; font-size: 0.95rem; margin-bottom: 14px; }
  label { display: block; font-size: 0.85rem; color: #94a3b8; margin-bottom: 6px; }
  input[type="text"], input[type="password"], select {
    width: 100%;
    background: #0f172a;
    border: 1px solid #334155;
    border-radius: 6px;
    color: #e2e8f0;
    padding: 8px 12px;
    font-size: 0.9rem;
    outline: none;
    transition: border-color 0.15s;
    margin-bottom: 10px;
  }
  input[type="text"]:focus, input[type="password"]:focus, select:focus { border-color: #38bdf8; }
  select option { background: #1e293b; }
  .info-row { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 14px; }
  .info-chip {
    background: #0f172a;
    border: 1px solid #334155;
    border-radius: 6px;
    padding: 6px 12px;
    font-size: 0.8rem;
    color: #94a3b8;
  }
  .info-chip span { color: #4ade80; font-weight: 600; }
  .notice {
    background: #1e3a5f;
    border: 1px solid #2563eb;
    border-radius: 6px;
    padding: 8px 12px;
    font-size: 0.8rem;
    color: #93c5fd;
    margin-top: 8px;
  }
  .warning { background: #3b1f10; border-color: #d97706; color: #fbbf24; }

  /* History */
  .history-item {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 8px;
    padding: 12px 14px;
    margin-bottom: 10px;
  }
  .history-meta { font-size: 0.75rem; color: #64748b; margin-bottom: 6px; }
  .history-prompt { color: #38bdf8; font-size: 0.85rem; margin-bottom: 4px; white-space: pre-wrap; }
  .history-response { color: #cbd5e1; font-size: 0.85rem; white-space: pre-wrap; max-height: 100px; overflow: hidden; position: relative; }
  .history-response.expanded { max-height: none; }
  .del-btn { float: right; background: none; border: none; color: #ef4444; cursor: pointer; font-size: 0.8rem; }

  /* Business tabs */
  nav.tabs { overflow-x: auto; flex-wrap: nowrap; white-space: nowrap; }
  .biz-output {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 10px;
    padding: 16px;
    min-height: 160px;
    max-height: 360px;
    overflow-y: auto;
    margin-bottom: 14px;
    font-size: 0.9rem;
    line-height: 1.7;
    white-space: pre-wrap;
    color: #e2e8f0;
  }
  .biz-placeholder { color: #64748b; }
  .biz-result { border-left: 3px solid #38bdf8; padding-left: 10px; position: relative; }
  .biz-err { color: #f87171; }
  .copy-btn {
    position: absolute;
    top: 4px;
    right: 4px;
    background: #334155;
    color: #94a3b8;
    border: none;
    border-radius: 6px;
    padding: 3px 9px;
    font-size: 0.75rem;
    cursor: pointer;
    transition: background 0.15s, color 0.15s;
    opacity: 0;
    pointer-events: none;
  }
  .msg-ai:hover .copy-btn,
  .biz-result:hover .copy-btn { opacity: 1; pointer-events: auto; }
  .copy-btn:hover { background: #38bdf8; color: #0f172a; }
  .copy-btn.copied { background: #4ade80; color: #0f172a; }
  .chips { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 14px; }
  .chip {
    background: #1e3a5f;
    border: 1px solid #2563eb;
    border-radius: 20px;
    color: #93c5fd;
    cursor: pointer;
    font-size: 0.8rem;
    padding: 5px 13px;
    transition: background 0.15s, color 0.15s;
    white-space: normal;
    text-align: left;
  }
  .chip:hover { background: #2563eb; color: #fff; }

  /* File attachment */
  .attach-row { display: flex; align-items: center; gap: 8px; margin-bottom: 8px; flex-wrap: wrap; }
  .attach-btn {
    background: #334155;
    color: #94a3b8;
    border: 1px dashed #475569;
    border-radius: 6px;
    padding: 5px 12px;
    font-size: 0.8rem;
    cursor: pointer;
    transition: background 0.15s, color 0.15s;
  }
  .attach-btn:hover { background: #475569; color: #e2e8f0; }
  .attach-file-input { display: none; }
  .file-badge {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    background: #1e3a5f;
    border: 1px solid #2563eb;
    border-radius: 12px;
    color: #93c5fd;
    font-size: 0.75rem;
    padding: 3px 10px;
  }
  .file-badge button {
    background: none;
    border: none;
    color: #93c5fd;
    cursor: pointer;
    font-size: 0.85rem;
    padding: 0 0 0 4px;
    line-height: 1;
  }
  .file-badge button:hover { color: #f87171; }

  /* Save modal */
  .modal-backdrop {
    display: none;
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.6);
    z-index: 1000;
    align-items: center;
    justify-content: center;
  }
  .modal-backdrop.open { display: flex; }
  .modal {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 12px;
    padding: 24px;
    width: 340px;
    max-width: 90vw;
  }
  .modal h3 { color: #38bdf8; font-size: 1rem; margin-bottom: 16px; }
  .modal input[type="text"] { margin-bottom: 14px; }
  .modal .btn-row { margin-top: 0; }

  /* Projects tab */
  .project-item {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 8px;
    padding: 12px 14px;
    margin-bottom: 10px;
  }
  .project-meta { font-size: 0.75rem; color: #64748b; margin-bottom: 6px; }
  .project-name { color: #38bdf8; font-size: 0.95rem; font-weight: 600; margin-bottom: 4px; }
  .project-preview { color: #cbd5e1; font-size: 0.82rem; white-space: pre-wrap; max-height: 80px; overflow: hidden; }
  .project-actions { margin-top: 8px; display: flex; gap: 8px; }
</style>
</head>
<body>

<header>
  <h1>🤖 MrT AI Hub PRO</h1>
  <div id="status-bar">Loading…</div>
</header>

<nav class="tabs">
  <button class="tab-btn active" data-tab="chat">💬 Chat</button>
  <button class="tab-btn" data-tab="email">📧 Email</button>
  <button class="tab-btn" data-tab="social">📱 Social</button>
  <button class="tab-btn" data-tab="sales">💼 Sales</button>
  <button class="tab-btn" data-tab="content">📝 Content</button>
  <button class="tab-btn" data-tab="seo">🔍 SEO</button>
  <button class="tab-btn" data-tab="support">🎧 Support</button>
  <button class="tab-btn" data-tab="setup">⚙️ Setup</button>
  <button class="tab-btn" data-tab="projects">💾 Projects</button>
  <button class="tab-btn" data-tab="history">📜 History</button>
</nav>

<main>

  <!-- ============================================================ CHAT -->
  <section id="tab-chat" class="tab active">
    <div id="chat-output"><span style="color:#64748b">Type a message and press Send.</span></div>
    <div class="attach-row">
      <button class="attach-btn" onclick="document.getElementById('chat-file').click()">📎 Attach file</button>
      <input type="file" id="chat-file" class="attach-file-input" accept=".txt,.md,.csv,.json,.js,.ts,.py,.html,.css,.xml,.yaml,.yml,.sh,.log">
      <span id="chat-file-badges"></span>
    </div>
    <textarea id="chat-input" rows="4" placeholder="Ask anything…"></textarea>
    <div class="btn-row">
      <button class="btn" id="btn-send">Send</button>
      <button class="btn-sec" id="btn-clear-chat">Clear</button>
      <button class="btn-sec btn-save-project" data-tab="chat" data-inp="chat-input" data-out="chat-output">💾 Save</button>
    </div>
  </section>

  <!-- ============================================================ EMAIL -->
  <section id="tab-email" class="tab">
    <p style="font-size:0.85rem;color:#94a3b8;margin-bottom:12px;">Quick prompts — click to fill the box, then customise and hit <strong>Generate</strong>.</p>
    <div class="chips" data-tab="email">
      <button class="chip">Write a professional follow-up email after a client meeting</button>
      <button class="chip">Write a cold outreach email to a potential business partner</button>
      <button class="chip">Write a polite but firm response to a customer complaint</button>
      <button class="chip">Write a thank-you email after a job interview</button>
      <button class="chip">Write a project status update email to stakeholders</button>
      <button class="chip">Write a meeting request email with agenda</button>
    </div>
    <div class="biz-output" id="out-email"><span class="biz-placeholder">Your AI-generated email will appear here.</span></div>
    <div class="attach-row">
      <button class="attach-btn" onclick="document.getElementById('file-email').click()">📎 Attach file</button>
      <input type="file" id="file-email" class="attach-file-input" accept=".txt,.md,.csv,.json,.js,.ts,.py,.html,.css,.xml,.yaml,.yml,.sh,.log">
      <span id="file-badges-email"></span>
    </div>
    <textarea id="inp-email" rows="4" placeholder="Describe the email you need — or click a quick prompt above…"></textarea>
    <div class="btn-row">
      <button class="btn biz-send" data-tab="email" data-out="out-email" data-inp="inp-email">Generate</button>
      <button class="btn-sec biz-clear" data-out="out-email" data-inp="inp-email">Clear</button>
      <button class="btn-sec btn-save-project" data-tab="email" data-inp="inp-email" data-out="out-email">💾 Save</button>
    </div>
  </section>

  <!-- ============================================================ SOCIAL -->
  <section id="tab-social" class="tab">
    <p style="font-size:0.85rem;color:#94a3b8;margin-bottom:12px;">Quick prompts — click to fill the box, then customise and hit <strong>Generate</strong>.</p>
    <div class="chips" data-tab="social">
      <button class="chip">Write a professional LinkedIn post announcing company news</button>
      <button class="chip">Write an engaging Instagram caption with relevant hashtags</button>
      <button class="chip">Write a concise X/Twitter post to promote a product launch</button>
      <button class="chip">Write a Facebook business page post to increase engagement</button>
      <button class="chip">Create a 5-day social media content calendar for a small business</button>
      <button class="chip">Write a short YouTube video description with keywords</button>
    </div>
    <div class="biz-output" id="out-social"><span class="biz-placeholder">Your AI-generated social media content will appear here.</span></div>
    <div class="attach-row">
      <button class="attach-btn" onclick="document.getElementById('file-social').click()">📎 Attach file</button>
      <input type="file" id="file-social" class="attach-file-input" accept=".txt,.md,.csv,.json,.js,.ts,.py,.html,.css,.xml,.yaml,.yml,.sh,.log">
      <span id="file-badges-social"></span>
    </div>
    <textarea id="inp-social" rows="4" placeholder="Describe the social media content you need — or click a quick prompt above…"></textarea>
    <div class="btn-row">
      <button class="btn biz-send" data-tab="social" data-out="out-social" data-inp="inp-social">Generate</button>
      <button class="btn-sec biz-clear" data-out="out-social" data-inp="inp-social">Clear</button>
      <button class="btn-sec btn-save-project" data-tab="social" data-inp="inp-social" data-out="out-social">💾 Save</button>
    </div>
  </section>

  <!-- ============================================================ SALES -->
  <section id="tab-sales" class="tab">
    <p style="font-size:0.85rem;color:#94a3b8;margin-bottom:12px;">Quick prompts — click to fill the box, then customise and hit <strong>Generate</strong>.</p>
    <div class="chips" data-tab="sales">
      <button class="chip">Write a compelling sales pitch for a new product or service</button>
      <button class="chip">Write a persuasive product description for an e-commerce listing</button>
      <button class="chip">Write a confident response to the objection "Your price is too high"</button>
      <button class="chip">Write a follow-up message to a prospect who went silent</button>
      <button class="chip">Write a limited-time promotional offer announcement</button>
      <button class="chip">Write an upsell script for an existing customer</button>
    </div>
    <div class="biz-output" id="out-sales"><span class="biz-placeholder">Your AI-generated sales content will appear here.</span></div>
    <div class="attach-row">
      <button class="attach-btn" onclick="document.getElementById('file-sales').click()">📎 Attach file</button>
      <input type="file" id="file-sales" class="attach-file-input" accept=".txt,.md,.csv,.json,.js,.ts,.py,.html,.css,.xml,.yaml,.yml,.sh,.log">
      <span id="file-badges-sales"></span>
    </div>
    <textarea id="inp-sales" rows="4" placeholder="Describe the sales content you need — or click a quick prompt above…"></textarea>
    <div class="btn-row">
      <button class="btn biz-send" data-tab="sales" data-out="out-sales" data-inp="inp-sales">Generate</button>
      <button class="btn-sec biz-clear" data-out="out-sales" data-inp="inp-sales">Clear</button>
      <button class="btn-sec btn-save-project" data-tab="sales" data-inp="inp-sales" data-out="out-sales">💾 Save</button>
    </div>
  </section>

  <!-- ============================================================ CONTENT -->
  <section id="tab-content" class="tab">
    <p style="font-size:0.85rem;color:#94a3b8;margin-bottom:12px;">Quick prompts — click to fill the box, then customise and hit <strong>Generate</strong>.</p>
    <div class="chips" data-tab="content">
      <button class="chip">Write an engaging blog post introduction and outline</button>
      <button class="chip">Write a press release for a product or service launch</button>
      <button class="chip">Write a monthly business newsletter with tips and updates</button>
      <button class="chip">Write an FAQ section for a small business website</button>
      <button class="chip">Write an About Us page for a company website</button>
      <button class="chip">Rewrite this content to sound more professional and engaging</button>
    </div>
    <div class="biz-output" id="out-content"><span class="biz-placeholder">Your AI-generated content will appear here.</span></div>
    <div class="attach-row">
      <button class="attach-btn" onclick="document.getElementById('file-content').click()">📎 Attach file</button>
      <input type="file" id="file-content" class="attach-file-input" accept=".txt,.md,.csv,.json,.js,.ts,.py,.html,.css,.xml,.yaml,.yml,.sh,.log">
      <span id="file-badges-content"></span>
    </div>
    <textarea id="inp-content" rows="4" placeholder="Describe the content you need — or click a quick prompt above…"></textarea>
    <div class="btn-row">
      <button class="btn biz-send" data-tab="content" data-out="out-content" data-inp="inp-content">Generate</button>
      <button class="btn-sec biz-clear" data-out="out-content" data-inp="inp-content">Clear</button>
      <button class="btn-sec btn-save-project" data-tab="content" data-inp="inp-content" data-out="out-content">💾 Save</button>
    </div>
  </section>

  <!-- ============================================================ SEO -->
  <section id="tab-seo" class="tab">
    <p style="font-size:0.85rem;color:#94a3b8;margin-bottom:12px;">Quick prompts — click to fill the box, then customise and hit <strong>Generate</strong>.</p>
    <div class="chips" data-tab="seo">
      <button class="chip">Write an SEO meta description (under 160 chars) for my page about…</button>
      <button class="chip">Generate 10 long-tail keyword ideas for a local business selling…</button>
      <button class="chip">Write an SEO-optimised page title (under 60 chars) for…</button>
      <button class="chip">Rewrite this text to naturally include the keyword…</button>
      <button class="chip">Write SEO-friendly H2 headings for an article about…</button>
      <button class="chip">Create a keyword-rich product category description for…</button>
    </div>
    <div class="biz-output" id="out-seo"><span class="biz-placeholder">Your AI-generated SEO content will appear here.</span></div>
    <div class="attach-row">
      <button class="attach-btn" onclick="document.getElementById('file-seo').click()">📎 Attach file</button>
      <input type="file" id="file-seo" class="attach-file-input" accept=".txt,.md,.csv,.json,.js,.ts,.py,.html,.css,.xml,.yaml,.yml,.sh,.log">
      <span id="file-badges-seo"></span>
    </div>
    <textarea id="inp-seo" rows="4" placeholder="Describe the SEO task you need — or click a quick prompt above…"></textarea>
    <div class="btn-row">
      <button class="btn biz-send" data-tab="seo" data-out="out-seo" data-inp="inp-seo">Generate</button>
      <button class="btn-sec biz-clear" data-out="out-seo" data-inp="inp-seo">Clear</button>
      <button class="btn-sec btn-save-project" data-tab="seo" data-inp="inp-seo" data-out="out-seo">💾 Save</button>
    </div>
  </section>

  <!-- ============================================================ SUPPORT -->
  <section id="tab-support" class="tab">
    <p style="font-size:0.85rem;color:#94a3b8;margin-bottom:12px;">Quick prompts — click to fill the box, then customise and hit <strong>Generate</strong>.</p>
    <div class="chips" data-tab="support">
      <button class="chip">Write an empathetic response to an angry customer complaint</button>
      <button class="chip">Write a helpful FAQ answer about our refund and returns policy</button>
      <button class="chip">Write an apology email to customers affected by a service outage</button>
      <button class="chip">Write a friendly response to a customer asking about delivery times</button>
      <button class="chip">Explain our privacy policy in simple, plain language</button>
      <button class="chip">Write a follow-up message to check customer satisfaction after support</button>
    </div>
    <div class="biz-output" id="out-support"><span class="biz-placeholder">Your AI-generated support response will appear here.</span></div>
    <div class="attach-row">
      <button class="attach-btn" onclick="document.getElementById('file-support').click()">📎 Attach file</button>
      <input type="file" id="file-support" class="attach-file-input" accept=".txt,.md,.csv,.json,.js,.ts,.py,.html,.css,.xml,.yaml,.yml,.sh,.log">
      <span id="file-badges-support"></span>
    </div>
    <textarea id="inp-support" rows="4" placeholder="Describe the support response you need — or click a quick prompt above…"></textarea>
    <div class="btn-row">
      <button class="btn biz-send" data-tab="support" data-out="out-support" data-inp="inp-support">Generate</button>
      <button class="btn-sec biz-clear" data-out="out-support" data-inp="inp-support">Clear</button>
      <button class="btn-sec btn-save-project" data-tab="support" data-inp="inp-support" data-out="out-support">💾 Save</button>
    </div>
  </section>

  <!-- ============================================================ SETUP -->
  <section id="tab-setup" class="tab">

    <div class="setup-card">
      <h3>🔍 Current Configuration</h3>
      <div class="info-row">
        <div class="info-chip">Provider: <span id="cfg-provider">–</span></div>
        <div class="info-chip">Model: <span id="cfg-model">–</span></div>
        <div class="info-chip">Port: <span id="cfg-port">–</span></div>
      </div>
    </div>

    <div class="setup-card">
      <h3>🤖 Model Selector</h3>
      <p style="font-size:0.85rem;color:#94a3b8;margin-bottom:12px;">
        Load available models from the provider, then choose one to activate.
        Changes are saved to <code style="color:#38bdf8">server/.env</code> and
        take effect after the server restarts.
      </p>
      <button class="btn-sec" id="btn-load-models">Load Available Models</button>
      <div id="model-loader-status" style="font-size:0.8rem;color:#94a3b8;margin-top:6px;"></div>

      <div id="model-select-wrap" style="margin-top:14px;display:none;">
        <label for="model-select">Select Model</label>
        <select id="model-select"></select>
        <button class="btn" id="btn-save-model">Save &amp; Restart Server</button>
        <div id="model-save-status" style="font-size:0.8rem;margin-top:6px;"></div>
        <div class="notice" style="margin-top:10px;">
          ℹ️ Saving will restart the server automatically. The page will reconnect in a few seconds.
        </div>
      </div>
    </div>

    <div class="setup-card">
      <h3>🔑 API Key</h3>
      <label for="key-input">New API Key (leave blank to keep current)</label>
      <input type="password" id="key-input" placeholder="Paste new key here…">
      <button class="btn" id="btn-save-key">Save Key &amp; Restart</button>
      <div id="key-status" style="font-size:0.8rem;margin-top:6px;"></div>
    </div>

  </section>

  <!-- ============================================================ PROJECTS -->
  <section id="tab-projects" class="tab">
    <div class="btn-row" style="margin-bottom:16px;">
      <button class="btn-sec" id="btn-load-projects">Refresh Projects</button>
    </div>
    <div id="projects-list"><span style="color:#64748b">Click Refresh to load saved projects.</span></div>
  </section>

  <!-- ============================================================ HISTORY -->
  <section id="tab-history" class="tab">
    <div class="btn-row" style="margin-bottom:16px;">
      <button class="btn-sec" id="btn-load-history">Refresh History</button>
    </div>
    <div id="history-list"><span style="color:#64748b">Click Refresh to load history.</span></div>
  </section>

</main>

<!-- ============================================================ SAVE MODAL -->
<div class="modal-backdrop" id="save-modal">
  <div class="modal">
    <h3>💾 Save Project</h3>
    <label for="save-project-name">Project Name</label>
    <input type="text" id="save-project-name" placeholder="e.g. Q1 Newsletter, Client Follow-up…" maxlength="80">
    <div class="btn-row">
      <button class="btn" id="btn-confirm-save">Save</button>
      <button class="btn-sec" id="btn-cancel-save">Cancel</button>
    </div>
    <div id="save-modal-status" style="font-size:0.8rem;margin-top:8px;"></div>
  </div>
</div>

<script>
// ------------------------------------------------------------------ Tabs
document.querySelectorAll('.tab-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById('tab-' + btn.dataset.tab).classList.add('active');
    if (btn.dataset.tab === 'history') loadHistory();
  });
});

// ------------------------------------------------------------------ Status
async function loadStatus() {
  try {
    const r = await fetch('/api/status');
    const d = await r.json();
    document.getElementById('status-bar').innerHTML =
      `<span>${d.provider.toUpperCase()}</span> · <span>${d.model}</span>`;
    document.getElementById('cfg-provider').textContent = d.provider.toUpperCase();
    document.getElementById('cfg-model').textContent = d.model;
    document.getElementById('cfg-port').textContent = window.location.port || '80';
  } catch {
    document.getElementById('status-bar').textContent = 'Server unreachable';
  }
}
loadStatus();

// ------------------------------------------------------------------ Chat
const chatOutput = document.getElementById('chat-output');
const chatInput  = document.getElementById('chat-input');

function makeCopyBtn(getText) {
  const btn = document.createElement('button');
  btn.className = 'copy-btn';
  btn.textContent = 'Copy';
  btn.addEventListener('click', () => {
    navigator.clipboard.writeText(getText()).then(() => {
      btn.textContent = 'Copied!';
      btn.classList.add('copied');
      setTimeout(() => { btn.textContent = 'Copy'; btn.classList.remove('copied'); }, 1500);
    }).catch(() => {
      btn.textContent = 'Error';
      setTimeout(() => { btn.textContent = 'Copy'; }, 1500);
    });
  });
  return btn;
}

function appendMsg(cls, text) {
  const d = document.createElement('div');
  d.className = cls;
  d.textContent = text;
  if (cls === 'msg-ai') {
    const cleanText = text.replace(/^🤖\s*/, '');
    d.appendChild(makeCopyBtn(() => cleanText));
  }
  if (chatOutput.children.length === 1 && chatOutput.children[0].tagName === 'SPAN') {
    chatOutput.innerHTML = '';
  }
  chatOutput.appendChild(d);
  chatOutput.scrollTop = chatOutput.scrollHeight;
}

document.getElementById('btn-send').addEventListener('click', async () => {
  const userPrompt = chatInput.value.trim();
  if (!userPrompt) return;
  chatInput.value = '';
  const fileContent = collectAttachedFileContent('chat');
  const prompt = fileContent ? fileContent + userPrompt : userPrompt;
  appendMsg('msg-user', '🧑 ' + userPrompt + (fileContent ? ' 📎' : ''));
  clearAttachedFiles('chat');
  const btn = document.getElementById('btn-send');
  btn.disabled = true;
  btn.textContent = 'Thinking…';
  try {
    const r = await fetch('/api/generate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt, tab: 'chat' })
    });
    const d = await r.json();
    if (d.result) {
      appendMsg('msg-ai', '🤖 ' + d.result);
    } else {
      appendMsg('msg-err', '❌ ' + (d.error || 'Unknown error'));
    }
  } catch (e) {
    appendMsg('msg-err', '❌ Network error: ' + e.message);
  }
  btn.disabled = false;
  btn.textContent = 'Send';
});

chatInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
    document.getElementById('btn-send').click();
  }
});

document.getElementById('btn-clear-chat').addEventListener('click', () => {
  chatOutput.innerHTML = '<span style="color:#64748b">Cleared. Type a new message.</span>';
});

// ------------------------------------------------------------------ Model selector
document.getElementById('btn-load-models').addEventListener('click', async () => {
  const status = document.getElementById('model-loader-status');
  const wrap   = document.getElementById('model-select-wrap');
  const sel    = document.getElementById('model-select');
  status.textContent = 'Loading models…';
  status.style.color = '#94a3b8';
  try {
    const r = await fetch('/api/models');
    const d = await r.json();
    if (d.error) throw new Error(d.error);
    sel.innerHTML = '';
    (d.models || []).forEach(m => {
      const opt = document.createElement('option');
      opt.value = m.id;
      opt.textContent = m.displayName || m.id;
      if (m.id === d.current) opt.selected = true;
      sel.appendChild(opt);
    });
    wrap.style.display = 'block';
    status.textContent = `${d.models.length} model(s) loaded.` + (d.warning ? ' ⚠️ ' + d.warning : '');
    status.style.color = d.warning ? '#fbbf24' : '#4ade80';
  } catch (e) {
    status.textContent = '❌ ' + e.message;
    status.style.color = '#f87171';
  }
});

document.getElementById('btn-save-model').addEventListener('click', async () => {
  const model  = document.getElementById('model-select').value;
  const status = document.getElementById('model-save-status');
  if (!model) return;
  status.textContent = 'Saving…';
  status.style.color = '#94a3b8';
  try {
    const r = await fetch('/api/setmodel', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model })
    });
    const d = await r.json();
    if (d.ok) {
      status.textContent = '✅ ' + d.message;
      status.style.color = '#4ade80';
      document.getElementById('cfg-model').textContent = model;
      // Poll until the server comes back up
      pollReconnect(status);
    } else {
      status.textContent = '❌ ' + (d.error || 'Failed');
      status.style.color = '#f87171';
    }
  } catch (e) {
    status.textContent = '❌ ' + e.message;
    status.style.color = '#f87171';
  }
});

function pollReconnect(statusEl) {
  let attempts = 0;
  const max = 20;
  const interval = setInterval(async () => {
    attempts++;
    try {
      const r = await fetch('/api/status');
      if (r.ok) {
        clearInterval(interval);
        const d = await r.json();
        if (statusEl) {
          statusEl.textContent = '✅ Server back online — model: ' + d.model;
          statusEl.style.color = '#4ade80';
        }
        document.getElementById('status-bar').innerHTML =
          `<span>${d.provider.toUpperCase()}</span> · <span>${d.model}</span>`;
        document.getElementById('cfg-model').textContent = d.model;
      }
    } catch (_) { /* still restarting */ }
    if (attempts >= max) {
      clearInterval(interval);
      if (statusEl) {
        statusEl.textContent = '⚠️ Server did not respond. Check your terminal.';
        statusEl.style.color = '#fbbf24';
      }
    }
  }, 1500);
}

// ------------------------------------------------------------------ API Key
document.getElementById('btn-save-key').addEventListener('click', async () => {
  const key    = document.getElementById('key-input').value.trim();
  const status = document.getElementById('key-status');
  if (!key) { status.textContent = 'No key entered.'; status.style.color = '#fbbf24'; return; }
  status.textContent = 'Saving…';
  status.style.color = '#94a3b8';
  try {
    const r = await fetch('/api/setkey', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key })
    });
    const d = await r.json();
    if (d.ok) {
      status.textContent = '✅ Key saved. Server is restarting…';
      status.style.color = '#4ade80';
      pollReconnect(status);
    } else {
      status.textContent = '❌ ' + (d.error || 'Failed');
      status.style.color = '#f87171';
    }
  } catch (e) {
    status.textContent = '❌ ' + e.message;
    status.style.color = '#f87171';
  }
});

// ------------------------------------------------------------------ History
async function loadHistory() {
  const list = document.getElementById('history-list');
  list.innerHTML = '<span style="color:#64748b">Loading…</span>';
  try {
    const r = await fetch('/api/history');
    const rows = await r.json();
    if (!rows.length) { list.innerHTML = '<span style="color:#64748b">No history yet.</span>'; return; }
    list.innerHTML = '';
    rows.forEach(row => {
      const item = document.createElement('div');
      item.className = 'history-item';
      item.innerHTML = `
        <button class="del-btn" data-id="${row.id}">✕</button>
        <div class="history-meta">${row.date} · ${row.provider} · ${row.tab}</div>
        <div class="history-prompt">${escHtml(row.prompt)}</div>
        <div class="history-response" id="hr-${row.id}">${escHtml(row.response)}</div>
        <button style="background:none;border:none;color:#38bdf8;cursor:pointer;font-size:0.75rem;margin-top:4px"
                onclick="toggleExpand('hr-${row.id}',this)">Show more</button>
      `;
      list.appendChild(item);
    });
    list.querySelectorAll('.del-btn').forEach(btn => {
      btn.addEventListener('click', async () => {
        await fetch('/api/history/' + btn.dataset.id, { method: 'DELETE' });
        loadHistory();
      });
    });
  } catch {
    list.innerHTML = '<span style="color:#f87171">Failed to load history.</span>';
  }
}

document.getElementById('btn-load-history').addEventListener('click', loadHistory);

function toggleExpand(id, btn) {
  const el = document.getElementById(id);
  el.classList.toggle('expanded');
  btn.textContent = el.classList.contains('expanded') ? 'Show less' : 'Show more';
}

function escHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ------------------------------------------------------------------ Business tabs
const BIZ_SYSTEMS = {
  email:   'You are a professional business email writer. Write clear, concise, and professional emails with a proper subject line, greeting, body, and sign-off. Adapt the tone (formal or friendly) to fit the context described.',
  social:  'You are a social media marketing expert. Create engaging, platform-appropriate content with relevant hashtags and a clear call to action. Match the platform tone: professional for LinkedIn, conversational for Facebook, punchy for X/Twitter, visual-led for Instagram.',
  sales:   'You are an expert sales professional. Create compelling, persuasive sales content that highlights customer value, overcomes objections, and drives action. Keep the tone confident yet helpful.',
  content: 'You are a professional content writer and editor. Create engaging, well-structured content that informs, educates, or entertains the reader. Use clear headings, short paragraphs, and an active voice.',
  seo:     'You are an SEO specialist. Create SEO-optimised content — including meta descriptions (max 160 chars), page titles (max 60 chars), keyword lists, and keyword-rich body copy — that improves search engine rankings while remaining readable and helpful.',
  support: "You are a customer support specialist. Write helpful, empathetic, and professional responses that acknowledge the customer's concern, provide a clear resolution, and maintain a positive relationship. Stay calm and constructive even when the customer is upset."
};

document.querySelectorAll('.chip').forEach(chip => {
  chip.addEventListener('click', () => {
    const section = chip.closest('section');
    if (!section) return;
    const tabId = section.id.replace('tab-', '');
    const inp = document.getElementById('inp-' + tabId);
    if (inp) { inp.value = chip.textContent.trim(); inp.focus(); }
  });
});

document.querySelectorAll('.biz-send').forEach(btn => {
  btn.addEventListener('click', async () => {
    const tabId    = btn.dataset.tab;
    const outEl    = document.getElementById(btn.dataset.out);
    const inpEl    = document.getElementById(btn.dataset.inp);
    const userPrompt = inpEl.value.trim();
    if (!userPrompt) return;
    const fileContent = collectAttachedFileContent(tabId);
    const prompt = fileContent ? fileContent + userPrompt : userPrompt;
    clearAttachedFiles(tabId);
    outEl.innerHTML = '<span style="color:#94a3b8">Thinking…</span>';
    btn.disabled = true;
    btn.textContent = 'Thinking…';
    try {
      const r = await fetch('/api/generate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt, system: BIZ_SYSTEMS[tabId] || '', tab: tabId })
      });
      const d = await r.json();
      if (d.result) {
        const div = document.createElement('div');
        div.className = 'biz-result';
        div.textContent = d.result;
        const resultText = d.result;
        div.appendChild(makeCopyBtn(() => resultText));
        outEl.innerHTML = '';
        outEl.appendChild(div);
      } else {
        outEl.innerHTML = '<span class="biz-err">❌ ' + escHtml(d.error || 'Unknown error') + '</span>';
      }
    } catch (e) {
      outEl.innerHTML = '<span class="biz-err">❌ Network error: ' + escHtml(e.message) + '</span>';
    }
    btn.disabled = false;
    btn.textContent = 'Generate';
  });
});

document.querySelectorAll('.biz-clear').forEach(btn => {
  const outEl = document.getElementById(btn.dataset.out);
  const inpEl = document.getElementById(btn.dataset.inp);
  btn.addEventListener('click', () => {
    outEl.innerHTML = '<span class="biz-placeholder">Cleared. Enter a new prompt or click a quick prompt above.</span>';
    inpEl.value = '';
  });
});

// ------------------------------------------------------------------ File attachment
// Map: tabId -> { filename, content }[]
const attachedFiles = {};

function getFileTabKey(tabId) {
  return tabId === 'chat' ? 'chat' : tabId;
}

function collectAttachedFileContent(tabId) {
  const files = attachedFiles[getFileTabKey(tabId)];
  if (!files || files.length === 0) return '';
  return files.map(f => `[Attached file: ${f.filename}]\n${f.content}`).join('\n\n') + '\n\n';
}

function clearAttachedFiles(tabId) {
  const key = getFileTabKey(tabId);
  attachedFiles[key] = [];
  const badgesId = tabId === 'chat' ? 'chat-file-badges' : 'file-badges-' + tabId;
  const badgesEl = document.getElementById(badgesId);
  if (badgesEl) badgesEl.innerHTML = '';
}

function setupFileInput(inputId, badgesId, tabId) {
  const input = document.getElementById(inputId);
  const badges = document.getElementById(badgesId);
  if (!input || !badges) return;
  const key = getFileTabKey(tabId);
  if (!attachedFiles[key]) attachedFiles[key] = [];
  input.addEventListener('change', () => {
    Array.from(input.files).forEach(file => {
      if (file.size > 500 * 1024) {
        alert('File "' + file.name + '" is too large (max 500 KB). Please choose a smaller file.');
        return;
      }
      const reader = new FileReader();
      reader.onload = (e) => {
        const content = e.target.result;
        // Reject files that look binary (contain null bytes)
        if (content.includes('\x00')) {
          alert('File "' + file.name + '" appears to be a binary file and cannot be attached. Please use plain text files.');
          return;
        }
        attachedFiles[key].push({ filename: file.name, content });
        const badge = document.createElement('span');
        badge.className = 'file-badge';
        badge.innerHTML = '📎 ' + escHtml(file.name) +
          '<button title="Remove" data-fname="' + escHtml(file.name) + '">×</button>';
        badge.querySelector('button').addEventListener('click', () => {
          attachedFiles[key] = attachedFiles[key].filter(f => f.filename !== file.name);
          badge.remove();
        });
        badges.appendChild(badge);
      };
      reader.readAsText(file);
    });
    input.value = '';
  });
}

// Wire up all file inputs
setupFileInput('chat-file',      'chat-file-badges',    'chat');
setupFileInput('file-email',     'file-badges-email',   'email');
setupFileInput('file-social',    'file-badges-social',  'social');
setupFileInput('file-sales',     'file-badges-sales',   'sales');
setupFileInput('file-content',   'file-badges-content', 'content');
setupFileInput('file-seo',       'file-badges-seo',     'seo');
setupFileInput('file-support',   'file-badges-support', 'support');

// ------------------------------------------------------------------ Project save
let _saveContext = null;  // { tab, inpId, outId }

document.querySelectorAll('.btn-save-project').forEach(btn => {
  btn.addEventListener('click', () => {
    _saveContext = { tab: btn.dataset.tab, inpId: btn.dataset.inp, outId: btn.dataset.out };
    const modal = document.getElementById('save-modal');
    document.getElementById('save-project-name').value = '';
    document.getElementById('save-modal-status').textContent = '';
    modal.classList.add('open');
    document.getElementById('save-project-name').focus();
  });
});

document.getElementById('btn-cancel-save').addEventListener('click', () => {
  document.getElementById('save-modal').classList.remove('open');
  _saveContext = null;
});

document.getElementById('save-modal').addEventListener('click', (e) => {
  if (e.target === e.currentTarget) {
    e.currentTarget.classList.remove('open');
    _saveContext = null;
  }
});

document.getElementById('btn-confirm-save').addEventListener('click', async () => {
  const name = document.getElementById('save-project-name').value.trim();
  const statusEl = document.getElementById('save-modal-status');
  if (!name) { statusEl.textContent = 'Please enter a project name.'; statusEl.style.color = '#fbbf24'; return; }
  if (!_saveContext) return;

  let prompt = '';
  let output = '';
  if (_saveContext.tab === 'chat') {
    const chatEl = document.getElementById('chat-output');
    prompt = document.getElementById('chat-input').value.trim();
    output = chatEl ? chatEl.innerText : '';
  } else {
    prompt = document.getElementById(_saveContext.inpId) ? document.getElementById(_saveContext.inpId).value.trim() : '';
    const outEl = document.getElementById(_saveContext.outId);
    output = outEl ? outEl.innerText : '';
  }

  statusEl.textContent = 'Saving…';
  statusEl.style.color = '#94a3b8';
  try {
    const r = await fetch('/api/projects', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, tab: _saveContext.tab, prompt, output })
    });
    const d = await r.json();
    if (d.ok) {
      statusEl.textContent = '✅ Saved as "' + escHtml(name) + '"!';
      statusEl.style.color = '#4ade80';
      setTimeout(() => {
        document.getElementById('save-modal').classList.remove('open');
        _saveContext = null;
      }, 1200);
    } else {
      statusEl.textContent = '❌ ' + (d.error || 'Save failed');
      statusEl.style.color = '#f87171';
    }
  } catch (e) {
    statusEl.textContent = '❌ ' + e.message;
    statusEl.style.color = '#f87171';
  }
});

document.getElementById('save-project-name').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') document.getElementById('btn-confirm-save').click();
  if (e.key === 'Escape') document.getElementById('btn-cancel-save').click();
});

// ------------------------------------------------------------------ Projects tab
async function loadProjects() {
  const list = document.getElementById('projects-list');
  list.innerHTML = '<span style="color:#64748b">Loading…</span>';
  try {
    const r = await fetch('/api/projects');
    const rows = await r.json();
    if (!rows.length) { list.innerHTML = '<span style="color:#64748b">No saved projects yet. Use the 💾 Save button in any tab.</span>'; return; }
    list.innerHTML = '';
    rows.forEach(row => {
      const item = document.createElement('div');
      item.className = 'project-item';
      item.innerHTML = `
        <div class="project-meta">${escHtml(row.date)} &bull; ${escHtml(row.tab)}</div>
        <div class="project-name">💾 ${escHtml(row.name)}</div>
        <div class="project-preview">${escHtml(row.output).substring(0, 200)}${row.output.length > 200 ? '…' : ''}</div>
        <div class="project-actions">
          <button class="btn-sec" style="font-size:0.8rem;padding:5px 12px;" data-id="${row.id}" data-tab="${escHtml(row.tab)}">Load</button>
          <button class="btn-danger" style="font-size:0.8rem;padding:5px 12px;" data-del="${row.id}">\u2715 Delete</button>
        </div>
      `;
      item.querySelector('[data-del]').addEventListener('click', async () => {
        await fetch('/api/projects/' + row.id, { method: 'DELETE' });
        loadProjects();
      });
      item.querySelector('[data-id]').addEventListener('click', async () => {
        const pr = await fetch('/api/projects/' + row.id);
        const proj = await pr.json();
        // Switch to the relevant tab
        const tabBtn = document.querySelector('.tab-btn[data-tab="' + proj.tab + '"]');
        if (tabBtn) tabBtn.click();
        setTimeout(() => {
          if (proj.tab === 'chat') {
            const outEl = document.getElementById('chat-output');
            if (outEl) { outEl.innerHTML = ''; const d = document.createElement('div'); d.className='msg-ai'; d.textContent = proj.output; const t0=proj.output; d.appendChild(makeCopyBtn(() => t0)); outEl.appendChild(d); }
            const inp = document.getElementById('chat-input');
            if (inp) inp.value = proj.prompt;
          } else {
            const outEl = document.getElementById('out-' + proj.tab);
            if (outEl) { const d = document.createElement('div'); d.className='biz-result'; d.textContent = proj.output; const t1=proj.output; d.appendChild(makeCopyBtn(() => t1)); outEl.innerHTML=''; outEl.appendChild(d); }
            const inp = document.getElementById('inp-' + proj.tab);
            if (inp) inp.value = proj.prompt;
          }
        }, 80);
      });
      list.appendChild(item);
    });
  } catch {
    list.innerHTML = '<span style="color:#f87171">Failed to load projects.</span>';
  }
}

document.getElementById('btn-load-projects').addEventListener('click', loadProjects);
</script>
</body>
</html>
FRONTEOF

# ===================================================================
# Helper scripts  (read PORT from .env at runtime — no hardcoding)
# ===================================================================

cat > "$INSTALL_DIR/start.sh" << 'STARTEOF'
#!/usr/bin/env bash
cd "$(dirname "$0")"
APP_PORT=$(grep -oP '(?<=PORT=)\d+' server/.env 2>/dev/null || echo "8080")
pkill -f "node server/app.js" 2>/dev/null || true
lsof -ti:"${APP_PORT}" | xargs kill -9 2>/dev/null || true
sleep 1
echo "🚀 Starting MrT AI Hub PRO v3.2 on port ${APP_PORT}..."
while true; do
  node server/app.js
  EXIT=$?
  # Exit 1   = startup config error (missing API key) — do not restart
  # Exit 130+ = signal (SIGINT / SIGKILL / SIGTERM) — user stopped it, do not restart
  # Any other exit (0 = clean model/key restart, 2+ = unexpected crash) — restart
  if [ "$EXIT" -eq 1 ] || [ "$EXIT" -ge 130 ]; then
    break
  fi
  echo "🔄 Restarting..."
  sleep 1
done
STARTEOF
chmod +x "$INSTALL_DIR/start.sh"

cat > "$INSTALL_DIR/stop.sh" << 'STOPEOF'
#!/usr/bin/env bash
APP_PORT=$(grep -oP '(?<=PORT=)\d+' "$(dirname "$0")/server/.env" 2>/dev/null || echo "8080")
pkill -f "node server/app.js" 2>/dev/null && echo "✅ Stopped" || echo "Not running"
lsof -ti:"${APP_PORT}" | xargs kill -9 2>/dev/null || true
STOPEOF
chmod +x "$INSTALL_DIR/stop.sh"

cat > "$INSTALL_DIR/restart.sh" << 'RESTARTEOF'
#!/usr/bin/env bash
cd "$(dirname "$0")"
./stop.sh
sleep 1
exec ./start.sh
RESTARTEOF
chmod +x "$INSTALL_DIR/restart.sh"

cat > "$INSTALL_DIR/status.sh" << 'STATEOF'
#!/usr/bin/env bash
APP_PORT=$(grep -oP '(?<=PORT=)\d+' "$(dirname "$0")/server/.env" 2>/dev/null || echo "8080")
if pgrep -f "node server/app.js" > /dev/null; then
  echo "✅ RUNNING → http://localhost:${APP_PORT}"
else
  echo "❌ NOT running → ./start.sh"
fi
STATEOF
chmod +x "$INSTALL_DIR/status.sh"

# ===================================================================
# Summary
# ===================================================================
echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}✅ MrT AI Hub PRO v3.2 — COMPLETE${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "  ${BLUE}Location:${NC} $INSTALL_DIR"
echo -e "  ${BLUE}Provider:${NC} $PROVIDER"
echo -e "  ${BLUE}Model:   ${NC} $MODEL_NAME"
echo -e "  ${BLUE}Port:    ${NC} $APP_PORT"
echo ""
echo "Commands:"
echo "  ./start.sh    → Start server  (http://localhost:${APP_PORT})"
echo "  ./stop.sh     → Stop server"
echo "  ./restart.sh  → Restart server"
echo "  ./status.sh   → Check status"
echo ""
echo -e "${GREEN}👉 Run:  ./start.sh${NC}"
echo ""
