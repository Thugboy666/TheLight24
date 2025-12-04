# Project Architecture & Logic Overview

## 1. Panoramica del progetto
TheLight24 è una piattaforma Python per automazione B2B/ecommerce che espone un'API HTTP asincrona (aiohttp) per autenticazione, gestione clienti/prodotti, logiche promozionali e notifiche, con una GUI web statica servita dalla stessa app. Il backend persiste i dati in SQLite e integra un endpoint LLM configurabile per completamenti testuali.【F:api/server.py†L1-L120】【F:api/server.py†L1528-L1592】 Principali dipendenze: `aiohttp`, `httpx`, `openpyxl`, `bcrypt`.【F:requirements.txt†L1-L4】 L'avvio standard è `python start.py`, che richiama `api.server.main()` per far partire il server.【F:start.py†L1-L4】 Il flusso alto livello: entrypoint → factory `create_app()` → routing aiohttp → handler che leggono/scrivono su SQLite tramite `api.db` e opzionalmente chiamano l'LLM via `llm/model_client.py`.

## 2. Struttura delle cartelle
```text
/ (root)
  api/            → server aiohttp, handler HTTP e accesso al DB
  core/           → configurazione, logging, scheduler di base
  cli/            → utility CLI per avviare l'API con uvicorn
  ecommerce/     → logiche B2B (pricing, segmentazione, bundle placeholder)
  governance/    → placeholder per audit e regole di governance
  llm/           → client per modelli linguistici e prompt JSON
  services/      → job di automazione/sync esterni
  scripts/       → importazione dati (ordini, utenti) da CSV/XLSX
  gui/ e ui/     → asset e script della GUI web
  data/          → database SQLite e file di esempio
```
Le cartelle sono collegate dal server: `api/server.py` serve la GUI (`/` e `/assets`), monta le route API e usa componenti `core`, `llm`, `ecommerce` e `services` dove appropriato.【F:api/server.py†L1528-L1592】

## 3. Moduli e componenti principali
- `api/server.py`: cuore dell'API aiohttp. Registra middleware, route per auth, ecommerce, admin, notifiche, e LLM; contiene utilità per logging, pricing, notifiche e upload Excel.【F:api/server.py†L1528-L1592】【F:api/server.py†L299-L361】
- `api/db.py`: strato di persistenza SQLite con creazione schema (utenti, clienti, prodotti, ordini, offerte, notifiche) e funzioni CRUD come `create_user`, `list_products`, `bulk_insert_orders` e gestione sessioni/token.【F:api/db.py†L1-L160】【F:api/db.py†L180-L272】【F:api/db.py†L940-L1006】
- `core/config.py`: centralizza variabili d'ambiente (host/port API, URL LLM, percorsi DB/log).【F:core/config.py†L1-L27】
- `core/logger.py`: logger rotante condiviso, usato da server, servizi e governance.【F:core/logger.py†L1-L27】
- `core/scheduler.py`: scheduler basato su thread per job a intervallo.【F:core/scheduler.py†L1-L37】
- `llm/model_client.py`: client asincrono che prepara prompt con sistema predefinito e chiama l'endpoint LLM configurato.【F:llm/model_client.py†L1-L25】
- `llm/prompts/*.json`: prompt di sistema e domini verticali caricati da `prompts_loader`.【F:llm/prompts_loader.py†L1-L17】
- `ecommerce/pricing.py` e `segmentation.py`: logiche base di sconto per segmento e quantità, e mapping turnover→segmento.【F:ecommerce/pricing.py†L1-L29】【F:ecommerce/segmentation.py†L1-L8】
- `services/automation.py` + `sync_*`: registrano job periodici (es. sync Ready Pro) usando lo scheduler; le funzioni di sync sono placeholder strumentati con logging.【F:services/automation.py†L1-L7】【F:services/sync_readypro.py†L1-L5】
- `scripts/import_orders.py`: tool CLI per caricare ordini da CSV/XLSX, con parsing/normalizzazione campi e inserimento bulk via `api.db`.【F:scripts/import_orders.py†L1-L206】
- `scripts/import_users_from_csv.py`: importa utenti da CSV nel DB SQLite, hashando le password.【F:scripts/import_users_from_csv.py†L1-L65】
- `gui/index.html` e `ui/product-editor.js`: interfaccia 3D/console e editor prodotto lato client, serviti dal backend (route `/`).【F:api/server.py†L1528-L1592】【F:gui/index.html†L1-L46】

## 4. Flusso di esecuzione
1. **Avvio**: `start.py` invoca `api.server.main()`, che costruisce l'app con `create_app()` e lancia `aiohttp.web.run_app` sull'host/porta di default o da env.【F:start.py†L1-L4】【F:api/server.py†L1528-L1609】
2. **Bootstrap**: `create_app()` inizializza il DB (`api.db.init_db()` è chiamato a import time) e attacca router e middleware; carica GUI statica e prepara coda notifiche in `app` state.【F:api/server.py†L61-L120】【F:api/server.py†L1528-L1592】
3. **Richieste HTTP**: il middleware `request_logger_middleware` logga tempi e gestisce errori; le route vengono gestite dai rispettivi handler (es. `/auth/login`, `/ecom/pricing`, `/admin/products/save`).【F:api/server.py†L1495-L1523】【F:api/server.py†L1528-L1592】
4. **Accesso dati**: gli handler chiamano funzioni di `api.db` per utenti, clienti, prodotti, ordini, offerte, e sessioni; il DB usa SQLite con row factory dict-friendly.【F:api/db.py†L17-L152】【F:api/db.py†L940-L1006】
5. **LLM**: endpoint `/llm/complete` (handler non mostrato qui) usa `llm/model_client.complete_text` per chiamare l'LLM via HTTP con prompt arricchito da `prompts_loader`.【F:llm/model_client.py†L1-L25】【F:llm/prompts_loader.py†L1-L17】
6. **Scheduler/Servizi**: `services/automation.register_jobs()` può essere richiamato per attivare job periodici (es. sync Ready Pro ogni 10 minuti) usando `core.scheduler.SimpleScheduler`.【F:services/automation.py†L1-L7】【F:core/scheduler.py†L1-L37】
7. **CLI e import**: script in `scripts/` possono essere lanciati manualmente/cron per popolare il DB con utenti e ordini; usano funzioni `api.db` e si appoggiano ai percorsi dati in `data/`.【F:scripts/import_orders.py†L17-L205】【F:scripts/import_users_from_csv.py†L1-L65】

## 5. Gestione dati / configurazioni
- **Configurazione**: `core/config.py` legge variabili ambiente per host/porta API, URL e modello LLM, e percorsi di DB/log; `api/server.py` aggiunge override per `LLM_BACKEND_URL` e `THELIGHT_UI_INDEX` per cambiare endpoint LLM o percorso GUI.【F:core/config.py†L1-L27】【F:api/server.py†L61-L120】
- **Database**: SQLite in `data/db/thelight_universe.db`, creato/migrato da `api.db.init_db()` con tabelle per utenti, clienti, prodotti, regole sconto, ordini, offerte giornaliere, notifiche, sessioni e meta key/value.【F:api/db.py†L1-L160】【F:api/db.py†L180-L272】【F:api/db.py†L940-L1006】
- **File di import**: `scripts/import_orders.py` legge CSV/XLSX (percorso da `--input` o `ORDERS_INPUT_FILE`), normalizza date/importi e inserisce gli ordini; `scripts/import_users_from_csv.py` importa utenti con password hashate SHA-256 da `data/users_plain.csv`.【F:scripts/import_orders.py†L31-L159】【F:scripts/import_users_from_csv.py†L1-L65】
- **Asset frontend**: GUI statica in `gui/` servita tramite route `/` e `/assets`; file `ui/` contengono script admin/editor richiamati dal frontend.【F:api/server.py†L1528-L1592】【F:gui/index.html†L1-L46】

## 6. Esempi REALI dal codice
```python
async def auth_login(request: web.Request) -> web.Response:
    body = await request.json()
    email = body.get("email", "").strip()
    password = body.get("password", "")
    ...
    if not verify_password(password, user.get("password_hash")):
        log_event("user_login_failed", email=email)
        return web.json_response({"status": "ko"})
    expires_delta = timedelta(days=30) if remember else timedelta(hours=24)
    token = create_session_with_expiry(user_id=user["id"], expires_delta=expires_delta)
    ...
```
Gestisce il login: controlla le credenziali (incluso account admin hardcoded), crea una sessione con scadenza e restituisce token/tier.【F:api/server.py†L440-L486】

```python
def compute_price_with_discounts(product: dict, customer_segment: str, quantity: int) -> dict:
    base_price = pick_price_for_segment(product, customer_segment, product.get("base_price", 0))
    amount = base_price * max(1, quantity)
    ...
    if offer_id:
        for cfg in discount_rules_to_configs():
            ...
            if amount >= float(rule.get("min", 0)) and amount <= float(max_amount):
                discount_value = (rule.get("discount", 0) or 0) / 100.0
                break
    final_amount = amount * (1 - discount_value)
    return {"price": final_amount, "discount_applied": discount_value * 100, ...}
```
Calcola il prezzo finale per un prodotto considerando il listino del segmento e regole di sconto per offerte configurate nel DB.【F:api/server.py†L310-L360】

```python
def complete_text(prompt: str, max_tokens: int = 256, temperature: float = 0.7) -> str:
    url = settings.LLM_COMPLETION_URL
    system_prompt = get_system_prompt("system")
    payload = {"model": settings.LLM_MODEL, "prompt": f"{system_prompt}\n\n{prompt}", ...}
    async with aiohttp.ClientSession() as session:
        async with session.post(url, json=payload, timeout=120) as resp:
            resp.raise_for_status()
            data = await resp.json()
            if "choices" in data and data["choices"]:
                return data["choices"][0].get("text", "").strip()
```
Client LLM che arricchisce il prompt con il system prompt e chiama un endpoint remoto configurabile.【F:llm/model_client.py†L1-L25】

```python
def register_jobs():
    # esempio: sync Ready Pro ogni 10 minuti
    scheduler.add_interval_job("sync_readypro", interval_sec=600, func=sync_readypro_once)
```
Esempio di registrazione di un job periodico con lo scheduler thread-based condiviso.【F:services/automation.py†L1-L7】

```python
def normalize_row(raw: Dict[str, str]) -> Optional[Dict[str, str]]:
    def pick(*keys: str) -> str:
        for key in keys:
            if key in raw and raw.get(key) not in (None, ""):
                return str(raw.get(key)).strip()
        return ""
    document_number = pick("numero documento", "n.doc.", "document_number")
    customer_email = pick("email", "email cliente", "customer_email")
    ...
    if not document_number or not customer_email:
        return None
    return {"document_number": document_number, "customer_email": customer_email, ...}
```
Parsing robusto per righe di ordini da CSV/XLSX, con fallback multipli per i nomi colonna e validazioni minime prima dell'inserimento bulk.【F:scripts/import_orders.py†L100-L159】

## 7. Flussi tipici di utilizzo
- **Login utente e accesso dati**: un client POSTa `/auth/login` con email/password; l'handler verifica le credenziali (bcrypt/legacy), crea un token di sessione e associa l'utente a un cliente; chiamate successive includono `Authorization: Bearer` per endpoint come `/auth/me` o `/account/orders`.【F:api/server.py†L142-L173】【F:api/server.py†L440-L520】
- **Calcolo listino e bozza ordine**: il frontend invia a `/ecom/pricing` dati prodotto/segmento/quantità; il server calcola il prezzo via `compute_price_with_discounts`, applicando eventuali regole di sconto su `discount_rules` e listini cliente, restituendo importi da usare per bozze ordine o offerte giornaliere.【F:api/server.py†L310-L360】【F:api/db.py†L85-L121】
- **Import ordini mensili**: un job cron esegue `scripts/import_orders.sh`/`.py`, che legge un export gestionale CSV/XLSX, normalizza le colonne e inserisce gli ordini nel DB (rimuovendo quelli più vecchi di un limite configurabile). Gli ordini sono poi visibili via `/account/orders` o riepiloghi admin.【F:scripts/import_orders.py†L17-L206】【F:api/db.py†L940-L1006】

## 8. Punti critici e dipendenze importanti
- **Database SQLite**: tutte le entità (utenti, clienti, prodotti, sessioni, ordini) risiedono in `data/db/thelight_universe.db`; corruzioni o permessi errati bloccano l'intera API.【F:api/db.py†L9-L160】【F:api/db.py†L940-L1006】 
- **Gestione sessioni e login**: le funzioni di verifica password supportano hash bcrypt, sha256 legacy e plain text; errori qui compromettono la sicurezza e l'accesso utenti.【F:api/server.py†L142-L160】【F:api/server.py†L440-L486】
- **Integrazione LLM**: endpoint LLM configurabili tramite env; indisponibilità del servizio LLM impatta le feature AI ma non il resto dell'API.【F:core/config.py†L14-L19】【F:llm/model_client.py†L1-L25】
- **Import Excel/CSV**: molte rotte admin (import promo, listini, ordini) usano `openpyxl` e parsing manuale; file malformati generano errori/skip e richiedono logging di supporto.【F:api/server.py†L800-L900】【F:scripts/import_orders.py†L85-L159】

## 9. Come estendere il progetto
- **Nuove API/endpoint**: aggiungere handler in `api/server.py` e registrarli in `create_app()` seguendo il pattern esistente (funzione async che usa `web.json_response` e `api.db`).【F:api/server.py†L1528-L1592】
- **Nuove tabelle o campi**: estendere `api/db.py` per migrazioni e CRUD; usare `ensure_db_dir()` e pattern di commit già adottati. Ad esempio, aggiungere una tabella e popolarla con funzioni simili a `bulk_insert_orders`.【F:api/db.py†L13-L160】【F:api/db.py†L940-L1006】
- **Logiche ecommerce**: implementare regole reali in `ecommerce/pricing.py`, `segmentation.py` e `bundling.py`, richiamandole dagli handler `/ecom/*` o da job in `services`.【F:ecommerce/pricing.py†L3-L29】【F:ecommerce/segmentation.py†L1-L8】
- **Automazioni/sync**: creare nuove funzioni `sync_*` in `services/` e registrarle in `services/automation.register_jobs()` per esecuzione periodica via `core.scheduler`.【F:services/automation.py†L1-L7】【F:core/scheduler.py†L1-L37】
- **Frontend/GUI**: aggiornare `gui/index.html` o gli script `ui/*.js` mantenendo la route di servizio `/` e l'uso delle API esistenti (es. toast, editor prodotti) come riferimento per pattern di integrazione.【F:api/server.py†L1528-L1592】【F:ui/product-editor.js†L1-L90】
