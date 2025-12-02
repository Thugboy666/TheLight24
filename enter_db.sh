#!/data/data/com.termux/files/usr/bin/bash

# Path base al progetto
PROJECT_DIR="$HOME/TheLight24"
DB_PATH="$PROJECT_DIR/data/db.sqlite3"

# Porta per sqlite-web
PORT=8082

# Controlla se sqlite_web è installato
if ! command -v sqlite_web >/dev/null 2>&1; then
    echo "sqlite_web non è installato. Installo ora..."
    pip install sqlite-web
fi

# Killa eventuali istanze precedenti sulla stessa porta
PID_OLD=$(lsof -t -i:$PORT)
if [ ! -z "$PID_OLD" ]; then
    echo "Killo vecchia istanza sqlite-web (PID $PID_OLD)..."
    kill -9 $PID_OLD
fi

# Avvia sqlite-web
echo "Avvio pannello DB su http://127.0.0.1:$PORT ..."
sqlite_web "$DB_PATH" --host 0.0.0.0 --port $PORT &
PID_NEW=$!
echo $PID_NEW > "$PROJECT_DIR/.db_pid"
sleep 1

# Apri browser
termux-open-url "http://127.0.0.1:$PORT"

echo "DB attivo. PID: $PID_NEW"
