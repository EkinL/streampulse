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

> **Cet indicateur n'est pas encore exploitable.** `stream_disconnections_total`
> existe mais n'a pas de label `reason` : les deconnexions propres et brutales
> sont comptees ensemble. Ajouter ce label est le prerequis de ce SLO.

---

## SLO 4 — Perte de chunks audio

> **Moins de 1 % des auditeurs subissent une perte de chunk sur une session.**

| | |
|---|---|
| SLI | a instrumenter : compteur incremente quand `Client.Send` tombe dans son `default` |
| Cible | **< 1 %** des sessions |

Quand le tampon d'un auditeur est plein (256 chunks, soit **64 secondes**
d'avance a 4 chunks/s), `Client.Send` abandonne le chunk plutot que de bloquer.
C'est un choix de conception : un auditeur lent degrade sa propre qualite, jamais
celle des autres, et ne peut pas bloquer le diffuseur.

Ce comportement est donc **correct**, mais il doit rester rare. S'il devient
frequent, c'est le signe d'un probleme reseau cote clients ou d'un debit trop
eleve pour la population reelle.

> **Non instrumente a ce jour.** La branche `default` de `Client.Send` ne
> comptabilise rien. C'est le seul SLO dont l'indicateur reste entierement a
> construire.

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

| Alerte | Condition | Gravite |
|--------|-----------|---------|
| `APIHighErrorRate` | taux de 5xx > 1 % pendant 5 min | critique |
| `APIHighLatency` | p95 > 500 ms pendant 10 min | avertissement |
| `NoListenersOnLiveStream` | `active_streams > 0` et `active_listeners == 0` pendant 15 min | avertissement |
| `AbruptDisconnectSpike` | taux de deconnexions brutales > 5 % pendant 10 min | critique |

Les seuils d'alerte sont **plus severes que les SLO** : une alerte doit se
declencher pendant qu'il reste du budget, pas une fois qu'il est epuise.

> Ces regles ne sont pas encore ecrites. `prometheus/` ne contient que
> `prometheus.yml`, il n'y a ni `rules/` ni Alertmanager dans la stack.

## Etat de l'instrumentation

| SLO | Metrique | Etat |
|-----|----------|------|
| 1 — Disponibilite | `http_requests_total{status}` | **Disponible** |
| 2 — Latence | `http_request_duration_seconds` | **Disponible** |
| 3 — Continuite | `stream_disconnections_total` | Present, **label `reason` manquant** |
| 4 — Perte de chunks | — | **A instrumenter** |

Les deux premiers SLO sont mesurables des aujourd'hui. Les deux suivants — ceux
qui decrivent l'experience reelle de l'auditeur — demandent chacun une
modification de quelques lignes dans
`internal/infrastructure/observability/metrics.go` et
`internal/infrastructure/streaming/client.go`.

## Voir aussi

- [Scalabilite et couts](scalability.md) — les mesures dont derivent ces seuils
- [ADR 004 — Observabilite](ADR/004-observabilite-otel.md) — comment les
  metriques sont collectees
- [Cahier de recette](cahier-de-recette.md) — la verification fonctionnelle
