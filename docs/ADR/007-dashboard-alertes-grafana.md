# ADR 007: Dashboard Grafana, traces distribuees et alertes

## Statut
Accepted

## Contexte
Le Bloc 3 du RNCP 38822 evalue explicitement la capacite a superviser une solution en production : dashboard Grafana distinguant metriques metier et techniques, traces distribuees de bout en bout, et alertes sur anomalies (criteres Ce3.3.x et Ce3.5.x). L'[ADR 004](004-observabilite-otel.md) couvre le socle (OTEL, Prometheus, format des logs) ; celui-ci couvre ce qui est construit dessus : visualisation, traces mobile -> base de donnees, et alertes.

A l'etat initial, la stack existait sur le papier (Prometheus scrape configure, un dashboard JSON, un exporteur OTLP) mais rien n'etait reellement operationnel :
- le dashboard Grafana n'etait pas provisionne (import manuel a chaque `docker compose up`, datasource a reconfigurer a la main) ;
- aucune trace ne partait du mobile (le client Flutter ne propageait pas `traceparent`) ni n'atteignait la base de donnees (aucun span sur les requetes pgx) ;
- aucune alerte n'existait, et les traces exportees n'avaient aucune destination visualisable (juste un exporteur `logging` qui dump du texte).

## Decision
Construire une stack d'observabilite **entierement provisionnee par fichiers** (jamais de configuration manuelle dans l'UI Grafana), avec Prometheus pour les metriques, Tempo pour les traces, et des alertes routees vers le canal Discord deja utilise par l'equipe pour la coordination quotidienne.

## Justification

### Provisioning par fichier plutot que configuration UI
Reproductible par n'importe quel membre de l'equipe via `docker compose up`, versionnable, et coherent avec le principe 12-Factor deja applique au reste du projet (zero configuration manuelle qui ne survivrait pas a un `docker compose down -v`).

### `otelpgx` pinne a v0.6.2 plutot que `@latest`
`go get @latest` a fait remonter en cascade tout le SDK OTel (v1.24.0 -> v1.43.0) et pgx (v5.5.5 -> v5.9.2) pour une simple feature d'instrumentation DB. v0.6.2 s'integre sans deplacer aucune version deja pinnee dans `go.mod` — un changement mesure plutot qu'une mise a jour globale non maitrisee a quelques semaines de la soutenance.

### `traceparent` synthetique cote Flutter plutot qu'un SDK OTel Dart complet
Le sujet recommande lui-meme de "commencer simple" avec OTEL (risque identifie dans le cahier des charges). Generer un `traceparent` W3C valide a chaque requete HTTP (trace-id/span-id aleatoires) suffit a faire porter la meme trace jusqu'a la base de donnees. Un vrai SDK OTel Dart exportant ses propres spans ajouterait une dependance et une configuration reseau fragile (un exporteur OTLP joignable depuis un emulateur n'est pas `localhost`) pour un gain marginal a ce stade : la trace mobile agit comme un ID transmis, pas comme un span a part entiere.

### Tempo plutot que Jaeger
Tempo s'integre nativement dans Grafana (meme mecanisme de datasource provisionnee que Prometheus), tourne en un seul binaire avec du stockage local — pas de composant supplementaire (Jaeger implique generalement Elasticsearch ou Cassandra pour un stockage serieux). Coherent avec le reste de la stack, deja mono-binaire par service.

### Discord plutot qu'email ou Slack pour les alertes
L'equipe utilise deja Discord pour la coordination quotidienne (cf. cahier des charges, §2.2). Aucun nouvel outil a apprendre, alertes visibles la ou l'equipe est deja presente. L'URL du webhook est un secret : jamais commitee, injectee via `$__env{DISCORD_WEBHOOK_URL}` dans le provisioning Grafana et lue depuis un `.env` racine ignore par git.

### Deux regles d'alerte distinctes (technique + metier) plutot qu'une seule
Coherent avec la distinction deja faite sur le dashboard (row "Metriques metier" separee des panels techniques). Repond explicitement a l'exigence du sujet de differencier les erreurs techniques (ex: API down) des anomalies metier (ex: deconnexions brutales d'auditeurs).

## Architecture

```
Flutter (traceparent synthetique)
  |
  v
API Go --[otel middleware]--> span HTTP
  |
  v
otelpgx --[span par requete SQL]--> Postgres
  |
  v (OTLP)
otel-collector --[traces]--> Tempo --[datasource]--> Grafana
               --[metrics]--> Prometheus --[datasource]--> Grafana
                                                              |
                                                              v
                                                     Alertes --[webhook]--> Discord
```

## Consequences

### Positif
- Stack entierement reproductible en une commande, sans etape manuelle
- Chaine de bout en bout demontrable en soutenance : trace-id unique visible du header HTTP jusqu'a la requete SQL, alerte declenchee et resolue en direct dans Discord
- Distinction metier/technique explicite a la fois sur le dashboard et dans les alertes, repond directement au critere du sujet

### Negatif / limites connues
- Le mobile ne cree pas de vrai span : il transmet un ID, il n'apparait pas comme un span a part entiere dans Tempo. Suffisant pour suivre une requete de bout en bout, insuffisant pour mesurer une latence cote client.
- Pas d'agregation de logs (Loki) : les logs JSON sortent correctement mais ne sont indexes/cherchables nulle part pour l'instant.
- Le seuil de l'alerte "deconnexions brutales" (`increase() > 3` sur 5 minutes) reste une estimation : pense pour l'echelle reelle du projet (poignee d'auditeurs en demo/soutenance, pas de la production a grande echelle) plutot que pour un vrai historique de trafic, qui n'existe pas encore.
- Chaque developpeur doit recreer son propre `.env` (`DISCORD_WEBHOOK_URL`) apres un `git clone` : sans ca, Grafana demarre avec un webhook vide et les alertes ne notifient personne, silencieusement.
