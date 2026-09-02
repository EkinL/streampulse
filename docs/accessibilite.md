# Accessibilite — utilisateurs en situation de handicap

Ce document decrit comment utiliser StreamPulse avec une technologie
d'assistance, ce que l'application prend en charge aujourd'hui, ce qu'elle ne
prend pas encore en charge, et comment la documentation elle-meme reste
utilisable par tous. Il s'adresse aux utilisateurs concernes, aux personnes qui
les accompagnent (voir le [plan de formation](guide-utilisateur.md#plan-de-formation))
et aux developpeurs qui font evoluer l'interface.

Le principe est le meme que dans le reste de la documentation : on decrit
l'etat reel, pas l'etat souhaite. Les limites connues sont listees en fin de
document avec leur prochaine etape.

## Utiliser l'application avec un lecteur d'ecran

L'application mobile fonctionne avec **VoiceOver** (iOS) et **TalkBack**
(Android), actives depuis les reglages du telephone — StreamPulse n'a rien a
configurer de son cote.

Les controles du lecteur audio sont annotes et annonces par le lecteur
d'ecran :

| Controle | Annonce |
|----------|---------|
| Lecture / pause | « Play » ou « Pause », selon l'etat, annonce comme bouton |
| Morceau precedent / suivant | « Previous » / « Next » |
| Curseur de volume | « Volume », suivi du pourcentage courant ; ajustable au geste habituel du lecteur d'ecran |
| Couper / retablir le son | « Mute » / « Unmute », selon l'etat |
| Ecouter / arreter un direct (mini-lecteur) | « Listen » / « Stop listening » |

Sur la console web, la navigation laterale, l'avatar du compte et la
deconnexion portent des infobulles, annoncees comme libelles par les lecteurs
d'ecran de bureau. Le rendu web de Flutter (CanvasKit) ne construit pas
l'arbre semantique par defaut : l'application l'active explicitement au
demarrage (`SemanticsBinding.instance.ensureSemantics()` dans `main.dart`),
sans quoi un lecteur d'ecran ne verrait qu'un canevas vide malgre les
annotations.

Au-dela du lecteur et de la console, chacun des 33 boutons icone de
l'application (retour, favoris, recherche, afficher/masquer le mot de passe,
supprimer, actualiser...) porte desormais une annonce dediee. Les vignettes de
pochette et de playlist (icone sur fond degrade, sans image reelle) sont
marquees explicitement decoratives : le lecteur d'ecran passe directement au
titre et a l'artiste, deja lus juste a cote, plutot que d'annoncer une icone
muette.

> **Limite connue.** Un parcours complet au lecteur d'ecran n'a pas encore ete
> audite ecran par ecran (listes de flux, playlists, recherche) : la
> couverture ci-dessus est verifiee controle par controle, pas rejouee de bout
> en bout comme un utilisateur le ferait.

## Taille du texte

L'application respecte la taille de texte reglee dans le systeme (Reglages >
Accessibilite) : aucun facteur d'echelle n'est impose dans le code. Le texte
grossit donc avec le reglage de l'utilisateur.

> **Limite connue.** L'interface n'a pas ete verifiee aux tres grandes tailles
> de texte ; des troncatures sont possibles sur les cartes les plus denses.

## Contraste et theme

L'interface utilise un theme sombre unique : texte clair sur fond fonce, avec
une couleur d'accent reservee aux actions principales. Aucune information
n'est portee par la couleur seule : l'etat « en direct » d'un flux, par
exemple, est aussi donne par le texte.

Les ratios de contraste (luminance relative, formule WCAG) ont ete mesures
pour toutes les paires texte/fond des jetons de design (`SP.*` dans
`app/theme.dart`) et pour les badges de statut (LIVE / HORS LIGNE) :

| Paire | Ratio | Seuil AA texte normal (4,5:1) |
|-------|------:|:------------------------------:|
| Texte principal sur fond | 14,65 | Conforme |
| Texte principal sur surface | 13,24 | Conforme |
| Texte secondaire sur fond | 11,07 | Conforme |
| Texte tertiaire sur surface variante | 4,55 | Conforme (marge faible) |
| Accent sur fond | 11,08 | Conforme |
| Texte de bouton sur accent | 8,47 | Conforme |
| Badge LIVE (texte sur fond plein) | 7,69 | Conforme |
| Badge HORS LIGNE (carte) | 8,56 | Conforme |
| Badge HORS LIGNE (page detail) | 6,80 | Conforme |

Toutes les paires texte/fond utilisees dans l'application depassent le seuil
AA du texte normal (4,5:1), y compris pour le texte le plus discret (tag
`text3` sur fond `surfaceVariant`, la marge la plus faible mesuree). Les
elements purement decoratifs a faible opacite (separateurs, ombre portee,
bordure de carte sur la console) ne portent aucune information et ne sont pas
concernes par cette exigence.

Un theme clair existe desormais et suit automatiquement le reglage clair/sombre
du systeme (mobile et console web), sans reglage a faire dans l'application.
Les tokens de couleur (fond, texte, accent) sont distincts entre les deux
themes et ont ete verifies au meme seuil WCAG AA que le theme sombre : le
plus faible est `text3` sur `surfaceVariant` a 4,55:1, toujours conforme.
L'accent, plus clair et peu contraste sur fond sombre, devient un indigo plus
sature en theme clair pour rester lisible en texte/icone sur fond blanc.

Un mode contraste eleve existe egalement, active manuellement depuis le profil
(independant du theme clair/sombre) : palettes dediees
(`SPColors.darkHighContrast` / `lightHighContrast` dans `app/theme.dart`) et
bordures renforcees (1,5 a 2 px) sur les champs et cartes.

> **Limite connue.** Les ratios de contraste de ces deux palettes dediees
> n'ont pas encore ete mesures (seuls le theme sombre et le theme clair
> standard le sont, ci-dessus) ; le mode ne suit pas non plus automatiquement
> le reglage systeme "Contraste eleve", il se choisit dans l'application.

## Zones tactiles

Les boutons de l'application utilisent les composants Material standard, dont
la zone tactile par defaut est de 48 px, y compris le bouton de sourdine du
mini-lecteur en mode compact : l'icone reste petite visuellement, mais la
zone tactile respecte la recommandation.

## Handicap auditif

StreamPulse est une plateforme d'ecoute en direct : le contenu principal est
sonore. Il n'existe pas de transcription ni de sous-titrage des flux — c'est
une limite assumee du produit a ce stade, pas un oubli. Les elements
d'interface, eux, ne dependent d'aucun signal sonore : toutes les
confirmations et erreurs sont affichees a l'ecran.

## Handicap moteur

- Mobile : tous les parcours se font par touches simples, sans geste complexe
  (pas de glisser obligatoire, pas d'appui long indispensable). Le curseur de
  progression et le volume sont aussi ajustables via le lecteur d'ecran.
- Console web : audite de bout en bout au clavier (Tab, Entree, Espace) sur
  l'ecran de connexion et le shell (barre laterale, carte utilisateur). L'ordre
  de tabulation des champs de formulaire est correct (email puis mot de
  passe) et leur focus est nettement visible (bordure). Le focus par defaut de
  Material 3 sur les boutons et icones etait en revanche trop discret sur
  cette palette sombre custom pour rester perceptible a la tabulation ; il a
  ete renforce (`ThemeData.focusColor`, `IconButtonThemeData`). Le bouton de
  connexion utilisait un widget `MaterialButton` historique plutot que la
  famille `ButtonStyleButton` (`TextButton`/`FilledButton`/...) employee
  partout ailleurs dans l'app ; il a ete aligne sur celle-ci par coherence et
  fiabilite d'activation clavier.

Rejoue apres correction du bug de plantage (voir ci-dessous) : connexion,
shell, puis deux allers-retours diffuseur <-> administration. La navigation ne
plante plus (aucune exception cote serveur de developpement ni console) et le
tableau des comptes (`User Management`) s'affiche normalement a chaque
passage.

> **Limite connue.** L'activation clavier (Entree/Espace) des elements non
> textuels — menu deroulant de role, bouton Grafana, bouton de connexion avant
> son passage a `TextButton` — n'a pas pu etre demontree de façon concluante
> avec l'outillage de test disponible pour cet audit (le clic souris active
> ces memes elements sans probleme). A verifier manuellement avec un clavier
> physique dans Chrome.

## Accessibilite de cette documentation

Le critere **Ce3.6.4** du bloc 3 (RNCP 38822) demande que la documentation
technique elle-meme inclue des solutions pour les personnes en situation de
handicap — pas seulement que l'application en propose. Trois formats
coexistent, chacun pour un besoin different :

| Format | Ou | Pour qui |
|--------|----|----------|
| Markdown (celui-ci) | `docs/`, lu sur GitHub ou dans un editeur | Lecteur d'ecran et plage braille : texte brut, titres hierarchises exploitables pour naviguer de section en section, tableaux avec ligne d'en-tete, aucune information portee par la seule couleur |
| **EPUB** — [`docs/accessible/streampulse-documentation.epub`](accessible/streampulse-documentation.epub) | L'ensemble de la documentation technique (README, tous les `docs/*.md`, tous les ADR), en un seul livre navigable | Basse vision et dyslexie : texte reflowable — police, taille, interligne et espacement au choix du lecteur, sans la mise en page figee d'un PDF ; aucune couleur n'est imposee dans le fichier, le theme (clair, sombre, contraste eleve) reste celui de la liseuse |
| **Audio (`.m4a`)** — [`guide-utilisateur.m4a`](accessible/guide-utilisateur.m4a), [`accessibilite.m4a`](accessible/accessibilite.m4a) | Narration par synthese vocale (voix francaise du systeme) du guide utilisateur et de ce document | Handicap visuel en formation, ou toute personne qui prefere ecouter : les tableaux sont restitues comme des phrases (« Controle : Lecture / pause. Annonce : ... ») plutot que lus colonne par colonne |

Les trois sont generes a partir des memes fichiers Markdown source par
[`docs/scripts/build_accessible_docs.py`](scripts/build_accessible_docs.py)
(bibliotheque standard Python uniquement ; l'audio demande en plus `say` et
`afconvert`, deux outils macOS) :

```bash
python3 docs/scripts/build_accessible_docs.py
# ou : make docs-accessible
```

**Choix assumes et limites** :

- La narration audio ne couvre que le guide utilisateur et ce document
  d'accessibilite, pas les 24 autres chapitres de l'EPUB : la reference API,
  les migrations SQL ou le code source des diagrammes Mermaid n'ont pas de
  valeur ecoutee et produiraient des heures d'audio inexploitables. Le
  script les affiche comme un texte a part (« extrait de code non lu ici »)
  plutot que de les lire caractere par caractere.
- La voix est une synthese vocale systeme (`Thomas`, fr_FR), pas un
  enregistrement humain : intelligible et suffisante pour de la formation,
  mais avec la prosodie d'une machine.
- Les liens internes entre documents (ex. vers [rgpd.md](rgpd.md)) sont
  reecrits pour pointer vers le bon chapitre a l'interieur de l'EPUB ; un
  lien vers une page qui n'existe pas dans le livre degrade en texte simple
  plutot que de rester un lien mort.

Au-dela des formats, l'accompagnement compte autant que le support : pour la
formation, l'atelier diffuseur et l'accompagnement administrateur (voir le
[plan de formation](guide-utilisateur.md#plan-de-formation)) s'adaptent au
rythme de la personne, et un utilisateur de lecteur d'ecran est accompagne
sur son propre appareil, avec sa propre configuration.

## Etat des lieux et feuille de route

| Sujet | Etat | Prochaine etape |
|-------|------|-----------------|
| Controles du lecteur annotes (`Semantics`, infobulles) | Fait | — |
| Volume et progression ajustables au lecteur d'ecran | Fait | — |
| Taille de texte systeme respectee | Fait | Verifier les grandes tailles sur les ecrans denses |
| Tooltips sur les boutons icone (33/33) | Fait | — |
| Pochettes/vignettes marquees decoratives (`ExcludeSemantics`) | Fait | — |
| Arbre semantique active au demarrage sur la console web (CanvasKit) | Fait | Rejouer un parcours au lecteur d'ecran de bureau sur la console deployee |
| Mesure des contrastes WCAG AA (texte/fond) | Fait | Revalider `text3` sur `surfaceVariant` (marge la plus faible, 4,55) si la palette change |
| Zone tactile du bouton sourdine compact (48 px) | Fait | — |
| Focus clavier visible sur boutons/icones (console web) | Fait | — |
| Bouton de connexion : `MaterialButton` -> `TextButton` | Fait | — |
| Crash de navigation diffuseur <-> admin (console web) | Fait | — |
| Theme clair (mobile + console web), suit le reglage systeme | Fait | — |
| Mode contraste eleve (palette dediee, active manuellement) | Fait | Mesurer les ratios WCAG de ces deux palettes |
| Activation clavier (Entree/Espace) des elements non textuels | A verifier | Test manuel au clavier physique dans Chrome (non concluant avec l'outillage automatise) |
| Audit VoiceOver / TalkBack ecran par ecran (mobile) | A faire | Derouler les parcours 1 a 3 du guide utilisateur au lecteur d'ecran et consigner les ecarts |
| Grandes tailles de texte sur cartes denses | A faire | Verifier a l'echelle de texte systeme maximale |
| Audit clavier console web ecran par ecran (au-dela login/shell/admin) | A faire | Playlists, recherche, autres ecrans non encore testes |
| Transcription / sous-titrage des flux | Non prevu a ce stade | A reevaluer avec les diffuseurs |

## Voir aussi

- [Guide utilisateur et plan de formation](guide-utilisateur.md) — parcours par
  role et adaptations aux besoins particuliers
- [Cahier de recette](cahier-de-recette.md) — le comportement attendu, verifie

---

## Summary (English)

The mobile app works with VoiceOver and TalkBack out of the box: player
controls, all 33 icon-only buttons, and web console tooltips are announced,
and purely decorative thumbnails are marked so screen readers skip them.
On the web console, the semantics tree is enabled explicitly at startup
(CanvasKit does not build it by default), so desktop screen readers see
the annotated controls instead of an empty canvas.
Text size follows the system setting. Contrast has been measured against
WCAG AA (4.5:1) for every text/background pair in the dark theme, the light
theme (which now follows the system setting), and a manually-selectable
high-contrast mode — the lowest measured ratio is 4.55:1, still conformant.
Touch targets meet the 48px Material minimum, and the web console has been
audited for keyboard navigation (tab order, visible focus) on the login
screen and shell. Known gaps, each with a next step: no full screen-reader
walkthrough yet (controls are verified individually, not replayed
end-to-end as a user would); very large system text sizes may truncate on
dense cards; the two high-contrast palettes are not yet measured; keyboard
activation (Enter/Space) of a few non-text controls could not be
conclusively demonstrated with the available automated tooling.

The documentation itself is also accessible: plain structured Markdown
(screen-reader and braille-display friendly), plus — to meet criterion
Ce3.6.4 of RNCP 38822 block 3 — a full EPUB edition of the entire technical
documentation (reflowable text, no imposed colors) and system
text-to-speech narrations of the user guide and this document, all
generated by [`docs/scripts/build_accessible_docs.py`](scripts/build_accessible_docs.py).
The audio deliberately excludes API references, SQL migrations and diagram
source code, which have no listening value; internal document links are
rewritten to resolve inside the EPUB rather than left dangling.
