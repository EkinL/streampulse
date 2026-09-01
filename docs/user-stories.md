# User stories

Ce document decrit les fonctionnalites de StreamPulse sous forme de user
stories, avec criteres d'acceptation verifiables. Il repond au critere
**Ce3.6.1** du bloc 3 (RNCP 38822) : la documentation technique doit inclure
des user stories, en plus du schema de base de donnees ([base-de-donnees.md](base-de-donnees.md)),
du schema de securite ([securite.md](securite.md)) et de diagrammes standardises
([diagrammes.md](diagrammes.md)). Une synthese en anglais figure en fin de document.

Chaque story est reliee a son cas d'usage (`UC-xx`) dans
[plan-de-tests.md](plan-de-tests.md), qui porte deja la trace vers les tests
automatises, et a ses cas de recette (`docs/cahier-de-recette.md`). Ce document
ne duplique pas cette matrice : il en donne la lecture "besoin utilisateur",
la ou le plan de tests donne la lecture "verification".

## Format

> **En tant que** `<role>`, **je veux** `<action>`, **afin de** `<benefice>`.
>
> Criteres d'acceptation (Given/When/Then) — Traçabilite

Quatre roles hierarchises : `anonymous` < `user` < `broadcaster` < `admin`
(chacun herite des droits du precedent, voir [ADR 006](ADR/006-strategie-auth-jwt.md)).

---

## Epic A — Comptes et authentification

### US-01 — Creer un compte
**En tant que** visiteur anonyme, **je veux** creer un compte avec un email,
un nom d'utilisateur et un mot de passe, **afin de** pouvoir ecouter des
flux, gerer des favoris et des playlists.

- **Given** un email non deja utilise et un mot de passe d'au moins 8
  caracteres, **when** j'envoie `POST /auth/register` avec la case
  "j'accepte les conditions d'utilisation" cochee, **then** mon compte est
  cree avec le role `user`, et je recois immediatement une paire de jetons
  (acces + refresh).
- **Given** un email deja enregistre, **when** je m'inscris avec cet email,
  **then** la requete est refusee (`409`).
- **Given** la case des conditions d'utilisation non cochee, **when**
  j'envoie la requete, **then** elle est refusee (`400`), y compris si le
  client mobile a ete contourne (revalidation serveur).
- Traçabilite : `UC-01`, `POST /auth/register`, `TestAuthService_Register`,
  `TestAuth_RegisterLoginRefresh`, `TestAuth_RegisterValidation`.

### US-02 — Se connecter
**En tant qu'**utilisateur enregistre, **je veux** me connecter avec mon
email et mon mot de passe, **afin d'**acceder aux fonctionnalites reservees
a mon role.

- **Given** des identifiants valides, **when** j'envoie `POST /auth/login`,
  **then** je recois un nouveau couple de jetons et toute session
  precedente est revoquee.
- **Given** un mauvais mot de passe ou un compte inconnu, **when** je me
  connecte, **then** la reponse est `401` dans les deux cas (aucune fuite
  d'information sur l'existence du compte).
- Traçabilite : `UC-02`, `POST /auth/login`, `TestAuthService_Login`,
  `TestAuth_RegisterLoginRefresh`.

### US-03 — Rester connecte sans ressaisir mon mot de passe
**En tant qu'**utilisateur, **je veux** que mon jeton d'acces se
renouvelle automatiquement, **afin de** ne pas etre deconnecte toutes les
15 minutes.

- **Given** un refresh token valide, **when** l'application appelle
  `POST /auth/refresh`, **then** j'obtiens un nouveau jeton d'acces et un
  nouveau refresh token, et l'ancien refresh token devient inutilisable.
- **Given** un refresh token deja utilise ou expire, **when** il est
  presente, **then** la requete est refusee (`401`).
- Traçabilite : `UC-03`, `POST /auth/refresh`, `TestAuthService_RefreshToken`,
  `TestAuth_ExpiredTokensRejected`.

### US-04 — Consulter et corriger mes informations
**En tant qu'**utilisateur, **je veux** consulter et modifier mon email et
mon nom d'utilisateur, **afin de** garder mon profil a jour (droit de
rectification, art. 16 RGPD).

- **Given** je suis connecte, **when** j'appelle `GET /users/me`, **then**
  je recois toutes mes donnees personnelles, sans jamais le hash de mon
  mot de passe.
- **Given** un nouvel email deja pris par un autre compte, **when**
  j'appelle `PATCH /users/me`, **then** la requete est refusee (`409`).
- Traçabilite : `handlers/user_handler.go`, [rgpd.md](rgpd.md#3-droits-des-personnes).

### US-05 — Supprimer mon compte
**En tant qu'**utilisateur, **je veux** supprimer definitivement mon
compte et tout ce qui s'y rattache, **afin d'**exercer mon droit a
l'effacement (art. 17 RGPD).

- **Given** je suis connecte, **when** j'appelle `DELETE /users/me`,
  **then** mon compte, mes flux, playlists, favoris et morceaux deposes
  disparaissent immediatement, en cascade.
- **Given** un jeton d'acces encore valide apres l'effacement, **when** je
  l'utilise, **then** toute route repond `404` : le jeton n'a plus de
  compte a designer.
- Traçabilite : `UC-20`, `DELETE /users/me`, `TestUsers_AccessAndErasure`,
  [ADR 007](ADR/007-effacement-compte-rgpd.md).

---

## Epic B — Consultation anonyme

### US-06 — Decouvrir la plateforme sans compte
**En tant que** visiteur anonyme, **je veux** consulter la liste des flux
en direct et les playlists publiques, **afin de** decider si je veux
m'inscrire.

- **Given** aucun jeton, **when** j'appelle `GET /streams` ou
  `GET /playlists/public`, **then** je recois la liste, paginee.
- **Given** aucun jeton, **when** j'appelle une route necessitant un
  compte (favoris, creation de flux, `/users/me`), **then** je recois
  `401`.
- Traçabilite : `UC-04`, `TestRBAC_EndpointMatrix`.

---

## Epic C — Ecoute et bibliotheque personnelle (role `user`)

### US-07 — Ecouter un flux en direct
**En tant qu'**auditeur, **je veux** ecouter un flux en cours de
diffusion, **afin de** profiter du contenu en temps reel.

- **Given** un flux au statut `live`, **when** je me connecte a
  `GET /streams/{id}/listen` (SSE) ou `/audio` (flux brut), **then** je
  recois les chunks audio diffuses par le broadcaster, et le compteur
  d'auditeurs du flux augmente de un.
- **Given** un flux au statut `idle` ou `ended`, **when** je tente de
  l'ecouter, **then** je recois une erreur `STREAM_NOT_LIVE` sans jamais
  ouvrir de connexion pendante.
- **Given** une ecoute en cours, **when** je me deconnecte, **then** le
  compteur d'auditeurs redescend sans intervention du serveur.
- Traçabilite : `UC-05`, `TestStreams_LifecycleWithLiveListener`,
  [ADR 003](ADR/003-streaming-sse.md).

### US-08 — Rechercher un flux ou un morceau
**En tant qu'**utilisateur, **je veux** rechercher par mot-cle dans les
flux et la bibliotheque musicale, **afin de** trouver rapidement un
contenu.

- **Given** un terme present dans un titre ou un artiste, **when**
  j'appelle `GET /search` ou `GET /music/search`, **then** les resultats
  pertinents sont renvoyes, tries par pertinence.
- Traçabilite : `GET /search`, `GET /music/search`, index `gin` sur
  `music.title` et `music.artist` (migration 004).

### US-09 — Mettre un flux ou un morceau en favori
**En tant qu'**utilisateur, **je veux** marquer des flux et des morceaux
comme favoris, **afin de** les retrouver facilement.

- **Given** un flux ou un morceau existant, **when** j'appelle
  `POST /favorites/{streamId}` ou `POST /music/{id}/favorite`, **then**
  il apparait dans `GET /favorites` ou `GET /music/favorites`.
- **Given** un identifiant inexistant, **when** je le mets en favori,
  **then** je recois `404` et rien n'est ecrit en base (contrainte de cle
  etrangere).
- Traçabilite : `UC-06`, `UC-07`, `TestFavorites_Streams`,
  `TestFavorites_Music`.

### US-10 — Creer et organiser mes playlists
**En tant qu'**utilisateur, **je veux** creer des playlists et en gerer
l'ordre des pistes, **afin de** composer mes propres sequences d'ecoute.

- **Given** une playlist que je possede, **when** j'ajoute, retire ou
  reordonne des pistes via `POST/PUT/DELETE /playlists/{id}/tracks*`,
  **then** l'ordre (`position`) est recalcule de facon atomique, sans
  jamais laisser deux pistes a la meme position.
- **Given** une playlist appartenant a un autre utilisateur, **when** je
  tente de la modifier, **then** je recois `403` (prive, deja visible) ou
  `404` (privee, invisible) selon `is_public`.
- **Given** je marque une playlist `is_public = true`, **when** un autre
  utilisateur appelle `GET /playlists/public`, **then** elle apparait avec
  mon nom d'utilisateur affiche.
- Traçabilite : `UC-08`, `UC-09`, `TestPlaylists_QueueManagement`,
  `TestPlaylists_VisibilityAndOwnership`, `TestPlaylistRepo_ReorderIsAtomic`.

---

## Epic D — Diffusion (role `broadcaster`)

### US-11 — Creer et piloter un flux
**En tant que** diffuseur, **je veux** creer un flux, le demarrer, y
diffuser de l'audio puis l'arreter, **afin de** faire une emission en
direct.

- **Given** mon compte a le role `broadcaster` ou `admin`, **when**
  j'appelle `POST /streams`, **then** un flux est cree au statut `idle`
  sous ma propriete.
- **Given** je suis proprietaire du flux, **when** j'appelle
  `POST /streams/{id}/start`, **then** son statut passe a `live` et les
  auditeurs connectes peuvent l'ecouter.
- **Given** un flux `live` dont je suis proprietaire, **when** j'envoie
  des chunks a `POST /streams/{id}/broadcast`, **then** ils sont relayes
  a tous les auditeurs connectes sans etre stockes.
- **Given** un flux appartenant a un autre diffuseur, **when** je tente de
  le demarrer, l'arreter ou d'y diffuser, **then** je recois `403`, meme
  si je suis moi-meme `broadcaster`.
- Traçabilite : `UC-10`, `TestStreams_LifecycleWithLiveListener`,
  `TestStreams_OwnershipAndErrors`.

### US-12 — Alimenter la bibliotheque musicale
**En tant que** diffuseur, **je veux** deposer un fichier audio ou
enregistrer l'URL d'une source, **afin de** constituer un catalogue
reutilisable dans mes playlists.

- **Given** un fichier audio valide, **when** je l'envoie a `POST /music`
  en `multipart/form-data`, **then** il est stocke sur disque et
  reference en base, avec moi comme `uploaded_by`.
- **Given** un depot refuse (format, taille, ou tiers pour une
  modification), **when** l'erreur survient, **then** rien n'est ecrit ni
  sur le disque ni en base (pas de fichier orphelin).
- Traçabilite : `UC-11`, `TestMusic_UploadFile`, `TestMusic_CatalogueByURL`.

---

## Epic E — Administration (role `admin`)

### US-13 — Gerer les comptes utilisateurs
**En tant qu'**administrateur, **je veux** lister les comptes et changer
le role d'un utilisateur, **afin de** promouvoir un diffuseur ou
suspendre un abus.

- **Given** je suis `admin`, **when** j'appelle `GET /admin/users`,
  **then** je recois la liste paginee, sans aucun hash de mot de passe.
- **Given** un role valide (`user`, `broadcaster`, `admin`), **when**
  j'appelle `PUT /admin/users/{id}/role`, **then** le changement prend
  effet au prochain rafraichissement de jeton de la personne concernee
  (les claims JWT sont figes a l'emission, [ADR 006](ADR/006-strategie-auth-jwt.md)).
- **Given** je ne suis pas `admin`, **when** je tente d'appeler une route
  `/admin/*`, **then** je recois `403`.
- Traçabilite : `UC-12`, `TestAdmin_UsersAndRoles`,
  `TestRBAC_EndpointMatrix`.

### US-14 — Supprimer un compte sur demande
**En tant qu'**administrateur, **je veux** supprimer le compte d'un
utilisateur qui en fait la demande hors application, **afin de**
respecter son droit a l'effacement.

- **Given** un identifiant de compte existant, **when** j'appelle
  `DELETE /admin/users/{id}`, **then** le compte et son contenu
  disparaissent en cascade, comme une auto-suppression.
- Traçabilite : `UC-21`, `TestAdmin_DeleteUser`.

### US-15 — Superviser la plateforme
**En tant qu'**administrateur, **je veux** consulter les metriques
globales (flux actifs, auditeurs, latences, erreurs), **afin de**
detecter une anomalie de production avant qu'elle n'affecte les
utilisateurs.

- **Given** je suis `admin`, **when** j'appelle `GET /metrics` ou
  j'ouvre le dashboard Grafana, **then** je distingue les metriques
  techniques (erreurs 500, latence) des metriques metier (auditeurs en
  ligne, deconnexions brutales).
- **Given** je ne suis pas `admin`, **when** j'appelle `GET /metrics`,
  **then** je recois `401` (anonyme) ou `403` (role insuffisant).
- Traçabilite : `UC-13`, `TestAdmin_MetricsExposePlatformGauges`,
  `TestMetricsAccess`, [ADR 008](ADR/008-dashboard-alertes-grafana.md).

---

## Epic F — Confiance et securite (transverses)

### US-16 — Etre protege contre les abus
**En tant qu'**utilisateur de l'API (legitime), **je veux** que la
plateforme reste disponible malgre des clients abusifs, **afin de**
continuer a l'utiliser normalement.

- **Given** un hote qui depasse le quota de requetes par seconde,
  **when** il continue d'emettre, **then** ses requetes en exces recoivent
  `429`, sans affecter les autres hotes.
- Traçabilite : `middleware/ratelimit.go`, [securite.md](securite.md#3-defense-en-profondeur).

### US-17 — Savoir ce que la plateforme sait de moi
**En tant qu'**utilisateur, **je veux** une documentation claire de mes
droits et des donnees conservees, **afin de** faire un choix eclaire.

- Traçabilite : `UC-22`, [rgpd.md](rgpd.md), [securite.md](securite.md).

---

## Matrice role x epic

| Epic | anonymous | user | broadcaster | admin |
|------|:---:|:---:|:---:|:---:|
| A — Comptes | US-01, US-02 | US-03, US-04, US-05 | herite de `user` | herite de `broadcaster` |
| B — Consultation | US-06 | herite | herite | herite |
| C — Ecoute et bibliotheque | — | US-07 a US-10 | herite | herite |
| D — Diffusion | — | — | US-11, US-12 | herite |
| E — Administration | — | — | — | US-13 a US-15 |
| F — Transverses | US-16, US-17 | US-16, US-17 | US-16, US-17 | US-16, US-17 |

---

## Summary (English)

This document restates StreamPulse's functionality as user stories with
Given/When/Then acceptance criteria, organised by role
(`anonymous` < `user` < `broadcaster` < `admin`) and grouped into six epics:
accounts & authentication, anonymous browsing, listening & personal library,
broadcasting, administration, and cross-cutting trust/security concerns.
Each story links to its use case (`UC-xx`) in [plan-de-tests.md](plan-de-tests.md)
and to the automated tests that verify it, so the story-to-code trace is
explicit rather than assumed. It answers criterion **Ce3.6.1** of RNCP 38822
block 3, alongside [base-de-donnees.md](base-de-donnees.md) (data model),
[securite.md](securite.md) (security overview) and [diagrammes.md](diagrammes.md)
(UML/BPMN diagrams).
