# Guide utilisateur et plan de formation

StreamPulse s'utilise differemment selon le role et selon le support. Ce
document decrit un parcours de prise en main par profil, puis le plan de
formation associe.

## Deux applications, un compte

| Support | Pour qui | Ou |
|---------|----------|-----|
| **Application mobile** iOS / Android | Auditeurs, et diffuseurs en mobilite | APK et `.ipa` publies par la CI |
| **Console web** | Diffuseurs et administrateurs, au poste de travail | Build web, cible `lib/main_web.dart` |

Le compte est le meme sur les deux. La console web n'accepte que les roles
`broadcaster` et `admin` : un compte `user` qui s'y connecte arrive sur une page
expliquant qu'il n'y a pas acces, et non sur une erreur.

## Les quatre roles

| Role | Ce qu'il peut faire |
|------|---------------------|
| **Visiteur** (non connecte) | Parcourir les flux et le catalogue musical, rechercher |
| **Auditeur** (`user`) | + ecouter le direct, gerer playlists et favoris |
| **Diffuseur** (`broadcaster`) | + creer et animer des flux, deposer des musiques |
| **Administrateur** (`admin`) | + gerer les comptes et consulter les metriques |

Les roles sont cumulatifs : un diffuseur peut tout ce que peut un auditeur.

> **Obtenir un role.** L'inscription cree toujours un compte `user`. Seul un
> administrateur peut promouvoir un compte, depuis **Users** dans la console web.
> Sur une installation neuve, le premier administrateur doit etre cree en base
> ([cahier de recette, section 2](cahier-de-recette.md)).

---

## Parcours 1 — Auditeur (mobile)

**Objectif : ecouter un direct et se constituer une playlist. Environ 10 minutes.**

### 1. Creer son compte
Ouvrir l'application, **Creer un compte**, saisir email, nom d'utilisateur et
mot de passe. La session s'ouvre immediatement, sans etape de confirmation.

### 2. Trouver un flux
L'onglet **Flux** liste les emissions. Une pastille indique celles qui sont en
direct. Toucher une carte ouvre son detail : titre, description, nombre
d'auditeurs connectes.

### 3. Ecouter
Sur un flux en direct, toucher **Lecture**. Le son demarre et un mini-lecteur
reste visible au bas de l'ecran pendant la navigation.

> Un flux qui n'est pas en direct ne peut pas etre ecoute : le bouton reste
> inactif. Ce n'est pas une panne.

### 4. Rechercher
L'ecran **Recherche** interroge d'un coup les flux et le catalogue musical.

### 5. Constituer une playlist
Onglet **Playlists** > **Nouvelle playlist**. Ajouter des morceaux depuis le
catalogue, puis **reordonner par glisser-deposer** : l'ordre est enregistre sur
le serveur et suit le compte d'un appareil a l'autre.

### 6. Mettre en favori
L'icone en forme de coeur, sur une carte de flux ou un morceau, l'ajoute a
l'onglet **Favoris**.

### 7. Consulter ou supprimer son compte
Toucher l'avatar (onglet **Profil**) affiche les informations du compte.
**Delete my account** supprime definitivement le compte, ses playlists, ses
favoris et, pour un diffuseur, ses flux et morceaux, apres une confirmation.
L'email redevient utilisable pour une nouvelle inscription.

> Cette suppression est immediate et irreversible. Ce que la plateforme
> conserve, et pourquoi, est detaille dans [rgpd.md](rgpd.md).

---

## Parcours 2 — Diffuseur

**Objectif : mettre un flux a l'antenne. Environ 15 minutes.**

Faisable depuis la console web comme depuis le mobile. La console est
recommandee : ecran plus grand, et pas de risque de mise en veille du telephone
pendant l'emission.

### 1. Se connecter a la console
Ouvrir l'URL de la console, se connecter. La barre laterale affiche
**Broadcast**.

### 2. Creer un flux
**Nouveau flux**, renseigner un titre et une description. Le flux est cree a
l'arret (`idle`) : il apparait dans la liste publique, mais personne ne peut
encore l'ecouter.

### 3. Passer a l'antenne
**Demarrer**. Le flux passe en direct et devient ecoutable. Le tableau de bord
affiche le nombre d'auditeurs connectes en temps reel.

### 4. Diffuser
Autoriser l'acces au microphone quand le navigateur ou le systeme le demande.
Le son capte est transmis a tous les auditeurs connectes.

### 5. Terminer
**Arreter**. Les auditeurs sont deconnectes proprement et le flux repasse a
l'arret. Il peut etre redemarre plus tard.

### 6. Deposer des musiques
Depuis l'ecran diffuseur du mobile, un morceau s'ajoute au catalogue en
fournissant son **URL** (titre, artiste, album, duree, lien du fichier audio).

> L'API accepte aussi le televersement d'un fichier audio en `multipart/form-data`
> sur `POST /music`, mais **aucun ecran ne propose ce parcours** aujourd'hui : la
> methode existe dans le client (`uploadMusic`) sans etre appelee. Pour deposer
> un fichier, il faut passer par l'API directement.

> **On ne modifie que ses propres flux.** Meme un administrateur ne peut pas
> renommer le flux d'un autre : le role autorise l'action, la propriete
> l'autorise sur cette ressource precise.

---

## Parcours 3 — Administrateur

**Objectif : gerer les comptes et surveiller la plateforme. Environ 10 minutes.**

### 1. Ouvrir Users
Dans la console web, la barre laterale affiche **Users** en plus de
**Broadcast**.

### 2. Promouvoir un compte
La liste presente tous les comptes avec leur role. Le menu deroulant de la
colonne role applique le changement immediatement.

> **Le changement ne prend effet qu'a la prochaine connexion** de la personne
> concernee. Les droits sont inscrits dans le jeton de session au moment ou il
> est emis ; le jeton en cours conserve l'ancien role jusqu'a 15 minutes.
> Demander a la personne de se deconnecter puis se reconnecter.

> **Il n'y a pas de garde-fou contre l'auto-retrogradation.** Un administrateur
> qui se retire son propre role perd l'acces a cet ecran, et il faudra un autre
> administrateur — ou un acces a la base — pour le retablir.

### 3. Consulter les metriques
`/metrics` expose les indicateurs Prometheus, reserves au role administrateur.
Le tableau de bord Grafana en donne une lecture visuelle.

### 4. Supprimer un compte sur demande
Une personne qui demande l'effacement de ses donnees par un autre canal que
l'application (courriel, courrier) est traitee par
`DELETE /admin/users/{id}` : meme effet que si elle l'avait fait elle-meme,
tout ce qui rattache le compte disparait. Verifier l'identite du demandeur
avant d'agir ; l'operation est irreversible.

---

## Plan de formation

Le public de StreamPulse n'est pas homogene : un auditeur decouvre une
application grand public, un diffuseur apprend un outil de production, un
administrateur exploite une plateforme. Les trois n'ont ni le meme temps
disponible, ni le meme niveau technique, ni le meme besoin.

| Public | Format | Duree | Support |
|--------|--------|-------|---------|
| **Auditeurs** | Autonomie complete | — | Le parcours 1 de ce guide. Aucune formation : si un auditeur a besoin d'etre forme, c'est l'interface qu'il faut corriger |
| **Diffuseurs** | Atelier pratique en petit groupe | 45 min | Parcours 2, suivi d'une emission de test reelle de bout en bout |
| **Administrateurs** | Accompagnement individuel | 1 h | Parcours 3, plus la lecture des [SLO](slo.md) et du tableau de bord Grafana |
| **Developpeurs** | Auto-formation | 2 h | [README](../README.md), les [ADR](ADR/), la description OpenAPI sur `/docs` |

### Adapter aux besoins particuliers

- **Sans lecture confortable de l'anglais** : ce guide, le README et le cahier
  de recette sont en francais. La description technique de l'API reste en
  anglais, conformement a l'usage du metier — le guide utilisateur ne l'exige
  jamais.
- **Peu a l'aise avec l'ecrit** : les parcours 1 et 2 sont concus pour etre
  refaits en demonstration guidee, une etape a la fois, sans lecture prealable.
- **Situation de handicap** : voir la section ci-dessous.
- **Sans connexion permanente** : l'application exige une connexion pour
  l'ecoute en direct. Le mode hors ligne n'existe pas encore.

### Accessibilite

L'engagement est de rendre l'application utilisable au lecteur d'ecran, avec un
contraste conforme et des zones tactiles suffisantes.

> **Etat reel a ce jour : cet engagement n'est pas tenu.** L'application mobile
> ne comporte aucune annotation d'accessibilite — aucun `Semantics` ni
> `semanticLabel` dans le code de l'interface mobile. Les seules annotations
> presentes sont trois infobulles de la console web. Un lecteur d'ecran
> annoncera donc des boutons sans nom sur les controles du lecteur audio.
>
> C'est un ecart identifie, pas un oubli de documentation. Le corriger consiste
> a annoter les controles du lecteur, les pochettes et les boutons d'icone.

## Depannage

| Symptome | Cause probable | Que faire |
|----------|----------------|-----------|
| « Ce flux n'est pas en direct » | Le diffuseur n'a pas demarre l'emission | Attendre, ou revenir plus tard |
| Deconnexion apres quelques minutes | Session expiree | Se reconnecter. La session dure 15 minutes et se renouvelle seule tant que l'application est active |
| La console web refuse l'acces | Compte `user` | Demander une promotion a un administrateur |
| Un nouveau role reste sans effet | Jeton emis avant le changement | Se deconnecter puis se reconnecter |
| Aucun son alors que le flux est en direct | Volume, ou sortie audio du systeme | Verifier le volume, puis reouvrir le flux |
| Trop de requetes | Limitation par adresse IP | Ralentir. Voir toutefois A-01 du [cahier de recette](cahier-de-recette.md) |

## Voir aussi

- [Cahier de recette](cahier-de-recette.md) — le comportement attendu, verifie
- [API](api.md) et `/docs` — pour integrer StreamPulse a un autre outil
- [SLO](slo.md) — ce que la plateforme s'engage a tenir
