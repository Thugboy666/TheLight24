#!/usr/bin/env sh
# Spegnimento ordinato di TheLight24
set -eu

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="$BASEDIR/runtime"

stop_service() {
  NAME="$1"
  PIDFILE="$RUN_DIR/$NAME.pid"

  if [ ! -f "$PIDFILE" ]; then
    echo "ℹ️  $NAME non ha PID file. Skip."
    return
  fi

  PID="$(cat "$PIDFILE" 2>/dev/null || true)"

  if [ -z "$PID" ]; then
    echo "ℹ️  $NAME PID vuoto. Skip."
    rm -f "$PIDFILE" 2>/dev/null || true
    return
  fi

  if kill -0 "$PID" 2>/dev/null; then
    echo "⛔ Stop $NAME (PID $PID)..."
    kill "$PID" 2>/dev/null || true
    sleep 1
    if kill -0 "$PID" 2>/dev/null; then
      echo "⚠️  Forzo kill -9 su $NAME..."
      kill -9 "$PID" 2>/dev/null || true
    fi
  else
    echo "ℹ️  $NAME non è attivo."
  fi

  rm -f "$PIDFILE" 2>/dev/null || true
  echo "✔️  $NAME stoppato."
}

echo "----- 🔻 STOP THELIGHT24 🔻 -----"
stop_service "gui"
stop_service "llm"
echo "--------------------------------"
echo "✅ Tutti i servizi stoppati."
