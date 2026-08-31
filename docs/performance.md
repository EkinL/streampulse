# Performance de l'interface — fluidite et jank

Ce document mesure la fluidite de rendu de l'application mobile (60 Hz,
16,67 ms de budget par image) avec l'outillage de profilage officiel de
Flutter, pas avec une impression visuelle. Meme principe que dans le reste de
la documentation : l'etat decrit est **mesure**, pas estime, et les commandes
de reproduction sont donnees a chaque fois (voir aussi
[scalability.md](scalability.md) pour la meme demarche cote backend).

## Pourquoi pas une capture DevTools manuelle telle quelle

L'outil naturel est la page **Performance** de Flutter DevTools (le graphe de
barres UI/Raster par image, avec le seuil de jank a 16,67 ms). Elle a servi de
premiere verification visuelle ici, mais son graphe est un flux **glissant** :
il affiche les images les plus recentes, y compris toute activite qui suit le
scenario teste (recompositions periodiques, interactions avec l'outillage de
debogage). Une simple capture d'ecran de ce graphe peut donc, selon le moment
exact ou elle est prise, montrer une fenetre propre ou une fenetre polluee par
autre chose que le geste teste — ce n'est pas fiable comme preuve reproductible.

La source de verite utilisee ici est donc la **timeline brute du VM Service
Dart** (celle que Flutter DevTools lit et affiche), recuperee et analysee
avec des bornes de temps explicites :

```bash
# 1. Lancer l'app en mode debug sur un simulateur/appareil et relever
#    l'URI du VM Service affichee au demarrage (ex: http://127.0.0.1:PORT/AUTH_CODE/)
cd mobile && flutter run -d <device-id>

# 2. Recuperer la timeline complete (evenements bruts du moteur)
curl -s "http://127.0.0.1:<PORT>/<AUTH_CODE>/getVMTimeline" -o timeline.json

# 3. Reperer les creneaux d'inactivite entre images (une image n'est produite
#    que si quelque chose change reellement a l'ecran)
python3 mobile/scripts/analyze_frame_timeline.py timeline.json --gaps

# 4. Isoler la fenetre du geste teste et calculer les statistiques
python3 mobile/scripts/analyze_frame_timeline.py timeline.json --from <debut_s> --to <fin_s>
```

`mobile/scripts/analyze_frame_timeline.py` reconstitue, depuis les evenements
`Frame` (thread UI, construction/layout/peinture) et `GPURasterizer::Draw`
(thread raster, soumission GPU), la meme paire de durees par image que le
graphe DevTools — moyenne, p50/p90/p99, et taux d'images au-dela du budget de
16,67 ms (jank) et 33,33 ms (jank severe, deux images ratees).

## Environnement de mesure

| | |
|---|---|
| Machine | Apple M4, 10 coeurs (4 performance + 6 efficacite), 16 Go |
| Flutter | 3.41.6 stable |
| Cible | Simulateur iPhone 16, iOS 18.6, arm64 |
| Build | **debug** (voir limite ci-dessous) |
| Ecran teste | Liste des flux (`streams_list_screen.dart`), 66 elements charges par pages de 20 |
| Geste | 6 balayages verticaux continus (4 vers le bas, 2 vers le haut) via des evenements tactiles synthetiques |

> **Limite connue — mode debug.** Le mode profile de Flutter n'est pas
> disponible sur simulateur iOS (uniquement sur appareil physique — message de
> l'outil : `Profile mode is not supported by iPhone 16`). Le mode debug
> inclut le JIT et les assertions, donc il **surestime** le cout reel : si le
> mode debug est deja fluide, le mode profile/release le sera au moins autant.
> A l'inverse, un jank observe en debug n'est pas automatiquement present en
> release. Un audit `--profile` sur appareil physique reste a faire (voir
> tableau en fin de document).

## Resultat 1 — fluidite du scroll (ce qui etait demande)

Fenetre isolee : 6,5 s de balayages continus sur la liste de 66 flux, entre
deux creneaux d'inactivite (`--from 3410.0 --to 3416.5` sur la trace de
reference).

| Thread | Images | Moyenne | p50 | p90 | p99 | Max | Images en jank (>16,67 ms) |
|--------|-------:|--------:|----:|----:|----:|----:|:---------------------------:|
| UI (build) | 138 | 3,40 ms | 2,52 ms | 5,46 ms | 15,44 ms | 19,17 ms | 1 / 138 (0,7 %) |
| Raster | 138 | 1,61 ms | 1,36 ms | 1,77 ms | 7,71 ms | 23,80 ms | 1 / 138 (0,7 %) |

Aucune image en jank severe (>33,33 ms) sur les deux threads. Marge tres
confortable sous le budget de 16,67 ms : le scroll de la liste tient le 60 Hz
en mode debug, avec de la marge pour le mode release.

## Resultat 2 — decouverte en cours de mesure : rafraichissement periodique

En analysant la trace au-dela de la fenetre de scroll, une image sur deux
apparait toutes les ~10 s, meme sans interaction. Cause identifiee dans le
code : [`streams_list_screen.dart:40`](../mobile/lib/features/streams/presentation/screens/streams_list_screen.dart#L40)
relance `fetchStreams()` toutes les 10 secondes (`Timer.periodic`), qui
remplace la liste complete et reconstruit les 66 cartes visibles.

| Thread | Images | Moyenne | p90 | p99 (= max) | Images en jank (>16,67 ms) | Jank severe (>33,33 ms) |
|--------|-------:|--------:|----:|------------:|:---------------------------:|:------------------------:|
| UI (build) | 39 | 11,37 ms | 30,70 ms | 43,27 ms | 12 / 39 (30,8 %) | 2 / 39 (5,1 %) |
| Raster | 39 | 12,14 ms | 57,49 ms | 122,60 ms | 4 / 39 (10,3 %) | 4 / 39 (10,3 %) |

Echantillon petit (39 images sur ~80 s, dont une partie correspond a mes
propres interactions avec l'outillage de debogage pendant la mesure — a
reproduire isolement). Mais le signal est net : le rafraichissement
periodique de la liste de flux est le point chaud de cet ecran, pas le scroll.
C'est attendu (reconstruction de 66 cartes vs. recyclage de quelques items
visibles par le scroll) mais pas gratuit, et n'a pas ete cible par cette
branche.

> **Limite connue.** Correctif non applique ici (hors perimetre de cette
> mesure) : remplacer le `setState` complet par une mise a jour differentielle
> (comparer les ids recus a l'etat courant), ou desactiver le
> rafraichissement pendant un scroll actif.

## Etat des lieux et feuille de route

| Sujet | Etat | Prochaine etape |
|-------|------|-----------------|
| Scroll liste de flux (66 elements), mode debug | Mesure — fluide (0,7 % de jank) | — |
| Rafraichissement periodique liste de flux | Mesure — point chaud identifie | Diff au lieu de remplacement complet |
| Mesure en mode profile/release | A faire | Necessite un appareil iOS physique (non disponible sur simulateur) |
| Autres ecrans (playlist longue, lecteur, recherche) | A faire | Rejouer le meme protocole (`analyze_frame_timeline.py`) sur chaque ecran |
| Android | A faire | Emulateur/appareil Android non disponible dans cet environnement de mesure |

## Voir aussi

- [Scalabilite et couts](scalability.md) — meme demarche de mesure, cote backend
- [Accessibilite](accessibilite.md) — etat des lieux dans le meme format
- `mobile/scripts/analyze_frame_timeline.py` — script de reproduction
