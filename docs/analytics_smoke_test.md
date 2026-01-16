# Analytics: ottenere customer_id e smoke test

## Come ottenere un customer_id valido

1. Chiama l'endpoint admin per la lista clienti:

```bash
curl -s -H "Authorization: Bearer <ADMIN_TOKEN>" \
  http://127.0.0.1:8080/admin/clients/all
```

2. Recupera il campo `id` del cliente desiderato e usalo per l'endpoint analytics:

```bash
curl -s -H "Authorization: Bearer <ADMIN_TOKEN>" \
  http://127.0.0.1:8080/api/analytics/customer/<ID_CLIENTE>
```

## Smoke test rapido

È disponibile lo script `scripts/smoke_test.sh` che esegue i check principali.
Impostare `ADMIN_TOKEN` e (opzionale) `BASE_URL` prima di eseguirlo.
