# Objectifs de niveau de service (SLO)

Ce document fixe ce que StreamPulse s'engage a tenir, comment c'est mesure, et
ce qu'on fait quand ce n'est plus tenu.

Les seuils ne sont pas choisis au hasard : ils derivent des mesures de
[scalability.md](scalability.md) et des metriques deja instrumentees. Un SLO qui
ne s'appuie sur aucune mesure n'est qu'une intention.

## Vocabulaire

| Terme | Definition |
|-------|------------|
| **SLI** | L'indicateur mesure : une valeur qu'on lit sur un tableau de bord |
| **SLO** | La cible que l'indicateur doit tenir sur une fenetre donnee |
| **Budget d'erreur** | Ce que le SLO autorise a rater. A 99,5 %, c'est 0,5 % |

Le budget d'erreur est la partie utile : tant qu'il reste du budget, on livre
des fonctionnalites. Quand il est epuise, on arrete de livrer et on repare.

## Fenetre

**28 jours glissants.** Assez long pour absorber un incident isole, assez court
pour qu'un mois degrade soit visible avant la fin du semestre.

---

## SLO 1 — Disponibilite de l'API

> **99,5 % des requetes HTTP aboutissent sans erreur serveur.**

| | |
|---|---|
| SLI | `1 - (rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]))` |
| Cible | **99,5 %** sur 28 jours |
| Budget d'erreur | 3 h 22 min d'indisponibilite totale, ou 0,5 % des requetes |

**Pourquoi 99,5 % et pas 99,9 %.** 99,9 % imposerait de la redondance : plusieurs
instances, bascule automatique, base repliquee. Or le Hub de fan-out est en
memoire du processus, donc deux instances ne partagent pas leurs auditeurs
([scalability.md, section 5](scalability.md)). Promettre 99,9 % sur une
architecture mono-instance serait un engagement qu'on ne peut pas tenir.

Les erreurs 4xx sont **exclues** : un client qui envoie un mauvais mot de passe
n'est pas une panne du service.

---

## SLO 2 — Latence des requetes

> **95 % des requetes hors streaming repondent en moins de 200 ms.**

| | |
|---|---|
| SLI | `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))` |
| Cible | **p95 < 200 ms** sur 28 jours |

**Exclusions explicites**, sans quoi l'indicateur ne veut rien dire :

- `/streams/{id}/listen` et `/streams/{id}/audio` durent le temps de l'ecoute,
  potentiellement des heures
- `/streams/{id}/broadcast` dure le temps de la diffusion
- `/auth/login` et `/auth/register` sont volontairement lents : bcrypt cout 12
  represente **184 ms** de calcul mesure ([ADR 006](ADR/006-strategie-auth-jwt.md)).
  C'est une protection, pas une lenteur a corriger.

**Pourquoi 200 ms.** Le pipeline complet debite 384 Mio/s et la charge nominale
en consomme 20 % ([scalability.md, section 4](scalability.md)). Les requetes CRUD
ne font qu'une a deux requetes SQL indexees. Un p95 au-dessus de 200 ms
signalerait une requete non indexee ou une saturation, pas une charge normale.

---

## SLO 3 — Continuite du flux audio

> **99 % des sessions d'ecoute se terminent a l'initiative de l'auditeur.**

| | |
|---|---|
| SLI | `1 - (rate(stream_disconnections_total{reason="abrupt"}[1h]) / rate(stream_disconnections_total[1h]))` |
| Cible | **99 %** sur 28 jours |

C'est le SLO **metier** : les deux precedents mesurent la sante technique, celui-ci
mesure ce que vit l'auditeur. Un flux qui se coupe ne produit aucune erreur HTTP
— la connexion se ferme, c'est tout. Sans cet indicateur, une degradation de
l'experience d'ecoute serait totalement invisible sur les deux premiers SLO.

`stream_disconnections_total` porte desormais un label `reason`, pose dans le
`defer` des handlers `Listen` et `AudioStream`
(`internal/transport/http/handlers/stream_handler.go`) : `"client"` quand le
contexte de la requete s'annule (deconnexion normale de l'auditeur, ou arret
du serveur), `"stream_closed"` quand le flux est ferme cote diffuseur, et
`"abrupt"` quand l'ecriture vers le client echoue. Le SLI et l'alerte
`streampulse-disconnections-spike` filtrent tous les deux sur
`reason="abrupt"`.

---

## SLO 4 — Perte de chunks audio

> **Moins de 1 % des auditeurs subissent une perte de chunk sur une session.**

| | |
|---|---|
| SLI | `1 - sessions_with_chunk_loss_total / listener_sessions_total` |
| Cible | **< 1 %** des sessions |

Quand le tampon d'un auditeur est plein (256 chunks, soit **64 secondes**
d'avance a 4 chunks/s), `Client.Send` abandonne le chunk plutot que de bloquer.
C'est un choix de conception : un auditeur lent degrade sa propre qualite, jamais
celle des autres, et ne peut pas bloquer le diffuseur.

Ce comportement est donc **correct**, mais il doit rester rare. S'il devient
frequent, c'est le signe d'un probleme reseau cote clients ou d'un debit trop
eleve pour la population reelle.

La branche `default` de `Client.Send` incremente desormais un compteur
atomique sur le `Client` (`internal/infrastructure/streaming/client.go`),
lu par le `defer` des handlers `Listen` et `AudioStream` a la fin de chaque
session : `listener_sessions_total` est incremente a chaque session,
`sessions_with_chunk_loss_total` seulement si `client.Dropped() > 0`. Le SLO
est formule *par session* ("moins de 1 % des auditeurs"), pas par chunk :
compter les sessions plutot que les chunks perdus colle a l'enonce et evite
qu'une seule session tres degradee ecrase l'indicateur.

---

## Politique de budget d'erreur

| Budget consomme | Ce qu'on fait |
|-----------------|---------------|
| < 50 % | Rien de special. On livre normalement |
| 50 – 75 % | On revoit les alertes recentes en revue d'equipe |
| 75 – 100 % | **Gel des fonctionnalites.** Seuls les correctifs de fiabilite passent |
| > 100 % | Post-mortem ecrit et action corrective avant toute nouvelle livraison |

C'est ce qui fait le lien entre la surveillance et la feuille de route : le
budget d'erreur decide de ce qui est livre, pas une impression.

## Alertes

Provisionnees par fichier dans `grafana/provisioning/alerting/` (alerting
unifie de Grafana, pas un Alertmanager Prometheus separe — voir
[ADR 008](ADR/008-dashboard-alertes-grafana.md) pour ce choix). Deux
regles existent reellement aujourd'hui, l'une technique, l'une metier,
toutes deux routees vers le canal Discord de l'equipe
(`contact-points.yaml`, `notification-policies.yaml`) :

| Alerte (uid) | Condition reelle | Categorie | Gravite |
|--------------|-------------------|-----------|---------|
| `streampulse-api-down` | `up{job="streampulse-api"} == 0` pendant 1 min | technique | critique |
| `streampulse-disconnections-spike` | `increase(stream_disconnections_total[5m]) > 3` | metier | avertissement |

Le seuil de la seconde regle (3 deconnexions brutales sur 5 minutes) est
un choix assume pour l'echelle actuelle du projet — une poignee
d'auditeurs en demonstration — et non une valeur deduite d'un historique
de production, qui n'existe pas encore.

> **Ce qui manque encore.** Ces deux regles ne couvrent ni le taux
> d'erreur (SLO 1) ni la latence (SLO 2), alors que leurs metriques sont
> deja disponibles (`http_requests_total`, `http_request_duration_seconds`
> — voir l'etat de l'instrumentation ci-dessous). Il n'existe donc
> aujourd'hui aucune alerte qui se declenche **avant** l'epuisement du
> budget d'erreur de ces deux SLO ; seule une panne franche (API injoignable)
> ou un pic brutal de deconnexions le sont. Ajouter une regle de taux
> d'erreur et une regle de latence, toutes deux a un seuil plus severe que
> le SLO correspondant, est la prochaine etape.

## Etat de l'instrumentation

| SLO | Metrique | Etat |
|-----|----------|------|
| 1 — Disponibilite | `http_requests_total{status}` | **Disponible** |
| 2 — Latence | `http_request_duration_seconds` | **Disponible** |
| 3 — Continuite | `stream_disconnections_total` | **Disponible** |
| 4 — Perte de chunks | `listener_sessions_total`, `sessions_with_chunk_loss_total` | **Disponible** |

Les quatre SLO sont mesurables des aujourd'hui.

## Voir aussi

- [Scalabilite et couts](scalability.md) — les mesures dont derivent ces seuils
- [ADR 004 — Observabilite](ADR/004-observabilite-otel.md) — comment les
  metriques sont collectees
- [Cahier de recette](cahier-de-recette.md) — la verification fonctionnelle

---

## Summary (English)

Four SLOs, measured over a rolling 28-day window, define what StreamPulse
commits to: **99.5%** of HTTP requests complete without a server error
(4xx excluded — a wrong password isn't an outage); **95%** of non-streaming
requests answer under 200ms (streaming, broadcast, and the deliberately
slow bcrypt-cost-12 auth endpoints are excluded, since including them would
make the indicator meaningless); **99%** of listening sessions end at the
listener's own initiative rather than dropping abruptly; and **under 1%**
of listeners lose an audio chunk per session. 99.5% rather than 99.9% is a
deliberate ceiling: the fan-out Hub lives in a single process's memory, so
two instances don't share listeners, and promising 99.9% on a
single-instance architecture would be a commitment the system can't keep.

An error-budget policy ties monitoring to the release calendar: under 50%
consumed, ship normally; 50-75%, review recent alerts; 75-100%, freeze new
features and fix reliability only; over 100%, a written post-mortem is
required before shipping again. All four SLOs are now measurable: SLO 3's
`stream_disconnections_total` carries a `reason` label (`client`,
`stream_closed`, `abrupt`) set in the `Listen` and `AudioStream` handlers'
`defer`, and SLO 4 gets two new counters, `listener_sessions_total` and
`sessions_with_chunk_loss_total`, fed by a per-client atomic counter that
`Client.Send` increments whenever it drops a chunk because a listener's
buffer is full. Two Grafana unified-alerting rules are provisioned by file
and route to the team's Discord channel — an API-down check
(`up{job="streampulse-api"} == 0`) and an abrupt-disconnect-spike check
(`increase(stream_disconnections_total{reason="abrupt"}[5m]) > 3`, its
threshold sized for demo-scale traffic, not production history) — but
neither SLO 1 (error rate) nor SLO 2 (latency) has a matching alert yet,
despite both metrics already being available.
