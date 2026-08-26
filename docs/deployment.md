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
- `DATABASE_URL` : utiliser une base externe
- `APP_ENV` : mettre `production`
- `CORS_ALLOWED_ORIGINS` : restreindre aux domaines autorises

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
2. Deployer PostgreSQL (RDS, Cloud SQL, etc.)
3. Configurer les variables d'environnement
4. Deployer derriere un reverse proxy (nginx, Traefik)
5. Configurer HTTPS (Let's Encrypt)
6. Configurer la collecte OTEL vers votre backend d'observabilite

## Monitoring

Le dashboard Grafana pre-configure affiche :
- Requetes par seconde
- Latence HTTP (p50/p95/p99)
- Nombre d'auditeurs connectes
- Taux d'erreur
