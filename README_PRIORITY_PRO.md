# Priority & Pro (Admin)

## Formato atteso File A – Stato clienti + punti + contatori (XLSX)
Colonne minime (mappabili via GUI):

- `customer_id`
- `ragione_sociale`
- `piva`
- `priority_enabled` (bool)
- `pro_enabled` (bool)
- `shipments_free_used_this_week` (int)
- `shipments_free_week_start` / `last_reset_week` (date/string)
- `points_balance_total`
- `points_balance_earned`
- `points_balance_purchased`

> Le intestazioni sono configurabili dalla sezione Admin “Priority & Pro”. Inserire più sinonimi separati da virgola.

## Formato atteso File B – Storico ordini live (XLSX)
Colonne minime (mappabili via GUI):

- `order_id`
- `customer_id`
- `order_date`
- `imponibile`
- `subcategoria`

Il match “reman” è configurabile (campo **Match reman** in Admin).

## Utilizzo in Admin
1. **Priority & Pro → Parametri**: aggiorna i parametri Priority/Pro/integrazione.
2. **Mapping colonne**: verifica/aggiorna le intestazioni per File A e File B.
3. **Importazioni XLSX**: carica File A (stato clienti) e File B (storico ordini).
4. **Simulazione/Calcolo**: avvia il calcolo deterministico.
5. **Output & Export**: usa i pulsanti “Export CSV/XLSX” per scaricare l’ultimo export.
6. **Log & Audit**: controlla il log delle operazioni.

## Salvataggi e persistenza
- **Config**: salvata in DB `meta` con chiave `prioritypro_config`.
- **Ultimi import**: `data/prioritypro/inputs/state.json` e `data/prioritypro/inputs/orders.json`.
- **Ultimo run**: `data/prioritypro/last_run.json`.
- **Export**: `data/prioritypro/exports/prioritypro_export.csv` + `.xlsx`.
- **Audit log**: `data/prioritypro/audit.jsonl`.

## CLI (opzionale)
Esecuzione da riga di comando:

```bash
python -m api.prioritypro_engine --state <fileA.xlsx> --orders <fileB.xlsx> --out <dir>
```

Genera `prioritypro_export.csv`, `prioritypro_export.xlsx` e `prioritypro_summary.json` nella cartella `--out`.
