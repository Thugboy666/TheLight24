#!/usr/bin/env sh
# Avvio ordinato: llama.cpp server + API+GUI aiohttp
# Versione "parla chiaro", niente morti silenziose
set -u

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$BASEDIR/runtime"
LOG_DIR="$RUN_DIR/logs"
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

LLM_HOST="127.0.0.1"
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

LLM_PID_FILE="$RUN_DIR/llm.pid"
GUI_PID_FILE="$RUN_DIR/gui.pid"
CLOUDFLARED_PID_FILE="$RUN_DIR/cloudflared.pid"

stop_dead_pidfile "$LLM_PID_FILE"
stop_dead_pidfile "$GUI_PID_FILE"
stop_dead_pidfile "$CLOUDFLARED_PID_FILE"

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

is_port_listening() {
  PORT="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -E "[:.]${PORT}\$" >/dev/null 2>&1
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | grep -E "[:.]${PORT}\$" >/dev/null 2>&1
    return $?
  fi
  return 1
}

describe_port_usage() {
  PORT="$1"
  if command -v ss >/dev/null 2>&1; then
    LINE="$(ss -ltnp "sport = :$PORT" 2>/dev/null | tail -n 1)"
    PID="$(printf "%s" "$LINE" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')"
    PROC="$(printf "%s" "$LINE" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')"
    if [ -n "$PID" ]; then
      echo "PID $PID (${PROC:-process})"
      return 0
    fi
    echo "$LINE"
    return 0
  fi
  if command -v lsof >/dev/null 2>&1; then
    LINE="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1, "pid", $2}')"
    if [ -n "$LINE" ]; then
      echo "$LINE"
      return 0
    fi
  fi
  echo "processo sconosciuto"
}

ensure_port_available() {
  PORT="$1"
  PID_FILE="$2"
  LABEL="$3"
  if is_port_listening "$PORT"; then
    PORT_INFO="$(describe_port_usage "$PORT")"
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
      echo "ℹ️  $LABEL già in ascolto sulla porta $PORT (PID $(cat "$PID_FILE"))."
      return 0
    fi
    echo "❌ Porta $PORT già in uso: $PORT_INFO"
    echo "Chiudi il processo o aggiorna il PID file ($PID_FILE) prima di continuare."
    exit 1
  fi
}

ensure_llm_running() {
  ensure_port_available "$LLM_PORT" "$LLM_PID_FILE" "LLM"
  if [ -f "$LLM_PID_FILE" ] && kill -0 "$(cat "$LLM_PID_FILE")" 2>/dev/null; then
    echo "ℹ️  LLM già avviato (PID $(cat "$LLM_PID_FILE"))."
    return 0
  fi
  echo "▶️  Avvio LLM: $LLM_BIN"
  (cd "$(dirname "$LLM_BIN")" && \
    nohup "$LLM_BIN" \
      -m "$MODEL" \
      --host "$LLM_HOST" \
      --port "$LLM_PORT" \
      --threads "$LLM_THREADS" \
      --ctx-size "$LLM_CTX" \
      > "$LOG_DIR/llm.log" 2>&1 & echo $! > "$LLM_PID_FILE")
  sleep 2
}

wait_for_llm_ready() {
  printf "⏳ Attendo LLM su 127.0.0.1:%s/completion ...\n" "$LLM_PORT"
  LLM_READY="false"
  if command -v curl >/dev/null 2>&1; then
    START_TS="$(date +%s)"
    while true; do
      CODE="$(curl -s -o /dev/null -w "%{http_code}" -m 3 -H "Content-Type: application/json" \
        -d '{"prompt":"ping","n_predict":1}' \
        "http://127.0.0.1:${LLM_PORT}/completion" || true)"
      if [ "$CODE" = "200" ]; then
        echo "✅ LLM ready (HTTP $CODE)"
        LLM_READY="true"
        break
      fi
      if [ "$CODE" = "503" ]; then
        echo "⏳ LLM warming up (HTTP 503)..."
        LLM_READY="warming"
        break
      elif [ "$CODE" = "000" ] || [ -z "$CODE" ]; then
        echo "⏳ LLM non raggiungibile..."
      else
        echo "ℹ️  LLM risponde HTTP $CODE, continuo attesa..."
      fi
      NOW_TS="$(date +%s)"
      if [ $((NOW_TS - START_TS)) -ge 120 ]; then
        echo "⚠️  Timeout attesa LLM (120s), procedo comunque."
        break
      fi
      sleep 1
    done
  else
    echo "⚠️  curl non disponibile, salto check LLM"
  fi
}

ensure_llm_running
wait_for_llm_ready

# === AVVIO API+GUI (aiohttp + index.html) ===
ensure_port_available "$API_PORT" "$GUI_PID_FILE" "API"
if [ -f "$GUI_PID_FILE" ] && kill -0 "$(cat "$GUI_PID_FILE")" 2>/dev/null; then
  echo "ℹ️  API+GUI già avviate (PID $(cat "$GUI_PID_FILE"))."
else
  echo "▶️  Avvio API+GUI (python -m api.server) su ${API_HOST}:${API_PORT}"
  (
    cd "$BASEDIR" && \
    . "$BASEDIR/.venv/bin/activate" && \
    export PYTHONPATH="$BASEDIR" && \
    API_HOST="$API_HOST" \
    API_PORT="$API_PORT" \
    LLM_BACKEND_URL="http://127.0.0.1:${LLM_PORT}/completion" \
    nohup python -m api.server > "$LOG_DIR/api.log" 2>&1 & echo $! > "$GUI_PID_FILE"
  )
  sleep 2
fi

wait_for_api_ready() {
  printf "⏳ Attendo API su 127.0.0.1:%s/system/health ...\n" "$API_PORT"
  if command -v curl >/dev/null 2>&1; then
    START_TS="$(date +%s)"
    while true; do
      CODE="$(curl -s -o /dev/null -w "%{http_code}" -m 3 "http://127.0.0.1:${API_PORT}/system/health" || true)"
      if [ "$CODE" = "200" ]; then
        echo "✅ API pronta (HTTP $CODE)"
        break
      fi
      if [ "$CODE" = "000" ] || [ -z "$CODE" ]; then
        echo "⏳ API non raggiungibile..."
      else
        echo "ℹ️  API risponde HTTP $CODE, continuo attesa..."
      fi
      NOW_TS="$(date +%s)"
      if [ $((NOW_TS - START_TS)) -ge 60 ]; then
        echo "⚠️  Timeout attesa API (60s), procedo comunque."
        break
      fi
      sleep 1
    done
  else
    echo "⚠️  curl non disponibile, salto check API"
  fi
}

wait_for_api_ready

start_cloudflared() {
  if [ -z "${CLOUDFLARED_CMD:-}" ]; then
    return 0
  fi
  if [ -f "$CLOUDFLARED_PID_FILE" ] && kill -0 "$(cat "$CLOUDFLARED_PID_FILE")" 2>/dev/null; then
    echo "ℹ️  cloudflared già avviato (PID $(cat "$CLOUDFLARED_PID_FILE"))."
    return 0
  fi
  echo "▶️  Avvio cloudflared: $CLOUDFLARED_CMD"
  nohup sh -c "$CLOUDFLARED_CMD" > "$LOG_DIR/cloudflared.log" 2>&1 & echo $! > "$CLOUDFLARED_PID_FILE"
  sleep 1
}

start_cloudflared

LAN_IP=""
if [ "$API_HOST" = "0.0.0.0" ] || [ "$API_HOST" = "::" ]; then
  if command -v hostname >/dev/null 2>&1; then
    LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
fi

if [ "$LLM_READY" = "true" ]; then
  echo "✅ LLM ready."
elif [ "$LLM_READY" = "warming" ]; then
  echo "⏳ LLM warming up (raggiungibile)."
else
  echo "⚠️  LLM non confermato pronto (controlla $LOG_DIR/llm.log)."
fi
echo "✅ API ready."
echo "- LLM:      PID $(cat "$LLM_PID_FILE" 2>/dev/null || echo '?')  | log: $LOG_DIR/llm.log  | http://127.0.0.1:$LLM_PORT"
echo "- API+GUI:  PID $(cat "$GUI_PID_FILE" 2>/dev/null || echo '?') | log: $LOG_DIR/api.log | http://127.0.0.1:$API_PORT"
if [ -n "$LAN_IP" ]; then
  echo "- LAN:      http://$LAN_IP:$API_PORT"
fi
if [ -n "$CLOUDFLARE_HOSTNAME" ]; then
  echo "Public URL via Cloudflare: https://$CLOUDFLARE_HOSTNAME"
else
  echo "Public URL via Cloudflare: (imposta CLOUDFLARE_HOSTNAME)"
fi
echo "------------------------------------"
