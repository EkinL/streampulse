# StreamPulse - Guide de Deploiement

## Prerequis

- Docker & Docker Compose v2+
- Go 1.26 (dev local backend)
- Flutter 3.x (dev local mobile)

## Demarrage rapide

```bash
# Cloner le projet
git clone <repo-url>
cd streampulse

# Lancer toute la stack
make up

# Verifier
curl http://localhost:8080/health
```

Services accessibles :
- API : http://localhost:8080
- Grafana : http://localhost:3000 (admin/admin)
- Prometheus : http://localhost:9090

## Configuration

Toutes les variables sont dans `docker-compose.yml` (section `environment` du service `api`).

Variables critiques pour la production :
- `JWT_SECRET` : changer absolument
- `DATABASE_URL` : utiliser une base externe, avec `sslmode=require`
- `APP_ENV` : mettre `production`
- `CORS_ALLOWED_ORIGINS` : restreindre aux domaines autorises
- `TLS_CERT_FILE` / `TLS_KEY_FILE` : voir [HTTPS](#https) ci-dessous
- `REFRESH_TOKEN_PURGE_INTERVAL` : purge des jetons expires (1 h par defaut,
  voir [rgpd.md](rgpd.md))

## Developpement local

### Backend seul
```bash
cd backend
cp .env.example .env  # editer les valeurs
make run
```

### Mobile
```bash
cd mobile
flutter pub get
flutter run
```

## Production

1. Construire l'image Docker du backend
2. Deployer PostgreSQL (RDS, Cloud SQL, etc.) et forcer `sslmode=require`
   dans `DATABASE_URL`
3. Configurer les variables d'environnement (jamais de secret dans l'image)
4. Activer HTTPS, par reverse proxy ou en natif (section suivante)
5. Restreindre `CORS_ALLOWED_ORIGINS` aux domaines de la console web
6. Configurer la collecte OTEL et la retention des logs vers votre backend
   d'observabilite (les logs contiennent des adresses IP, voir [rgpd.md](rgpd.md))
7. Ne jamais jouer `backend/scripts/seed.sql` : comptes de developpement

## HTTPS

Le sujet exige des flux chiffres. Deux montages sont possibles ; dans les deux
cas le listener interne `METRICS_PORT` reste en clair et non publie.

### Option A — terminaison TLS sur un reverse proxy (recommandee)

L'API reste en HTTP sur le reseau Docker, le proxy porte le certificat et
le renouvelle. Exemple avec Caddy, qui obtient un certificat Let's Encrypt
tout seul :

```yaml
# docker-compose.prod.yml (extrait)
services:
  api:
    ports: []            # plus de publication directe du 8080
  caddy:
    image: caddy:2
    ports: ["80:80", "443:443"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy-data:/data
    networks: [streampulse]
volumes:
  caddy-data:
```

```
# Caddyfile
api.example.com {
    reverse_proxy api:8080
}
```

Le middleware `RealIP` lit `X-Forwarded-For` : le rate limiting et les logs
voient l'adresse du client, pas celle du proxy.

### Option B — TLS natif

Sans proxy, le serveur Go sert lui-meme en HTTPS des que les deux variables
sont renseignees (TLS 1.2 minimum). Un seul des deux fichiers fait echouer
le demarrage, volontairement.

```yaml
services:
  api:
    environment:
      TLS_CERT_FILE: /certs/fullchain.pem
      TLS_KEY_FILE: /certs/privkey.pem
    volumes:
      - /etc/letsencrypt/live/api.example.com:/certs:ro
```

Verification :

```bash
curl -sv https://api.example.com/health 2>&1 | grep -E 'SSL connection|"status"'
```

En local, un certificat auto-signe suffit pour tester :

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=localhost' \
  -keyout key.pem -out cert.pem
TLS_CERT_FILE=cert.pem TLS_KEY_FILE=key.pem make run
curl -k https://localhost:8080/health
```

## Monitoring

Le dashboard Grafana pre-configure affiche :
- Requetes par seconde
- Latence HTTP (p50/p95/p99)
- Nombre d'auditeurs connectes
- Taux d'erreur
