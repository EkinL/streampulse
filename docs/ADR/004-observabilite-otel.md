# ADR 004: OpenTelemetry, Prometheus et logs JSON correles

## Statut
Accepted

## Contexte
Un flux audio qui se coupe ne produit pas d'erreur : le client cesse simplement
de recevoir des octets. Sans instrumentation, la seule remontee possible est
"ca ne marche plus", sans moyen de savoir si le probleme vient du diffuseur, du
Hub, du reseau ou du client.

Il faut donc pouvoir repondre a trois questions distinctes :

1. **Que s'est-il passe pour cette requete ?** -> traces
2. **Le systeme va-t-il bien en ce moment ?** -> metriques
3. **Pourquoi cette requete precise a-t-elle echoue ?** -> logs

Ces trois signaux n'ont de valeur que s'ils se recoupent. Un log sans
identifiant partage avec la trace ne permet aucune investigation.

## Decision

**OpenTelemetry pour les traces, Prometheus pour les metriques, zerolog en JSON
pour les logs, et un identifiant de requete unique qui relie les trois.**

- Traces exportees en OTLP/gRPC vers un OpenTelemetry Collector, qui reexpose
  les metriques a Prometheus et affiche les traces (`otel-collector-config.yaml`).
- Metriques exposees sur **deux** listeners : `/metrics` sur le routeur public,
  reserve au role `admin`, et un listener interne sur `METRICS_PORT` (9091) que
  Prometheus scrute depuis le reseau Docker, jamais publie sur l'hote.
- Logs en JSON une ligne par evenement, format pilote par `LOG_FORMAT`.
- L'identifiant genere par `chi/middleware.RequestID` est renvoye au client dans
  l'en-tete `X-Request-Id` et dans `meta.requestId`, et emis dans chaque ligne
  de log sous `request_id`, aux cotes de `trace_id` et `span_id`.

## Justification

### Pourquoi OpenTelemetry plutot que Jaeger ou Zipkin en direct
- **Standard neutre** : l'instrumentation du code ne depend d'aucun backend. Le
  Collector peut router vers Jaeger, Tempo, Datadog ou autre sans qu'une ligne
  de Go change.
- **Propagation W3C** : le format `traceparent` est standard, donc une trace
  peut demarrer sur le client mobile et se poursuivre cote serveur sans code
  proprietaire.
- **Traces et metriques dans la meme chaine** : un seul agent a deployer.

### Pourquoi le format des logs ne suit pas l'environnement
Le premier reflexe est de conditionner le format a `APP_ENV` : texte lisible en
developpement, JSON en production. C'est un piege, et le projet est tombe
dedans : `docker-compose.yml` fixe `APP_ENV: development`, donc la stack de
demonstration produisait du texte non indexable alors que le code pretendait
faire du JSON. Personne ne s'en apercevait avant de chercher a indexer.

Le format de sortie et l'environnement sont deux preoccupations distinctes.
`LOG_FORMAT` (`json` par defaut, `console` en option) les separe. Une valeur
inconnue **fait echouer le demarrage** plutot que de retomber en silence : une
faute de frappe donnerait sinon des logs non indexables en production sans
aucun signal.

### Pourquoi un identifiant partage, et pourquoi en en-tete
Avant cette decision, le projet portait **trois identifiants sans rapport** :
`chi/middleware.RequestID` vivait dans le contexte sans jamais sortir, l'enveloppe
de reponse generait un `uuid.New()` neuf a chaque reponse, et le trace id OTEL
n'apparaissait dans aucun log. Un utilisateur citant son `meta.requestId` etait
introuvable.

L'identifiant est expose en **en-tete de reponse** plutot que passe en parametre
aux helpers de reponse, pour deux raisons :

- Les helpers `respondJSON` / `respondError` / `respondPaginated` totalisent
  191 appels. Changer leur signature aurait produit un diff mecanique de deux
  cents lignes pour un gain nul.
- Surtout, l'en-tete accompagne **aussi** les reponses ecrites par `http.Error`
  dans la chaine de middlewares (401, 403, 429). Ces reponses n'ont pas
  d'enveloppe `meta` et n'avaient donc, jusque-la, aucun identifiant
  exploitable. Ce sont pourtant celles qu'un utilisateur signale le plus.

### Pourquoi deux listeners pour les metriques
`/metrics` expose la topologie interne du service. Le laisser public etait une
fuite d'information. Mais Prometheus ne peut pas porter de JWT d'administrateur.

Un seul listener imposait donc de choisir entre securite et scrutabilite. Deux
listeners resolvent les deux : le port interne n'est joignable que depuis le
reseau Docker, et la route publique reste derriere le RBAC pour l'usage humain.

### Ordre des middlewares
`OTELTracing` doit etre enregistre **avant** `Logging`. Le middleware OTEL cree
le span et le place dans le contexte qu'il transmet en aval ; un contexte ne
remonte pas la chaine. Enregistre en premier, `Logging` n'observerait aucun span
et le `trace_id` disparaitrait des logs sans qu'aucun test unitaire ne le voie.
Cette contrainte est verrouillee par `TestLoggingAfterOTELSeesTheSpan`, qui
verifie les deux ordres.

## Consequences

### Positif
- Un identifiant unique relie l'en-tete recu par le client, le corps de la
  reponse, la ligne de log et la trace distribuee. Un rapport de bug devient
  actionnable.
- Le backend n'est couple a aucun outil d'observabilite : changer de backend de
  traces est un changement de configuration du Collector.
- Les logs sont indexables des le poste de developpement, donc ce qui est
  observe en local est ce qui sera observe en production.
- `/metrics` est scrutable sans etre public.

### Negatif
- Le Collector est un composant de plus a deployer et a surveiller. S'il tombe,
  les traces sont perdues (les metriques et les logs, non).
- L'echantillonnage est fixe a `AlwaysSample()`. Correct au volume actuel,
  intenable a l'echelle : il faudra passer a un echantillonnage par taux.
- Si `InitTracer` echoue au demarrage, le service continue sans traces et le
  champ `trace_id` disparait des logs. C'est deliberement non bloquant :
  l'observabilite ne doit pas empecher le service de tourner.
- L'identifiant chi est prefixe du nom d'hote, qui se retrouve donc expose au
  client. En conteneur il s'agit de l'identifiant du conteneur, ce qui est utile
  pour savoir quelle replique a servi la requete ; hors conteneur, c'est le nom
  de la machine.
- Ni Loki ni Elasticsearch ne sont dans la stack : les logs sont structures et
  indexables, mais rien ne les indexe encore.

## Voir aussi
- [ADR 003 - Streaming SSE](003-streaming-sse.md) pour la mesure du fan-out
- [Scalabilite et couts](../scalability.md) pour ce que les metriques revelent

---

## Summary (English)

Because a dropped audio stream produces no error — the client simply
stops receiving bytes — the platform needs three correlated signals:
OpenTelemetry traces (what happened to this request), Prometheus metrics
(is the system healthy right now), and structured JSON logs (why did this
specific request fail), all tied together by one request id. Metrics are
exposed on two separate listeners — a public, `admin`-only `/metrics`
route for humans, and an internal, never-published port that Prometheus
scrapes directly — resolving a tension between not leaking the service's
internal topology and still letting Prometheus scrape it (which can't
carry a JWT). `chi/middleware.RequestID` is surfaced in the `X-Request-Id`
response header, in `meta.requestId`, and in every log line alongside
`trace_id`/`span_id`, replacing three previously unrelated identifiers
that made a user-reported id untraceable. The log format is controlled by
its own `LOG_FORMAT` variable rather than inferred from `APP_ENV`, after
the project's own dev stack silently produced unindexable text logs while
believing it was emitting JSON. Known limitations: the OTEL Collector is a
single point of failure for traces (not for metrics or logs), sampling is
fixed at "always" rather than rate-based, and no log aggregator (Loki,
Elasticsearch) is deployed yet despite the logs being structured for one.
