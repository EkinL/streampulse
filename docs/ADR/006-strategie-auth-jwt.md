# ADR 006: Authentification par JWT court et refresh token opaque

## Statut
Accepted

## Contexte
StreamPulse sert une application mobile, une console web et une API publique,
avec quatre roles hierarchises (`anonymous` < `user` < `broadcaster` < `admin`).

Deux contraintes structurent le choix :

- **Le serveur doit rester sans etat de session.** Le Hub de fan-out garde deja
  ses auditeurs en memoire du processus ; y ajouter des sessions rendrait toute
  mise a l'echelle horizontale dependante d'un store partage.
- **Les connexions sont longues.** Un auditeur reste connecte a
  `/streams/{id}/listen` pendant toute la duree d'un flux. Une expiration de
  jeton en cours d'ecoute ne doit pas couper le son.

## Decision

**Jeton d'acces JWT HS256 de courte duree, plus un refresh token opaque a usage
unique stocke hache en base.**

| | |
|---|---|
| Acces | JWT HS256, 15 min (`JWT_EXPIRY`), claims `user_id`, `email`, `username`, `role` |
| Refresh | UUID v4 opaque, 168 h (`JWT_REFRESH_EXPIRY`), stocke en SHA-256 |
| Mots de passe | bcrypt, cout 12 |
| Autorisation | `RequireRole(min)` compare des niveaux entiers |

## Justification

### Pourquoi JWT plutot que des sessions serveur
Une session imposerait une lecture partagee a chaque requete, donc un Redis ou
une table de sessions. Le JWT porte ses claims : la validation est une
verification de signature locale, sans aller-retour.

C'est ce qui permet a `RequireRole` d'etre un simple middleware sans acces base,
et a une instance de valider un jeton emis par une autre — condition necessaire
pour repartir la charge un jour.

### Pourquoi HS256 plutot que RS256
HS256 est symetrique : le meme secret signe et verifie. C'est adapte tant qu'un
**seul service** emet et verifie les jetons, ce qui est le cas ici.

RS256 deviendrait le bon choix le jour ou un service tiers doit verifier les
jetons sans pouvoir en emettre. Ce jour-la, il faudra changer : la cle publique
peut alors etre distribuee sans donner le pouvoir de signature. Documenter ce
seuil est plus utile que de payer d'avance la complexite d'une paire de cles.

### Pourquoi 15 minutes
Un JWT ne peut pas etre revoque : il est valide tant qu'il n'est pas expire. La
duree de vie est donc directement la fenetre d'exposition en cas de vol.

15 minutes bornent le risque a un cout acceptable — un rafraichissement toutes
les 15 minutes n'est rien pour un client mobile. Une heure quadruplerait la
fenetre pour un gain nul.

Les connexions longues ne sont pas affectees : le jeton est verifie **a
l'ouverture** de la connexion SSE. Un flux ecoute pendant deux heures ne se
coupe pas parce que le jeton expire en cours de route.

### Pourquoi un refresh token opaque plutot qu'un second JWT
- **Il est revocable.** Un UUID stocke en base disparait quand on le supprime.
  Un second JWT resterait valide jusqu'a son expiration, ce qui rendrait la
  deconnexion illusoire.
- **Il ne porte aucune information.** Un jeton vole ne revele ni le role, ni
  l'email, ni l'identifiant de l'utilisateur.
- **Il est stocke hache en SHA-256** (`token_hash`), jamais en clair. Une fuite
  de la table `refresh_tokens` ne donne aucun jeton utilisable.

SHA-256 et non bcrypt ici : le jeton est un UUID v4 aleatoire de 122 bits
d'entropie, pas un mot de passe choisi par un humain. Il n'y a pas de dictionnaire
a attaquer, donc rien a ralentir. bcrypt ajouterait une latence a chaque
rafraichissement sans gain de securite.

### Pourquoi bcrypt cout 12 pour les mots de passe
Ceux-la, en revanche, sont devinables. Le cout 12 correspond a 2^12 = 4096
iterations, soit **184 ms** mesures sur un Apple M4 (contre 72 ms au cout 10 et
721 ms au cout 14). C'est le point d'equilibre : assez lent pour rendre une
attaque par dictionnaire economiquement inutile, assez rapide pour rester
imperceptible sur un `login`, qui est une operation rare.

Ce cout est a **reevaluer periodiquement** : il doit suivre la puissance de
calcul disponible, pas rester fige a la valeur choisie aujourd'hui.

### Pourquoi une hierarchie de roles plutot que des permissions
`RequireRole(domain.RoleBroadcaster)` accepte aussi un `admin`, parce que les
roles sont ordonnes par niveau entier. Un systeme de permissions granulaires
serait plus souple, mais le produit n'a que quatre roles strictement inclusifs :
la souplesse ne servirait a rien et se paierait en complexite.

La propriete d'une ressource est verifiee **separement**, dans la couche
application : etre `broadcaster` autorise a creer un flux, pas a modifier celui
d'un autre. Les deux controles sont distincts et ne doivent pas etre confondus.

## Consequences

### Positif
- Aucun etat de session serveur : la validation d'un jeton est locale.
- La fenetre d'exposition d'un jeton vole est bornee a 15 minutes.
- Le refresh token est revocable et inexploitable en cas de fuite de la base.
- Le RBAC tient en un middleware sans acces base.

### Negatif
- **Un JWT d'acces ne peut pas etre revoque avant son expiration.** Bannir un
  utilisateur ne le deconnecte pas immediatement : il conserve son acces jusqu'a
  15 minutes. Une liste de revocation supprimerait l'interet du JWT ; c'est le
  compromis assume.
- **Le rafraichissement revoque tous les jetons de l'utilisateur.**
  `RefreshToken` appelle `DeleteByUserID`, pas une suppression du seul jeton
  presente. Se rafraichir sur le telephone deconnecte donc la console web. Le
  comportement est sur (aucun jeton rejoue ne survit) mais brutal : une
  suppression ciblee par hachage serait le bon correctif.
- **Le secret est unique et global.** Le faire tourner invalide toutes les
  sessions d'un coup. Une rotation propre supposerait de gerer deux secrets
  valides pendant une periode de recouvrement.
- Les claims sont figes a l'emission : promouvoir un utilisateur en
  `broadcaster` ne prend effet qu'apres rafraichissement.
- `JWT_SECRET` est obligatoire et sans valeur par defaut — le service refuse de
  demarrer sans lui, ce qui est voulu.

## Voir aussi
- [ADR 005 - PostgreSQL](005-choix-postgresql.md) pour le stockage des refresh
  tokens
- [ADR 003 - Streaming SSE](003-streaming-sse.md) pour les connexions longues

---

## Summary (English)

Authentication combines a short-lived HS256 JWT access token (15 minutes,
carrying `user_id`/`email`/`username`/`role`) with an opaque, single-use
refresh token (a random UUID v4, 168 hours, stored as its SHA-256 hash)
and bcrypt cost-12 password hashing. The server stays stateless — no
session store, no Redis — because the fan-out Hub already keeps listener
state in process memory, and adding shared session state would couple
horizontal scaling to an external store. HS256 (not RS256) is appropriate
because a single service both signs and verifies tokens; RS256 would only
earn its complexity once a third party needs to verify tokens without
being able to issue them. 15 minutes bounds a stolen token's exposure
window without disrupting long SSE connections, since the token is
checked once, at connection open. The refresh token is opaque and
DB-stored specifically so it can be revoked and carries no information if
leaked; SHA-256 (not bcrypt) is enough for it since it's 122 bits of
random entropy, not a guessable human password. A four-level role
hierarchy (`anonymous < user < broadcaster < admin`) replaces granular
permissions the product doesn't need; resource ownership is checked
separately, in the application layer. Accepted trade-offs: an access
token cannot be revoked before it expires (banning a user takes up to 15
minutes to bite), refreshing revokes **all** of a user's sessions at once,
and the signing secret is single and global — rotating it invalidates
every session simultaneously.
