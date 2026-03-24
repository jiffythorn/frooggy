#!/usr/bin/env bash
# ================================================
# MrT AI Hub PRO - Auto Installer v3.0
# Multi-AI Support | Enhanced Debugging
# Updated: March 2026
# ================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting MrT AI Hub PRO v3.0 Installation...${NC}"

CURRENT_DIR="$(pwd)"
if [[ "$CURRENT_DIR" == "$HOME/Downloads"* ]]; then
    echo -e "${YELLOW}⚠️  Detected running from Downloads folder.${NC}"
    mkdir -p "$HOME/mrt-ai-hub-pro"
    cp "$0" "$HOME/mrt-ai-hub-pro/install-mrt-pro-v3.0.sh"
    cd "$HOME/mrt-ai-hub-pro"
    chmod +x install-mrt-pro-v3.0.sh
    echo -e "${GREEN}✅ Moving to clean folder and restarting...${NC}"
    exec "$HOME/mrt-ai-hub-pro/install-mrt-pro-v3.0.sh"
fi

INSTALL_DIR="$(pwd)"
echo -e "${BLUE}📍 Installing in: $INSTALL_DIR${NC}"

# === Aggressive process cleanup ===
echo -e "${YELLOW}🛑 Cleaning up any existing MrT server processes...${NC}"
pkill -9 -f "node server/app.js" 2>/dev/null || true
pkill -9 -f "node.*app\.js" 2>/dev/null || true
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
sleep 2

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

# === API Provider Selection ===
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
    EXISTING_KEY=$(grep -oP "(?<=${PROVIDER^^}_KEY=).*" "$INSTALL_DIR/server/.env" 2>/dev/null || true)
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

if [ ${#API_KEY} -lt 10 ]; then
    echo -e "${RED}❌ API key appears too short. Please verify.${NC}"
    exit 1
fi

cat > "$INSTALL_DIR/server/.env" << EOF
PROVIDER=${PROVIDER}
${PROVIDER^^}_KEY=${API_KEY}
PORT=8080
NODE_ENV=production
DEBUG=false
EOF

chmod 600 "$INSTALL_DIR/server/.env"
echo -e "${GREEN}✅ Config saved to server/.env (permissions: 600)${NC}"

# === Backend app.js ===
cat > "$INSTALL_DIR/server/app.js" << 'APPEOF'
'use strict';
const dotenv = require('dotenv');
dotenv.config({ path: __dirname + '/.env' });

const express = require('express');
const path = require('path');
const fs = require('fs');
const sqlite3 = require('sqlite3').verbose();

const PORT = parseInt(process.env.PORT, 10) || 8080;
const PROVIDER = (process.env.PROVIDER || 'gemini').toLowerCase();

let API_KEY = '';
let MODEL_NAME = '';
let AI_SERVICE = null;

switch (PROVIDER) {
  case 'claude':
    API_KEY = (process.env.CLAUDE_KEY || '').trim();
    if (!API_KEY) {
      console.error('❌  CLAUDE_KEY is missing from server/.env');
      console.error('    Visit: https://console.anthropic.com/api_keys');
      process.exit(1);
    }
    MODEL_NAME = 'claude-3-5-sonnet-20241022';
    try {
      const Anthropic = require('@anthropic-ai/sdk');
      AI_SERVICE = new Anthropic({ apiKey: API_KEY });
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
    MODEL_NAME = 'gpt-4o-mini';
    try {
      const OpenAI = require('openai');
      AI_SERVICE = new OpenAI({ apiKey: API_KEY });
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
    MODEL_NAME = 'gemini-1.5-flash';
    try {
      const { GoogleGenerativeAI } = require('@google/generative-ai');
      const genAI = new GoogleGenerativeAI(API_KEY);
      AI_SERVICE = genAI.getGenerativeModel({ model: MODEL_NAME });
    } catch (e) {
      console.error('❌  Google SDK not installed. Run: npm install @google/generative-ai');
      process.exit(1);
    }
    break;
}

console.log(`✅ Initialized ${PROVIDER.toUpperCase()} (${MODEL_NAME})`);

const app = express();
const dataDir = path.join(__dirname, '../data');
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

const db = new sqlite3.Database(path.join(dataDir, 'mrt_pro.db'));
db.serialize(() => {
  db.run(`CREATE TABLE IF NOT EXISTS history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tab TEXT NOT NULL DEFAULT 'chat',
    prompt TEXT NOT NULL,
    response TEXT NOT NULL,
    provider TEXT NOT NULL DEFAULT 'gemini',
    date DATETIME DEFAULT CURRENT_TIMESTAMP
  )`);
});

app.use(express.json({ limit: '2mb' }));
app.use(express.static(path.join(__dirname, '../frontend')));

let lastCall = 0;
const RATE_MS = 1500;

app.get('/api/status', (_req, res) => {
  res.json({ ok: true, provider: PROVIDER, model: MODEL_NAME });
});

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

    db.run('INSERT INTO history (tab, prompt, response, provider) VALUES (?, ?, ?, ?)',
      [tab || 'chat', prompt.trim(), text, PROVIDER]);
    res.json({ result: text });
  } catch (err) {
    console.error(`${PROVIDER.toUpperCase()} error:`, err.message);
    res.status(500).json({ error: `AI error. Check your API key in server/.env` });
  }
});

app.post('/api/setkey', (req, res) => {
  const { key, provider } = req.body || {};
  if (!key || key.trim().length < 10) {
    return res.status(400).json({ ok: false, error: 'Invalid key' });
  }
  const p = (provider || PROVIDER).toLowerCase();
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
    setTimeout(() => process.exit(0), 400);
  } catch (e) {
    res.status(500).json({ ok: false, error: 'Could not write .env' });
  }
});

app.get('/api/history', (req, res) => {
  db.all('SELECT * FROM history ORDER BY date DESC LIMIT 25', [], (err, rows) => {
    res.json(err ? [] : rows);
  });
});

app.delete('/api/history/:id', (req, res) => {
  db.run('DELETE FROM history WHERE id=?', [req.params.id], (err) => {
    res.json({ ok: !err });
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n✅ MrT AI Hub PRO v3.0 → http://localhost:${PORT}`);
  console.log(`   Provider: ${PROVIDER.toUpperCase()} | Model: ${MODEL_NAME}\n`);
});
APPEOF

cd "$INSTALL_DIR"
npm init -y >/dev/null 2>&1
npm install express sqlite3 dotenv @google/generative-ai --save >/dev/null 2>&1

cat > "$INSTALL_DIR/start.sh" << 'STARTEOF'
#!/usr/bin/env bash
cd "$(dirname "$0")"
pkill -9 -f "node server/app.js" 2>/dev/null || true
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
sleep 2
echo "🚀 Starting MrT AI Hub PRO..."
while true; do
  node server/app.js
  EXIT=$?
  if [ "$EXIT" -eq 0 ]; then
    echo "🔄 Restarting..."
    sleep 1
  else
    break
  fi
done
STARTEOF
chmod +x "$INSTALL_DIR/start.sh"

cat > "$INSTALL_DIR/stop.sh" << 'STOPEOF'
#!/usr/bin/env bash
pkill -9 -f "node server/app.js" 2>/dev/null && echo "✅ Stopped" || echo "Not running"
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
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
if pgrep -f "node server/app.js" > /dev/null; then
  echo "✅ RUNNING → http://localhost:8080"
else
  echo "❌ NOT running → ./start.sh"
fi
STATEOF
chmod +x "$INSTALL_DIR/status.sh"

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}✅ MrT AI Hub PRO v3.0 — COMPLETE${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "${BLUE}Location: $INSTALL_DIR${NC}"
echo -e "${BLUE}Provider: $PROVIDER${NC}"
echo ""
echo "Commands:"
echo "  ./start.sh    → Run server"
echo "  ./stop.sh     → Stop server"
echo "  ./restart.sh  → Restart"
echo "  ./status.sh   → Check status"
echo ""
echo -e "${GREEN}👉 Run:](#)*
