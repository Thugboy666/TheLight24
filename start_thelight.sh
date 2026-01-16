#!/usr/bin/env sh
# Avvio ordinato: llama.cpp server + API+GUI aiohttp
# Versione "parla chiaro", niente morti silenziose
set -u

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$BASEDIR/run"
LOG_DIR="$BASEDIR/logs"
UI_INDEX="$BASEDIR/gui/index.html"
PYTHON_BIN="${PYTHON_BIN:-python3}"

mkdir -p "$RUN_DIR" "$LOG_DIR"

if [ ! -f "$UI_INDEX" ]; then
  echo "❌ File GUI mancante: $UI_INDEX"
  echo "Assicurati che gui/index.html esista prima di avviare TheLight24."
  exit 1
fi

echo "----- 🚀 START THELIGHT24 -----"
echo "BASEDIR = $BASEDIR"

# Attiva/crea venv
if [ ! -d "$BASEDIR/.venv" ]; then
  echo "→ Creo virtualenv .venv"
  "$PYTHON_BIN" -m venv "$BASEDIR/.venv" || {
    echo "❌ Impossibile creare la virtualenv (.venv)."
    exit 1
  }
fi

echo "→ Attivo virtualenv .venv"
. "$BASEDIR/.venv/bin/activate"

if [ -f "$BASEDIR/requirements.txt" ]; then
  echo "→ Aggiorno pip e installo dipendenze da requirements.txt"
  python -m pip install --upgrade pip >/dev/null 2>&1 || true
  python -m pip install -r "$BASEDIR/requirements.txt" || {
    echo "❌ Installazione dipendenze fallita (controlla la rete o riprova)."
    exit 1
  }
fi

LLM_BIN="$BASEDIR/llm/llama.cpp/build/bin/llama-server"

# Possibili percorsi modello
MODEL_A="$BASEDIR/llm/models/Phi-3-mini-4k-instruct-q4"
MODEL_B="$BASEDIR/llm/models/Phi-3-mini-4k-instruct-q4"
MODELS_DIR1="$BASEDIR/llm/models"
MODELS_DIR2="$BASEDIR/llm/llama.cpp/build/bin"

LLM_HOST="0.0.0.0"
LLM_PORT="8081"
LLM_THREADS="${LLM_THREADS:-6}"
LLM_CTX="${LLM_CTX:-1024}"

API_PORT="8080"
API_HOST="${API_HOST:-0.0.0.0}"
CLOUDFLARE_HOSTNAME="${CLOUDFLARE_HOSTNAME:-${CLOUDFLARE_TUNNEL_HOSTNAME:-}}"

stop_dead_pidfile() {
  PF="$1"
  if [ -f "$PF" ]; then
    PID="$(cat "$PF" 2>/dev/null || true)"
    if [ -n "${PID:-}" ] && ! kill -0 "$PID" 2>/dev/null; then
      echo "ℹ️  Rimuovo PID file orfano: $PF"
      rm -f "$PF" 2>/dev/null || true
    fi
  fi
}

mkdir -p "$RUN_DIR"

stop_dead_pidfile "$RUN_DIR/llm.pid"
stop_dead_pidfile "$RUN_DIR/gui.pid"

# === CHECK BINARIO LLM ===
if [ ! -x "$LLM_BIN" ]; then
  echo "❌ Binario llama-server non trovato o non eseguibile:"
  echo "   $LLM_BIN"
  echo "Controlla di aver compilato llama.cpp e che il path sia corretto."
  exit 1
fi
echo "✔️  Trovato llama-server: $LLM_BIN"

# === SCELTA MODELLO ===
MODEL=""

if [ -n "${LLM_MODEL_PATH:-}" ] && [ -f "$LLM_MODEL_PATH" ]; then
  MODEL="$LLM_MODEL_PATH"
elif [ -f "$MODEL_A" ]; then
  MODEL="$MODEL_A"
elif [ -f "$MODEL_B" ]; then
  MODEL="$MODEL_B"
else
  # uso find ma senza far esplodere lo script se una cartella non esiste
  CANDIDATE=""
  if [ -d "$MODELS_DIR1" ] || [ -d "$MODELS_DIR2" ]; then
    CANDIDATE="$(find "$MODELS_DIR1" "$MODELS_DIR2" -maxdepth 2 -type f -name '*.gguf' 2>/dev/null | head -n 1 || true)"
  fi
  if [ -n "$CANDIDATE" ] && [ -f "$CANDIDATE" ]; then
    MODEL="$CANDIDATE"
  fi
fi

if [ -z "$MODEL" ]; then
  echo "❌ Nessun modello GGUF trovato.
Ho cercato qui:
  - $MODEL_A
  - $MODEL_B
  - $MODELS_DIR1 (tutti i .gguf)
  - $MODELS_DIR2 (tutti i .gguf)

Sposta il tuo modello .gguf in una di queste cartelle
(o lancia con:  LLM_MODEL_PATH=/percorso/modello.gguf ./start_thelight.sh )"
  exit 1
fi

echo "🧠 Userò il modello: $MODEL"

# === AVVIO LLM ===
if [ -f "$RUN_DIR/llm.pid" ] && kill -0 "$(cat "$RUN_DIR/llm.pid")" 2>/dev/null; then
  echo "ℹ️  LLM già avviato (PID $(cat "$RUN_DIR/llm.pid"))."
else
  echo "▶️  Avvio LLM: $LLM_BIN"
  (cd "$(dirname "$LLM_BIN")" && \
    nohup "$LLM_BIN" \
      -m "$MODEL" \
      --host "$LLM_HOST" \
      --port "$LLM_PORT" \
      --threads "$LLM_THREADS" \
      --ctx-size "$LLM_CTX" \
      > "$LOG_DIR/llm.log" 2>&1 & echo $! > "$RUN_DIR/llm.pid")
  sleep 2
fi

# === CHECK LLM RAPIDO ===
printf "⏳ Attendo LLM su 127.0.0.1:%s/completion ...\n" "$LLM_PORT"
LLM_READY="false"
if command -v curl >/dev/null 2>&1; then
  START_TS="$(date +%s)"
  while true; do
    CODE="$(curl -s -o /dev/null -w "%{http_code}" -m 3 -H "Content-Type: application/json" \
      -d '{"prompt":"ping","n_predict":8}' \
      "http://127.0.0.1:${LLM_PORT}/completion" || true)"
    if [ "$CODE" = "200" ] || [ "$CODE" = "400" ] || [ "$CODE" = "405" ]; then
      echo "✅ LLM ready (HTTP $CODE)"
      LLM_READY="true"
      break
    fi
    if [ "$CODE" = "503" ]; then
      echo "⏳ LLM warming up (HTTP 503)..."
    elif [ "$CODE" = "000" ] || [ -z "$CODE" ]; then
      echo "⏳ LLM non raggiungibile..."
    else
      echo "ℹ️  LLM risponde HTTP $CODE, continuo attesa..."
    fi
    NOW_TS="$(date +%s)"
    if [ $((NOW_TS - START_TS)) -ge 90 ]; then
      echo "⚠️  Timeout attesa LLM (90s), procedo comunque."
      break
    fi
    sleep 2
  done
else
  echo "⚠️  curl non disponibile, salto check LLM"
fi

# === AVVIO API+GUI (aiohttp + index.html) ===
if [ -f "$RUN_DIR/gui.pid" ] && kill -0 "$(cat "$RUN_DIR/gui.pid")" 2>/dev/null; then
  echo "ℹ️  API+GUI già avviate (PID $(cat "$RUN_DIR/gui.pid"))."
else
  echo "▶️  Avvio API+GUI (python -m api.server) su ${API_HOST}:${API_PORT}"
  (
    cd "$BASEDIR" && \
    . "$BASEDIR/.venv/bin/activate" && \
    export PYTHONPATH="$BASEDIR" && \
    API_HOST="$API_HOST" \
    API_PORT="$API_PORT" \
    LLM_BACKEND_URL="http://127.0.0.1:${LLM_PORT}/completion" \
    nohup python -m api.server > "$LOG_DIR/gui.log" 2>&1 & echo $! > "$RUN_DIR/gui.pid"
  )
  sleep 2
fi

if [ "$LLM_READY" = "true" ]; then
  echo "✅ LLM ready."
else
  echo "⚠️  LLM non confermato pronto (controlla logs/llm.log)."
fi
echo "✅ API ready."
echo "- LLM:      PID $(cat "$RUN_DIR/llm.pid" 2>/dev/null || echo '?')  | log: $LOG_DIR/llm.log  | http://127.0.0.1:$LLM_PORT"
echo "- API+GUI:  PID $(cat "$RUN_DIR/gui.pid" 2>/dev/null || echo '?') | log: $LOG_DIR/gui.log | http://127.0.0.1:$API_PORT"
if [ -n "$CLOUDFLARE_HOSTNAME" ]; then
  echo "Public URL via Cloudflare: https://$CLOUDFLARE_HOSTNAME"
else
  echo "Public URL via Cloudflare: (imposta CLOUDFLARE_HOSTNAME)"
fi
echo "------------------------------------"
