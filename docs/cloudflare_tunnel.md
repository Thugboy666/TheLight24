# Cloudflare Tunnel (TheLight24)

## Config esempio (config.yml)

```yaml
tunnel: <TUNNEL_ID>
credentials-file: /etc/cloudflared/<TUNNEL_ID>.json
ingress:
  - hostname: thelight24.<tuodominio>
    service: http://127.0.0.1:8080
  - service: http_status:404
```

## Comandi systemd

```bash
sudo systemctl enable --now cloudflared
sudo systemctl restart cloudflared
sudo systemctl status cloudflared --no-pager -l
```

## Accesso pubblico

Dall'esterno si accede **solo** tramite l'hostname Cloudflare:
`https://thelight24.<tuodominio>`.
Non usare `127.0.0.1` o IP pubblici diretti.

Per rendere visibile l'URL nel log di avvio, esporta la variabile:

```bash
export CLOUDFLARE_HOSTNAME=thelight24.<tuodominio>
```
