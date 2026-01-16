# TheLight24 Portable (Windows)

Questa guida descrive come rendere TheLight24 **portabile** su Windows con runtime isolata.

## Struttura attesa

```
C:\Ormanet\
├─ app\        (repo git clonato qui)
└─ runtime\    (NON versionata)
```

### Dentro `C:\Ormanet\runtime\`

```
runtime\
├─ .env                  (locale, non commit)
├─ .env.example          (nel repo, da copiare)
├─ python\python.exe     (Python 3.10 portable/embedded)
├─ venv\                 (creato dagli script)
├─ bin\llama-server.exe
├─ bin\cloudflared.exe
├─ llm\models\*.gguf
├─ logs\
└─ pids\
```

## Preparazione runtime

1. Copia `runtime\.env.example` in `C:\Ormanet\runtime\.env` e personalizza i valori.
2. Metti **Python 3.10 portable** in `C:\Ormanet\runtime\python\python.exe`.
3. Metti `llama-server.exe` in `C:\Ormanet\runtime\bin\llama-server.exe`.
4. Metti `cloudflared.exe` in `C:\Ormanet\runtime\bin\cloudflared.exe`.
5. Metti il modello GGUF (default Qwen 2.5 3B instruct) in `C:\Ormanet\runtime\llm\models\`.

> Default LLM: `qwen2.5-3b-instruct-q4_k_m.gguf`. Puoi cambiare modello modificando `LLM_MODEL` in `runtime\.env`.

## Avvio

Da PowerShell:

```
C:\Ormanet\app\scripts\windows\start_thelight.ps1
```

Avvierà:
- llama.cpp su `127.0.0.1:8081`
- API/GUI su `0.0.0.0:8080`
- cloudflared (se `CLOUDFLARE_TUNNEL_TOKEN` è impostato)

Log in `C:\Ormanet\runtime\logs\`.

## Stop

```
C:\Ormanet\app\scripts\windows\stop_thelight.ps1
```

## Update (git pull + dipendenze)

```
C:\Ormanet\app\scripts\windows\update_thelight.ps1
```

## Note

- Gli script usano **solo** `runtime\python\python.exe` (mai il Python di sistema).
- La runtime resta separata dal repo: puoi fare `git pull` in `app\` senza rompere `runtime\`.
