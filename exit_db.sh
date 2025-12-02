#!/data/data/com.termux/files/usr/bin/bash

PROJECT_DIR="$HOME/TheLight24"
PID_FILE="$PROJECT_DIR/.db_pid"

if [ ! -f "$PID_FILE" ]; then
    echo "Nessun file PID trovato. Forse sqlite-web non è attivo?"
    exit 0
fi

PID=$(cat "$PID_FILE")

if ps -p $PID > /dev/null 2>&1; then
    echo "Chiudo sqlite-web (PID $PID)..."
    kill -9 $PID
    rm "$PID_FILE"
    echo "DB chiuso correttamente."
else
    echo "Il processo salvato ($PID) non esiste più. Pulisco file PID."
    rm "$PID_FILE"
fi
