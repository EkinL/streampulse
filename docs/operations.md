# Exploitation : cycle de livraison et boucle de retour

Ce document decrit comment le code passe d'une idee a la production, et
comment ce qui est observe en production revient dans la feuille de route.

## 1. Cycle court

L'unite de travail est la **branche a but unique** : une branche, un sujet, une
PR. Pas de branche « divers ».

```
develop ──┬── feat/xxx ──► PR ──► CI ──► revue ──► merge ──┬──► develop
          └── docs/xxx ──►                                  │
                                                            └──► tag ──► release
```

| Etape | Ce qui se passe | Duree cible |
|-------|-----------------|-------------|
| Branche | Depuis `develop`, nommee par intention : `feat/`, `fix/`, `chore/`, `docs/`, `test/` | — |
| PR | Ouverte des le premier commit, meme incomplete : elle rend le travail visible aux autres | — |
| CI | Lint, tests, seuil de couverture, description OpenAPI, scans de securite | < 10 min |
| Revue | Au moins une relecture. La CI verte est un prerequis, pas une approbation | < 24 h |
| Merge | `--no-ff` vers `develop`, pour que l'historique garde la trace de l'unite de travail | — |
| Release | Tag `vX.Y.Z` sur `develop` quand un lot est coherent | a la demande |

**Pourquoi des branches courtes.** Quatre personnes travaillent en parallele sur
un depot unique. Une branche qui vit une semaine diverge, et son merge coute
plus cher que la fonctionnalite elle-meme. La regle pratique : si une branche
touche un fichier qu'une autre branche modifie deja, l'une des deux doit passer
en premier — c'est une decision a prendre au moment d'ouvrir la branche, pas au
moment du conflit.

### Ce qui bloque un merge

1. CI rouge
2. Couverture sous le seuil (`COVERAGE_MIN`, voir [plan de tests](plan-de-tests.md))
3. Description OpenAPI divergente du routeur — un test le detecte
4. Vulnerabilite corrigeable de severite HIGH ou CRITICAL

Aucun de ces points ne se contourne a la main : ce sont des jobs, pas des
conventions.

## 2. Publier une version

Le tag est **pose manuellement**. C'est la seule action humaine de la chaine, et
c'est deliberé : decider qu'un lot est publiable est un jugement, pas une
condition automatisable.

```bash
# 1. Basculer [Non publie] vers la version dans CHANGELOG.md
# 2. Aligner mobile/pubspec.yaml et info.version de backend/api/openapi.yaml
# 3. Taguer
git tag -a v1.1.0 -m "v1.1.0"
git push origin v1.1.0
```

Tout le reste est automatique. `.github/workflows/release.yml` :

| Job | Produit |
|-----|---------|
| `verify` | **Echoue** si le tag, `pubspec.yaml`, `openapi.yaml` et le CHANGELOG ne concordent pas |
| `image` | Image multi-architecture publiee sur `ghcr.io`, etiquetee `X.Y.Z`, `X.Y` et `latest`, puis scannee |
| `android` | `streampulse-X.Y.Z.apk` |
| `ios` | `StreamPulse-X.Y.Z+N.ipa` — **non signe**, a re-signer avant installation |
| `web` | `streampulse-console-X.Y.Z.zip`, a servir en statique |
| `release` | Release GitHub, notes extraites du CHANGELOG, livrables attaches |

Le job `verify` existe pour une raison precise : sans lui, on peut publier une
`v1.1.0` dont l'APK s'annonce en `1.0.0`. L'utilisateur installe alors une
version qui ment sur son propre numero, et tout rapport de bug devient
inexploitable.

```bash
docker pull ghcr.io/ekinl/streampulse-api:1.1.0
```

### Revenir en arriere

Les etiquettes de version sont immuables : la version precedente reste
disponible sur le registre. Un retour arriere consiste a redeployer
`ghcr.io/ekinl/streampulse-api:X.Y.Z-1`, sans reconstruction ni attente de CI.

Attention aux migrations : elles sont appliquees au demarrage et **ne sont pas
annulees** par un retour arriere. Une migration destructrice doit donc etre
scindee en deux versions — d'abord ajouter, puis supprimer une version plus
tard, une fois l'ancienne hors service.

## 3. Boucle de retour : de la surveillance a la feuille de route

Une surveillance qui n'entraine aucune decision est un tableau de bord decoratif.
Voici comment ce qui est observe redevient du travail.

### Les trois entrees

| Source | Cadence | Ce qu'on en fait |
|--------|---------|------------------|
| **Alertes** | temps reel | Traitees immediatement. Une alerte qui se declenche sans qu'on agisse doit etre supprimee ou son seuil corrige |
| **Budget d'erreur** | hebdomadaire | Voir [SLO](slo.md). Au-dela de 75 % consomme, les fonctionnalites sont gelees |
| **Scan de securite** | hebdomadaire, le lundi | Une vulnerabilite corrigeable ouvre une issue automatiquement |

### Le point hebdomadaire

Trente minutes, le lundi, apres l'execution des scans planifies. Trois
questions, dans cet ordre :

1. **Qu'est-ce qui s'est declenche cette semaine ?** Alertes, echecs de CI,
   issues ouvertes automatiquement.
2. **Combien de budget d'erreur reste-t-il ?** Il decide de ce qui est livrable
   la semaine suivante.
3. **Qu'est-ce que la mesure a revele qu'on ne savait pas ?**

La troisieme question est celle qui produit du travail. Deux exemples reels
issus de ce projet :

- La mesure de charge du Hub a montre que **le reseau sature a 86 % quand le
  CPU est a 20 %** ([scalability.md](scalability.md)). Consequence directe sur
  la feuille de route : optimiser le fan-out ne sert a rien, et privilegier
  `/audio` sur `/listen` economise 33 % de bande passante sur le poste qui
  sature. La priorite a change grace a une mesure, pas a une intuition.
- L'execution du [cahier de recette](cahier-de-recette.md) a revele que **le
  rate limiting etait inoperant** : la cle du compteur incluait le port source,
  donc chaque requete repartait avec un quota neuf. Aucune alerte ne pouvait le
  detecter, parce que le systeme se comportait normalement — c'est le test qui
  l'a trouve.

### Ce qui devient du travail

| Constat | Devient |
|---------|---------|
| Alerte recurrente | Une issue de correction, prioritaire |
| Budget d'erreur en baisse continue | Un point de fiabilite au sprint suivant |
| Mesure qui invalide une hypothese | Une mise a jour de l'ADR concerne |
| Vulnerabilite | Une PR Dependabot a relire, ou une montee de version manuelle |
| Cas de recette en echec | Une anomalie datee dans le cahier de recette, puis une issue |

Les anomalies restent **visibles dans le cahier de recette** tant qu'elles ne
sont pas corrigees. C'est volontaire : une anomalie connue et documentee est
moins dangereuse qu'une anomalie oubliee.

## 4. Chaine d'outils

```
commit ──► GitHub Actions ──► image GHCR ──► deploiement
              │                     ▲
              ├── lint              │
              ├── tests + seuil     │
              ├── OpenAPI           │
              └── securite ─────────┘
                    │
                    └──► issue automatique en cas d'echec

execution ──► OTEL ──► Collector ──► Prometheus ──► Grafana ──► alerte ──► issue
                                          │
                                          └──► budget d'erreur ──► feuille de route
```

Chaque controle est automatise et bloquant. Le seul maillon manuel est **la
decision de publier** (poser le tag) et **le deploiement de l'image** sur
l'hebergeur cible.

## Voir aussi

- [Plan de tests](plan-de-tests.md) — les niveaux et les seuils
- [Cahier de recette](cahier-de-recette.md) — les anomalies ouvertes
- [SLO](slo.md) — le budget d'erreur et la politique associee
- [Scalabilite](scalability.md) — les mesures qui orientent les priorites
- [CHANGELOG](../CHANGELOG.md) — l'historique des versions

---

## Summary (English)

Work moves through single-purpose short-lived branches (`feat/`, `fix/`,
`docs/`, ...) opened from `develop`, merged `--no-ff` only once CI is green,
coverage is above threshold, the OpenAPI description matches the router,
and no fixable HIGH/CRITICAL vulnerability is open. Publishing a version is
the one deliberately manual step — a human judgment call — after which
`.github/workflows/release.yml` verifies the git tag, `pubspec.yaml` and
`openapi.yaml` agree, then builds and publishes the multi-arch Docker
image, the Android APK, the unsigned iOS `.ipa`, the web console bundle,
and a GitHub release with CHANGELOG-derived notes. Version tags are
immutable, so rolling back means redeploying the previous tag — except
destructive database migrations, which are never reverted automatically
and must ship as two separate versions (add, then later remove).

A weekly 30-minute review turns monitoring into a roadmap: what fired this
week (alerts, CI failures, auto-opened issues), how much error budget is
left (which gates what can ship, see [slo.md](slo.md)), and what the data
revealed that wasn't already known. Two real examples from this project:
load testing showed the network saturates at 86% while CPU sits at 20%
([scalability.md](scalability.md)), which redirected effort away from
optimizing the fan-out Hub and toward favoring the raw-audio endpoint over
SSE; and running the acceptance cahier revealed that rate limiting was
silently broken because its counter key included the ephemeral source
port — no alert could have caught it, since the system looked healthy the
whole time.
