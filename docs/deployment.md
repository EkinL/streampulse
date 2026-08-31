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
- `APP_ENV` : mettre `production`. Le serveur refuse alors de demarrer avec
  `CORS_ALLOWED_ORIGINS=*` (ou vide) : il faut nommer les origines
- `CORS_ALLOWED_ORIGINS` : les origines de la console web, separees par des
  virgules (`https://console.example.com`)
- `TRUSTED_PROXIES` : le reseau du reverse proxy, sinon `X-Forwarded-For`
  n'est pas cru et le rate limiting compte le proxy comme unique client
- `TLS_CERT_FILE` / `TLS_KEY_FILE` : voir [HTTPS](#https) ci-dessous
- `PUBLIC_BASE_URL` : l'URL que les clients utilisent (`https://api.example.com`),
  sinon les liens des fichiers uploades pointent sur `localhost`
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
5. Renseigner `CORS_ALLOWED_ORIGINS` avec les domaines de la console web
   (obligatoire : avec `APP_ENV=production`, le joker fait echouer le
   demarrage)
6. Configurer la collecte OTEL et la retention des logs vers votre backend
   d'observabilite (les logs contiennent des adresses IP, voir [rgpd.md](rgpd.md))
7. Ne jamais jouer `backend/scripts/seed.sql` : comptes de developpement

## HTTPS

Le sujet exige des flux chiffres. Deux montages sont possibles ; dans les deux
cas le listener interne `METRICS_PORT` reste en clair et non publie.

### Option A — terminaison TLS sur un reverse proxy (recommandee)

L'API reste en HTTP sur le reseau Docker, le proxy porte le certificat et
le renouvelle. Ce montage est fourni dans le depot : la surcouche
[`docker-compose.prod.yml`](../docker-compose.prod.yml) ajoute un service
Caddy configure par [`caddy/Caddyfile`](../caddy/Caddyfile), qui obtient un
certificat Let's Encrypt tout seul pour le domaine `API_DOMAIN`.

```bash
# .env a la racine du depot (lu par docker compose, jamais commite)
API_DOMAIN=api.example.com
CORS_ALLOWED_ORIGINS=https://console.example.com
JWT_SECRET=<un vrai secret>

make up-prod     # docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

Ce que la surcouche change par rapport a la stack de dev :

| Quoi | Dev (`make up`) | Prod (`make up-prod`) |
|------|-----------------|-----------------------|
| API | `http://localhost:8080` publie | non publiee, joignable seulement via Caddy en `https://API_DOMAIN` (80 redirige vers 443) |
| `APP_ENV` / CORS | `development`, `*` | `production` : `CORS_ALLOWED_ORIGINS` doit nommer les origines, sinon le serveur refuse de demarrer |
| `JWT_SECRET` | valeur de dev du fichier de base | exige dans l'environnement |
| `TRUSTED_PROXIES` | vide | sous-reseau Docker (`DOCKER_SUBNET`, `172.28.0.0/16` par defaut) : seul Caddy peut poser `X-Forwarded-For` |
| PostgreSQL, collecteur OTEL | ports publies | non publies |
| Prometheus, Grafana | `0.0.0.0:9090` / `:3000` | `127.0.0.1` seulement : acces par tunnel SSH (`ssh -L 3000:localhost:3000 hote`) |
| En-tetes | — | `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `Server` retire |

Le rate limiting lit `X-Forwarded-For` **uniquement** quand la connexion vient
d'une adresse de `TRUSTED_PROXIES` (chi a deprecie son middleware `RealIP`,
qui croyait cet en-tete sans condition, GHSA-3fxj-6jh8-hvhx). Avec la
surcouche, il voit donc l'adresse du client, pas celle de Caddy.

Essai en local, sans domaine : avec `API_DOMAIN=localhost` Caddy signe le
certificat avec son autorite locale, `curl -k https://localhost/health`
repond en HTTPS, et `curl http://localhost:8080/health` ne repond plus.

Les flux longs (SSE `/streams/{id}/listen`, audio `/streams/{id}/audio`)
passent sans mise en tampon (`flush_interval -1` dans le Caddyfile).

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
    # Le HEALTHCHECK de l'image interroge http://localhost:8080/health : en
    # TLS natif il faut le remplacer, sinon le conteneur reste `unhealthy`.
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- --no-check-certificate https://localhost:8080/health || exit 1"]
      interval: 30s
      timeout: 3s
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
