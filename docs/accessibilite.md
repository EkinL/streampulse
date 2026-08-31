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
d'ecran de bureau.

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

> **Limite connue.** Les ratios de contraste n'ont pas ete mesures contre le
> seuil WCAG AA (4,5:1). Il n'existe ni theme clair ni mode contraste eleve.

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
- Console web : l'interface est utilisable au clavier via la navigation par
  tabulation fournie par Flutter web. Ce parcours clavier n'a pas encore ete
  audite de bout en bout.

## Accessibilite de cette documentation

La documentation du projet est concue pour rester lisible avec une technologie
d'assistance :

- structure par titres hierarchises, exploitables pour naviguer de section en
  section au lecteur d'ecran ;
- tableaux avec ligne d'en-tete, jamais d'information portee uniquement par la
  mise en forme ou la couleur ;
- texte brut Markdown, lisible sans outil particulier, compatible avec les
  plages braille et la synthese vocale ;
- parcours de prise en main du [guide utilisateur](guide-utilisateur.md)
  concus pour etre suivis une etape a la fois, y compris en demonstration
  guidee pour les personnes peu a l'aise avec l'ecrit.

Pour la formation, l'atelier diffuseur et l'accompagnement administrateur
(voir le [plan de formation](guide-utilisateur.md#plan-de-formation))
s'adaptent au rythme de la personne ; un utilisateur de lecteur d'ecran est
accompagne sur son propre appareil, avec sa propre configuration.

## Etat des lieux et feuille de route

| Sujet | Etat | Prochaine etape |
|-------|------|-----------------|
| Controles du lecteur annotes (`Semantics`, infobulles) | Fait | — |
| Volume et progression ajustables au lecteur d'ecran | Fait | — |
| Taille de texte systeme respectee | Fait | Verifier les grandes tailles sur les ecrans denses |
| Description des pochettes et icones restantes | A faire | Ajouter `semanticLabel` sur les images et boutons d'icone |
| Audit VoiceOver / TalkBack ecran par ecran | A faire | Derouler les parcours 1 a 3 du guide utilisateur au lecteur d'ecran et consigner les ecarts |
| Mesure des contrastes WCAG AA | A faire | Passer la palette du theme au verificateur de contraste |
| Zone tactile du bouton sourdine compact | A faire | Remonter a 48 px |
| Transcription / sous-titrage des flux | Non prevu a ce stade | A reevaluer avec les diffuseurs |

## Voir aussi

- [Guide utilisateur et plan de formation](guide-utilisateur.md) — parcours par
  role et adaptations aux besoins particuliers
- [Cahier de recette](cahier-de-recette.md) — le comportement attendu, verifie
